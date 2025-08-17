# HVDC Batch Loader - TDB2 오프라인 대량 적재
# 야간 배치용 안전/고속 데이터 로딩

param(
    [string]$FusekiDir = ".\fuseki\apache-jena-fuseki-4.10.0",
    [string]$TdbLocation = ".\fuseki\apache-jena-fuseki-4.10.0\data\tdb-hvdc",
    [string]$DataDir = ".\batch_data",
    [string]$BackupDir = ".\backup",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$SkipBackup
)

$ErrorActionPreference = "Stop"

Write-Host "=== HVDC TDB2 Batch Loader ===" -ForegroundColor Green
Write-Host "TDB Location: $TdbLocation" -ForegroundColor Cyan
Write-Host "Data Directory: $DataDir" -ForegroundColor Cyan

# 1. 사전 검사
Write-Host "`n=== Pre-flight Checks ===" -ForegroundColor Yellow

# Fuseki 서버 상태 확인
$fusekiProcess = Get-Process java -ErrorAction SilentlyContinue | Where-Object {$_.CommandLine -like "*fuseki*"}
if ($fusekiProcess) {
    Write-Warning "⚠️  Fuseki server is running (PID: $($fusekiProcess.Id))"
    if (-not $Force) {
        $confirm = Read-Host "Stop Fuseki server for batch loading? (y/N)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            Write-Host "Stopping Fuseki server..." -ForegroundColor Yellow
            $fusekiProcess | Stop-Process -Force
            Start-Sleep 3
            Write-Host "✅ Fuseki server stopped" -ForegroundColor Green
        } else {
            Write-Error "❌ Cannot proceed with server running. Use -Force to override."
            exit 1
        }
    }
}

# TDB2 도구 존재 확인
$tdbLoader = Join-Path $FusekiDir "tdb2.tdbloader.bat"
if (-not (Test-Path $tdbLoader)) {
    # Windows에서는 .bat 없이도 시도
    $tdbLoader = Join-Path $FusekiDir "tdb2.tdbloader"
    if (-not (Test-Path $tdbLoader)) {
        Write-Error "❌ TDB2 loader not found: $tdbLoader"
        exit 1
    }
}
Write-Host "✅ TDB2 loader found: $tdbLoader" -ForegroundColor Green

# 데이터 디렉토리 확인
if (-not (Test-Path $DataDir)) {
    Write-Error "❌ Data directory not found: $DataDir"
    exit 1
}

$ttlFiles = Get-ChildItem -Path $DataDir -Filter "*.ttl" -Recurse
if ($ttlFiles.Count -eq 0) {
    Write-Error "❌ No TTL files found in: $DataDir"
    exit 1
}

Write-Host "✅ Found $($ttlFiles.Count) TTL files to load" -ForegroundColor Green
foreach ($file in $ttlFiles) {
    $sizeKB = [math]::Round($file.Length / 1KB, 2)
    Write-Host "   - $($file.Name) ($sizeKB KB)" -ForegroundColor White
}

# 2. 백업 (선택적)
if (-not $SkipBackup -and (Test-Path $TdbLocation)) {
    Write-Host "`n=== Creating Backup ===" -ForegroundColor Yellow
    
    $backupTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $BackupDir "tdb_backup_$backupTimestamp"
    
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    
    try {
        Write-Host "Creating backup: $backupPath" -ForegroundColor Yellow
        Copy-Item -Path $TdbLocation -Destination $backupPath -Recurse -Force
        Write-Host "✅ Backup created successfully" -ForegroundColor Green
        
        # 백업 크기 확인
        $backupSize = (Get-ChildItem -Path $backupPath -Recurse | Measure-Object -Property Length -Sum).Sum
        $backupSizeMB = [math]::Round($backupSize / 1MB, 2)
        Write-Host "   Backup size: $backupSizeMB MB" -ForegroundColor White
        
    } catch {
        Write-Error "❌ Backup failed: $($_.Exception.Message)"
        if (-not $Force) {
            exit 1
        }
    }
}

# 3. DryRun 모드
if ($DryRun) {
    Write-Host "`n=== DRY RUN MODE ===" -ForegroundColor Magenta
    Write-Host "Would execute the following commands:" -ForegroundColor Yellow
    
    foreach ($file in $ttlFiles) {
        $cmd = "& `"$tdbLoader`" --loc `"$TdbLocation`" `"$($file.FullName)`""
        Write-Host "   $cmd" -ForegroundColor White
    }
    
    Write-Host "`nDry run completed. Use without -DryRun to execute." -ForegroundColor Cyan
    exit 0
}

# 4. 실제 로딩
Write-Host "`n=== Loading Data ===" -ForegroundColor Yellow

$totalStartTime = Get-Date
$successCount = 0
$errorCount = 0
$loadResults = @()

foreach ($file in $ttlFiles) {
    Write-Host "`nLoading: $($file.Name)" -ForegroundColor Cyan
    
    $startTime = Get-Date
    try {
        # TDB2 로더 실행
        $arguments = @("--loc", $TdbLocation, $file.FullName)
        
        if ($tdbLoader.EndsWith(".bat")) {
            $result = & cmd /c "`"$tdbLoader`" $($arguments -join ' ')" 2>&1
        } else {
            $result = & $tdbLoader $arguments 2>&1
        }
        
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        # 결과 분석 (TDB2 로더 출력 파싱)
        $tripleCount = 0
        if ($result -match "(\d+) triples") {
            $tripleCount = [int]$matches[1]
        } elseif ($result -match "(\d+) tuples") {
            $tripleCount = [int]$matches[1]
        }
        
        Write-Host "✅ Loaded successfully" -ForegroundColor Green
        Write-Host "   Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor White
        if ($tripleCount -gt 0) {
            Write-Host "   Triples: $tripleCount" -ForegroundColor White
            Write-Host "   Rate: $([math]::Round($tripleCount / $duration, 0)) triples/sec" -ForegroundColor White
        }
        
        $successCount++
        $loadResults += @{
            File = $file.Name
            Status = "SUCCESS"
            Duration = $duration
            Triples = $tripleCount
            Error = $null
        }
        
    } catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        Write-Host "❌ Loading failed" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        
        $errorCount++
        $loadResults += @{
            File = $file.Name
            Status = "ERROR"
            Duration = $duration
            Triples = 0
            Error = $_.Exception.Message
        }
        
        if (-not $Force) {
            Write-Error "Stopping due to error. Use -Force to continue on errors."
            exit 1
        }
    }
}

$totalEndTime = Get-Date
$totalDuration = ($totalEndTime - $totalStartTime).TotalSeconds

# 5. 결과 요약
Write-Host "`n=== Loading Summary ===" -ForegroundColor Green
Write-Host "Total files: $($ttlFiles.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $errorCount" -ForegroundColor Red
Write-Host "Total duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White

$totalTriples = ($loadResults | Where-Object {$_.Status -eq "SUCCESS"} | Measure-Object -Property Triples -Sum).Sum
if ($totalTriples -gt 0) {
    Write-Host "Total triples loaded: $totalTriples" -ForegroundColor White
    Write-Host "Average rate: $([math]::Round($totalTriples / $totalDuration, 0)) triples/sec" -ForegroundColor White
}

# 상세 결과
Write-Host "`n=== Detailed Results ===" -ForegroundColor Cyan
foreach ($result in $loadResults) {
    $status = if ($result.Status -eq "SUCCESS") { "✅" } else { "❌" }
    Write-Host "$status $($result.File) - $([math]::Round($result.Duration, 2))s" -ForegroundColor White
    
    if ($result.Status -eq "SUCCESS" -and $result.Triples -gt 0) {
        Write-Host "     $($result.Triples) triples" -ForegroundColor Gray
    } elseif ($result.Status -eq "ERROR") {
        Write-Host "     Error: $($result.Error)" -ForegroundColor Red
    }
}

# 6. 후속 작업 안내
Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. Start Fuseki server:" -ForegroundColor White
Write-Host "   .\start-hvdc-fuseki.bat" -ForegroundColor Gray
Write-Host "2. Validate data:" -ForegroundColor White  
Write-Host "   .\scripts\hvdc-named-graph-manager.ps1 -Action validate" -ForegroundColor Gray
Write-Host "3. Run health check:" -ForegroundColor White
Write-Host "   Invoke-WebRequest http://localhost:3030/$/ping" -ForegroundColor Gray

if ($errorCount -gt 0) {
    Write-Host "`n⚠️  Some files failed to load. Check errors above." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n🎉 Batch loading completed successfully!" -ForegroundColor Green
    exit 0
}
