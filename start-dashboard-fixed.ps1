# HVDC Dashboard Fixed - SPARQL 호출 문제 해결 버전
# CORS 회피 + 올바른 헤더/방식으로 수정

param(
    [string]$FusekiUrl = "http://localhost:3030/hvdc",
    [int]$Port = 8091,
    [switch]$OpenBrowser
)

Write-Host "=== HVDC Dashboard Fixed Version ===" -ForegroundColor Green
Write-Host "Fuseki URL: $FusekiUrl" -ForegroundColor Cyan
Write-Host "Dashboard Port: $Port" -ForegroundColor Cyan

# Fuseki 서버 상태 확인
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3030/$/ping" -TimeoutSec 5
    Write-Host "✅ Fuseki server is healthy" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server is not accessible"
    exit 1
}

# 포트 사용 가능 여부 확인
function Test-PortAvailable {
    param([int]$Port)
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        $listener.Stop()
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-PortAvailable -Port $Port)) {
    Write-Warning "Port $Port is in use, trying alternative ports..."
    $alternatives = @(8091, 8092, 8093, 9001, 9002)
    $found = $false
    foreach ($alt in $alternatives) {
        if (Test-PortAvailable -Port $alt) {
            $Port = $alt
            $found = $true
            Write-Host "✅ Using alternative port: $Port" -ForegroundColor Green
            break
        }
    }
    if (-not $found) {
        Write-Error "❌ No available ports found"
        exit 1
    }
}

# 수정된 HTML (SPARQL 호출 문제 해결)
$htmlContent = @"
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HVDC Ontology Insight Dashboard - Fixed</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
        
        .header {
            text-align: center;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 3px solid #667eea;
        }
        
        .header h1 {
            color: #333;
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
        }
        
        .status-bar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: #f8f9fa;
            padding: 15px 20px;
            border-radius: 10px;
            margin-bottom: 30px;
            border-left: 5px solid #28a745;
        }
        
        .status-item {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .status-icon {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #28a745;
            animation: pulse 2s infinite;
        }
        
        .status-error {
            background: #dc3545;
            animation: none;
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metric-card {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            padding: 25px;
            border-radius: 15px;
            text-align: center;
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 30px rgba(102, 126, 234, 0.4);
        }
        
        .metric-card.error {
            background: linear-gradient(135deg, #dc3545, #c82333);
        }
        
        .metric-value {
            font-size: 3em;
            font-weight: bold;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .metric-label {
            font-size: 1.1em;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .query-section {
            background: #f8f9fa;
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 20px;
        }
        
        .query-section h3 {
            color: #333;
            margin-bottom: 15px;
            font-size: 1.3em;
        }
        
        .query-log {
            background: #2d3748;
            color: #a0aec0;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            max-height: 300px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .error-message {
            color: #dc3545;
            font-weight: bold;
        }
        
        .success-message {
            color: #28a745;
            font-weight: bold;
        }
        
        .footer {
            text-align: center;
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Samsung HVDC Ontology Insight</h1>
            <p>실시간 온톨로지 데이터 대시보드 (Fixed Version - Port: $Port)</p>
        </div>
        
        <div class="status-bar">
            <div class="status-item">
                <div class="status-icon" id="statusIcon"></div>
                <span id="statusText">Initializing...</span>
            </div>
            <div class="status-item">
                <span id="lastUpdate">Last Update: Loading...</span>
            </div>
            <div class="status-item">
                <span id="queryCount">Queries: 0</span>
            </div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card" id="triplesCard">
                <div class="metric-value" id="totalTriples">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Total Triples</div>
            </div>
            
            <div class="metric-card" id="casesCard">
                <div class="metric-value" id="totalCases">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">HVDC Cases</div>
            </div>
            
            <div class="metric-card" id="graphsCard">
                <div class="metric-value" id="namedGraphs">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Named Graphs</div>
            </div>
            
            <div class="metric-card" id="classesCard">
                <div class="metric-value" id="dataClasses">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Data Classes</div>
            </div>
        </div>
        
        <div class="query-section">
            <h3>🔍 SPARQL Query Log & Debug</h3>
            <div class="query-log" id="queryLog">Initializing SPARQL connection...\n</div>
        </div>
        
        <div class="footer">
            <p>Samsung HVDC Project • Powered by Apache Jena Fuseki • Dashboard Port: $Port</p>
        </div>
    </div>
    
    <script>
        // 설정
        const FUSEKI_BASE = 'http://localhost:3030';
        const DATASET = 'hvdc';
        const SPARQL_URL = `\${FUSEKI_BASE}/\${DATASET}/sparql`;
        
        let queryCounter = 0;
        let hasErrors = false;
        
        // 로그 함수
        function logMessage(message, isError = false) {
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = `[\${timestamp}] \${isError ? 'ERROR' : 'INFO'}: \${message}\n`;
            
            const logElement = document.getElementById('queryLog');
            logElement.textContent = logEntry + logElement.textContent;
            
            // 최대 100줄 유지
            const lines = logElement.textContent.split('\n');
            if (lines.length > 100) {
                logElement.textContent = lines.slice(0, 100).join('\n');
            }
        }
        
        // 상태 업데이트
        function updateStatus(connected, message) {
            const statusIcon = document.getElementById('statusIcon');
            const statusText = document.getElementById('statusText');
            
            if (connected) {
                statusIcon.className = 'status-icon';
                statusText.textContent = message || 'Fuseki Server Connected';
                statusText.className = 'success-message';
            } else {
                statusIcon.className = 'status-icon status-error';
                statusText.textContent = message || 'Connection Error';
                statusText.className = 'error-message';
            }
        }
        
        // SPARQL 쿼리 실행 (수정된 버전)
        async function executeSparqlQuery(query, description) {
            queryCounter++;
            document.getElementById('queryCount').textContent = `Queries: \${queryCounter}`;
            
            logMessage(`Executing query \${queryCounter}: \${description}`);
            logMessage(`Query: \${query.substring(0, 100)}...`);
            
            try {
                // 방법 1: application/sparql-query (표준)
                let response = await fetch(SPARQL_URL, {
                    method: 'POST',
                    headers: {
                        'Accept': 'application/sparql-results+json',
                        'Content-Type': 'application/sparql-query'
                    },
                    body: query
                });
                
                if (!response.ok) {
                    // 방법 2: form-urlencoded (폴백)
                    logMessage(`Method 1 failed (\${response.status}), trying form-urlencoded...`);
                    
                    response = await fetch(SPARQL_URL, {
                        method: 'POST',
                        headers: {
                            'Accept': 'application/sparql-results+json',
                            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
                        },
                        body: new URLSearchParams({ query: query }).toString()
                    });
                }
                
                if (!response.ok) {
                    throw new Error(`HTTP \${response.status}: \${response.statusText}`);
                }
                
                const data = await response.json();
                logMessage(`✅ Query \${queryCounter} successful: \${data.results.bindings.length} results`);
                
                // 연결 상태 업데이트
                if (hasErrors) {
                    updateStatus(true);
                    hasErrors = false;
                }
                
                return data;
                
            } catch (error) {
                const errorMsg = `❌ Query \${queryCounter} failed: \${error.message}`;
                logMessage(errorMsg, true);
                
                // 상태 업데이트
                updateStatus(false, `SPARQL Error: \${error.message}`);
                hasErrors = true;
                
                return null;
            }
        }
        
        // 메트릭 업데이트
        async function updateMetrics() {
            logMessage('=== Starting metrics update ===');
            
            // 1. Total Triples
            const triplesQuery = 'SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }';
            const triplesResult = await executeSparqlQuery(triplesQuery, 'Total Triples Count');
            
            if (triplesResult && triplesResult.results.bindings.length > 0) {
                const count = parseInt(triplesResult.results.bindings[0].count.value);
                document.getElementById('totalTriples').textContent = count.toLocaleString();
                document.getElementById('triplesCard').classList.remove('error');
            } else {
                document.getElementById('totalTriples').innerHTML = '<span class="error-message">Error</span>';
                document.getElementById('triplesCard').classList.add('error');
            }
            
            // 2. HVDC Cases
            const casesQuery = 'PREFIX ex:<http://samsung.com/project-logistics#> SELECT (COUNT(?case) AS ?count) WHERE { ?case a ex:Case }';
            const casesResult = await executeSparqlQuery(casesQuery, 'HVDC Cases Count');
            
            if (casesResult && casesResult.results.bindings.length > 0) {
                const count = parseInt(casesResult.results.bindings[0].count.value);
                document.getElementById('totalCases').textContent = count.toLocaleString();
                document.getElementById('casesCard').classList.remove('error');
            } else {
                document.getElementById('totalCases').innerHTML = '<span class="error-message">Error</span>';
                document.getElementById('casesCard').classList.add('error');
            }
            
            // 3. Named Graphs
            const graphsQuery = 'SELECT (COUNT(DISTINCT ?g) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } }';
            const graphsResult = await executeSparqlQuery(graphsQuery, 'Named Graphs Count');
            
            if (graphsResult && graphsResult.results.bindings.length > 0) {
                const count = parseInt(graphsResult.results.bindings[0].count.value);
                document.getElementById('namedGraphs').textContent = count.toLocaleString();
                document.getElementById('graphsCard').classList.remove('error');
            } else {
                document.getElementById('namedGraphs').innerHTML = '<span class="error-message">Error</span>';
                document.getElementById('graphsCard').classList.add('error');
            }
            
            // 4. Data Classes
            const classesQuery = 'SELECT (COUNT(DISTINCT ?class) AS ?count) WHERE { ?s a ?class }';
            const classesResult = await executeSparqlQuery(classesQuery, 'Data Classes Count');
            
            if (classesResult && classesResult.results.bindings.length > 0) {
                const count = parseInt(classesResult.results.bindings[0].count.value);
                document.getElementById('dataClasses').textContent = count.toLocaleString();
                document.getElementById('classesCard').classList.remove('error');
            } else {
                document.getElementById('dataClasses').innerHTML = '<span class="error-message">Error</span>';
                document.getElementById('classesCard').classList.add('error');
            }
            
            // 업데이트 시간 갱신
            document.getElementById('lastUpdate').textContent = `Last Update: \${new Date().toLocaleTimeString()}`;
            
            logMessage('=== Metrics update completed ===');
        }
        
        // 초기화
        async function initialize() {
            logMessage('Dashboard initializing...');
            updateStatus(false, 'Connecting to Fuseki...');
            
            // 초기 메트릭 업데이트
            await updateMetrics();
            
            // 30초마다 자동 갱신
            setInterval(updateMetrics, 30000);
            
            logMessage('Dashboard initialization completed');
        }
        
        // 페이지 로드 시 시작
        document.addEventListener('DOMContentLoaded', initialize);
    </script>
</body>
</html>
"@

# HTTP 서버 시작
Write-Host "🚀 Starting fixed dashboard server on port $Port..." -ForegroundColor Yellow

try {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    
    $dashboardUrl = "http://localhost:$Port"
    Write-Host "✅ Fixed dashboard server started!" -ForegroundColor Green
    Write-Host "🌐 Dashboard URL: $dashboardUrl" -ForegroundColor Cyan
    Write-Host "📊 Fuseki Data: $FusekiUrl" -ForegroundColor Cyan
    
    # 브라우저 열기
    if ($OpenBrowser -or -not $PSBoundParameters.ContainsKey('OpenBrowser')) {
        Write-Host "🌐 Opening browser..." -ForegroundColor Yellow
        Start-Process $dashboardUrl
    }
    
    Write-Host "`n=== Fixed Dashboard Server Running ===" -ForegroundColor Green
    Write-Host "🔧 SPARQL 호출 문제 해결 완료" -ForegroundColor Green
    Write-Host "📈 실시간 데이터 업데이트 중..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    
    # 요청 처리 루프
    $requestCount = 0
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $requestCount++
            Write-Host "[$requestCount] $(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $($request.Url.LocalPath)" -ForegroundColor Gray
            
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            
        } catch [System.Net.HttpListenerException] {
            break
        } catch {
            Write-Warning "Request error: $($_.Exception.Message)"
        }
    }
    
} catch {
    Write-Error "❌ Failed to start server: $($_.Exception.Message)"
} finally {
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        Write-Host "🛑 Fixed dashboard server stopped" -ForegroundColor Yellow
    }
    Write-Host "=== Session ended ===" -ForegroundColor Green
}
