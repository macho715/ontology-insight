# SPARQL Proxy 테스트 스크립트

$proxyUrl = "http://localhost:8092/api/sparql"
$query = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"

$requestBody = @{
    query = $query
} | ConvertTo-Json

Write-Host "Testing SPARQL Proxy..." -ForegroundColor Yellow
Write-Host "URL: $proxyUrl" -ForegroundColor Cyan
Write-Host "Query: $query" -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri $proxyUrl -Method Post -Body $requestBody -ContentType "application/json"
    
    Write-Host "✅ Proxy test successful!" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor White
    $response | ConvertTo-Json -Depth 5
    
    if ($response.results -and $response.results.bindings) {
        $count = $response.results.bindings[0].count.value
        Write-Host "🔢 Total Triples: $count" -ForegroundColor Green
    }
    
} catch {
    Write-Host "❌ Proxy test failed: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $errorText = $reader.ReadToEnd()
        Write-Host "Error details: $errorText" -ForegroundColor Red
    }
}
