# HVDC Named Graph Rollback - 긴급 복구 스크립트
# Named Graph → Default Graph 롤백 또는 특정 그래프 복원

param(
    [string]$BaseUrl = "http://localhost:3030",
    [string]$Dataset = "hvdc",
    [string]$Action = "list",  # list, restore-from-archive, move-to-default, delete-graph
    [string]$SourceGraph = "",
    [string]$ArchiveGraph = "",
    [switch]$Force,
    [switch]$DryRun
)

# System.Web 어셈블리 로드
Add-Type -AssemblyName System.Web

# 엔드포인트
$PingUrl = "$BaseUrl/$/ping"
$UpdateUrl = "$BaseUrl/$Dataset/update"
$SparqlUrl = "$BaseUrl/$Dataset/sparql"
$DataUrl = "$BaseUrl/$Dataset/data"

Write-Host "=== HVDC Named Graph Rollback ===" -ForegroundColor Red
Write-Host "Action: $Action" -ForegroundColor Cyan

# 헬스체크
try {
    $response = Invoke-WebRequest -Uri $PingUrl -TimeoutSec 5
    Write-Host "✅ Fuseki server healthy: $($response.Content.Trim())" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server not accessible"
    exit 1
}

# UPDATE 권한 확인
try {
    $testUpdate = "ASK { ?s ?p ?o }"
    Invoke-RestMethod -Uri $UpdateUrl -Method Post -Body $testUpdate -ContentType "application/sparql-update" -ErrorAction Stop | Out-Null
    Write-Host "✅ SPARQL UPDATE endpoint accessible" -ForegroundColor Green
} catch {
    Write-Error "❌ SPARQL UPDATE not accessible. Ensure server started with --update option"
    exit 1
}

function Get-AllGraphs {
    $query = "SELECT DISTINCT ?g (COUNT(*) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } } GROUP BY ?g ORDER BY DESC(?count)"
    try {
        $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$query" $SparqlUrl
        $jsonResult = $curlResult | ConvertFrom-Json
        return $jsonResult.results.bindings
    } catch {
        Write-Error "Failed to list graphs: $($_.Exception.Message)"
        return @()
    }
}

function Get-DefaultGraphCount {
    $query = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
    try {
        $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$query" $SparqlUrl
        $jsonResult = $curlResult | ConvertFrom-Json
        return [int]$jsonResult.results.bindings[0].count.value
    } catch {
        return 0
    }
}

switch ($Action.ToLower()) {
    "list" {
        Write-Host "`n=== Current Graph Status ===" -ForegroundColor Yellow
        
        # Default Graph
        $defaultCount = Get-DefaultGraphCount
        Write-Host "DEFAULT GRAPH: $defaultCount triples" -ForegroundColor White
        
        # Named Graphs
        $graphs = Get-AllGraphs
        if ($graphs.Count -gt 0) {
            Write-Host "`nNAMED GRAPHS:" -ForegroundColor White
            foreach ($binding in $graphs) {
                $graphUri = $binding.g.value
                $count = $binding.count.value
                
                # 그래프 타입 식별
                $graphType = "OTHER"
                if ($graphUri -match "samsung\.com/graph/ARCHIVE") { $graphType = "🗄️  ARCHIVE" }
                elseif ($graphUri -match "samsung\.com/graph/OFCO") { $graphType = "📦 OFCO" }
                elseif ($graphUri -match "samsung\.com/graph/DSV") { $graphType = "🚢 DSV" }
                elseif ($graphUri -match "samsung\.com/graph/PKGS") { $graphType = "📋 PKGS" }
                elseif ($graphUri -match "samsung\.com/graph/PAY") { $graphType = "💰 PAY" }
                else { $graphType = "❓ OTHER" }
                
                Write-Host "  $graphType`: $count triples" -ForegroundColor White
                Write-Host "    URI: $graphUri" -ForegroundColor Gray
            }
        } else {
            Write-Host "  No named graphs found" -ForegroundColor Yellow
        }
    }
    
    "restore-from-archive" {
        if (-not $ArchiveGraph) {
            Write-Error "restore-from-archive requires -ArchiveGraph parameter"
            exit 1
        }
        
        Write-Host "`nRestoring from archive: $ArchiveGraph" -ForegroundColor Yellow
        
        # Archive Graph 존재 확인
        $archiveCountQuery = "SELECT (COUNT(*) AS ?count) WHERE { GRAPH <$ArchiveGraph> { ?s ?p ?o } }"
        $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$archiveCountQuery" $SparqlUrl
        $jsonResult = $curlResult | ConvertFrom-Json
        $archiveCount = [int]$jsonResult.results.bindings[0].count.value
        
        if ($archiveCount -eq 0) {
            Write-Error "Archive graph is empty or doesn't exist: $ArchiveGraph"
            exit 1
        }
        
        Write-Host "Archive graph contains: $archiveCount triples" -ForegroundColor White
        
        # Default Graph 현재 상태 확인
        $defaultCount = Get-DefaultGraphCount
        if ($defaultCount -gt 0 -and -not $Force) {
            Write-Warning "Default graph contains $defaultCount triples"
            $confirm = Read-Host "This will overwrite the default graph. Continue? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute: MOVE <$ArchiveGraph> TO DEFAULT" -ForegroundColor Magenta
        } else {
            try {
                $moveQuery = "MOVE <$ArchiveGraph> TO DEFAULT"
                Write-Host "Executing: $moveQuery" -ForegroundColor Cyan
                Invoke-RestMethod -Uri $UpdateUrl -Method Post -Body $moveQuery -ContentType "application/sparql-update"
                
                # 검증
                $newDefaultCount = Get-DefaultGraphCount
                Write-Host "✅ Restore completed. Default graph now has: $newDefaultCount triples" -ForegroundColor Green
                
            } catch {
                Write-Error "❌ Restore failed: $($_.Exception.Message)"
                exit 1
            }
        }
    }
    
    "move-to-default" {
        if (-not $SourceGraph) {
            Write-Error "move-to-default requires -SourceGraph parameter"
            exit 1
        }
        
        Write-Host "`nMoving graph to default: $SourceGraph" -ForegroundColor Yellow
        
        # Source Graph 존재 확인
        $sourceCountQuery = "SELECT (COUNT(*) AS ?count) WHERE { GRAPH <$SourceGraph> { ?s ?p ?o } }"
        $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$sourceCountQuery" $SparqlUrl
        $jsonResult = $curlResult | ConvertFrom-Json
        $sourceCount = [int]$jsonResult.results.bindings[0].count.value
        
        if ($sourceCount -eq 0) {
            Write-Error "Source graph is empty or doesn't exist: $SourceGraph"
            exit 1
        }
        
        Write-Host "Source graph contains: $sourceCount triples" -ForegroundColor White
        
        # Default Graph 현재 상태 확인
        $defaultCount = Get-DefaultGraphCount
        if ($defaultCount -gt 0 -and -not $Force) {
            Write-Warning "Default graph contains $defaultCount triples"
            $confirm = Read-Host "Move will ADD to default graph (not replace). Continue? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute: ADD <$SourceGraph> TO DEFAULT" -ForegroundColor Magenta
        } else {
            try {
                $addQuery = "ADD <$SourceGraph> TO DEFAULT"
                Write-Host "Executing: $addQuery" -ForegroundColor Cyan
                Invoke-RestMethod -Uri $UpdateUrl -Method Post -Body $addQuery -ContentType "application/sparql-update"
                
                # 검증
                $newDefaultCount = Get-DefaultGraphCount
                Write-Host "✅ Move completed. Default graph now has: $newDefaultCount triples" -ForegroundColor Green
                
            } catch {
                Write-Error "❌ Move failed: $($_.Exception.Message)"
                exit 1
            }
        }
    }
    
    "delete-graph" {
        if (-not $SourceGraph) {
            Write-Error "delete-graph requires -SourceGraph parameter"
            exit 1
        }
        
        Write-Host "`nDeleting graph: $SourceGraph" -ForegroundColor Red
        
        # Source Graph 존재 확인
        $sourceCountQuery = "SELECT (COUNT(*) AS ?count) WHERE { GRAPH <$SourceGraph> { ?s ?p ?o } }"
        $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$sourceCountQuery" $SparqlUrl
        $jsonResult = $curlResult | ConvertFrom-Json
        $sourceCount = [int]$jsonResult.results.bindings[0].count.value
        
        if ($sourceCount -eq 0) {
            Write-Warning "Source graph is already empty: $SourceGraph"
        } else {
            Write-Host "Source graph contains: $sourceCount triples" -ForegroundColor White
        }
        
        if (-not $Force) {
            $confirm = Read-Host "This will permanently delete the graph. Continue? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute: DROP GRAPH <$SourceGraph>" -ForegroundColor Magenta
        } else {
            try {
                $dropQuery = "DROP GRAPH <$SourceGraph>"
                Write-Host "Executing: $dropQuery" -ForegroundColor Cyan
                Invoke-RestMethod -Uri $UpdateUrl -Method Post -Body $dropQuery -ContentType "application/sparql-update"
                
                Write-Host "✅ Graph deleted successfully" -ForegroundColor Green
                
            } catch {
                Write-Error "❌ Delete failed: $($_.Exception.Message)"
                exit 1
            }
        }
    }
    
    default {
        Write-Host "Usage: rollback-named-graphs.ps1 -Action <action> [options]" -ForegroundColor Cyan
        Write-Host "`nActions:" -ForegroundColor Yellow
        Write-Host "  list                    - List all graphs and their triple counts" -ForegroundColor White
        Write-Host "  restore-from-archive    - Move archive graph back to default (requires -ArchiveGraph)" -ForegroundColor White
        Write-Host "  move-to-default         - Add named graph to default graph (requires -SourceGraph)" -ForegroundColor White
        Write-Host "  delete-graph            - Permanently delete a named graph (requires -SourceGraph)" -ForegroundColor White
        Write-Host "`nOptions:" -ForegroundColor Yellow
        Write-Host "  -Force                  - Skip confirmation prompts" -ForegroundColor White
        Write-Host "  -DryRun                 - Show what would be executed without doing it" -ForegroundColor White
        Write-Host "`nExamples:" -ForegroundColor Yellow
        Write-Host "  List graphs:            -Action list" -ForegroundColor White
        Write-Host "  Restore from archive:   -Action restore-from-archive -ArchiveGraph 'http://samsung.com/graph/ARCHIVE-20250117-2100'" -ForegroundColor White
        Write-Host "  Move OFCO to default:   -Action move-to-default -SourceGraph 'http://samsung.com/graph/OFCO'" -ForegroundColor White
        Write-Host "  Delete PKGS graph:      -Action delete-graph -SourceGraph 'http://samsung.com/graph/PKGS' -Force" -ForegroundColor White
    }
}

Write-Host "`n=== Rollback operation completed ===" -ForegroundColor Green
