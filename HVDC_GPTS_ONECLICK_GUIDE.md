# 🚀 HVDC GPTs Actions 원클릭 연결 가이드

## **Executive Summary**

* **목표**: HVDC Gateway Mock 서버를 ngrok으로 공개하여 ChatGPT GPTs Actions와 완전 통합
* **방법**: `gpts_oneclick.ps1` 스크립트로 **Mock 기동 → ngrok 터널 → 스키마 패치 → GPTs 연결**을 한 번에 처리
* **결과**: `/health`, `/mrr/draft`, `/predict/eta`, `/costguard/estimate` 엔드포인트가 GPTs에서 직접 호출 가능

---

## **🎯 원클릭 실행 (권장)**

### **1단계: 사전 준비**

```powershell
# ngrok 설치 및 AuthToken 등록
winget install ngrok.ngrok
ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>

# Python 의존성 설치
pip install flask pyyaml requests
```

### **2단계: 원클릭 실행**

```powershell
# 완전 자동화: Mock 기동 + ngrok 터널 + 스키마 패치
.\gpts_oneclick.ps1 -AuthToken "<YOUR_NGROK_AUTHTOKEN>" -InSchema ".\openapi.yaml" -StartMock

# (선택) 스키마 URL 호스팅까지 포함
.\gpts_oneclick.ps1 -AuthToken "<YOUR_NGROK_AUTHTOKEN>" -InSchema ".\openapi.yaml" -StartMock -HostSchema
```

### **3단계: 출력 결과 확인**

스크립트 실행 후 다음과 같은 정보가 표시됩니다:

```
=== ONE-CLICK SUMMARY ===
Public API:    https://abc123.ngrok.app
Health:        https://abc123.ngrok.app/v1/health
Schema file:   .\openapi.updated.yaml
Schema URL:    https://def456.ngrok.app/openapi.updated.yaml (HostSchema 사용시)
Paste this into your OpenAPI if needed:
servers:
  - url: https://abc123.ngrok.app/v1
```

---

## **🔧 GPTs Builder 연결**

### **방법 A: 스키마 파일 붙여넣기 (기본)**

1. **ChatGPT Plus → GPT Builder → 작업(Actions) 추가**
2. **스키마 설정**:
   - "URL에서 가져오기": **아니오**
   - `openapi.updated.yaml` 파일 내용 전체 복사하여 붙여넣기
3. **인증 설정** (초기):
   - 인증 방식: **없음**
   - 연결 테스트: "게이트웨이 상태 확인" → `/health` 호출 성공 확인

### **방법 B: 스키마 URL 사용 (-HostSchema 옵션)**

1. **ChatGPT Plus → GPT Builder → 작업(Actions) 추가**
2. **스키마 설정**:
   - "URL에서 가져오기": **예**
   - Schema URL 입력: `https://def456.ngrok.app/openapi.updated.yaml`
3. **인증 설정** (초기): **없음**

### **인증 전환 (실사용)**

초기 `/health` 테스트 성공 후:

1. **인증 방식**: **API 키**로 변경
2. **API 키**: `demo-key` (Mock 서버용)
3. **인증 헤더**: `X-API-Key`
4. **테스트**: "CostGuard 예측 12000 토큰" → 성공 응답 확인

---

## **🧪 테스트 시나리오**

### **기본 헬스 체크**
```
프롬프트: "게이트웨이 상태 확인해줘"
기대 응답: {"status": "ok", "timestamp": "..."}
```

### **CostGuard 예측**
```
프롬프트: "입력토큰 12000, 출력토큰 3000, 입력비용 0.50, 출력비용 1.50으로 CostGuard 예측해줘"
기대 응답: {"estimated_cost": 21.0, "band": "WARN", ...}
```

### **ETA 예측**
```
프롬프트: "Khalifa Port에서 MIR substation까지 SEA 모드로 ETA 예측해줘"
기대 응답: {"eta_utc": "...", "transit_hours": 72, "risk_level": "MEDIUM"}
```

### **MRR 드래프트**
```
프롬프트: "PO-2025-001, MIR 사이트로 MRR 드래프트 만들어줘"
기대 응답: {"po_no": "PO-2025-001", "site": "MIR", "confidence": 0.95, ...}
```

---

## **🔍 트러블슈팅**

### **일반적인 오류**

| 오류 | 원인 | 해결책 |
|------|------|--------|
| `Could not parse valid OpenAPI spec` | 스키마 형식 문제 | `openapi: 3.1.0`, 단일 서버, 공백 들여쓰기 확인 |
| `Found multiple hostnames` | servers 배열에 여러 항목 | servers 배열을 단일 항목으로 수정 |
| `401 Unauthorized` | API 키 미설정/잘못됨 | GPTs Builder에서 `X-API-Key: demo-key` 설정 |
| `502 Bad Gateway` | 로컬 서버 미실행 | `python mock_gateway_server.py` 재시작 |
| `Failed to get public URL` | ngrok 터널 실패 | AuthToken 확인, ngrok 재시작 |

### **디버깅 명령어**

```powershell
# Mock 서버 상태 확인
curl http://localhost:8080/v1/health

# ngrok 터널 상태 확인
curl http://127.0.0.1:4040/api/tunnels

# 공개 URL 헬스 체크
curl https://abc123.ngrok.app/v1/health

# 스키마 유효성 검사
python -c "import yaml; print(yaml.safe_load(open('openapi.updated.yaml'))['openapi'])"
```

---

## **🔒 보안 고려사항**

### **개발/테스트 환경**
- Mock 서버 API 키: `demo-key` (하드코딩)
- ngrok 무료 플랜: 임시 URL (매 실행마다 변경)
- 기본 인증: 없음 → API 키 전환

### **운영 환경 권장사항**
- **API 키 로테이션**: 90일마다 갱신
- **ngrok 유료 플랜**: 고정 도메인/서브도메인 사용
- **Basic Auth 추가**: ngrok 레벨 보안 강화
- **IP 화이트리스트**: 허용된 IP에서만 접근
- **HTTPS 강제**: 모든 통신 암호화

---

## **📋 체크리스트**

### **실행 전**
- [ ] ngrok 설치 및 AuthToken 등록 완료
- [ ] Python 환경 및 의존성 설치 완료
- [ ] `openapi.yaml` 파일 존재 확인
- [ ] Mock Gateway 서버 실행 중 (8080)

### **실행 후**
- [ ] ngrok 터널 정상 생성 (Public URL 확인)
- [ ] 공개 `/v1/health` 엔드포인트 200 응답
- [ ] `openapi.updated.yaml` 파일 생성됨
- [ ] GPTs Builder에서 스키마 로드 성공

### **GPTs 연결 후**
- [ ] "게이트웨이 상태 확인" 테스트 성공
- [ ] API 키 인증 설정 완료
- [ ] 모든 엔드포인트 호출 가능 확인
- [ ] 실제 업무 시나리오 테스트 완료

---

## **🚀 다음 단계**

1. **개발 완료**: 모든 테스트 통과 후 운영 환경 준비
2. **운영 배포**: 실제 HVDC Gateway API 연결
3. **사용자 교육**: GPTs 활용 방법 팀 공유
4. **모니터링**: API 사용량 및 성능 추적
5. **확장**: 추가 엔드포인트 및 기능 개발

---

## **💡 추가 리소스**

- **ngrok 공식 문서**: https://ngrok.com/docs
- **OpenAPI 3.1 스펙**: https://swagger.io/specification/
- **ChatGPT GPTs 가이드**: https://help.openai.com/en/articles/8554397-creating-a-gpt
- **HVDC 프로젝트 저장소**: https://github.com/macho715/ontology-insight

---

**🎉 축하합니다! HVDC GPTs Actions 통합이 완료되었습니다.**
