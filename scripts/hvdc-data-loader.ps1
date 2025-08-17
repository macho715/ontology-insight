# HVDC Ontology Insight - Data Loader Script (PowerShell)
# TTL 데이터 적재 및 검증 자동화

param(
    [string]$BaseUrl = "http://localhost:3030",
    [string]$Dataset = "hvdc",
    [string]$TtlFile = "triples.ttl",
    [switch]$Force,
    [switch]$Validate
)

# 핵심 4라인 - 경로 정합성 보장
$FusekiUrl = $BaseUrl
$PingUrl = "$BaseUrl/$/ping"
$GspDefault = "$BaseUrl/$Dataset/data?default"
$SparqlUrl = "$BaseUrl/$Dataset/sparql"

Write-Host "=== HVDC Data Loader ===" -ForegroundColor Green

# 1. Fuseki 서버 상태 확인 (표준 ping 엔드포인트)
Write-Host "Fuseki 서버 상태 확인 중..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $PingUrl -Method GET -TimeoutSec 5
    Write-Host "✓ Fuseki 서버 연결 성공 (ping: $($response.Content.Trim()))" -ForegroundColor Green
} catch {
    Write-Error "✗ Fuseki 서버에 연결할 수 없습니다. 서버가 실행 중인지 확인하세요."
    Write-Host "서버 실행: .\start-hvdc-fuseki.bat" -ForegroundColor Cyan
    exit 1
}

# 2. TTL 파일 존재 확인
if (-not (Test-Path $TtlFile)) {
    Write-Error "✗ TTL 파일을 찾을 수 없습니다: $TtlFile"
    exit 1
}

$fileSize = (Get-Item $TtlFile).Length
Write-Host "✓ TTL 파일 확인: $TtlFile ($([math]::Round($fileSize/1KB, 2)) KB)" -ForegroundColor Green

# 3. 기존 데이터 확인 및 삭제 (Force 옵션)
if ($Force) {
    Write-Host "기존 데이터 삭제 중..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri $GspDefault -Method Delete
        Write-Host "✓ 기존 데이터 삭제 완료" -ForegroundColor Green
    } catch {
        Write-Warning "기존 데이터 삭제 실패 (데이터가 없을 수 있음)"
    }
} else {
    # 데이터 존재 여부 확인
    $countQuery = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
    try {
        $result = Invoke-RestMethod -Uri $SparqlUrl -Method Post -Body @{ query = $countQuery } -ContentType "application/x-www-form-urlencoded"
        $tripleCount = $result.results.bindings[0].count.value
        
        if ([int]$tripleCount -gt 0) {
            Write-Warning "기존 데이터가 $tripleCount 개의 트리플로 존재합니다."
            Write-Host "기존 데이터를 삭제하려면 -Force 옵션을 사용하세요." -ForegroundColor Cyan
            
            $confirm = Read-Host "계속 진행하시겠습니까? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "작업이 취소되었습니다." -ForegroundColor Yellow
                exit 0
            }
        }
    } catch {
        Write-Warning "기존 데이터 확인 실패"
    }
}

# 4. TTL 데이터 업로드
Write-Host "TTL 데이터 업로드 중..." -ForegroundColor Yellow
try {
    $ttlContent = Get-Content -Path $TtlFile -Raw -Encoding UTF8
    $response = Invoke-RestMethod -Uri $GspDefault -Method Post -Body $ttlContent -ContentType "text/turtle; charset=utf-8"
    Write-Host "✓ TTL 데이터 업로드 완료" -ForegroundColor Green
} catch {
    Write-Error "✗ TTL 데이터 업로드 실패: $($_.Exception.Message)"
    exit 1
}

# 5. 업로드 검증
Write-Host "데이터 업로드 검증 중..." -ForegroundColor Yellow
try {
    $countQuery = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
    
    # cURL을 사용하여 JSON 파싱 문제 우회
    $curlResult = & curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query=$countQuery" $SparqlUrl
    $jsonResult = $curlResult | ConvertFrom-Json
    $tripleCount = $jsonResult.results.bindings[0].count.value
    
    Write-Host "✓ 업로드된 트리플 수: $tripleCount" -ForegroundColor Green
    
    if ([int]$tripleCount -eq 0) {
        Write-Warning "트리플이 업로드되지 않았습니다. TTL 파일을 확인하세요."
        exit 1
    }
} catch {
    Write-Error "✗ 데이터 검증 실패: $($_.Exception.Message)"
    exit 1
}

# 6. 상세 검증 (Validate 옵션)
if ($Validate) {
    Write-Host "상세 데이터 검증 중..." -ForegroundColor Yellow
    
    # 클래스별 인스턴스 수 확인
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
        $result = Invoke-RestMethod -Uri $SparqlUrl -Method Post -Body @{ query = $classCountQuery } -ContentType "application/x-www-form-urlencoded"
        
        Write-Host "`n=== 클래스별 인스턴스 수 ===" -ForegroundColor Cyan
        foreach ($binding in $result.results.bindings) {
            $className = $binding.class.value -replace "http://samsung.com/project-logistics#", "ex:"
            $count = $binding.count.value
            Write-Host "  $className`: $count" -ForegroundColor White
        }
    } catch {
        Write-Warning "상세 검증 실패"
    }
}

Write-Host "`n=== 데이터 로딩 완료 ===" -ForegroundColor Green
Write-Host "Web UI: $FusekiUrl" -ForegroundColor Cyan
Write-Host "SPARQL Endpoint: $FusekiUrl/sparql" -ForegroundColor Cyan
Write-Host "`n쿼리 실행 예시:" -ForegroundColor Cyan
Write-Host "  .\scripts\hvdc-query-runner.ps1 -QueryFile queries\01-monthly-warehouse-stock.rq" -ForegroundColor White
