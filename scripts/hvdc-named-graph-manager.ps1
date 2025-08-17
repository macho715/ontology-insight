# HVDC Named Graph Manager - 소스별 그래프 분리 관리
# GSP Named Graph 기반 OFCO/DSV/PKGS/PAY 분리 운영

param(
    [string]$BaseUrl = "http://localhost:3030",
    [string]$Dataset = "hvdc",
    [string]$Action = "upload",  # upload, delete, list, validate
    [string]$Source = "",        # OFCO, DSV, PKGS, PAY
    [string]$TtlFile = "",
    [switch]$Force
)

# 그래프 URI 정책
$GraphUriBase = "http://samsung.com/graph"
$SourceGraphs = @{
    "OFCO" = "$GraphUriBase/OFCO"
    "DSV"  = "$GraphUriBase/DSV" 
    "PKGS" = "$GraphUriBase/PKGS"
    "PAY"  = "$GraphUriBase/PAY"
    "META" = "$GraphUriBase/META"  # 메타데이터/온톨로지
}

# Fuseki 엔드포인트
$PingUrl = "$BaseUrl/$/ping"
$SparqlUrl = "$BaseUrl/$Dataset/sparql"
$DataUrl = "$BaseUrl/$Dataset/data"

# System.Web 어셈블리 로드 (URL 인코딩용)
Add-Type -AssemblyName System.Web

Write-Host "=== HVDC Named Graph Manager ===" -ForegroundColor Green
Write-Host "Action: $Action, Source: $Source" -ForegroundColor Cyan

# 헬스체크
try {
    $pingResponse = Invoke-WebRequest -Uri $PingUrl -TimeoutSec 5
    Write-Host "✅ Fuseki server healthy: $($pingResponse.Content.Trim())" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server not accessible"
    exit 1
}

switch ($Action.ToLower()) {
    "upload" {
        if (-not $Source -or -not $TtlFile) {
            Write-Error "Upload requires -Source and -TtlFile parameters"
            exit 1
        }
        
        if (-not $SourceGraphs.ContainsKey($Source.ToUpper())) {
            Write-Error "Invalid source. Valid sources: $($SourceGraphs.Keys -join ', ')"
            exit 1
        }
        
        if (-not (Test-Path $TtlFile)) {
            Write-Error "TTL file not found: $TtlFile"
            exit 1
        }
        
        $graphUri = $SourceGraphs[$Source.ToUpper()]
        # URI 이스케이프 처리
        $escapedGraphUri = [System.Web.HttpUtility]::UrlEncode($graphUri)
        $uploadUrl = "$DataUrl?graph=$escapedGraphUri"
        
        Write-Host "Uploading $TtlFile to graph: $graphUri" -ForegroundColor Yellow
        
        try {
            $ttlContent = Get-Content -Path $TtlFile -Raw -Encoding UTF8
            $response = Invoke-RestMethod -Uri $uploadUrl -Method Post -Body $ttlContent -ContentType "text/turtle; charset=utf-8"
            
            Write-Host "✅ Upload successful" -ForegroundColor Green
            if ($response.count) {
                Write-Host "   Triples added: $($response.tripleCount)" -ForegroundColor White
            }
            
            # 검증
            $countQuery = "SELECT (COUNT(*) AS ?count) WHERE { GRAPH <$graphUri> { ?s ?p ?o } }"
            $countResult = Invoke-RestMethod -Uri $SparqlUrl -Method Post -Body @{ query = $countQuery } -ContentType "application/x-www-form-urlencoded" -Headers @{ Accept = "application/sparql-results+json" }
            
            # cURL 백업 (JSON 파싱 문제 시)
            $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$countQuery" $SparqlUrl
            $jsonResult = $curlResult | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($jsonResult -and $jsonResult.results.bindings) {
                $tripleCount = $jsonResult.results.bindings[0].count.value
                Write-Host "   Graph $Source now contains: $tripleCount triples" -ForegroundColor White
            }
            
        } catch {
            Write-Error "❌ Upload failed: $($_.Exception.Message)"
            exit 1
        }
    }
    
    "delete" {
        if (-not $Source) {
            Write-Error "Delete requires -Source parameter"
            exit 1
        }
        
        if (-not $SourceGraphs.ContainsKey($Source.ToUpper())) {
            Write-Error "Invalid source. Valid sources: $($SourceGraphs.Keys -join ', ')"
            exit 1
        }
        
        $graphUri = $SourceGraphs[$Source.ToUpper()]
        $escapedGraphUri = [System.Web.HttpUtility]::UrlEncode($graphUri)
        $deleteUrl = "$DataUrl?graph=$escapedGraphUri"
        
        if (-not $Force) {
            $confirm = Read-Host "Delete all data in graph $graphUri? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        Write-Host "Deleting graph: $graphUri" -ForegroundColor Yellow
        
        try {
            Invoke-RestMethod -Uri $deleteUrl -Method Delete
            Write-Host "✅ Graph deleted successfully" -ForegroundColor Green
        } catch {
            Write-Error "❌ Delete failed: $($_.Exception.Message)"
        }
    }
    
    "list" {
        Write-Host "Listing all named graphs..." -ForegroundColor Yellow
        
        $listQuery = "SELECT DISTINCT ?g (COUNT(*) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } } GROUP BY ?g ORDER BY DESC(?count)"
        
        try {
            $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$listQuery" $SparqlUrl
            $jsonResult = $curlResult | ConvertFrom-Json
            
            if ($jsonResult.results.bindings) {
                Write-Host "`n=== Named Graphs ===" -ForegroundColor Cyan
                foreach ($binding in $jsonResult.results.bindings) {
                    $graphUri = $binding.g.value
                    $count = $binding.count.value
                    
                    # 소스 식별
                    $sourceName = "UNKNOWN"
                    foreach ($src in $SourceGraphs.Keys) {
                        if ($graphUri -eq $SourceGraphs[$src]) {
                            $sourceName = $src
                            break
                        }
                    }
                    
                    Write-Host "  $sourceName`: $count triples" -ForegroundColor White
                    Write-Host "    URI: $graphUri" -ForegroundColor Gray
                }
            } else {
                Write-Host "No named graphs found" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Error "❌ List failed: $($_.Exception.Message)"
        }
    }
    
    "validate" {
        Write-Host "Validating graph integrity..." -ForegroundColor Yellow
        
        # 1. 각 그래프별 트리플 수
        $validationQueries = @{
            "Graph Counts" = "SELECT ?g (COUNT(*) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } } GROUP BY ?g ORDER BY DESC(?count)"
            "Total Triples" = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
            "HVDC Cases" = "PREFIX ex:<http://samsung.com/project-logistics#> SELECT (COUNT(DISTINCT ?code) AS ?count) WHERE { ?case a ex:Case ; ex:caseNumber ?code }"
            "Data Sources" = "PREFIX ex:<http://samsung.com/project-logistics#> SELECT (COUNT(?ds) AS ?count) WHERE { ?ds a ex:DataSource }"
        }
        
        foreach ($name in $validationQueries.Keys) {
            $query = $validationQueries[$name]
            Write-Host "`n--- $name ---" -ForegroundColor Cyan
            
            try {
                $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$query" $SparqlUrl
                $jsonResult = $curlResult | ConvertFrom-Json
                
                if ($name -eq "Graph Counts") {
                    foreach ($binding in $jsonResult.results.bindings) {
                        $graphUri = $binding.g.value
                        $count = $binding.count.value
                        Write-Host "  $graphUri`: $count triples" -ForegroundColor White
                    }
                } else {
                    if ($jsonResult.results.bindings) {
                        $count = $jsonResult.results.bindings[0].count.value
                        Write-Host "  Count: $count" -ForegroundColor White
                    }
                }
            } catch {
                Write-Host "  ❌ Query failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 2. 무결성 검사 (입고-출고=재고)
        Write-Host "`n--- Stock Integrity Check ---" -ForegroundColor Cyan
        $integrityQuery = @"
PREFIX ex:<http://samsung.com/project-logistics#>
SELECT ?wh ?ym ((SUM(?inb)-SUM(?out)) AS ?calc) (SUM(?closing) AS ?stock)
WHERE {
  ?s a ex:StockSnapshot ; ex:snapshotDate ?d ;
     ex:inboundCount ?inb ; ex:outboundCount ?out ; ex:closingStock ?closing ;
     ex:snapshotLocation ?wh .
  BIND (SUBSTR(STR(?d),1,7) AS ?ym)
} GROUP BY ?wh ?ym
HAVING( SUM(?inb)-SUM(?out) = SUM(?closing) )
"@
        
        try {
            $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$integrityQuery" $SparqlUrl
            $jsonResult = $curlResult | ConvertFrom-Json
            
            if ($jsonResult.results.bindings -and $jsonResult.results.bindings.Count -gt 0) {
                Write-Host "  ✅ Stock integrity verified for $($jsonResult.results.bindings.Count) warehouse-months" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  No stock data or integrity issues found" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  ❌ Integrity check failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    default {
        Write-Host "Usage: hvdc-named-graph-manager.ps1 -Action <upload|delete|list|validate>" -ForegroundColor Cyan
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  Upload:   -Action upload -Source OFCO -TtlFile ofco_data.ttl" -ForegroundColor White
        Write-Host "  Delete:   -Action delete -Source DSV -Force" -ForegroundColor White  
        Write-Host "  List:     -Action list" -ForegroundColor White
        Write-Host "  Validate: -Action validate" -ForegroundColor White
        Write-Host "`nValid sources: $($SourceGraphs.Keys -join ', ')" -ForegroundColor Gray
    }
}

Write-Host "`n=== Operation completed ===" -ForegroundColor Green
