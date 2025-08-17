# 🚀 HVDC Ontology Insight - 5분 실행 가이드

## ⚡ 초고속 시작 (Java 설치 필요)

### 1️⃣ Java 설치 확인 (30초)
```powershell
java -version
# 없으면 → install-java.md 참고
```

### 2️⃣ Fuseki 설치 & 실행 (2분)
```powershell
# 자동 설치
.\setup-fuseki.ps1

# 서버 실행
.\start-hvdc-fuseki.bat
# → 브라우저: http://localhost:3030/hvdc
```

### 3️⃣ 데이터 적재 & 검증 (1분)
```powershell
# 데이터 로딩
.\scripts\hvdc-data-loader.ps1 -Force -Validate

# 연기 테스트
.\smoke-test.ps1
```

### 4️⃣ SPARQL 쿼리 실행 (1분)
```powershell
# 모든 핵심 쿼리 실행
.\scripts\hvdc-query-runner.ps1 -AllQueries

# 특정 쿼리 + CSV 출력
.\scripts\hvdc-query-runner.ps1 -QueryFile queries\03-invoice-risk-analysis.rq -OutputFormat csv -OutputFile risks.csv
```

### 5️⃣ 완전 검증 (30초)
```powershell
# 전체 시스템 검증
.\full-validation.ps1 -DetailedReport
```

---

## 🎯 예상 결과

### ✅ 성공 시 출력
```
=== HVDC Ontology Insight - Full Validation ===
[PASS] Triple Count: 150+ triples loaded
[PASS] Monthly Warehouse Stock: 5 rows returned (245.67ms)
[PASS] Case Timeline Events: 7 rows returned (189.23ms)  
[PASS] Invoice Risk Analysis: 2 rows returned (156.78ms)
[PASS] OOG HS Risk Assessment: 4 rows returned (198.45ms)

🎉 FULL VALIDATION PASSED!
✅ HVDC Ontology Insight system is fully operational
```

### 📊 샘플 쿼리 결과
1. **월별 창고 재고**: Ulsan Plant, Busan Port, Dubai Hub (2024-10/11)
2. **케이스 타임라인**: 3개 케이스 × 울산→부산→두바이 운송체인
3. **Invoice 리스크**: 2개 리스크 케이스 탐지 (VAT/Duty 누락, 음수금액)
4. **OOG/HS 리스크**: 45t/28t 초중량 화물 HIGH 리스크 분류

---

## 🚨 문제 발생시

### Java 없음
```powershell
# Chocolatey로 빠른 설치
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco install openjdk17 -y
```

### 서버 연결 실패
```powershell
# 포트 확인
netstat -an | findstr :3030

# 프로세스 정리
Get-Process java | Stop-Process -Force

# 재시작
.\start-hvdc-fuseki.bat
```

### 데이터 적재 실패
```powershell
# 강제 재적재
.\scripts\hvdc-data-loader.ps1 -Force

# 수동 업로드
Invoke-RestMethod -Uri "http://localhost:3030/hvdc/data?default" -Method Post -ContentType "text/turtle" -InFile "triples.ttl"
```

---

## 📋 체크리스트

- [ ] Java 11+ 설치 확인
- [ ] Fuseki 서버 실행 (http://localhost:3030/hvdc)
- [ ] TTL 데이터 적재 완료 (150+ triples)
- [ ] 4개 핵심 쿼리 정상 실행
- [ ] 연기 테스트 통과
- [ ] 완전 검증 통과

---

## 🎉 성공! 이제 사용 가능

### Web UI
- **관리 콘솔**: http://localhost:3030/hvdc
- **SPARQL 쿼리**: http://localhost:3030/hvdc/sparql

### 자동화 스크립트
- **일일 체크**: `.\smoke-test.ps1`
- **데이터 재로딩**: `.\scripts\hvdc-data-loader.ps1 -Force`
- **배치 처리**: `.\scripts\hvdc-batch-processor.bat`

### 상세 가이드
- **README.md**: 전체 시스템 가이드
- **troubleshooting-guide.md**: 문제 해결
- **operational-checklist.md**: 운영 루틴

---

**🎯 목표 달성**: Docker 없이 로컬 환경에서 완전한 Fuseki + SPARQL 기반 HVDC 물류 분석 시스템 구축 완료! 🏗️✨
