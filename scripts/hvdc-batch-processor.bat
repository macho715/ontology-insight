@echo off
REM HVDC Ontology Insight - Batch Processor (Windows)
REM 배치 데이터 처리 및 보고서 생성

setlocal EnableDelayedExpansion

set FUSEKI_URL=http://localhost:3030/hvdc
set QUERIES_DIR=queries
set RESULTS_DIR=results
set TTL_FILE=triples.ttl

for /f "tokens=1-4 delims=/ " %%i in ('date /t') do (
    set DATE=%%l%%j%%k
)
for /f "tokens=1-2 delims=: " %%i in ('time /t') do (
    set TIME=%%i%%j
)
set TIMESTAMP=%DATE%_%TIME%

echo === HVDC Batch Processor ===

REM Create results directory
if not exist "%RESULTS_DIR%" mkdir "%RESULTS_DIR%"

REM Check Fuseki server
echo Checking Fuseki server...
curl -s -f "%FUSEKI_URL%/sparql" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Fuseki server is not accessible
    echo Start server: start-hvdc-fuseki.bat
    exit /b 1
) else (
    echo [OK] Fuseki server is running
)

REM Process reload option
if "%1"=="--reload" (
    echo Reloading TTL data...
    curl -s -X DELETE "%FUSEKI_URL%/data?default" >nul 2>&1
    if exist "%TTL_FILE%" (
        curl -s -X POST -H "Content-Type: text/turtle" --data-binary "@%TTL_FILE%" "%FUSEKI_URL%/data?default"
        echo [OK] TTL data reloaded
    ) else (
        echo [ERROR] TTL file not found: %TTL_FILE%
        exit /b 1
    )
)

echo Processing queries...

REM Execute all queries
for %%f in ("%QUERIES_DIR%\*.rq") do (
    set QUERY_NAME=%%~nf
    set OUTPUT_FILE=%RESULTS_DIR%\!QUERY_NAME!_%TIMESTAMP%.json
    
    echo Executing: !QUERY_NAME!
    curl -s -H "Accept: application/sparql-results+json" --data-urlencode "query@%%f" "%FUSEKI_URL%/sparql" > "!OUTPUT_FILE!"
    
    if exist "!OUTPUT_FILE!" (
        for %%s in ("!OUTPUT_FILE!") do set FILE_SIZE=%%~zs
        echo [OK] Results saved: !OUTPUT_FILE! (!FILE_SIZE! bytes)
    ) else (
        echo [ERROR] Query failed: !QUERY_NAME!
    )
)

REM Generate simple report
set REPORT_FILE=%RESULTS_DIR%\hvdc_report_%TIMESTAMP%.txt
echo HVDC Ontology Insight Report > "%REPORT_FILE%"
echo Generated: %DATE% %TIME% >> "%REPORT_FILE%"
echo. >> "%REPORT_FILE%"
echo Results: >> "%REPORT_FILE%"
dir /b "%RESULTS_DIR%\*_%TIMESTAMP%.*" >> "%REPORT_FILE%" 2>nul

echo === Batch processing completed ===
echo Results directory: %RESULTS_DIR%
echo Report file: %REPORT_FILE%

REM Show results summary
echo.
echo Summary:
dir "%RESULTS_DIR%\*_%TIMESTAMP%.*"

pause
