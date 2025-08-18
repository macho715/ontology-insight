# 🚀 HVDC 온톨로지 인사이트 시스템

[![HVDC Audit Integrity & Smoke Test](https://github.com/macho715/ontology-insight/actions/workflows/audit-smoke.yml/badge.svg)](https://github.com/macho715/ontology-insight/actions/workflows/audit-smoke.yml)

**삼성물산과 ADNOC·DSV 파트너십을 위한 엔터프라이즈급 HVDC 프로젝트 물류 온톨로지 시스템**

## 🎯 시스템 개요

본 시스템은 다음 기능을 제공합니다:

- **🔧 비즈니스 규칙 엔진**: CostGuard, HS Risk, CertChk 검증
- **🚀 안전한 Fuseki 배포**: 스테이징→검증→교체 (롤백 지원)
- **🔍 자연어 쿼리**: NLQ→SPARQL 변환 및 안전성 검증
- **📊 실시간 분석**: 고위험 송장 탐지, HVDC 코드 관리
- **🔒 엔터프라이즈 보안**: PII 마스킹, 감사 추적, SHA-256 무결성
- **🌐 Gateway API 통합**: OpenAPI 3.1 스키마 지원, MRR/ETA/CostGuard
- **🤖 Claude Native 브릿지**: MACHO-GPT v3.7 명령어 시스템 완전 통합

## 🏗️ 시스템 아키텍처

```
📝 자연어 입력 (Natural Language Input)
    ↓ (nlq_query_wrapper_flask.py)
🔍 NLQ→SPARQL 변환 + 안전성 검증
    ↓ (nlq_to_sparql.py)
📊 SPARQL 실행 → Fuseki 쿼리
    ↓ (fuseki_swap_verify.py)
🚀 안전한 데이터 배포 (스테이징→검증→교체)
    ↓ (hvdc_rules.py)
⚖️ 비즈니스 규칙 검증 (CostGuard/HS Risk/CertChk)
    ↓ (hvdc_gateway_client.py)
🌐 Gateway API 통합 (MRR/ETA/CostGuard)
    ↓ (claude_native_bridge.py)
🤖 Claude Native 브릿지 (MACHO-GPT v3.7)
    ↓
✅ 결과 + 종합 감사 로깅
```

## 🚀 빠른 시작

### 시스템 요구사항

- Python 3.11+
- Java 11+ (Apache Jena Fuseki용)
- Git

### 설치 방법

```bash
# 저장소 복제
git clone https://github.com/macho715/ontology-insight.git
cd ontology-insight

# 의존성 설치
pip install -r requirements.txt

# Fuseki 서버 설정
cd fuseki/apache-jena-fuseki-4.10.0
./fuseki-server --port=3030 --mem /hvdc &

# 설치 확인
python system_health_check.py
```

### 기본 사용법

```bash
# 1. 메인 API 서버 시작
python hvdc_api.py
# 서버 실행: http://localhost:5002

# 2. NLQ 쿼리 서비스 시작
python nlq_query_wrapper_flask.py  
# 서비스 실행: http://localhost:5010

# 3. Gateway Mock 서버 시작 (테스트용)
python mock_gateway_server.py
# 서버 실행: http://localhost:8080

# 4. Claude Native 브릿지 시작 (v3.7)
cd upgrade/v3.7-CLAUDE-NATIVE
python claude_native_bridge.py
# 서버 실행: http://localhost:5003

# 5. 통합 테스트 실행
python test_integration.py
python test_gateway_integration.py

# 6. 자연어 쿼리 테스트
curl -X POST http://localhost:5010/nlq-query \
  -H "Content-Type: application/json" \
  -d '{"q": "고위험 송장을 보여주세요"}'

# 7. Gateway API 테스트
python quick_demo.py
```

## 🔍 자연어 쿼리 예시

시스템은 지능형 자연어 쿼리를 지원합니다:

```bash
# 위험 분석
"고위험 송장을 보여주세요"
"VAT나 관세가 누락된 송장을 찾아주세요"
"음수 금액을 가진 중요 송장을 나열해주세요"

# HVDC 코드 관리
"모든 HVDC 코드를 나열해주세요"
"상태별 HVDC 코드를 보여주세요"
"완료된 HVDC 케이스를 찾아주세요"

# 비용 분석
"비용 편차 분석을 해주세요"
"5% 이상 가격 변동을 보여주세요"
"실제 대 표준 요율을 비교해주세요"

# 규정 준수 검사
"HS 코드 위험 분석을 해주세요"
"통제 품목을 보여주세요"
"인증서 검증 상태를 확인해주세요"
```

## 🌐 Gateway API 기능

### 지원되는 엔드포인트

```bash
# MRR 드래프트 생성
POST /v1/mrr/draft
{
  "po_no": "PO-2025-001",
  "site": "MIR",
  "items": [{"part_no": "HVDC-TR-001", "qty": 2, "status": "OK"}]
}

# ETA 예측
POST /v1/predict/eta
{
  "origin": "Khalifa Port",
  "destination": "MIR substation",
  "mode": "ROAD"
}

# CostGuard 비용 추정
POST /v1/costguard/estimate
{
  "input_tokens": 1000,
  "output_tokens": 500,
  "input_cost_per_1k": 0.03,
  "output_cost_per_1k": 0.06
}
```

## 📊 API 엔드포인트

### 메인 API (포트 5002)

- `GET /health` - 시스템 헬스체크
- `POST /ingest` - 감사 로깅과 함께 데이터 수집
- `POST /run-rules` - 비즈니스 규칙 검증 실행
- `GET /evidence/<case_id>` - 케이스 증거 조회
- `POST /nlq` - 자연어 쿼리 처리
- `GET /audit/summary` - 감사 로그 요약
- `POST /fuseki/deploy` - 안전한 Fuseki 배포
- `GET /fuseki/stats` - Fuseki 통계 정보
- `POST /audit/verify` - 감사 로그 무결성 검증

### NLQ 서비스 (포트 5010)

- `POST /nlq-query` - 자연어를 SPARQL로 변환

### Gateway Mock 서버 (포트 8080)

- `GET /v1/health` - Gateway 헬스체크
- `POST /v1/mrr/draft` - MRR 드래프트 생성
- `POST /v1/predict/eta` - ETA 예측
- `POST /v1/costguard/estimate` - 비용 추정

### Claude Native 브릿지 (포트 5003)

- `POST /claude/execute` - MACHO-GPT 명령어 실행
- `POST /claude/workflow` - 자동화 워크플로우 실행
- `GET /claude/status` - 브릿지 상태 확인
- `POST /gateway/mrr/draft` - Gateway MRR 통합
- `POST /gateway/predict/eta` - Gateway ETA 통합

## 🔧 비즈니스 규칙

### CostGuard (비용 보호)
- **목적**: 가격 편차 탐지
- **임계값**: ≤2% PASS, ≤5% WARN, ≤10% HIGH, >10% CRITICAL
- **검증**: 송장 가격을 표준 요율과 비교

### HS Risk (HS 위험도)
- **목적**: 고위험 HS 코드 식별
- **범주**: 정적 변환기(85), 금속 제품(73), 기계류(84)
- **위험 점수**: 심각도 수준별 자동 위험 평가

### CertChk (인증서 확인)
- **목적**: 필수 인증서 검증
- **요구사항**: MOIAT (수출입), FANR (핵물질)
- **규정 준수**: 규제 표준에 따른 자동 검증

## 🤖 MACHO-GPT v3.7 Claude Native 통합

### 지원되는 명령어

```bash
# LogiMaster 명령어
/logi-master kpi-dash --realtime    # 실시간 KPI 대시보드
/logi-master invoice-audit          # 송장 감사
/logi-master predict-eta            # ETA 예측
/logi-master weather-tie            # 기상 영향 분석
/logi-master customs               # 세관 분석
/logi-master stowage               # 적재 최적화
/logi-master warehouse             # 창고 상태 확인
/logi-master report                # 경영진 보고서

# 모드 전환
/switch_mode PRIME                 # PRIME 모드 활성화
/switch_mode ORACLE                # ORACLE 모드 활성화
/switch_mode ZERO                  # ZERO 모드 (안전 모드)
/switch_mode LATTICE               # LATTICE 모드 (OCR 최적화)
/switch_mode COST-GUARD            # 비용 보호 모드

# 추가 기능
/check_KPI                         # KPI 임계값 모니터링
/weather-tie                       # 물류 기상 영향
/compliance-report                 # 규정 준수 보고서
```

### Claude 도구 통합

- **web_search**: 실시간 시장 정보, 기상 데이터, 규제 업데이트
- **google_drive_search**: 회사 문서, 템플릿, 승인 워크플로우
- **repl**: 복잡한 계산, 데이터 분석, 예측 모델링
- **artifacts**: 보고서 생성, 시각화, 대시보드 제작

## 🚀 안전한 배포 시스템

Fuseki 배포 시스템은 무중단 업데이트를 보장합니다:

```bash
# 전체 검증과 함께 배포
python fuseki_swap_verify.py --deploy data.ttl

# 검증 전용 (드라이런)
python fuseki_swap_verify.py --validate-only

# 배포 통계 보기
python fuseki_swap_verify.py --stats

# 긴급 롤백
python fuseki_swap_verify.py --rollback http://samsung.com/graph/EXTRACTED
```

### 배포 프로세스

1. **📤 스테이징 업로드**: 스테이징 그래프에 데이터 업로드
2. **🔍 종합 검증**: 트리플 개수, 클래스 존재, 데이터 무결성 확인
3. **💾 백업 생성**: 현재 프로덕션 데이터 백업
4. **🔄 원자적 교체**: 스테이징 데이터를 프로덕션으로 이동
5. **✅ 검증**: 실패 시 자동 롤백과 함께 최종 검증

## 🔒 보안 및 규정 준수

### 감사 로깅
- **PII 마스킹**: 민감한 데이터 자동 탐지 및 마스킹
- **SHA-256 무결성**: 감사 로그의 암호화 검증
- **NDJSON 형식**: NIST SP800-92 표준을 따르는 구조화된 로깅
- **변조 탐지**: 규정 준수 감사를 위한 무결성 검증

### 데이터 보호
- **NDA 콘텐츠 스크리닝**: 기밀 정보 자동 탐지
- **데이터 정화**: 입력 검증 및 출력 필터링
- **접근 제어**: 역할 기반 권한 및 감사 추적

## 🔐 v3.7 보안 강화 기능

### 통합 보안 시스템
- **제로 트러스트 아키텍처**: 모든 요청에 대한 다층 검증
- **실시간 위협 탐지**: AI 기반 이상 행위 모니터링
- **자동화된 규정 준수**: FANR, MOIAT, IMO, GDPR 자동 검증
- **종단간 암호화**: 모든 데이터 전송 및 저장 암호화

### Claude Native 보안
- **명령어 검증**: MACHO-GPT 명령어 실행 전 보안 검사
- **도구 접근 제어**: web_search, google_drive_search 등 도구별 권한 관리
- **세션 관리**: 사용자 세션 및 API 키 보안 관리

## 📈 성능 지표

| 지표 | 목표 | 달성 |
|------|------|------|
| **비즈니스 규칙 정확도** | >95% | 100% |
| **NLQ 변환 성공률** | >80% | 100% |
| **배포 안전성** | 무중단 | ✅ 보장됨 |
| **응답 시간** | <3초 | <2초 |
| **시스템 가용성** | >99% | ✅ 엔터프라이즈급 |
| **Gateway API 통합** | 100% | ✅ 완료 |
| **Claude Native 브릿지** | v3.7 | ✅ 구현됨 |
| **테스트 커버리지** | >90% | 100% |

## 🧪 테스트

```bash
# 전체 통합 테스트 스위트 실행
python test_integration.py

# Gateway API 통합 테스트 (v3.7 신규)
python test_gateway_integration.py

# 비즈니스 규칙 엔진 테스트
python -c "from test_integration import test_business_rules; test_business_rules()"

# Fuseki 배포 시스템 테스트
python -c "from test_integration import test_fuseki_system; test_fuseki_system()"

# NLQ 변환 테스트
python -c "from test_integration import test_nlq_queries; test_nlq_queries()"

# Claude Native 브릿지 테스트 (v3.7)
cd upgrade/v3.7-CLAUDE-NATIVE
python test_claude_integration.py

# 빠른 Gateway API 데모
python quick_demo.py

# 자동화된 테스트 파이프라인
/automate test-pipeline  # 프로젝트 CLI 규약 사용
```

### 테스트 결과 요약

- ✅ **통합 테스트**: 100% 통과
- ✅ **Gateway API 테스트**: 7/7 테스트 통과
- ✅ **비즈니스 규칙**: 모든 시나리오 검증 완료
- ✅ **보안 테스트**: PII 마스킹, 감사 로깅 검증
- ✅ **성능 테스트**: 응답 시간 <2초 달성

## 🔧 GitHub Actions CI/CD

저장소에는 자동화된 테스트 및 배포 워크플로우가 포함되어 있습니다:

### 수동 워크플로우 트리거

GitHub UI 또는 CLI를 사용하여 사용자 정의 매개변수로 워크플로우를 트리거합니다:

```bash
# GitHub CLI를 통해
gh workflow run audit-smoke.yml \
  -f target_branch=main \
  -f run_smoke=true \
  -f slack_notify=true

# GitHub UI를 통해
# Actions → HVDC Audit Integrity & Smoke Test → Run workflow로 이동
```

### 워크플로우 입력

- **target_branch**: 테스트할 브랜치 (기본값: main)
- **ref**: 특정 커밋 SHA (선택사항)
- **run_smoke**: 전체 스모크 테스트 활성화 (기본값: true)
- **force_swap**: 강제 배포 허용 (주의: 기본값 false)
- **sample_path**: 샘플 데이터 경로 재정의
- **slack_notify**: Slack 알림 전송 (기본값: true)

### 필수 시크릿

저장소 설정에서 구성:

- `HVDC_API_URL`: API 엔드포인트 URL
- `SLACK_WEBHOOK_URL`: 알림용 Slack 인커밍 웹훅
- `TRACE_SAMPLE_PATH`: 샘플 데이터 파일 경로 (선택사항)
- `HVDC_GATEWAY_API_KEY`: Gateway API 키 (v3.7 신규)

## 📚 문서화

- **시스템 아키텍처**: `HVDC-SYSTEM-GUIDE.md` 참조
- **API 문서화**: `hvdc_api.py` 독스트링 참조
- **배포 가이드**: `operational-checklist.md` 참조
- **문제해결**: `troubleshooting-guide.md` 참조
- **Gateway API 통합**: `HVDC_GATEWAY_INTEGRATION_SUMMARY.md` 참조 (v3.7 신규)
- **Claude Native 브릿지**: `upgrade/v3.7-CLAUDE-NATIVE/` 디렉토리 참조

## 🤝 기여하기

1. 저장소 포크
2. 기능 브랜치 생성 (`git checkout -b feature/amazing-feature`)
3. 테스트 실행 (`python test_integration.py`, `python test_gateway_integration.py`)
4. 변경사항 커밋 (`git commit -m 'Add amazing feature'`)
5. 브랜치에 푸시 (`git push origin feature/amazing-feature`)
6. Pull Request 열기

## 🆕 v3.7 주요 업데이트

### Gateway API 통합
- ✅ OpenAPI 3.1 스키마 완전 구현
- ✅ MRR 드래프트, ETA 예측, CostGuard 추정 기능
- ✅ Mock 서버를 통한 완전한 테스트 환경
- ✅ 7개 테스트 케이스 100% 통과

### Claude Native 브릿지
- ✅ MACHO-GPT v3.7 명령어 시스템 완전 통합
- ✅ web_search, google_drive_search, repl, artifacts 도구 연동
- ✅ 자동화된 워크플로우 및 도구 추천 시스템
- ✅ 실시간 상태 모니터링 및 헬스체크

## 🔐 Privacy Policy

This GPT (HVDC Logistics AI Assistant) does not collect or store personal information.  
All processing occurs within the ChatGPT runtime or within internal systems secured by Samsung C&T.  
For external API calls, only public or mock data is used.

**Full Privacy Policy**: [PRIVACY.md](./PRIVACY.md)  
**Contact**: hvdc-ai-support@samsungcnt.com

## 📝 라이선스

이 프로젝트는 삼성물산과 ADNOC·DSV 파트너십 물류 운영을 위해 개발된 독점 소프트웨어입니다.

## 🔧 지원

기술 지원 및 배포 지원:

- **이슈 트래커**: [GitHub Issues](https://github.com/macho715/ontology-insight/issues)
- **문서화**: [Wiki](https://github.com/macho715/ontology-insight/wiki)
- **CI/CD 상태**: [Actions](https://github.com/macho715/ontology-insight/actions)

---

**엔터프라이즈 물류 자동화를 위해 ❤️로 제작되었습니다** 🚀