#!/usr/bin/env powershell
# HVDC Gateway ngrok 설정 및 실행 스크립트

param(
    [string]$AuthToken = "",
    [string]$Domain = "",
    [switch]$BasicAuth,
    [string]$AuthUser = "hvdcadmin",
    [string]$AuthPass = "HVDCGateway2025!",
    [switch]$DryRun
)

Write-Host "🌐 HVDC Gateway ngrok 설정 시작..." -ForegroundColor Green

# 1. AuthToken 등록 (필요한 경우)
if ($AuthToken -ne "") {
    Write-Host "🔑 ngrok AuthToken 등록 중..." -ForegroundColor Yellow
    if (-not $DryRun) {
        ngrok config add-authtoken $AuthToken
        Write-Host "✅ AuthToken 등록 완료" -ForegroundColor Green
    } else {
        Write-Host "🔍 DRY RUN: Would register AuthToken: $($AuthToken.Substring(0,8))..." -ForegroundColor Cyan
    }
}

# 2. Mock Gateway 서버 상태 확인
Write-Host "📡 Mock Gateway 서버 상태 확인..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8080/v1/health" -TimeoutSec 5
    Write-Host "✅ Mock Gateway 서버 정상 작동: $($response.status)" -ForegroundColor Green
} catch {
    Write-Host "❌ Mock Gateway 서버가 실행되지 않음. 먼저 서버를 시작하세요:" -ForegroundColor Red
    Write-Host "   python mock_gateway_server.py" -ForegroundColor Yellow
    exit 1
}

# 3. ngrok 설정 파일 생성
$configPath = "$env:USERPROFILE\.config\ngrok\ngrok.yml"
$configDir = Split-Path $configPath -Parent

if (-not (Test-Path $configDir)) {
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
}

$configContent = @"
version: "3"
authtoken: $AuthToken

tunnels:
  hvdc-gateway:
    addr: 8080
    proto: http
"@

if ($Domain -ne "") {
    $configContent += "`n    domain: $Domain"
}

if ($BasicAuth) {
    $configContent += "`n    basic_auth:`n      - ${AuthUser}:${AuthPass}"
}

if (-not $DryRun) {
    $configContent | Out-File -FilePath $configPath -Encoding UTF8
    Write-Host "✅ ngrok 설정 파일 생성: $configPath" -ForegroundColor Green
} else {
    Write-Host "🔍 DRY RUN: Would create config file:" -ForegroundColor Cyan
    Write-Host $configContent -ForegroundColor Gray
}

# 4. ngrok 터널 실행
Write-Host "🚀 ngrok 터널 시작 중..." -ForegroundColor Yellow

if (-not $DryRun) {
    if ($Domain -ne "") {
        Write-Host "🔗 고정 도메인으로 터널 실행: $Domain" -ForegroundColor Cyan
        $ngrokArgs = @("http", "--domain", $Domain, "8080")
    } else {
        Write-Host "🔗 임시 URL로 터널 실행 (무료 플랜)" -ForegroundColor Cyan
        $ngrokArgs = @("http", "8080")
    }
    
    if ($BasicAuth) {
        $ngrokArgs += @("--basic-auth", "${AuthUser}:${AuthPass}")
    }
    
    Write-Host "💡 실행 명령어: ngrok $($ngrokArgs -join ' ')" -ForegroundColor Gray
    Write-Host ""
    Write-Host "📋 다음 단계:" -ForegroundColor Yellow
    Write-Host "1. ngrok 터널이 시작되면 'Forwarding' URL을 확인하세요" -ForegroundColor White
    Write-Host "2. 해당 URL로 헬스체크: curl https://[URL]/v1/health" -ForegroundColor White
    Write-Host "3. OpenAPI 스키마의 servers.url을 해당 URL로 업데이트하세요" -ForegroundColor White
    Write-Host ""
    
    # ngrok 실행
    & ngrok @ngrokArgs
} else {
    Write-Host "🔍 DRY RUN: Would execute ngrok with args: $ngrokArgs" -ForegroundColor Cyan
}

Write-Host "🎉 ngrok 설정 완료!" -ForegroundColor Green
