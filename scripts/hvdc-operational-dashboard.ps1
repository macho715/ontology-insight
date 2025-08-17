# HVDC Operational Dashboard - 운영 KPI 실시간 모니터링
# HS/OOG Risk, DEM/DET KPI, 비용 효율성 대시보드

param(
    [string]$BaseUrl = "http://localhost:3030",
    [string]$Dataset = "hvdc",
    [string]$ReportType = "summary",  # summary, hsrisk, oog, demdet, cost, alerts
    [string]$OutputFormat = "console", # console, csv, json
    [string]$OutputFile = "",
    [string]$DateFrom = "",
    [string]$DateTo = "",
    [switch]$RealTime,
    [int]$RefreshInterval = 30
)

$SparqlUrl = "$BaseUrl/$Dataset/sparql"
$PingUrl = "$BaseUrl/$/ping"

Write-Host "=== HVDC Operational Dashboard ===" -ForegroundColor Green
Write-Host "Report Type: $ReportType" -ForegroundColor Cyan
Write-Host "Output Format: $OutputFormat" -ForegroundColor Cyan

# 헬스체크
try {
    $response = Invoke-WebRequest -Uri $PingUrl -TimeoutSec 5
    Write-Host "✅ Fuseki server healthy: $($response.Content.Trim())" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server not accessible"
    exit 1
}

# 쿼리 템플릿 정의
$OPERATIONAL_QUERIES = @{
    "summary" = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT 
  (COUNT(DISTINCT ?case) AS ?totalCases)
  (COUNT(DISTINCT ?hsRisk) AS ?highRiskHS)
  (COUNT(DISTINCT ?oogCase) AS ?oogCases)
  (AVG(?demCost) AS ?avgDemurrage)
  (AVG(?detCost) AS ?avgDetention)
WHERE {
  GRAPH ?g {
    ?case a ex:Case .
    
    OPTIONAL {
      ?case ex:hsCode ?hs .
      ?hs ex:riskLevel ?risk .
      FILTER(?risk IN ("HIGH", "CRITICAL"))
      BIND(?case AS ?hsRisk)
    }
    
    OPTIONAL {
      ?case ex:packageWeight ?weight .
      FILTER(?weight > 30000)
      BIND(?case AS ?oogCase)
    }
    
    OPTIONAL { ?case ex:demurrageCost ?demCost . FILTER(?demCost > 0) }
    OPTIONAL { ?case ex:detentionCost ?detCost . FILTER(?detCost > 0) }
  }
}
"@

    "hsrisk" = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?hsCode ?hsDescription ?riskLevel (COUNT(?case) AS ?caseCount) (SUM(?value) AS ?totalValue)
WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:hsCode ?hsCode ;
          ex:invoiceValue ?value .
    
    ?hsCode ex:hsDescription ?hsDescription ;
            ex:riskLevel ?riskLevel .
    
    FILTER(?riskLevel IN ("HIGH", "CRITICAL"))
  }
}
GROUP BY ?hsCode ?hsDescription ?riskLevel
ORDER BY DESC(?totalValue) DESC(?caseCount)
LIMIT 20
"@

    "oog" = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?caseCode ?weight ?length ?width ?height ?oogType ?handlingCost
WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:caseCode ?caseCode ;
          ex:packageWeight ?weight ;
          ex:packageLength ?length ;
          ex:packageWidth ?width ;
          ex:packageHeight ?height ;
          ex:oogType ?oogType ;
          ex:handlingCost ?handlingCost .
    
    FILTER(?weight > 30000 || ?length > 12.0 || ?width > 2.4 || ?height > 2.6)
  }
}
ORDER BY DESC(?weight) DESC(?length)
LIMIT 50
"@

    "demdet" = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?yearMonth 
       (COUNT(?case) AS ?totalCases)
       (AVG(?demCost) AS ?avgDemurrage)
       (AVG(?detCost) AS ?avgDetention)
       (AVG(?demDays) AS ?avgDemDays)
       (AVG(?detDays) AS ?avgDetDays)
WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:arrivalDate ?arrivalDate .
    
    BIND(SUBSTR(STR(?arrivalDate), 1, 7) AS ?yearMonth)
    
    OPTIONAL { ?case ex:demurrageCost ?demCost . FILTER(?demCost > 0) }
    OPTIONAL { ?case ex:detentionCost ?detCost . FILTER(?detCost > 0) }
    OPTIONAL { ?case ex:demurrageDays ?demDays . FILTER(?demDays > 0) }
    OPTIONAL { ?case ex:detentionDays ?detDays . FILTER(?detDays > 0) }
  }
}
GROUP BY ?yearMonth
ORDER BY ?yearMonth
"@

    "cost" = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?origin ?destination 
       (COUNT(?case) AS ?caseCount)
       (AVG(?totalCost) AS ?avgCost)
       (AVG(?costPerTEU) AS ?avgCostPerTEU)
WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:originPort ?origin ;
          ex:destinationPort ?destination ;
          ex:totalLogisticsCost ?totalCost ;
          ex:teuEquivalent ?teu .
    
    BIND(?totalCost / ?teu AS ?costPerTEU)
    FILTER(?teu > 0)
  }
}
GROUP BY ?origin ?destination
ORDER BY DESC(?avgCostPerTEU)
LIMIT 20
"@

    "alerts" = @"
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?caseCode ?status ?priority ?alertReason ?daysOverdue ?expectedDate
WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:caseCode ?caseCode ;
          ex:currentStatus ?status ;
          ex:priority ?priority ;
          ex:expectedDate ?expectedDate .
    
    BIND((NOW() - ?expectedDate) / (60*60*24) AS ?daysOverdue)
    
    OPTIONAL { ?case ex:alertReason ?alertReason }
    
    FILTER(
      ?priority IN ("HIGH", "CRITICAL") ||
      ?daysOverdue > 3 ||
      ?status IN ("DELAYED", "EXCEPTION", "HOLD")
    )
  }
}
ORDER BY DESC(?priority) DESC(?daysOverdue)
LIMIT 30
"@
}

function Execute-SparqlQuery {
    param($Query, $QueryName)
    
    try {
        Write-Host "`nExecuting: $QueryName..." -ForegroundColor Yellow
        
        $startTime = Get-Date
        $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$Query" $SparqlUrl
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        $jsonResult = $curlResult | ConvertFrom-Json -ErrorAction Stop
        
        Write-Host "✅ Query completed in $([math]::Round($duration, 0))ms" -ForegroundColor Green
        
        return $jsonResult.results.bindings
        
    } catch {
        Write-Host "❌ Query failed: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Format-Results {
    param($Results, $ReportType, $OutputFormat)
    
    if (-not $Results -or $Results.Count -eq 0) {
        Write-Host "No results found" -ForegroundColor Yellow
        return
    }
    
    switch ($OutputFormat.ToLower()) {
        "console" {
            Format-ConsoleOutput -Results $Results -ReportType $ReportType
        }
        "csv" {
            Format-CsvOutput -Results $Results -ReportType $ReportType
        }
        "json" {
            Format-JsonOutput -Results $Results -ReportType $ReportType
        }
    }
}

function Format-ConsoleOutput {
    param($Results, $ReportType)
    
    Write-Host "`n=== $($ReportType.ToUpper()) REPORT ===" -ForegroundColor Cyan
    
    switch ($ReportType) {
        "summary" {
            foreach ($result in $Results) {
                Write-Host "📊 OPERATIONAL SUMMARY" -ForegroundColor White
                Write-Host "   Total Cases: $($result.totalCases.value)" -ForegroundColor White
                Write-Host "   High-Risk HS: $($result.highRiskHS.value)" -ForegroundColor Yellow
                Write-Host "   OOG Cases: $($result.oogCases.value)" -ForegroundColor Yellow
                
                if ($result.avgDemurrage.value) {
                    $avgDem = [math]::Round([double]$result.avgDemurrage.value, 2)
                    Write-Host "   Avg Demurrage: `$$avgDem" -ForegroundColor Red
                }
                
                if ($result.avgDetention.value) {
                    $avgDet = [math]::Round([double]$result.avgDetention.value, 2)
                    Write-Host "   Avg Detention: `$$avgDet" -ForegroundColor Red
                }
            }
        }
        
        "hsrisk" {
            Write-Host "🚨 HIGH-RISK HS CODES:" -ForegroundColor Red
            foreach ($result in $Results) {
                $value = if ($result.totalValue.value) { [math]::Round([double]$result.totalValue.value, 0) } else { 0 }
                Write-Host "   $($result.hsCode.value) ($($result.riskLevel.value)): $($result.caseCount.value) cases, `$$value" -ForegroundColor White
                Write-Host "     $($result.hsDescription.value)" -ForegroundColor Gray
            }
        }
        
        "oog" {
            Write-Host "📦 OUT-OF-GAUGE CASES:" -ForegroundColor Yellow
            foreach ($result in $Results) {
                $weight = [math]::Round([double]$result.weight.value, 1)
                $cost = if ($result.handlingCost.value) { [math]::Round([double]$result.handlingCost.value, 0) } else { 0 }
                Write-Host "   $($result.caseCode.value): ${weight}kg, $($result.oogType.value), `$$cost" -ForegroundColor White
                
                if ($result.length.value) {
                    $dims = "$($result.length.value) x $($result.width.value) x $($result.height.value)m"
                    Write-Host "     Dimensions: $dims" -ForegroundColor Gray
                }
            }
        }
        
        "demdet" {
            Write-Host "💰 DEMURRAGE & DETENTION TRENDS:" -ForegroundColor Red
            foreach ($result in $Results) {
                $avgDem = if ($result.avgDemurrage.value) { [math]::Round([double]$result.avgDemurrage.value, 0) } else { 0 }
                $avgDet = if ($result.avgDetention.value) { [math]::Round([double]$result.avgDetention.value, 0) } else { 0 }
                Write-Host "   $($result.yearMonth.value): $($result.totalCases.value) cases, Dem: `$$avgDem, Det: `$$avgDet" -ForegroundColor White
            }
        }
        
        "cost" {
            Write-Host "💵 COST EFFICIENCY BY ROUTE:" -ForegroundColor Green
            foreach ($result in $Results) {
                $avgCost = [math]::Round([double]$result.avgCost.value, 0)
                $costPerTEU = [math]::Round([double]$result.avgCostPerTEU.value, 0)
                Write-Host "   $($result.origin.value) → $($result.destination.value): $($result.caseCount.value) cases" -ForegroundColor White
                Write-Host "     Avg Cost: `$$avgCost, Cost/TEU: `$$costPerTEU" -ForegroundColor Gray
            }
        }
        
        "alerts" {
            Write-Host "🚨 ACTIVE ALERTS:" -ForegroundColor Red
            foreach ($result in $Results) {
                $daysOverdue = if ($result.daysOverdue.value) { [math]::Round([double]$result.daysOverdue.value, 1) } else { 0 }
                $priority = $result.priority.value
                $status = $result.status.value
                
                $priorityColor = switch ($priority) {
                    "CRITICAL" { "Red" }
                    "HIGH" { "Yellow" }
                    default { "White" }
                }
                
                Write-Host "   $($result.caseCode.value) ($priority): $status" -ForegroundColor $priorityColor
                if ($daysOverdue -gt 0) {
                    Write-Host "     Overdue: $daysOverdue days" -ForegroundColor Red
                }
                if ($result.alertReason.value) {
                    Write-Host "     Reason: $($result.alertReason.value)" -ForegroundColor Gray
                }
            }
        }
    }
}

function Format-CsvOutput {
    param($Results, $ReportType)
    
    if (-not $OutputFile) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $OutputFile = "reports\hvdc_${ReportType}_$timestamp.csv"
    }
    
    # CSV 헤더 생성
    if ($Results.Count -gt 0) {
        $headers = $Results[0].PSObject.Properties.Name | ForEach-Object { $_.Split('.')[0] }
        $csvHeaders = $headers -join ','
        
        # CSV 데이터 생성
        $csvData = @()
        $csvData += $csvHeaders
        
        foreach ($result in $Results) {
            $row = @()
            foreach ($header in $headers) {
                $value = $result.$header.value
                if ($value -match '^\d+\.?\d*$') {
                    $row += $value
                } else {
                    $row += "`"$value`""
                }
            }
            $csvData += ($row -join ',')
        }
        
        # 출력 디렉토리 생성
        $outputDir = Split-Path $OutputFile -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        $csvData | Set-Content -Path $OutputFile -Encoding UTF8
        Write-Host "📄 CSV report saved: $OutputFile" -ForegroundColor Cyan
    }
}

function Format-JsonOutput {
    param($Results, $ReportType)
    
    if (-not $OutputFile) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $OutputFile = "reports\hvdc_${ReportType}_$timestamp.json"
    }
    
    $jsonOutput = @{
        reportType = $ReportType
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        resultCount = $Results.Count
        data = $Results
    }
    
    # 출력 디렉토리 생성
    $outputDir = Split-Path $OutputFile -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $jsonOutput | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "📄 JSON report saved: $OutputFile" -ForegroundColor Cyan
}

# 메인 실행 로직
do {
    if ($RealTime -and $iteration -gt 1) {
        Clear-Host
    }
    
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Generating $ReportType report..." -ForegroundColor Gray
    
    if ($OPERATIONAL_QUERIES.ContainsKey($ReportType)) {
        $query = $OPERATIONAL_QUERIES[$ReportType]
        $results = Execute-SparqlQuery -Query $query -QueryName $ReportType
        Format-Results -Results $results -ReportType $ReportType -OutputFormat $OutputFormat
    } else {
        Write-Error "Invalid report type: $ReportType"
        Write-Host "Valid types: $($OPERATIONAL_QUERIES.Keys -join ', ')" -ForegroundColor Cyan
        exit 1
    }
    
    if ($RealTime) {
        Write-Host "`nNext refresh in $RefreshInterval seconds... (Ctrl+C to stop)" -ForegroundColor Gray
        Start-Sleep $RefreshInterval
    }
    
} while ($RealTime)

Write-Host "`n=== Dashboard completed ===" -ForegroundColor Green
