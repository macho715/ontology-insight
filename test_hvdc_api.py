#!/usr/bin/env python3
"""
HVDC API Integration Tests - TDD 방식으로 API 엔드포인트 검증
"""

import pytest
import requests
import json
import pandas as pd
import os
from pathlib import Path
from hvdc_api import app
from hvdc_rules import run_all_rules
from audit_logger import write_audit

# Test Configuration
TEST_BASE_URL = "http://localhost:5002"
TEST_FUSEKI_URL = "http://localhost:3030"

@pytest.fixture
def client():
    """Flask 테스트 클라이언트"""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

@pytest.fixture
def sample_data():
    """테스트용 샘플 데이터"""
    return pd.DataFrame({
        'HVDC_CODE': ['HVDC-ADOPT-SCT-0001', 'HVDC-ADOPT-SCT-0002'],
        'INVOICE_VALUE': [1000.0, 750.0],
        'QTY': [1, 1],
        'UNIT_PRICE': [1000.0, 750.0],
        'HS_CODE': ['8504.40.90', '8544.60.90'],
        'CERTS': 'MOIAT,FANR',
        'SOURCE_FILE': 'test_sample.xlsx',
        'LOGICAL_SOURCE': 'TEST_CASE_001',
        'EXTRACTION_TRACE': 'test_trace',
        'ROW_INDEX': [1, 2]
    })

class TestHealthEndpoint:
    """헬스체크 엔드포인트 테스트"""
    
    def test_health_endpoint_should_return_ok_when_system_healthy(self, client):
        """시스템이 정상일 때 헬스체크가 OK를 반환해야 함"""
        response = client.get('/health')
        
        assert response.status_code == 200
        data = response.get_json()
        assert 'ok' in data
        assert isinstance(data['ok'], bool)

class TestIngestEndpoint:
    """데이터 수집 엔드포인트 테스트"""
    
    def test_ingest_should_accept_json_path_input(self, client):
        """JSON 형태로 파일 경로를 받아 처리해야 함"""
        payload = {
            "path": "sample_data/DSV_Sample.xlsx",
            "actor": "test_user",
            "min_conf": 0.6
        }
        
        response = client.post('/ingest', json=payload)
        
        # 파일이 존재하지 않을 수 있으므로 적절한 에러 처리 확인
        assert response.status_code in [200, 400]
        
        if response.status_code == 200:
            data = response.get_json()
            assert 'rows' in data
            assert 'trace_log' in data

    def test_ingest_should_require_file_when_no_path_provided(self, client):
        """파일 경로가 없을 때 파일 업로드가 필요함을 알려야 함"""
        response = client.post('/ingest', json={})
        
        assert response.status_code == 400
        data = response.get_json()
        assert 'error' in data
        assert 'No file provided' in data['error']

class TestEvidenceEndpoint:
    """증적 조회 엔드포인트 테스트"""
    
    def test_evidence_should_return_case_traces(self, client):
        """케이스 ID로 추출 증적을 조회할 수 있어야 함"""
        case_id = "TEST_CASE_001"
        
        response = client.get(f'/evidence/{case_id}')
        
        assert response.status_code == 200
        data = response.get_json()
        assert 'case_id' in data
        assert data['case_id'] == case_id
        assert 'traces' in data
        assert 'triples' in data

class TestRulesEndpoint:
    """비즈니스 룰 실행 엔드포인트 테스트"""
    
    def test_run_rules_should_execute_all_business_rules(self, client, sample_data):
        """비즈니스 룰을 실행하고 결과를 반환해야 함"""
        # 먼저 테스트 데이터를 artifacts 디렉토리에 저장
        os.makedirs("artifacts", exist_ok=True)
        trace_file = "artifacts/test_extraction_trace.csv"
        sample_data.to_csv(trace_file, index=False)
        
        payload = {
            "trace_log": trace_file,
            "actor": "test_user"
        }
        
        response = client.post('/run-rules', json=payload)
        
        assert response.status_code == 200
        data = response.get_json()
        
        # 결과 구조 검증
        assert 'cost_alerts' in data
        assert 'hs_alerts' in data
        assert 'cert_alerts' in data
        assert 'summary' in data
        
        # 요약 정보 검증
        summary = data['summary']
        assert 'cost_count' in summary
        assert 'hs_count' in summary
        assert 'cert_count' in summary
        
        # 정리
        if os.path.exists(trace_file):
            os.remove(trace_file)

    def test_run_rules_should_handle_empty_data_gracefully(self, client):
        """데이터가 없을 때 적절한 에러를 반환해야 함"""
        payload = {
            "case_ids": ["NONEXISTENT_CASE"],
            "actor": "test_user"
        }
        
        response = client.post('/run-rules', json=payload)
        
        assert response.status_code == 400
        data = response.get_json()
        assert 'error' in data
        assert 'no data found' in data['error']

class TestNLQEndpoint:
    """자연어 쿼리 엔드포인트 테스트"""
    
    def test_nlq_should_handle_boe_cipl_queries(self, client):
        """BOE와 CIPL 관련 자연어 쿼리를 처리해야 함"""
        payload = {
            "q": "Show invoices where BOE != CIPL for SHPT NO 0049"
        }
        
        response = client.post('/nlq', json=payload)
        
        # Fuseki가 실행 중이지 않을 수 있으므로 적절한 에러 처리 확인
        assert response.status_code in [200, 500]
        
        data = response.get_json()
        if response.status_code == 500:
            assert 'error' in data
            assert 'SPARQL engine not available' in data['error']

    def test_nlq_should_reject_unsupported_queries(self, client):
        """지원하지 않는 쿼리는 거부해야 함"""
        payload = {
            "q": "What is the weather today?"
        }
        
        response = client.post('/nlq', json=payload)
        
        assert response.status_code == 400
        data = response.get_json()
        assert 'error' in data
        assert 'unsupported NLQ' in data['error']

class TestBusinessRules:
    """비즈니스 룰 로직 테스트"""
    
    def test_costguard_should_detect_price_deviations(self, sample_data):
        """CostGuard가 가격 편차를 정확히 탐지해야 함"""
        std_rate_table = {
            "HVDC-ADOPT-SCT-0001": 1000.00,
            "HVDC-ADOPT-SCT-0002": 800.00  # 실제 750과 차이 발생
        }
        
        from hvdc_rules import run_costguard
        alerts = run_costguard(sample_data, std_rate_table)
        
        assert len(alerts) >= 1
        
        # SCT-0002에서 가격 편차 알림이 있어야 함
        sct002_alerts = [a for a in alerts if a['hvdc_code'] == 'HVDC-ADOPT-SCT-0002']
        assert len(sct002_alerts) == 1
        
        alert = sct002_alerts[0]
        assert alert['draft_rate'] == 750.0
        assert alert['std_rate'] == 800.0
        assert abs(alert['delta_pct'] - (-6.25)) < 0.01  # (750-800)/800 * 100 = -6.25%
        assert alert['severity'] == 'WARN'  # 5% < 6.25% < 10%

    def test_hs_risk_should_identify_high_risk_codes(self, sample_data):
        """HS Risk가 고위험 코드를 식별해야 함"""
        high_risk_prefixes = ["85"]  # 8504, 8544 모두 85로 시작
        
        from hvdc_rules import run_hs_risk
        alerts = run_hs_risk(sample_data, high_risk_prefixes)
        
        assert len(alerts) == 2  # 두 개 모두 85로 시작
        
        for alert in alerts:
            assert alert['hs_code'].startswith('85')
            assert alert['risk_score'] == 0.8
            assert alert['severity'] == 'HIGH'

    def test_cert_check_should_validate_required_certificates(self, sample_data):
        """CertChk가 필수 인증서를 검증해야 함"""
        required_certs = ["MOIAT", "FANR"]
        
        from hvdc_rules import run_cert_check
        alerts = run_cert_check(sample_data, required_certs)
        
        # 샘플 데이터에는 MOIAT,FANR이 모두 있으므로 알림이 없어야 함
        assert len(alerts) == 0

class TestAuditLogging:
    """감사 로깅 테스트"""
    
    def test_audit_logger_should_record_actions(self):
        """감사 로거가 액션을 기록해야 함"""
        from audit_logger import write_audit
        
        # 테스트 액션 기록
        result = write_audit("test_action", "test_user", {"test": "data"})
        
        assert result['action'] == 'test_action'
        assert result['actor'] == 'test_user'
        assert 'ts' in result
        
        # 파일이 생성되었는지 확인
        audit_file = Path("artifacts/audit_log.csv")
        assert audit_file.exists()

if __name__ == "__main__":
    # 테스트 실행
    pytest.main([__file__, "-v", "--tb=short"])
