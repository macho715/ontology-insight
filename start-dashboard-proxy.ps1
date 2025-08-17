# HVDC Dashboard with SPARQL Proxy - CORS 문제 완전 해결
# 8091에서 SPARQL 프록시 제공하여 동일 오리진으로 만들기

param(
    [int]$Port = 8092,
    [switch]$OpenBrowser
)

Write-Host "=== HVDC Dashboard with SPARQL Proxy ===" -ForegroundColor Green
Write-Host "Dashboard Port: $Port" -ForegroundColor Cyan
Write-Host "SPARQL Proxy: /api/sparql" -ForegroundColor Cyan

# Fuseki 서버 확인
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3030/$/ping" -TimeoutSec 5
    Write-Host "✅ Fuseki server is healthy: $($response.Content.Trim())" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server is not accessible"
    exit 1
}

# 포트 확인
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
    $alternatives = @(8092, 8093, 8094, 9010, 9020)
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

# HTML with Proxy-based SPARQL (CORS 완전 해결)
$htmlContent = @"
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HVDC Dashboard - CORS Fixed</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
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
            transition: transform 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
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
        
        .success { color: #28a745; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        
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
            <p>실시간 온톨로지 데이터 대시보드 (CORS Fixed - Port: $Port)</p>
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
            <h3>🔍 SPARQL Query Log (via Proxy)</h3>
            <div class="query-log" id="queryLog">Initializing SPARQL proxy connection...\n</div>
        </div>
        
        <div class="footer">
            <p>Samsung HVDC Project • SPARQL via Proxy • Port: $Port • CORS Fixed</p>
        </div>
    </div>
    
    <script>
        // 프록시를 통한 SPARQL 호출 (동일 오리진)
        const PROXY_URL = '/api/sparql';
        let queryCounter = 0;
        
        function logMessage(message, isError = false) {
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = `[\${timestamp}] \${isError ? 'ERROR' : 'INFO'}: \${message}\n`;
            
            const logElement = document.getElementById('queryLog');
            logElement.textContent = logEntry + logElement.textContent;
            
            const lines = logElement.textContent.split('\n');
            if (lines.length > 80) {
                logElement.textContent = lines.slice(0, 80).join('\n');
            }
        }
        
        function updateStatus(connected, message) {
            const statusIcon = document.getElementById('statusIcon');
            const statusText = document.getElementById('statusText');
            
            if (connected) {
                statusIcon.className = 'status-icon';
                statusText.innerHTML = '<span class="success">' + (message || 'SPARQL Proxy Connected') + '</span>';
            } else {
                statusIcon.className = 'status-icon status-error';
                statusText.innerHTML = '<span class="error">' + (message || 'Proxy Connection Error') + '</span>';
            }
        }
        
        // 프록시를 통한 SPARQL 실행
        async function executeSparqlQuery(query, description) {
            queryCounter++;
            document.getElementById('queryCount').textContent = `Queries: \${queryCounter}`;
            
            logMessage(`🔄 Query \${queryCounter}: \${description}`);
            
            try {
                const response = await fetch(PROXY_URL, {
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
                
                logMessage(`✅ Query \${queryCounter} success: \${data.results.bindings.length} results`);
                updateStatus(true, 'SPARQL Proxy Working');
                
                return data;
                
            } catch (error) {
                logMessage(`❌ Query \${queryCounter} failed: \${error.message}`, true);
                updateStatus(false, `Proxy Error: \${error.message}`);
                return null;
            }
        }
        
        async function updateMetrics() {
            logMessage('=== Starting metrics update via proxy ===');
            
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
                    document.getElementById(queryInfo.cardId).classList.remove('error');
                } else {
                    document.getElementById(queryInfo.elementId).innerHTML = '<span class="error">Error</span>';
                    document.getElementById(queryInfo.cardId).classList.add('error');
                }
                
                // 각 쿼리 간 100ms 간격
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            
            document.getElementById('lastUpdate').textContent = `Last Update: \${new Date().toLocaleTimeString()}`;
            logMessage('=== Metrics update completed ===');
        }
        
        async function initialize() {
            logMessage('🚀 Dashboard initializing with SPARQL proxy...');
            updateStatus(false, 'Connecting to Proxy...');
            
            await updateMetrics();
            setInterval(updateMetrics, 30000);
            
            logMessage('✅ Dashboard initialization completed');
        }
        
        document.addEventListener('DOMContentLoaded', initialize);
    </script>
</body>
</html>
"@

# HTTP 서버 시작 (SPARQL 프록시 포함)
Write-Host "🚀 Starting dashboard with SPARQL proxy..." -ForegroundColor Yellow

try {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    
    $dashboardUrl = "http://localhost:$Port"
    Write-Host "✅ Dashboard with proxy started!" -ForegroundColor Green
    Write-Host "🌐 Dashboard URL: $dashboardUrl" -ForegroundColor Cyan
    Write-Host "🔄 SPARQL Proxy: $dashboardUrl/api/sparql" -ForegroundColor Cyan
    
    if ($OpenBrowser -or -not $PSBoundParameters.ContainsKey('OpenBrowser')) {
        Write-Host "🌐 Opening browser..." -ForegroundColor Yellow
        Start-Process $dashboardUrl
    }
    
    Write-Host "`n=== Dashboard + SPARQL Proxy Running ===" -ForegroundColor Green
    Write-Host "🔧 CORS 문제 완전 해결 (프록시 방식)" -ForegroundColor Green
    Write-Host "📊 동일 오리진으로 SPARQL 호출" -ForegroundColor Green
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
                # SPARQL 프록시 처리
                try {
                    $reader = [System.IO.StreamReader]::new($request.InputStream)
                    $requestBody = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $jsonRequest = $requestBody | ConvertFrom-Json
                    $sparqlQuery = $jsonRequest.query
                    
                    Write-Host "    🔄 Proxying SPARQL: $($sparqlQuery.Substring(0, [Math]::Min(50, $sparqlQuery.Length)))..." -ForegroundColor Blue
                    
                    # Fuseki에 SPARQL 요청
                    $fusekiResponse = Invoke-RestMethod -Uri "http://localhost:3030/hvdc/sparql" -Method Post -Headers @{
                        "Accept" = "application/sparql-results+json"
                        "Content-Type" = "application/sparql-query"
                    } -Body $sparqlQuery
                    
                    # JSON 응답 반환
                    $jsonResponse = $fusekiResponse | ConvertTo-Json -Depth 10
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                    
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    
                    Write-Host "    ✅ SPARQL proxy success" -ForegroundColor Green
                    
                } catch {
                    Write-Host "    ❌ SPARQL proxy error: $($_.Exception.Message)" -ForegroundColor Red
                    
                    $errorResponse = @{ error = $_.Exception.Message } | ConvertTo-Json
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
    Write-Error "❌ Failed to start server: $($_.Exception.Message)"
} finally {
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        Write-Host "🛑 Dashboard server stopped" -ForegroundColor Yellow
    }
    Write-Host "=== Session ended ===" -ForegroundColor Green
}
