# 🤖 HVDC Gateway GPTs Actions 연결 가이드

**날짜:** 2025-08-18  
**버전:** v3.7 Claude Native Integration  
**목적:** HVDC Gateway API를 GPTs Actions로 연결하여 ChatGPT에서 직접 사용 가능하게 설정

---

## 🎯 **개요**

이 가이드는 로컬에서 실행되는 HVDC Mock Gateway를 ngrok을 통해 공개 HTTPS URL로 노출하고, GPTs Actions에 연결하는 전체 과정을 설명합니다.

### **지원 기능**
- ✅ **헬스체크**: 서비스 상태 확인
- ✅ **MRR 드래프트 생성**: Purchase Order 기반 자재 접수 드래프트
- ✅ **ETA 예측**: 운송 모드별 도착 예정 시간 예측
- ✅ **CostGuard 추정**: LLM 비용 추정 및 임계값 분류

---

## 🚀 **1단계: 사전 준비**

### **필수 요구사항**
- ✅ Python 3.11+ 설치
- ✅ HVDC Gateway Mock 서버 실행 중 (포트 8080)
- ✅ ngrok 계정 및 AuthToken (https://ngrok.com 무료 회원가입)
- ✅ ChatGPT Plus 구독 (GPTs 기능 사용)

### **로컬 서버 상태 확인**
```bash
# Mock Gateway 서버 실행
python mock_gateway_server.py

# 다른 터미널에서 헬스체크
curl http://localhost:8080/v1/health
# 예상 응답: {"status":"ok","timestamp":"2025-08-18T..."}
```

---

## 🌐 **2단계: ngrok 설정 및 실행**

### **A) ngrok 설치 (Windows)**
```powershell
# Windows Package Manager로 설치
winget install ngrok.ngrok

# 설치 확인
ngrok version
```

### **B) AuthToken 등록**
```bash
# ngrok 대시보드(https://ngrok.com)에서 AuthToken 복사 후 등록
ngrok config add-authtoken YOUR_NGROK_AUTHTOKEN_HERE
```

### **C) 터널 실행 (무료 플랜 - 임시 URL)**
```bash
# 기본 실행 (URL이 매번 바뀜)
ngrok http 8080

# 출력 예시:
# Forwarding  https://abc123.ngrok.app -> http://localhost:8080
```

### **D) 터널 실행 (유료 플랜 - 고정 URL)**
```bash
# Reserved Domain 사용 (사전 예약 필요)
ngrok http --domain your-hvdc-gateway.ngrok.app 8080
```

### **E) 보안 강화 (권장)**
```bash
# Basic Auth 추가
ngrok http --basic-auth hvdcadmin:StrongPassword123! 8080
```

---

## 📝 **3단계: OpenAPI 스키마 준비**

### **A) 자동 스키마 업데이트**
```bash
# ngrok 터널이 실행된 상태에서
python update_openapi_schema.py

# 출력:
# ✅ OpenAPI 스키마 업데이트 완료: hvdc_gateway_openapi_public.yaml
# 🔗 Public URL: https://abc123.ngrok.app
```

### **B) 수동 스키마 업데이트**
ngrok URL을 확인한 후 다음 스키마의 `servers.url`을 업데이트:

```yaml
openapi: 3.1.0
info:
  title: HVDC GPT Gateway
  version: "1.0.2"
servers:
  - url: https://YOUR_NGROK_URL_HERE/v1  # 이 부분을 실제 ngrok URL로 교체
    description: Public ngrok tunnel
# ... 나머지 스키마 내용
```

---

## 🤖 **4단계: GPTs Actions 설정**

### **A) GPT Builder 접근**
1. ChatGPT Plus 계정으로 로그인
2. 좌측 사이드바에서 "Explore" 클릭
3. "Create a GPT" 선택
4. "Configure" 탭으로 이동

### **B) 기본 정보 설정**
- **Name**: `HVDC Logistics Assistant`
- **Description**: `Samsung HVDC 프로젝트 물류 관리 AI 어시스턴트`
- **Instructions**:
```
당신은 삼성 HVDC 프로젝트의 물류 전문 AI 어시스턴트입니다.

주요 기능:
1. MRR 드래프트 생성 - PO 번호와 사이트 정보로 자재 접수 드래프트 작성
2. ETA 예측 - 출발지, 목적지, 운송 모드로 도착 시간 예측
3. 비용 추정 - 토큰 사용량 기반 LLM 비용 계산 및 임계값 분류
4. 시스템 상태 확인 - Gateway 서비스 헬스체크

항상 정확하고 전문적인 물류 용어를 사용하며, 결과는 한국어로 친근하게 설명해주세요.
```

### **C) Actions 설정**
1. "Actions" 섹션에서 "Create new action" 클릭
2. **Schema 입력 방식**: 
   - "Import from URL" **사용하지 않음** (로컬 서버라서 접근 불가)
   - 직접 스키마 텍스트 붙여넣기

3. **스키마 붙여넣기**:
   - `hvdc_gateway_openapi_public.yaml` 파일 내용을 전체 복사
   - Schema 텍스트박스에 붙여넣기
   - "Test" 버튼으로 파싱 확인

### **D) Authentication 설정**
1. **Authentication Type**: `API Key`
2. **API Key**: `demo-key` (Mock 서버용)
3. **Auth Type**: `Custom`
4. **Custom Header Name**: `X-API-Key`

### **E) Privacy Policy (선택사항)**
```
이 GPT는 삼성 HVDC 프로젝트 내부 물류 관리 목적으로만 사용됩니다.
모든 데이터는 로컬 Mock 서버에서 처리되며 외부로 전송되지 않습니다.
```

---

## 🧪 **5단계: 테스트 및 검증**

### **A) 기본 연결 테스트**
GPT와 대화:
```
"시스템 상태를 확인해주세요"
```
예상 응답: Gateway 헬스체크 결과 표시

### **B) MRR 드래프트 테스트**
```
"PO-2025-001 주문서로 MIR 사이트의 MRR 드래프트를 생성해주세요"
```

### **C) ETA 예측 테스트**
```
"Khalifa Port에서 MIR substation까지 도로 운송으로 ETA를 예측해주세요"
```

### **D) 비용 추정 테스트**
```
"입력 토큰 1000개, 출력 토큰 500개로 비용을 추정해주세요. 
입력 비용은 토큰 1000개당 0.03달러, 출력 비용은 0.06달러입니다"
```

---

## 🔒 **6단계: 보안 설정 (프로덕션)**

### **A) Basic Auth 추가**
```bash
ngrok http --basic-auth hvdcadmin:SecurePassword2025! 8080
```

### **B) IP 제한 (유료 플랜)**
ngrok 대시보드에서 Policy 설정:
```json
{
  "inbound": [
    {
      "name": "restrict-ips",
      "expressions": ["conn.client_ip != '203.0.113.1'"],
      "actions": [{"type": "deny"}]
    }
  ]
}
```

### **C) API Key 강화**
실제 운영 시 `demo-key` 대신 강력한 API 키 사용:
```python
# mock_gateway_server.py에서 API 키 검증 강화
VALID_API_KEYS = {
    "hvdc-prod-key-2025": "production",
    "hvdc-dev-key-2025": "development"
}
```

---

## 🛠️ **7단계: 문제해결**

### **A) 일반적인 문제들**

**1. "Failed to connect" 오류**
```bash
# 해결책: Mock 서버가 실행 중인지 확인
python mock_gateway_server.py
curl http://localhost:8080/v1/health
```

**2. "502 Bad Gateway" 오류**
```bash
# 해결책: ngrok이 올바른 포트를 가리키는지 확인
ngrok http 8080  # 8080 포트 확인
```

**3. "Authentication failed" 오류**
- GPTs Actions에서 API Key가 `X-API-Key` 헤더로 설정되었는지 확인
- Mock 서버의 API Key 검증 로직 확인

**4. "Schema parsing error" 오류**
- YAML 형식이 올바른지 확인
- 들여쓰기 및 특수문자 확인
- OpenAPI 3.1.0 호환성 확인

### **B) 디버깅 도구**

**ngrok 로컬 대시보드**
```
http://127.0.0.1:4040
```
- 실시간 요청/응답 모니터링
- 터널 상태 확인
- 트래픽 분석

**Mock 서버 로그**
```bash
# 서버 실행 시 로그 확인
python mock_gateway_server.py
# INFO:mock_gateway_server:✅ MRR draft created for PO PO-2025-001
```

---

## 📚 **8단계: 고급 기능**

### **A) 자동화 스크립트**
```powershell
# ngrok_setup.ps1 사용
.\ngrok_setup.ps1 -AuthToken "your_token" -BasicAuth

# 또는 고정 도메인 사용 (유료)
.\ngrok_setup.ps1 -AuthToken "your_token" -Domain "hvdc.ngrok.app"
```

### **B) 지속적 실행 (서버 환경)**
```bash
# systemd 서비스 생성 (Linux)
sudo systemctl enable --now ngrok-hvdc

# Windows 서비스 등록
sc create "HVDC-ngrok" binPath="C:\path\to\ngrok.exe http 8080"
```

### **C) 모니터링 및 알림**
```python
# 터널 상태 모니터링 스크립트
import requests
import time

def monitor_tunnel():
    try:
        response = requests.get("http://127.0.0.1:4040/api/tunnels")
        tunnels = response.json()["tunnels"]
        if not tunnels:
            print("⚠️ 터널이 실행되지 않음")
            # Slack/이메일 알림 전송
    except:
        print("❌ ngrok 모니터링 실패")

# 주기적 실행
while True:
    monitor_tunnel()
    time.sleep(300)  # 5분마다 확인
```

---

## 🎉 **완료 체크리스트**

- [ ] ngrok 설치 및 AuthToken 등록
- [ ] Mock Gateway 서버 실행 (포트 8080)
- [ ] ngrok 터널 실행 및 공개 URL 확인
- [ ] OpenAPI 스키마 업데이트 (servers.url)
- [ ] GPTs Actions 설정 완료
- [ ] API Key 인증 설정 (`X-API-Key: demo-key`)
- [ ] 기본 연결 테스트 (헬스체크)
- [ ] 주요 기능 테스트 (MRR, ETA, CostGuard)
- [ ] 보안 설정 적용 (Basic Auth/IP 제한)
- [ ] 문제해결 도구 준비 (ngrok 대시보드, 로그)

---

## 💡 **추가 리소스**

### **관련 파일들**
- `mock_gateway_server.py`: Mock Gateway 서버
- `update_openapi_schema.py`: 스키마 자동 업데이트 도구
- `ngrok_setup.ps1`: ngrok 설정 자동화 스크립트
- `hvdc_gateway_openapi_public.yaml`: GPTs용 공개 스키마

### **유용한 링크**
- [ngrok 공식 문서](https://ngrok.com/docs)
- [OpenAPI 3.1 스펙](https://swagger.io/specification/)
- [GPTs Actions 가이드](https://platform.openai.com/docs/actions)
- [HVDC GitHub 저장소](https://github.com/macho715/ontology-insight)

### **지원 및 문의**
- **GitHub Issues**: 기술적 문제 및 버그 리포트
- **프로젝트 Wiki**: 상세 문서 및 FAQ
- **CI/CD Status**: 자동화 테스트 및 배포 상태

---

**🚀 이제 ChatGPT에서 직접 HVDC Gateway API를 사용할 수 있습니다!**
