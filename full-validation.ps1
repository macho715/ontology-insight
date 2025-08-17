# HVDC Ontology Insight - Full Validation Script
# 완전 검증: 데이터 적재 + 4가지 핵심 SPARQL 쿼리 실행 + 결과 검증

param(
    [string]$FusekiUrl = "http://localhost:3030/hvdc",
    [switch]$ReloadData,
    [switch]$DetailedReport
)

Write-Host "=== HVDC Ontology Insight - Full Validation ===" -ForegroundColor Green

$validationResults = @()
$allPassed = $true

function Add-ValidationResult {
    param($Component, $Status, $Message, $Details = $null)
    $script:validationResults += @{
        Component = $Component
        Status = $Status
        Message = $Message
        Details = $Details
        Timestamp = Get-Date
    }
    
    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        "INFO" { "Cyan" }
    }
    
    Write-Host "[$Status] $Component`: $Message" -ForegroundColor $color
    if ($Details -and $DetailedReport) {
        Write-Host "    Details: $Details" -ForegroundColor Gray
    }
    
    if ($Status -eq "FAIL") {
        $script:allPassed = $false
    }
}

# Step 1: Pre-flight Checks
Write-Host "`n=== Pre-flight Checks ===" -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri "$FusekiUrl" -Method GET -TimeoutSec 10 -UseBasicParsing
    Add-ValidationResult "Server Status" "PASS" "Fuseki server responding (HTTP $($response.StatusCode))"
} catch {
    Add-ValidationResult "Server Status" "FAIL" "Fuseki server not accessible: $($_.Exception.Message)"
    exit 1
}

# Step 2: Data Loading (if requested)
if ($ReloadData) {
    Write-Host "`n=== Data Reloading ===" -ForegroundColor Yellow
    
    try {
        # Delete existing data
        Write-Host "Clearing existing data..." -ForegroundColor Gray
        Invoke-RestMethod -Uri "$FusekiUrl/data?default" -Method Delete -ErrorAction SilentlyContinue
        
        # Load TTL data
        Write-Host "Loading triples.ttl..." -ForegroundColor Gray
        $ttlContent = Get-Content -Path "triples.ttl" -Raw -Encoding UTF8
        Invoke-RestMethod -Uri "$FusekiUrl/data?default" -Method Post -Body $ttlContent -ContentType "text/turtle; charset=utf-8"
        
        Add-ValidationResult "Data Loading" "PASS" "TTL data successfully loaded"
    } catch {
        Add-ValidationResult "Data Loading" "FAIL" "Failed to load TTL data: $($_.Exception.Message)"
    }
}

# Step 3: Basic Data Verification
Write-Host "`n=== Basic Data Verification ===" -ForegroundColor Yellow

try {
    $countQuery = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
    $result = Invoke-RestMethod -Uri "$FusekiUrl/sparql" -Method Post -Body @{ query = $countQuery } -ContentType "application/x-www-form-urlencoded"
    $tripleCount = [int]$result.results.bindings[0].count.value
    
    if ($tripleCount -gt 0) {
        Add-ValidationResult "Triple Count" "PASS" "$tripleCount triples loaded"
    } else {
        Add-ValidationResult "Triple Count" "FAIL" "No triples found in database"
    }
} catch {
    Add-ValidationResult "Triple Count" "FAIL" "Failed to count triples: $($_.Exception.Message)"
}

# Step 4: Class Instance Verification
Write-Host "`n=== Class Instance Verification ===" -ForegroundColor Yellow

$classCountQuery = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?class (COUNT(?instance) AS ?count) WHERE {
  ?instance a ?class .
  FILTER(STRSTARTS(STR(?class), "http://samsung.com/project-logistics#"))
}
GROUP BY ?class
ORDER BY DESC(?count)
"@

try {
    $result = Invoke-RestMethod -Uri "$FusekiUrl/sparql" -Method Post -Body @{ query = $classCountQuery } -ContentType "application/x-www-form-urlencoded"
    
    $expectedClasses = @{
        "StockSnapshot" = 5
        "TransportEvent" = 7
        "CargoItem" = 4
        "Invoice" = 4
        "Case" = 3
        "HSCode" = 3
    }
    
    $foundClasses = @{}
    foreach ($binding in $result.results.bindings) {
        $className = $binding.class.value -replace "http://samsung.com/project-logistics#", ""
        $count = [int]$binding.count.value
        $foundClasses[$className] = $count
        
        if ($DetailedReport) {
            Write-Host "  $className`: $count instances" -ForegroundColor Gray
        }
    }
    
    foreach ($expectedClass in $expectedClasses.Keys) {
        $expectedCount = $expectedClasses[$expectedClass]
        if ($foundClasses.ContainsKey($expectedClass)) {
            $actualCount = $foundClasses[$expectedClass]
            if ($actualCount -ge $expectedCount) {
                Add-ValidationResult "Class $expectedClass" "PASS" "$actualCount instances (expected ≥$expectedCount)"
            } else {
                Add-ValidationResult "Class $expectedClass" "WARN" "$actualCount instances (expected ≥$expectedCount)"
            }
        } else {
            Add-ValidationResult "Class $expectedClass" "FAIL" "No instances found (expected ≥$expectedCount)"
        }
    }
} catch {
    Add-ValidationResult "Class Verification" "FAIL" "Failed to verify class instances: $($_.Exception.Message)"
}

# Step 5: Core SPARQL Query Validation
Write-Host "`n=== Core SPARQL Query Validation ===" -ForegroundColor Yellow

$coreQueries = @(
    @{
        Name = "Monthly Warehouse Stock"
        File = "queries\01-monthly-warehouse-stock.rq"
        ExpectedMinRows = 3
        Description = "월별/창고별 재고 분석"
    },
    @{
        Name = "Case Timeline Events"
        File = "queries\02-case-timeline-events.rq"
        ExpectedMinRows = 5
        Description = "케이스 타임라인 및 FINAL_OUT 추적"
    },
    @{
        Name = "Invoice Risk Analysis"
        File = "queries\03-invoice-risk-analysis.rq"
        ExpectedMinRows = 2
        Description = "Invoice 리스크 분석"
    },
    @{
        Name = "OOG HS Risk Assessment"
        File = "queries\04-oog-hs-risk-assessment.rq"
        ExpectedMinRows = 4
        Description = "OOG 및 HS Code 리스크 평가"
    }
)

foreach ($queryTest in $coreQueries) {
    try {
        if (-not (Test-Path $queryTest.File)) {
            Add-ValidationResult $queryTest.Name "FAIL" "Query file not found: $($queryTest.File)"
            continue
        }
        
        $query = Get-Content -Path $queryTest.File -Raw -Encoding UTF8
        $startTime = Get-Date
        $result = Invoke-RestMethod -Uri "$FusekiUrl/sparql" -Method Post -Body @{ query = $query } -ContentType "application/x-www-form-urlencoded" -Headers @{ Accept = "application/sparql-results+json" }
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $resultCount = $result.results.bindings.Count
        
        if ($resultCount -ge $queryTest.ExpectedMinRows) {
            Add-ValidationResult $queryTest.Name "PASS" "$resultCount rows returned ($([math]::Round($duration, 2))ms)" $queryTest.Description
            
            # Show sample results for detailed report
            if ($DetailedReport -and $resultCount -gt 0) {
                Write-Host "    Sample results:" -ForegroundColor Gray
                $vars = $result.head.vars
                for ($i = 0; $i -lt [Math]::Min(2, $resultCount); $i++) {
                    $row = $result.results.bindings[$i]
                    $values = @()
                    foreach ($var in $vars) {
                        if ($row.$var) {
                            $values += "$var=$($row.$var.value)"
                        }
                    }
                    Write-Host "      Row $($i+1): $($values -join ', ')" -ForegroundColor DarkGray
                }
            }
        } else {
            Add-ValidationResult $queryTest.Name "FAIL" "Only $resultCount rows returned (expected ≥$($queryTest.ExpectedMinRows))"
        }
    } catch {
        Add-ValidationResult $queryTest.Name "FAIL" "Query execution failed: $($_.Exception.Message)"
    }
}

# Step 6: Automation Scripts Test
Write-Host "`n=== Automation Scripts Test ===" -ForegroundColor Yellow

$scripts = @(
    "scripts\hvdc-data-loader.ps1",
    "scripts\hvdc-query-runner.ps1"
)

foreach ($script in $scripts) {
    if (Test-Path $script) {
        try {
            # Test script syntax by parsing it
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$null)
            Add-ValidationResult "Script $(Split-Path $script -Leaf)" "PASS" "PowerShell syntax valid"
        } catch {
            Add-ValidationResult "Script $(Split-Path $script -Leaf)" "FAIL" "PowerShell syntax error: $($_.Exception.Message)"
        }
    } else {
        Add-ValidationResult "Script $(Split-Path $script -Leaf)" "FAIL" "Script file not found"
    }
}

# Final Report
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan

$passCount = ($validationResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($validationResults | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($validationResults | Where-Object { $_.Status -eq "WARN" }).Count

Write-Host "Results: $passCount PASS, $failCount FAIL, $warnCount WARN" -ForegroundColor White

if ($DetailedReport) {
    Write-Host "`nDetailed Results:" -ForegroundColor Gray
    foreach ($result in $validationResults) {
        $color = switch ($result.Status) {
            "PASS" { "Green" }
            "FAIL" { "Red" }
            "WARN" { "Yellow" }
            "INFO" { "Cyan" }
        }
        Write-Host "  [$($result.Status)] $($result.Component): $($result.Message)" -ForegroundColor $color
    }
}

if ($allPassed) {
    Write-Host "`n🎉 FULL VALIDATION PASSED!" -ForegroundColor Green
    Write-Host "✅ HVDC Ontology Insight system is fully operational" -ForegroundColor Green
    Write-Host "`nSystem Ready For:" -ForegroundColor Cyan
    Write-Host "  • Monthly warehouse stock analysis" -ForegroundColor White
    Write-Host "  • Case timeline and FINAL_OUT tracking" -ForegroundColor White
    Write-Host "  • Invoice risk detection" -ForegroundColor White
    Write-Host "  • OOG and HS code risk assessment" -ForegroundColor White
    Write-Host "`nWeb Interface: $FusekiUrl" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`n❌ VALIDATION FAILED" -ForegroundColor Red
    Write-Host "Please review the failed components above and take corrective action." -ForegroundColor Yellow
    exit 1
}
