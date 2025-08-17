# HVDC Ontology Insight - Smoke Test Script
# 연기 테스트: Fuseki + SPARQL 환경 기본 동작 검증

param(
    [string]$FusekiUrl = "http://localhost:3030/hvdc",
    [int]$TimeoutSeconds = 30
)

Write-Host "=== HVDC Ontology Insight - Smoke Test ===" -ForegroundColor Green
Write-Host "Target: $FusekiUrl" -ForegroundColor Cyan
Write-Host "Timeout: $TimeoutSeconds seconds" -ForegroundColor Cyan

$testResults = @()
$allPassed = $true

# Test Function
function Test-Component {
    param($Name, $TestBlock)
    Write-Host "`n--- Testing: $Name ---" -ForegroundColor Yellow
    try {
        $result = & $TestBlock
        if ($result) {
            Write-Host "✓ PASS: $Name" -ForegroundColor Green
            $script:testResults += @{Name=$Name; Status="PASS"; Message=$result}
        } else {
            Write-Host "✗ FAIL: $Name" -ForegroundColor Red
            $script:testResults += @{Name=$Name; Status="FAIL"; Message="Test returned false"}
            $script:allPassed = $false
        }
    } catch {
        Write-Host "✗ ERROR: $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:testResults += @{Name=$Name; Status="ERROR"; Message=$_.Exception.Message}
        $script:allPassed = $false
    }
}

# Test 1: Java Runtime Check
Test-Component "Java Runtime" {
    $javaVersion = java -version 2>&1 | Select-String "version" | ForEach-Object { $_.ToString() }
    if ($javaVersion) {
        Write-Host "  Java: $javaVersion" -ForegroundColor White
        return "Java available: $javaVersion"
    }
    throw "Java not found in PATH"
}

# Test 2: Fuseki Server Connectivity
Test-Component "Fuseki Server Connectivity" {
    $response = Invoke-WebRequest -Uri "$FusekiUrl" -Method GET -TimeoutSec $TimeoutSeconds -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "  Status: $($response.StatusCode)" -ForegroundColor White
        Write-Host "  Content-Length: $($response.Content.Length) bytes" -ForegroundColor White
        return "Server responding on port 3030"
    }
    throw "Server not responding"
}

# Test 3: SPARQL Endpoint Check
Test-Component "SPARQL Endpoint" {
    $testQuery = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
    $response = Invoke-RestMethod -Uri "$FusekiUrl/sparql" -Method Post -Body @{ query = $testQuery } -ContentType "application/x-www-form-urlencoded" -TimeoutSec $TimeoutSeconds
    
    if ($response.results -and $response.results.bindings) {
        $tripleCount = $response.results.bindings[0].count.value
        Write-Host "  Triple count: $tripleCount" -ForegroundColor White
        return "SPARQL endpoint working, $tripleCount triples"
    }
    throw "SPARQL endpoint not responding correctly"
}

# Test 4: Graph Store Protocol (Data Endpoint)
Test-Component "Graph Store Protocol" {
    try {
        # Try to access the data endpoint
        $response = Invoke-WebRequest -Uri "$FusekiUrl/data?default" -Method GET -TimeoutSec $TimeoutSeconds -UseBasicParsing
        Write-Host "  Data endpoint accessible" -ForegroundColor White
        return "Graph Store Protocol endpoint available"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Host "  Data endpoint returns 404 (normal for empty graph)" -ForegroundColor Gray
            return "Graph Store Protocol endpoint available (empty)"
        }
        throw $_.Exception.Message
    }
}

# Test 5: TTL File Existence
Test-Component "TTL Data File" {
    if (Test-Path "triples.ttl") {
        $fileSize = (Get-Item "triples.ttl").Length
        Write-Host "  File size: $([math]::Round($fileSize/1KB, 2)) KB" -ForegroundColor White
        return "TTL file available ($fileSize bytes)"
    }
    throw "triples.ttl not found"
}

# Test 6: Query Files Existence
Test-Component "SPARQL Query Templates" {
    $queryFiles = Get-ChildItem -Path "queries" -Filter "*.rq" -ErrorAction SilentlyContinue
    if ($queryFiles.Count -ge 4) {
        Write-Host "  Found query files:" -ForegroundColor White
        $queryFiles | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Gray }
        return "Found $($queryFiles.Count) query templates"
    }
    throw "Expected 4+ query files in queries/ directory"
}

# Test 7: Automation Scripts
Test-Component "Automation Scripts" {
    $scripts = @("scripts\hvdc-data-loader.ps1", "scripts\hvdc-query-runner.ps1")
    $foundScripts = @()
    
    foreach ($script in $scripts) {
        if (Test-Path $script) {
            $foundScripts += $script
        }
    }
    
    if ($foundScripts.Count -eq $scripts.Count) {
        Write-Host "  All automation scripts present" -ForegroundColor White
        return "All $($scripts.Count) automation scripts available"
    }
    throw "Missing automation scripts: $($scripts.Count - $foundScripts.Count) of $($scripts.Count)"
}

# Summary Report
Write-Host "`n=== Smoke Test Results ===" -ForegroundColor Cyan
foreach ($result in $testResults) {
    $color = switch ($result.Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "ERROR" { "Magenta" }
    }
    Write-Host "$($result.Status.PadRight(5)) | $($result.Name)" -ForegroundColor $color
    Write-Host "       | $($result.Message)" -ForegroundColor Gray
}

Write-Host "`n=== Overall Result ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "🎉 ALL TESTS PASSED - System Ready!" -ForegroundColor Green
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Load data: .\scripts\hvdc-data-loader.ps1 -Force -Validate" -ForegroundColor White
    Write-Host "2. Run queries: .\scripts\hvdc-query-runner.ps1 -AllQueries" -ForegroundColor White
    Write-Host "3. Web UI: $FusekiUrl" -ForegroundColor White
    exit 0
} else {
    Write-Host "❌ SOME TESTS FAILED - Check issues above" -ForegroundColor Red
    Write-Host "`nCommon Solutions:" -ForegroundColor Yellow
    Write-Host "- Java not installed: See install-java.md" -ForegroundColor White
    Write-Host "- Server not running: .\start-hvdc-fuseki.bat" -ForegroundColor White
    Write-Host "- Port conflict: Check if port 3030 is available" -ForegroundColor White
    exit 1
}
