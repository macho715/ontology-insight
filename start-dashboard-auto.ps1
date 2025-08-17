# HVDC Dashboard Auto-Port Finder - 포트 충돌 자동 해결
# 사용 가능한 포트를 찾아서 대시보드 자동 실행

param(
    [string]$FusekiUrl = "http://localhost:3030/hvdc",
    [int[]]$PortCandidates = @(8090, 9000, 9080, 8081, 8888, 8889, 8999),
    [switch]$OpenBrowser
)

Write-Host "=== HVDC Dashboard Auto-Port Finder ===" -ForegroundColor Green
Write-Host "Fuseki URL: $FusekiUrl" -ForegroundColor Cyan

# Fuseki 서버 상태 확인
Write-Host "Checking Fuseki server..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3030/$/ping" -TimeoutSec 5
    Write-Host "✅ Fuseki server is healthy" -ForegroundColor Green
} catch {
    Write-Error "❌ Fuseki server is not accessible. Please start the server first:"
    Write-Host "   .\start-hvdc-fuseki.bat" -ForegroundColor Cyan
    exit 1
}

# 포트 사용 가능 여부 확인 함수
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

# 사용 가능한 포트 찾기
$availablePort = $null
Write-Host "Scanning for available ports..." -ForegroundColor Yellow

foreach ($port in $PortCandidates) {
    Write-Host "Testing port $port..." -ForegroundColor Gray -NoNewline
    
    if (Test-PortAvailable -Port $port) {
        Write-Host " ✅ Available" -ForegroundColor Green
        $availablePort = $port
        break
    } else {
        Write-Host " ❌ In use" -ForegroundColor Red
    }
}

if (-not $availablePort) {
    Write-Error "❌ No available ports found. Tried: $($PortCandidates -join ', ')"
    Write-Host "Please free up one of these ports or specify a different port range." -ForegroundColor Yellow
    exit 1
}

Write-Host "🚀 Using port: $availablePort" -ForegroundColor Green

# HTML 대시보드 생성
$htmlContent = @"
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HVDC Ontology Insight Dashboard</title>
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
            max-height: 200px;
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
        
        .footer {
            text-align: center;
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 20px;
                margin: 10px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .status-bar {
                flex-direction: column;
                gap: 10px;
            }
            
            .metrics-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Samsung HVDC Ontology Insight</h1>
            <p>실시간 온톨로지 데이터 대시보드 (Port: $availablePort)</p>
        </div>
        
        <div class="status-bar">
            <div class="status-item">
                <div class="status-icon"></div>
                <span>Fuseki Server Connected</span>
            </div>
            <div class="status-item">
                <span id="lastUpdate">Last Update: Loading...</span>
            </div>
            <div class="status-item">
                <span id="queryCount">Queries: 0</span>
            </div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-value" id="totalTriples">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Total Triples</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-value" id="totalCases">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">HVDC Cases</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-value" id="namedGraphs">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Named Graphs</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-value" id="dataClasses">
                    <div class="loading"></div>
                </div>
                <div class="metric-label">Data Classes</div>
            </div>
        </div>
        
        <div class="query-section">
            <h3>🔍 SPARQL Query Log</h3>
            <div class="query-log" id="queryLog">Initializing dashboard...\n</div>
        </div>
        
        <div class="footer">
            <p>Samsung HVDC Project • Powered by Apache Jena Fuseki • Dashboard Port: $availablePort</p>
        </div>
    </div>
    
    <script>
        const fusekiUrl = '$FusekiUrl';
        let queryCounter = 0;
        
        function logQuery(query, result) {
            queryCounter++;
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = `[\${timestamp}] Query \${queryCounter}: \${query.substring(0, 50)}...\nResult: \${result}\n\n`;
            
            const logElement = document.getElementById('queryLog');
            logElement.textContent = logEntry + logElement.textContent;
            
            // Keep only last 10 entries
            const lines = logElement.textContent.split('\n');
            if (lines.length > 50) {
                logElement.textContent = lines.slice(0, 50).join('\n');
            }
            
            document.getElementById('queryCount').textContent = `Queries: \${queryCounter}`;
        }
        
        async function executeSparqlQuery(query) {
            try {
                const response = await fetch(`\${fusekiUrl}/sparql`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/sparql-query',
                        'Accept': 'application/sparql-results+json'
                    },
                    body: query
                });
                
                if (!response.ok) {
                    throw new Error(`HTTP \${response.status}`);
                }
                
                const data = await response.json();
                return data;
            } catch (error) {
                logQuery(query, `Error: \${error.message}`);
                return null;
            }
        }
        
        async function updateMetrics() {
            // Total Triples
            const triplesQuery = 'SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }';
            const triplesResult = await executeSparqlQuery(triplesQuery);
            if (triplesResult && triplesResult.results.bindings.length > 0) {
                const count = triplesResult.results.bindings[0].count.value;
                document.getElementById('totalTriples').textContent = parseInt(count).toLocaleString();
                logQuery(triplesQuery, `\${count} triples`);
            }
            
            // HVDC Cases
            const casesQuery = 'PREFIX ex:<http://samsung.com/project-logistics#> SELECT (COUNT(?case) AS ?count) WHERE { ?case a ex:Case }';
            const casesResult = await executeSparqlQuery(casesQuery);
            if (casesResult && casesResult.results.bindings.length > 0) {
                const count = casesResult.results.bindings[0].count.value;
                document.getElementById('totalCases').textContent = parseInt(count).toLocaleString();
                logQuery(casesQuery, `\${count} cases`);
            }
            
            // Named Graphs
            const graphsQuery = 'SELECT (COUNT(DISTINCT ?g) AS ?count) WHERE { GRAPH ?g { ?s ?p ?o } }';
            const graphsResult = await executeSparqlQuery(graphsQuery);
            if (graphsResult && graphsResult.results.bindings.length > 0) {
                const count = graphsResult.results.bindings[0].count.value;
                document.getElementById('namedGraphs').textContent = parseInt(count).toLocaleString();
                logQuery(graphsQuery, `\${count} graphs`);
            }
            
            // Data Classes
            const classesQuery = 'SELECT (COUNT(DISTINCT ?class) AS ?count) WHERE { ?s a ?class }';
            const classesResult = await executeSparqlQuery(classesQuery);
            if (classesResult && classesResult.results.bindings.length > 0) {
                const count = classesResult.results.bindings[0].count.value;
                document.getElementById('dataClasses').textContent = parseInt(count).toLocaleString();
                logQuery(classesQuery, `\${count} classes`);
            }
            
            // Update timestamp
            document.getElementById('lastUpdate').textContent = `Last Update: \${new Date().toLocaleTimeString()}`;
        }
        
        // Initialize dashboard
        updateMetrics();
        
        // Auto-refresh every 30 seconds
        setInterval(updateMetrics, 30000);
    </script>
</body>
</html>
"@

# 임시 HTML 파일 생성
$tempHtmlFile = "dashboard_temp_$availablePort.html"
$htmlContent | Out-File -FilePath $tempHtmlFile -Encoding UTF8

Write-Host "📄 Dashboard HTML generated: $tempHtmlFile" -ForegroundColor Green

# PowerShell HTTP 서버 시작
Write-Host "🚀 Starting dashboard server on port $availablePort..." -ForegroundColor Yellow

try {
    # HTTP 리스너 생성
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$availablePort/")
    $listener.Start()
    
    $dashboardUrl = "http://localhost:$availablePort"
    Write-Host "✅ Dashboard server started successfully!" -ForegroundColor Green
    Write-Host "🌐 Dashboard URL: $dashboardUrl" -ForegroundColor Cyan
    Write-Host "📊 Fuseki Data: $FusekiUrl" -ForegroundColor Cyan
    
    # 브라우저 자동 열기
    if ($OpenBrowser -or -not $PSBoundParameters.ContainsKey('OpenBrowser')) {
        Write-Host "🌐 Opening browser..." -ForegroundColor Yellow
        Start-Process $dashboardUrl
    }
    
    Write-Host "`n=== Dashboard Server Running ===" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
    Write-Host "Dashboard: $dashboardUrl" -ForegroundColor White
    Write-Host "Fuseki: $FusekiUrl" -ForegroundColor White
    
    # 요청 처리 루프
    $requestCount = 0
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $requestCount++
            Write-Host "[$requestCount] $(Get-Date -Format 'HH:mm:ss') - $($request.HttpMethod) $($request.Url.LocalPath)" -ForegroundColor Gray
            
            # HTML 콘텐츠 제공
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            
        } catch [System.Net.HttpListenerException] {
            # 서버 중지 시 정상적인 예외
            break
        } catch {
            Write-Warning "Request handling error: $($_.Exception.Message)"
        }
    }
    
} catch {
    Write-Error "❌ Failed to start dashboard server: $($_.Exception.Message)"
} finally {
    # 정리
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        Write-Host "🛑 Dashboard server stopped" -ForegroundColor Yellow
    }
    
    # 임시 파일 삭제
    if (Test-Path $tempHtmlFile) {
        Remove-Item $tempHtmlFile -Force
        Write-Host "🗑️  Temporary files cleaned up" -ForegroundColor Gray
    }
    
    Write-Host "`n=== Dashboard session ended ===" -ForegroundColor Green
}
