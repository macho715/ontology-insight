# HVDC Ontology Insight - 문제 해결 가이드

## 🚨 60초 트러블슈팅 체크리스트

### 1️⃣ 서버 연결 문제

| 증상 | 원인 추정 | 해결 방법 |
|------|-----------|-----------|
| `localhost:3030` 접속 안됨 | 서버 미실행 | `.\start-hvdc-fuseki.bat` 실행 |
| `Connection refused` | 포트 충돌 | `netstat -an \| findstr 3030` 확인 후 프로세스 종료 |
| `404 Not Found /hvdc` | 잘못된 엔드포인트 | 경로 확인: `/hvdc` (대소문자 구분) |
| 서버 실행 후 즉시 종료 | Java 버전 문제 | `java -version` 확인, Java 11+ 필요 |

**빠른 해결:**
```powershell
# 서버 상태 확인
Test-NetConnection -ComputerName localhost -Port 3030

# 프로세스 확인
Get-Process | Where-Object {$_.ProcessName -like "*java*"}

# 서버 재시작
.\start-hvdc-fuseki.bat
```

### 2️⃣ 데이터 적재 문제

| 증상 | 원인 추정 | 해결 방법 |
|------|-----------|-----------|
| `415 Unsupported Media Type` | Content-Type 헤더 누락 | `-H "Content-Type: text/turtle"` 추가 |
| `COUNT(*) = 0` | 데이터 미적재 | TTL 파일 경로 및 구문 확인 |
| `403 Forbidden /data` | 업데이트 권한 없음 | 서버 실행 시 `--update` 옵션 확인 |
| `Turtle parsing error` | TTL 구문 오류 | TTL 파일 구문 검증 |

**빠른 해결:**
```powershell
# 강제 데이터 재적재
.\scripts\hvdc-data-loader.ps1 -Force -Validate

# 수동 업로드 (cURL 대신)
Invoke-RestMethod -Uri "http://localhost:3030/hvdc/data?default" -Method Post -ContentType "text/turtle" -InFile "triples.ttl"

# 데이터 확인
$query = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
Invoke-RestMethod -Uri "http://localhost:3030/hvdc/sparql" -Method Post -Body @{ query = $query } -ContentType "application/x-www-form-urlencoded"
```

### 3️⃣ SPARQL 쿼리 문제

| 증상 | 원인 추정 | 해결 방법 |
|------|-----------|-----------|
| `Query parse error` | SPARQL 구문 오류 | PREFIX 선언 및 구문 확인 |
| `No results returned` | 데이터 없음/잘못된 필터 | 기본 `SELECT * WHERE { ?s ?p ?o } LIMIT 10` 테스트 |
| `Timeout` | 복잡한 쿼리/대용량 | LIMIT 추가 또는 쿼리 최적화 |
| `406 Not Acceptable` | Accept 헤더 문제 | `Accept: application/sparql-results+json` 설정 |

**빠른 해결:**
```powershell
# 기본 연결 테스트
.\scripts\hvdc-query-runner.ps1 -QueryFile queries\01-monthly-warehouse-stock.rq -ShowResults

# 전체 쿼리 테스트
.\scripts\hvdc-query-runner.ps1 -AllQueries

# 수동 쿼리 실행
$testQuery = "PREFIX ex:<http://samsung.com/project-logistics#> SELECT ?s ?p ?o WHERE { ?s a ex:Case } LIMIT 5"
Invoke-RestMethod -Uri "http://localhost:3030/hvdc/sparql" -Method Post -Body @{ query = $testQuery } -ContentType "application/x-www-form-urlencoded"
```

### 4️⃣ 성능 문제

| 증상 | 원인 추정 | 해결 방법 |
|------|-----------|-----------|
| `OutOfMemoryError` | JVM 힙 부족 | `JAVA_OPTS=-Xmx4g` 환경변수 설정 |
| 쿼리 응답 느림 | 인덱스 미최적화 | TDB2 통계 업데이트 |
| 서버 응답 없음 | 메모리 누수 | 서버 재시작 |
| 대용량 데이터 로딩 실패 | 메모리/시간 초과 | `tdb2.tdbloader` 오프라인 로딩 |

**빠른 해결:**
```powershell
# JVM 메모리 설정
$env:JAVA_OPTS = "-Xmx4g -Xms1g"
.\start-hvdc-fuseki.bat

# 오프라인 데이터 로딩 (서버 정지 상태)
cd fuseki\apache-jena-fuseki-4.10.0
.\tdb2.tdbloader --loc .\data\tdb-hvdc ..\..\..\triples.ttl

# 통계 업데이트
.\tdb2.tdbstats --loc .\data\tdb-hvdc
```

## 🔧 고급 문제 해결

### TDB2 데이터베이스 문제

**증상**: 데이터 손상, 락 오류, 인덱스 문제
```powershell
# 데이터베이스 검증
cd fuseki\apache-jena-fuseki-4.10.0
.\tdb2.tdbquery --loc .\data\tdb-hvdc "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"

# 데이터베이스 복구 (백업 후 실행)
.\tdb2.tdbdump --loc .\data\tdb-hvdc > backup.ttl
Remove-Item -Recurse -Force .\data\tdb-hvdc
.\tdb2.tdbloader --loc .\data\tdb-hvdc backup.ttl
```

### 동시 접근 문제

**증상**: `Database is in use by another process`
```powershell
# 모든 Java 프로세스 확인
Get-Process java

# Fuseki 프로세스 강제 종료
Get-Process | Where-Object {$_.ProcessName -eq "java" -and $_.CommandLine -like "*fuseki*"} | Stop-Process -Force

# 락 파일 제거 (주의: 서버 완전 종료 후에만)
Remove-Item -Path "fuseki\apache-jena-fuseki-4.10.0\data\tdb-hvdc\tdb.lock" -ErrorAction SilentlyContinue
```

### 네트워크 및 방화벽 문제

**증상**: 외부에서 접근 불가, 연결 거부
```powershell
# 방화벽 규칙 확인
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*3030*"}

# 포트 리스닝 확인
netstat -an | findstr :3030

# 방화벽 예외 추가 (관리자 권한 필요)
New-NetFirewallRule -DisplayName "Fuseki SPARQL Server" -Direction Inbound -Protocol TCP -LocalPort 3030 -Action Allow
```

## 📊 진단 도구

### 1. 자동 진단 스크립트
```powershell
# 전체 시스템 진단
.\smoke-test.ps1

# 상세 검증 (데이터 재로딩 포함)
.\full-validation.ps1 -ReloadData -DetailedReport
```

### 2. 수동 진단 명령어
```powershell
# 시스템 상태 체크
Write-Host "=== System Status Check ==="
Write-Host "Java Version:"
java -version
Write-Host "`nFuseki Server:"
Test-NetConnection localhost -Port 3030 -InformationLevel Quiet
Write-Host "`nTTL File:"
if (Test-Path "triples.ttl") { "Found" } else { "Missing" }
Write-Host "`nQuery Files:"
(Get-ChildItem queries -Filter "*.rq").Count
```

### 3. 로그 분석
```powershell
# Fuseki 로그 확인 (실행 중인 터미널에서)
# 일반적인 오류 패턴:
# - "Address already in use" → 포트 충돌
# - "Permission denied" → 권한 문제
# - "Out of memory" → JVM 힙 부족
# - "Parse error" → TTL/SPARQL 구문 오류
```

## 🚑 응급 복구 절차

### 완전 재설치 (10분)
```powershell
# 1. 모든 Java 프로세스 종료
Get-Process java | Stop-Process -Force

# 2. 기존 데이터 백업
if (Test-Path "fuseki\apache-jena-fuseki-4.10.0\data\tdb-hvdc") {
    Copy-Item -Recurse "fuseki\apache-jena-fuseki-4.10.0\data\tdb-hvdc" "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

# 3. 클린 재설치
Remove-Item -Recurse -Force "fuseki" -ErrorAction SilentlyContinue
.\setup-fuseki.ps1

# 4. 서버 실행
.\start-hvdc-fuseki.bat

# 5. 데이터 재적재
.\scripts\hvdc-data-loader.ps1 -Force -Validate

# 6. 검증
.\full-validation.ps1 -DetailedReport
```

## 📞 에스컬레이션 가이드

### Level 1: 자체 해결 (15분)
- [ ] 이 가이드의 60초 체크리스트 실행
- [ ] 자동 진단 스크립트 실행
- [ ] 기본 재시작 절차 시도

### Level 2: 고급 진단 (30분)
- [ ] 로그 분석 및 오류 패턴 확인
- [ ] TDB2 데이터베이스 검증
- [ ] 네트워크/방화벽 설정 확인

### Level 3: 전문가 지원 (60분+)
- [ ] Apache Jena 메일링 리스트 문의
- [ ] GitHub Issues 검색/등록
- [ ] 시스템 관리자 에스컬레이션

**지원 요청 시 포함할 정보:**
- OS 버전 및 Java 버전
- Fuseki 버전 및 실행 명령어
- 오류 메시지 전문 (로그 포함)
- 재현 단계
- `.\smoke-test.ps1` 실행 결과
