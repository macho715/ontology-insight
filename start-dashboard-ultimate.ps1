# HVDC Dashboard Ultimate - 모든 CORS/호출 문제 완전 해결
# 브라우저 개발자 도구 가이드 + 완벽한 프록시 + 디버깅

param(
    [int]$Port = 8095,
    [switch]$OpenBrowser,
    [switch]$Debug
)

Write-Host "=== HVDC Dashboard Ultimate (All Issues Fixed) ===" -ForegroundColor Green
Write-Host "Port: $Port" -ForegroundColor Cyan

# Fuseki 확인
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3030/$/ping" -TimeoutSec 5
    Write-Host "✅ Fuseki server: $($response.Content.Trim())" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server not accessible"
    exit 1
}

# 포트 확인 및 할당
function Test-PortAvailable {
    param([int]$Port)
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        $listener.Stop()
        return $true
    } catch { return $false }
}

$alternatives = @(8095, 8096, 8097, 8098, 9050)
if (-not (Test-PortAvailable -Port $Port)) {
    foreach ($alt in $alternatives) {
        if (Test-PortAvailable -Port $alt) {
            $Port = $alt
            break
        }
    }
}

Write-Host "🚀 Using port: $Port" -ForegroundColor Green

# 완전한 HTML (모든 문제 해결 + 디버깅 가이드)
$htmlContent = @"
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HVDC Dashboard Ultimate - All Issues Fixed</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 3px solid #667eea;
        }
        
        .header h1 {
            color: #333;
            font-size: 2.2em;
            margin-bottom: 10px;
        }
        
        .debug-panel {
            background: #f8f9fa;
            border: 2px solid #007bff;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 30px;
        }
        
        .debug-panel h3 {
            color: #007bff;
            margin-bottom: 15px;
            font-size: 1.2em;
        }
        
        .debug-steps {
            background: #e9ecef;
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 0.9em;
            line-height: 1.4;
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
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metric-card {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            padding: 20px;
            border-radius: 15px;
            text-align: center;
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
            transition: all 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
        }
        
        .metric-card.error {
            background: linear-gradient(135deg, #dc3545, #c82333);
        }
        
        .metric-card.loading {
            background: linear-gradient(135deg, #6c757d, #5a6268);
        }
        
        .metric-value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .metric-label {
            font-size: 1em;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .debug-section {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .log-panel {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 15px;
        }
        
        .log-panel h3 {
            color: #333;
            margin-bottom: 15px;
            font-size: 1.1em;
        }
        
        .log-content {
            background: #2d3748;
            color: #a0aec0;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.85em;
            max-height: 250px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        
        .test-buttons {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s ease;
        }
        
        .btn-primary {
            background: #007bff;
            color: white;
        }
        
        .btn-success {
            background: #28a745;
            color: white;
        }
        
        .btn-warning {
            background: #ffc107;
            color: #212529;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
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
        
        .success { color: #28a745; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        
        @media (max-width: 768px) {
            .debug-section {
                grid-template-columns: 1fr;
            }
            .container {
                padding: 20px;
                margin: 10px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Samsung HVDC Ontology Insight</h1>
            <p>Ultimate Dashboard - All CORS/SPARQL Issues Fixed (Port: $Port)</p>
        </div>
        
        <div class="debug-panel">
            <h3>🔧 브라우저 개발자 도구 확인 방법</h3>
            <div class="debug-steps">
1. F12를 눌러 개발자 도구를 엽니다
2. "Console" 탭에서 에러 메시지를 확인하세요
3. "Network" 탭에서 SPARQL 요청을 확인하세요
4. CORS 에러가 보이면 → 아래 "Test Direct SPARQL" 버튼을 클릭
5. 404/500 에러가 보이면 → "Test Proxy" 버튼을 클릭
6. 모든 요청이 성공하면 → 자동으로 데이터가 로드됩니다
            </div>
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
        
        <div class="test-buttons">
            <button class="btn btn-primary" onclick="testDirectSparql()">Test Direct SPARQL</button>
            <button class="btn btn-success" onclick="testProxy()">Test Proxy</button>
            <button class="btn btn-warning" onclick="refreshMetrics()">Refresh Data</button>
            <button class="btn btn-primary" onclick="clearLogs()">Clear Logs</button>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card loading" id="triplesCard">
                <div class="metric-value" id="totalTriples">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Total Triples</div>
            </div>
            
            <div class="metric-card loading" id="casesCard">
                <div class="metric-value" id="totalCases">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">HVDC Cases</div>
            </div>
            
            <div class="metric-card loading" id="graphsCard">
                <div class="metric-value" id="namedGraphs">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Named Graphs</div>
            </div>
            
            <div class="metric-card loading" id="classesCard">
                <div class="metric-value" id="dataClasses">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Data Classes</div>
            </div>
        </div>
        
        <div class="debug-section">
            <div class="log-panel">
                <h3>🔍 SPARQL Query Log</h3>
                <div class="log-content" id="queryLog">Initializing dashboard...\n</div>
            </div>
            
            <div class="log-panel">
                <h3>🐛 Debug Information</h3>
                <div class="log-content" id="debugLog">Debug mode active...\n</div>
            </div>
        </div>
    </div>
    
    <script>
        // 글로벌 설정
        const CONFIG = {
            DIRECT_SPARQL_URL: 'http://localhost:3030/hvdc/sparql',
            PROXY_URL: '/api/sparql',
            DEBUG: true
        };
        
        let queryCounter = 0;
        let useProxy = true; // 기본값: 프록시 사용
        
        // 로그 함수들
        function logQuery(message, isError = false) {
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = `[\${timestamp}] \${isError ? 'ERROR' : 'INFO'}: \${message}\n`;
            
            const logElement = document.getElementById('queryLog');
            logElement.textContent = logEntry + logElement.textContent;
            
            // 최대 50줄 유지
            const lines = logElement.textContent.split('\n');
            if (lines.length > 50) {
                logElement.textContent = lines.slice(0, 50).join('\n');
            }
        }
        
        function logDebug(message, isError = false) {
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = `[\${timestamp}] \${isError ? 'ERROR' : 'DEBUG'}: \${message}\n`;
            
            const logElement = document.getElementById('debugLog');
            logElement.textContent = logEntry + logElement.textContent;
            
            // 최대 50줄 유지
            const lines = logElement.textContent.split('\n');
            if (lines.length > 50) {
                logElement.textContent = lines.slice(0, 50).join('\n');
            }
        }
        
        function updateStatus(connected, message) {
            const statusIcon = document.getElementById('statusIcon');
            const statusText = document.getElementById('statusText');
            
            if (connected) {
                statusIcon.className = 'status-icon';
                statusText.innerHTML = '<span class="success">' + (message || 'SPARQL Connected') + '</span>';
            } else {
                statusIcon.className = 'status-icon status-error';
                statusText.innerHTML = '<span class="error">' + (message || 'Connection Error') + '</span>';
            }
        }
        
        // SPARQL 실행 함수 (다중 방식 지원)
        async function executeSparqlQuery(query, description) {
            queryCounter++;
            document.getElementById('queryCount').textContent = `Queries: \${queryCounter}`;
            
            logQuery(`🔄 Query \${queryCounter}: \${description}`);
            logDebug(`Using \${useProxy ? 'PROXY' : 'DIRECT'} mode for: \${description}`);
            
            if (useProxy) {
                return await executeSparqlViaProxy(query, description);
            } else {
                return await executeSparqlDirect(query, description);
            }
        }
        
        // 프록시를 통한 SPARQL 실행
        async function executeSparqlViaProxy(query, description) {
            try {
                const response = await fetch(CONFIG.PROXY_URL, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ query: query })
                });
                
                if (!response.ok) {
                    throw new Error(`Proxy error: \${response.status} \${response.statusText}`);
                }
                
                const data = await response.json();
                
                if (data.error) {
                    throw new Error(data.error);
                }
                
                logQuery(`✅ Query \${queryCounter} success (PROXY): \${data.results.bindings.length} results`);
                logDebug(`Proxy response OK: \${JSON.stringify(data).substring(0, 100)}...`);
                
                updateStatus(true, 'SPARQL Proxy Working');
                return data;
                
            } catch (error) {
                logQuery(`❌ Query \${queryCounter} failed (PROXY): \${error.message}`, true);
                logDebug(`Proxy error details: \${error.stack}`, true);
                
                // 프록시 실패 시 Direct 모드로 전환
                logDebug('Switching to DIRECT mode due to proxy failure');
                useProxy = false;
                return await executeSparqlDirect(query, description);
            }
        }
        
        // 직접 SPARQL 실행
        async function executeSparqlDirect(query, description) {
            try {
                // 방법 1: application/sparql-query
                let response = await fetch(CONFIG.DIRECT_SPARQL_URL, {
                    method: 'POST',
                    headers: {
                        'Accept': 'application/sparql-results+json',
                        'Content-Type': 'application/sparql-query'
                    },
                    body: query
                });
                
                if (!response.ok) {
                    // 방법 2: form-urlencoded
                    logDebug(`Direct method 1 failed (\${response.status}), trying form-urlencoded...`);
                    
                    response = await fetch(CONFIG.DIRECT_SPARQL_URL, {
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
                
                logQuery(`✅ Query \${queryCounter} success (DIRECT): \${data.results.bindings.length} results`);
                logDebug(`Direct response OK: \${JSON.stringify(data).substring(0, 100)}...`);
                
                updateStatus(true, 'Direct SPARQL Working');
                return data;
                
            } catch (error) {
                logQuery(`❌ Query \${queryCounter} failed (DIRECT): \${error.message}`, true);
                logDebug(`Direct error details: \${error.stack}`, true);
                
                updateStatus(false, `SPARQL Error: \${error.message}`);
                return null;
            }
        }
        
        // 메트릭 업데이트
        async function updateMetrics() {
            logDebug('=== Starting metrics update ===');
            
            const queries = [
                {
                    query: 'SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }',
                    description: 'Total Triples',
                    elementId: 'totalTriples',
                    cardId: 'triplesCard'
                },
                {
                    query: 'PREFIX ex:<http://samsung.com/project-logistics#> SELECT (COUNT(?case) AS ?count) WHERE { ?case a ex:Case }',
                    description: 'HVDC Cases',
                    elementId: 'totalCases',
                    cardId: 'casesCard'
                },
                {
                    query: 'SELECT (COUNT(DISTINCT ?g) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } }',
                    description: 'Named Graphs',
                    elementId: 'namedGraphs',
                    cardId: 'graphsCard'
                },
                {
                    query: 'SELECT (COUNT(DISTINCT ?class) AS ?count) WHERE { ?s a ?class }',
                    description: 'Data Classes',
                    elementId: 'dataClasses',
                    cardId: 'classesCard'
                }
            ];
            
            for (const queryInfo of queries) {
                const result = await executeSparqlQuery(queryInfo.query, queryInfo.description);
                
                if (result && result.results.bindings.length > 0) {
                    const count = parseInt(result.results.bindings[0].count.value);
                    document.getElementById(queryInfo.elementId).textContent = count.toLocaleString();
                    document.getElementById(queryInfo.cardId).className = 'metric-card';
                    logDebug(`✅ \${queryInfo.description}: \${count}`);
                } else {
                    document.getElementById(queryInfo.elementId).innerHTML = '<span class="error">Error</span>';
                    document.getElementById(queryInfo.cardId).className = 'metric-card error';
                    logDebug(`❌ \${queryInfo.description}: Failed`, true);
                }
                
                // 각 쿼리 간 간격
                await new Promise(resolve => setTimeout(resolve, 200));
            }
            
            document.getElementById('lastUpdate').textContent = `Last Update: \${new Date().toLocaleTimeString()}`;
            logDebug('=== Metrics update completed ===');
        }
        
        // 테스트 함수들
        async function testDirectSparql() {
            logDebug('🧪 Testing direct SPARQL connection...');
            useProxy = false;
            const result = await executeSparqlQuery('SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }', 'Direct SPARQL Test');
            if (result) {
                logDebug('✅ Direct SPARQL test successful');
            } else {
                logDebug('❌ Direct SPARQL test failed', true);
            }
        }
        
        async function testProxy() {
            logDebug('🧪 Testing proxy connection...');
            useProxy = true;
            const result = await executeSparqlQuery('SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }', 'Proxy Test');
            if (result) {
                logDebug('✅ Proxy test successful');
            } else {
                logDebug('❌ Proxy test failed', true);
            }
        }
        
        async function refreshMetrics() {
            logDebug('🔄 Manual metrics refresh requested');
            await updateMetrics();
        }
        
        function clearLogs() {
            document.getElementById('queryLog').textContent = 'Logs cleared...\n';
            document.getElementById('debugLog').textContent = 'Debug logs cleared...\n';
            logDebug('Logs cleared by user');
        }
        
        // 초기화
        async function initialize() {
            logDebug('🚀 Dashboard initializing...');
            logQuery('Dashboard starting up...');
            
            updateStatus(false, 'Initializing...');
            
            // 자동 모드 감지 (프록시 → 직접 순서)
            logDebug('Auto-detecting best connection method...');
            
            // 먼저 프록시 시도
            useProxy = true;
            await updateMetrics();
            
            // 30초마다 자동 갱신
            setInterval(updateMetrics, 30000);
            
            logDebug('✅ Dashboard initialization completed');
        }
        
        // 페이지 로드 시 시작
        document.addEventListener('DOMContentLoaded', initialize);
        
        // 글로벌 에러 핸들러
        window.addEventListener('error', function(e) {
            logDebug(`🚨 Global error: \${e.error}`, true);
        });
        
        window.addEventListener('unhandledrejection', function(e) {
            logDebug(`🚨 Unhandled promise rejection: \${e.reason}`, true);
        });
    </script>
</body>
</html>
"@

# HTTP 서버 시작 (향상된 프록시 포함)
Write-Host "🚀 Starting ultimate dashboard..." -ForegroundColor Yellow

try {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    
    $dashboardUrl = "http://localhost:$Port"
    Write-Host "✅ Ultimate dashboard started!" -ForegroundColor Green
    Write-Host "🌐 Dashboard URL: $dashboardUrl" -ForegroundColor Cyan
    Write-Host "🔄 SPARQL Proxy: $dashboardUrl/api/sparql" -ForegroundColor Cyan
    Write-Host "🔧 Debug Mode: Enabled" -ForegroundColor Yellow
    
    if ($OpenBrowser -or -not $PSBoundParameters.ContainsKey('OpenBrowser')) {
        Write-Host "🌐 Opening browser..." -ForegroundColor Yellow
        Start-Process $dashboardUrl
    }
    
    Write-Host "`n=== Ultimate Dashboard Running ===" -ForegroundColor Green
    Write-Host "🎯 All CORS/SPARQL issues addressed" -ForegroundColor Green
    Write-Host "🔍 Browser debug guide included" -ForegroundColor Green
    Write-Host "🧪 Manual test buttons available" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    
    $requestCount = 0
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $requestCount++
            $path = $request.Url.LocalPath
            Write-Host "[$requestCount] $(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $path" -ForegroundColor Gray
            
            if ($path -eq "/api/sparql" -and $request.HttpMethod -eq "POST") {
                # 향상된 SPARQL 프록시
                try {
                    $reader = [System.IO.StreamReader]::new($request.InputStream, [System.Text.Encoding]::UTF8)
                    $requestBody = $reader.ReadToEnd()
                    $reader.Close()
                    
                    if ($Debug) { Write-Host "    📥 Request body: $($requestBody.Substring(0, [Math]::Min(100, $requestBody.Length)))..." -ForegroundColor Blue }
                    
                    $jsonRequest = $requestBody | ConvertFrom-Json
                    $sparqlQuery = $jsonRequest.query
                    
                    Write-Host "    🔄 Proxying: $($sparqlQuery.Substring(0, [Math]::Min(60, $sparqlQuery.Length)))..." -ForegroundColor Blue
                    
                    # Fuseki에 SPARQL 요청 (여러 방법 시도)
                    $fusekiResponse = $null
                    
                    try {
                        # 방법 1: application/sparql-query
                        $fusekiResponse = Invoke-RestMethod -Uri "http://localhost:3030/hvdc/sparql" -Method Post -Headers @{
                            "Accept" = "application/sparql-results+json"
                            "Content-Type" = "application/sparql-query"
                        } -Body $sparqlQuery
                    } catch {
                        # 방법 2: form-urlencoded
                        Write-Host "    🔄 Trying form-urlencoded..." -ForegroundColor Yellow
                        $fusekiResponse = Invoke-RestMethod -Uri "http://localhost:3030/hvdc/sparql" -Method Post -Headers @{
                            "Accept" = "application/sparql-results+json"
                            "Content-Type" = "application/x-www-form-urlencoded"
                        } -Body "query=$([System.Web.HttpUtility]::UrlEncode($sparqlQuery))"
                    }
                    
                    # JSON 응답 반환
                    $jsonResponse = $fusekiResponse | ConvertTo-Json -Depth 10 -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                    
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    
                    Write-Host "    ✅ Proxy success: $($fusekiResponse.results.bindings.Count) results" -ForegroundColor Green
                    
                } catch {
                    Write-Host "    ❌ Proxy error: $($_.Exception.Message)" -ForegroundColor Red
                    
                    $errorResponse = @{ 
                        error = $_.Exception.Message
                        details = $_.Exception.GetType().Name
                    } | ConvertTo-Json
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorResponse)
                    
                    $response.StatusCode = 500
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
            } else {
                # HTML 대시보드 제공
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                $response.ContentType = "text/html; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            
            $response.Close()
            
        } catch [System.Net.HttpListenerException] {
            break
        } catch {
            Write-Warning "Request error: $($_.Exception.Message)"
        }
    }
    
} catch {
    Write-Error "❌ Server start failed: $($_.Exception.Message)"
} finally {
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        Write-Host "🛑 Ultimate dashboard stopped" -ForegroundColor Yellow
    }
    Write-Host "=== Session ended ===" -ForegroundColor Green
}
