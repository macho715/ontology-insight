# HVDC Ontology Insight - Query Runner Script (PowerShell)
# SPARQL 쿼리 실행 및 결과 처리 자동화

param(
    [string]$FusekiUrl = "http://localhost:3030/hvdc",
    [string]$QueryFile,
    [string]$OutputFormat = "json",  # json, csv, xml, tsv
    [string]$OutputFile,
    [switch]$ShowResults,
    [switch]$AllQueries
)

Write-Host "=== HVDC Query Runner ===" -ForegroundColor Green

# Accept 헤더 설정
$acceptHeaders = @{
    "json" = "application/sparql-results+json"
    "csv"  = "text/csv"
    "xml"  = "application/sparql-results+xml"
    "tsv"  = "text/tab-separated-values"
}

if (-not $acceptHeaders.ContainsKey($OutputFormat)) {
    Write-Error "지원하지 않는 출력 형식: $OutputFormat (지원: json, csv, xml, tsv)"
    exit 1
}

# 1. 모든 쿼리 실행 (AllQueries 옵션)
if ($AllQueries) {
    Write-Host "모든 쿼리 실행 중..." -ForegroundColor Yellow
    
    $queryFiles = Get-ChildItem -Path "queries" -Filter "*.rq" | Sort-Object Name
    
    foreach ($qFile in $queryFiles) {
        Write-Host "`n--- $($qFile.Name) ---" -ForegroundColor Cyan
        
        try {
            $query = Get-Content -Path $qFile.FullName -Raw -Encoding UTF8
            $result = Invoke-RestMethod -Uri "$FusekiUrl/sparql" -Method Post -Body @{ query = $query } -ContentType "application/x-www-form-urlencoded" -Headers @{ Accept = $acceptHeaders["json"] }
            
            $resultCount = $result.results.bindings.Count
            Write-Host "✓ 결과: $resultCount 행" -ForegroundColor Green
            
            # 결과 미리보기 (첫 3행)
            if ($resultCount -gt 0) {
                $vars = $result.head.vars
                Write-Host "컬럼: $($vars -join ', ')" -ForegroundColor Gray
                
                for ($i = 0; $i -lt [Math]::Min(3, $resultCount); $i++) {
                    $row = $result.results.bindings[$i]
                    $values = @()
                    foreach ($var in $vars) {
                        if ($row.$var) {
                            $values += $row.$var.value
                        } else {
                            $values += "NULL"
                        }
                    }
                    Write-Host "  $($values -join ' | ')" -ForegroundColor White
                }
                
                if ($resultCount -gt 3) {
                    Write-Host "  ... ($($resultCount - 3) 행 더 있음)" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Warning "✗ 쿼리 실행 실패: $($_.Exception.Message)"
        }
    }
    
    Write-Host "`n=== 모든 쿼리 실행 완료 ===" -ForegroundColor Green
    exit 0
}

# 2. 단일 쿼리 실행
if (-not $QueryFile) {
    Write-Error "쿼리 파일을 지정해주세요: -QueryFile queries/01-monthly-warehouse-stock.rq"
    Write-Host "`n사용 가능한 쿼리:" -ForegroundColor Cyan
    Get-ChildItem -Path "queries" -Filter "*.rq" | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor White }
    exit 1
}

if (-not (Test-Path $QueryFile)) {
    Write-Error "쿼리 파일을 찾을 수 없습니다: $QueryFile"
    exit 1
}

Write-Host "쿼리 파일: $QueryFile" -ForegroundColor Yellow
Write-Host "출력 형식: $OutputFormat" -ForegroundColor Yellow

# 3. 쿼리 실행
try {
    $query = Get-Content -Path $QueryFile -Raw -Encoding UTF8
    Write-Host "쿼리 실행 중..." -ForegroundColor Yellow
    
    $startTime = Get-Date
    $result = Invoke-RestMethod -Uri "$FusekiUrl/sparql" -Method Post -Body @{ query = $query } -ContentType "application/x-www-form-urlencoded" -Headers @{ Accept = $acceptHeaders[$OutputFormat] }
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalMilliseconds
    
    Write-Host "✓ 쿼리 실행 완료 ($([math]::Round($duration, 2))ms)" -ForegroundColor Green
    
} catch {
    Write-Error "✗ 쿼리 실행 실패: $($_.Exception.Message)"
    exit 1
}

# 4. 결과 처리
if ($OutputFormat -eq "json") {
    $resultCount = $result.results.bindings.Count
    Write-Host "결과: $resultCount 행" -ForegroundColor Green
    
    if ($ShowResults -and $resultCount -gt 0) {
        Write-Host "`n=== 쿼리 결과 ===" -ForegroundColor Cyan
        $result.results.bindings | ForEach-Object {
            $row = $_
            Write-Host "---" -ForegroundColor Gray
            $result.head.vars | ForEach-Object {
                $var = $_
                if ($row.$var) {
                    Write-Host "  $var`: $($row.$var.value)" -ForegroundColor White
                }
            }
        }
    }
    
    # JSON 결과를 파일로 저장
    if ($OutputFile) {
        $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "✓ 결과 저장: $OutputFile" -ForegroundColor Green
    }
} else {
    # CSV, XML, TSV 등의 경우 직접 저장
    if ($OutputFile) {
        $result | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "✓ 결과 저장: $OutputFile ($OutputFormat)" -ForegroundColor Green
    } else {
        Write-Host "`n=== 쿼리 결과 ($OutputFormat) ===" -ForegroundColor Cyan
        Write-Host $result -ForegroundColor White
    }
}

Write-Host "`n=== 쿼리 실행 완료 ===" -ForegroundColor Green

# 5. 사용 예시 출력
if (-not $OutputFile) {
    Write-Host "`n결과를 파일로 저장하려면:" -ForegroundColor Cyan
    Write-Host "  .\scripts\hvdc-query-runner.ps1 -QueryFile $QueryFile -OutputFile results.json" -ForegroundColor White
    Write-Host "  .\scripts\hvdc-query-runner.ps1 -QueryFile $QueryFile -OutputFormat csv -OutputFile results.csv" -ForegroundColor White
}
