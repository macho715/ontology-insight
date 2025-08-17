# HVDC Ontology Insight - Fuseki Setup Script (PowerShell)
# Apache Jena Fuseki 다운로드 및 설치 자동화

param(
    [string]$FusekiVersion = "4.10.0",
    [string]$InstallDir = ".\fuseki",
    [switch]$SkipDownload
)

Write-Host "=== HVDC Ontology Insight - Fuseki Setup ===" -ForegroundColor Green

# Java 버전 확인
Write-Host "Java 버전 확인 중..." -ForegroundColor Yellow
try {
    $javaVersion = java -version 2>&1 | Select-String "version" | ForEach-Object { $_.ToString() }
    Write-Host "Java: $javaVersion" -ForegroundColor Green
} catch {
    Write-Error "Java가 설치되지 않았거나 PATH에 없습니다. Java 11+ 설치 후 다시 실행하세요."
    exit 1
}

# 설치 디렉토리 생성
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "설치 디렉토리 생성: $InstallDir" -ForegroundColor Green
}

# Fuseki 다운로드 (생략 가능)
$fusekiZip = "$InstallDir\apache-jena-fuseki-$FusekiVersion.zip"
$fusekiUrl = "https://archive.apache.org/dist/jena/binaries/apache-jena-fuseki-$FusekiVersion.zip"

if (-not $SkipDownload -and -not (Test-Path $fusekiZip)) {
    Write-Host "Fuseki $FusekiVersion 다운로드 중..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $fusekiUrl -OutFile $fusekiZip -UseBasicParsing
        Write-Host "다운로드 완료: $fusekiZip" -ForegroundColor Green
    } catch {
        Write-Error "다운로드 실패. 수동으로 다운로드하거나 -SkipDownload 옵션을 사용하세요."
        Write-Host "수동 다운로드 URL: $fusekiUrl" -ForegroundColor Cyan
        exit 1
    }
}

# 압축 해제
$extractDir = "$InstallDir\apache-jena-fuseki-$FusekiVersion"
if (-not (Test-Path $extractDir)) {
    if (Test-Path $fusekiZip) {
        Write-Host "Fuseki 압축 해제 중..." -ForegroundColor Yellow
        Expand-Archive -Path $fusekiZip -DestinationPath $InstallDir -Force
        Write-Host "압축 해제 완료: $extractDir" -ForegroundColor Green
    } else {
        Write-Warning "Fuseki ZIP 파일을 찾을 수 없습니다. 수동으로 압축을 해제하세요."
    }
}

# TDB2 데이터 디렉토리 생성
$dataDir = "$extractDir\data\tdb-hvdc"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Write-Host "TDB2 데이터 디렉토리 생성: $dataDir" -ForegroundColor Green
}

# 실행 스크립트 생성
$startScript = @"
@echo off
REM HVDC Ontology Insight - Fuseki Server Start
cd /d "$extractDir"
echo Starting Fuseki server for HVDC dataset...
echo Web UI: http://localhost:3030/hvdc
echo SPARQL Endpoint: http://localhost:3030/hvdc/sparql
echo.
fuseki-server.bat --tdb2 --loc .\data\tdb-hvdc --update /hvdc
"@

$startScript | Out-File -FilePath "start-hvdc-fuseki.bat" -Encoding ascii
Write-Host "실행 스크립트 생성: start-hvdc-fuseki.bat" -ForegroundColor Green

# 리눅스/맥용 실행 스크립트
$startScriptUnix = @"
#!/bin/bash
# HVDC Ontology Insight - Fuseki Server Start
cd "$extractDir"
echo "Starting Fuseki server for HVDC dataset..."
echo "Web UI: http://localhost:3030/hvdc"
echo "SPARQL Endpoint: http://localhost:3030/hvdc/sparql"
echo
./fuseki-server --tdb2 --loc ./data/tdb-hvdc --update /hvdc
"@

$startScriptUnix | Out-File -FilePath "start-hvdc-fuseki.sh" -Encoding utf8
Write-Host "Unix 실행 스크립트 생성: start-hvdc-fuseki.sh" -ForegroundColor Green

Write-Host "`n=== 설치 완료 ===" -ForegroundColor Green
Write-Host "실행 방법:" -ForegroundColor Cyan
Write-Host "  Windows: .\start-hvdc-fuseki.bat" -ForegroundColor White
Write-Host "  Linux/Mac: chmod +x start-hvdc-fuseki.sh && ./start-hvdc-fuseki.sh" -ForegroundColor White
Write-Host "`nWeb UI: http://localhost:3030/hvdc" -ForegroundColor Cyan
Write-Host "SPARQL Endpoint: http://localhost:3030/hvdc/sparql" -ForegroundColor Cyan
