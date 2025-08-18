#!/usr/bin/env python3
"""
HVDC Gateway Integration Test Suite
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import json
from datetime import datetime, timezone
import sys
import os

# 로컬 모듈 import
from hvdc_gateway_client import (
    HVDCGatewayClient, HVDCGatewayIntegration,
    MRRItem, Site, Status, UOM, TransportMode, RiskLevel, CostBand
)
from hvdc_gateway_config import get_config

class TestHVDCGatewayClient(unittest.TestCase):
    """Gateway 클라이언트 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.config = get_config("dev")
        self.client = HVDCGatewayClient(
            base_url=self.config.base_url,
            api_key=self.config.api_key
        )
    
    @patch('requests.Session.get')
    def test_health_check_success(self, mock_get):
        """헬스체크 성공 테스트"""
        # Mock 응답 설정
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "ok",
            "timestamp": "2025-08-18T00:00:00Z"
        }
        mock_get.return_value = mock_response
        
        # 테스트 실행
        result = self.client.health_check()
        
        # 검증
        self.assertEqual(result["status"], "ok")
        self.assertIn("timestamp", result)
        mock_get.assert_called_once()
    
    @patch('requests.Session.post')
    def test_create_mrr_draft_success(self, mock_post):
        """MRR 드래프트 생성 성공 테스트"""
        # Mock 응답 설정
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "po_no": "PO-2025-001",
            "site": "MIR",
            "items": [
                {
                    "part_no": "HVDC-TR-001",
                    "qty": 2,
                    "status": "OK",
                    "uom": "EA"
                }
            ],
            "confidence": 0.95,
            "warnings": []
        }
        mock_post.return_value = mock_response
        
        # 테스트 데이터
        items = [MRRItem(part_no="HVDC-TR-001", qty=2, status=Status.OK, uom=UOM.EA)]
        
        # 테스트 실행
        result = self.client.create_mrr_draft("PO-2025-001", Site.MIR, items)
        
        # 검증
        self.assertEqual(result["po_no"], "PO-2025-001")
        self.assertEqual(result["confidence"], 0.95)
        self.assertEqual(len(result["items"]), 1)
        mock_post.assert_called_once()
    
    @patch('requests.Session.post')
    def test_predict_eta_success(self, mock_post):
        """ETA 예측 성공 테스트"""
        # Mock 응답 설정
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "eta_utc": "2025-08-20T14:30:00Z",
            "transit_hours": 48.5,
            "risk_level": "LOW",
            "notes": "Normal conditions"
        }
        mock_post.return_value = mock_response
        
        # 테스트 실행
        result = self.client.predict_eta(
            "Khalifa Port",
            "MIR substation", 
            TransportMode.ROAD
        )
        
        # 검증
        self.assertEqual(result.risk_level, RiskLevel.LOW)
        self.assertEqual(result.transit_hours, 48.5)
        self.assertIsInstance(result.eta_utc, datetime)
        mock_post.assert_called_once()
    
    @patch('requests.Session.post')
    def test_estimate_cost_success(self, mock_post):
        """비용 추정 성공 테스트"""
        # Mock 응답 설정
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "estimated_cost": 0.045,
            "band": "PASS",
            "thresholds": {
                "pass": 0.02,
                "warn": 0.05,
                "high": 0.10
            }
        }
        mock_post.return_value = mock_response
        
        # 테스트 실행
        result = self.client.estimate_cost(1000, 500, 0.03, 0.06)
        
        # 검증
        self.assertEqual(result.estimated_cost, 0.045)
        self.assertEqual(result.band, CostBand.PASS)
        self.assertIn("pass", result.thresholds)
        mock_post.assert_called_once()

class TestHVDCGatewayIntegration(unittest.TestCase):
    """Gateway 통합 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.mock_client = Mock(spec=HVDCGatewayClient)
        self.integration = HVDCGatewayIntegration(self.mock_client)
    
    @patch('requests.post')
    def test_sync_mrr_with_local_success(self, mock_post):
        """MRR 로컬 동기화 성공 테스트"""
        # Gateway 클라이언트 Mock 설정
        self.mock_client.create_mrr_draft.return_value = {
            "po_no": "PO-2025-001",
            "site": "MIR",
            "items": [],
            "confidence": 0.90,
            "warnings": []
        }
        
        # 로컬 API Mock 설정
        mock_response = Mock()
        mock_response.status_code = 200
        mock_post.return_value = mock_response
        
        # 테스트 데이터
        items = [MRRItem(part_no="HVDC-TR-001", qty=2, status=Status.OK)]
        
        # 테스트 실행
        result = self.integration.sync_mrr_with_local("PO-2025-001", Site.MIR, items)
        
        # 검증
        self.assertEqual(result["sync_status"], "completed")
        self.assertEqual(result["po_no"], "PO-2025-001")
        self.assertIn("gateway_result", result)
        self.mock_client.create_mrr_draft.assert_called_once()
    
    @patch('requests.post')
    def test_enhanced_eta_prediction_with_claude(self, mock_post):
        """Claude 통합 ETA 예측 테스트"""
        # Gateway 클라이언트 Mock 설정
        from hvdc_gateway_client import EtaResult
        self.mock_client.predict_eta.return_value = EtaResult(
            eta_utc=datetime.now(timezone.utc),
            transit_hours=48.0,
            risk_level=RiskLevel.LOW,
            notes="Test prediction"
        )
        
        # Claude 브릿지 Mock 설정
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": "success",
            "claude_integration": {
                "web_search_suggestions": ["weather forecast", "port conditions"],
                "recommended_tools": ["web_search", "repl"]
            }
        }
        mock_post.return_value = mock_response
        
        # 테스트 실행
        result = self.integration.enhanced_eta_prediction(
            "Khalifa Port",
            "MIR substation",
            TransportMode.ROAD
        )
        
        # 검증
        self.assertIn("gateway_eta", result)
        self.assertIn("claude_integration", result)
        self.assertIn("confidence_score", result)
        self.assertGreaterEqual(result["confidence_score"], 0.75)

class TestGatewayEndToEnd(unittest.TestCase):
    """End-to-End 통합 테스트"""
    
    def setUp(self):
        """테스트 설정"""
        self.config = get_config("dev")
    
    @patch('hvdc_gateway_client.HVDCGatewayClient.health_check')
    @patch('hvdc_gateway_client.HVDCGatewayClient.create_mrr_draft')
    @patch('hvdc_gateway_client.HVDCGatewayClient.predict_eta')
    @patch('hvdc_gateway_client.HVDCGatewayClient.estimate_cost')
    def test_complete_workflow(self, mock_cost, mock_eta, mock_mrr, mock_health):
        """완전한 워크플로우 테스트"""
        # Mock 설정
        mock_health.return_value = {"status": "ok", "timestamp": "2025-08-18T00:00:00Z"}
        mock_mrr.return_value = {
            "po_no": "PO-2025-001",
            "confidence": 0.95,
            "items": []
        }
        
        from hvdc_gateway_client import EtaResult, CostEstimate
        mock_eta.return_value = EtaResult(
            eta_utc=datetime.now(timezone.utc),
            transit_hours=48.0,
            risk_level=RiskLevel.LOW
        )
        mock_cost.return_value = CostEstimate(
            estimated_cost=0.045,
            band=CostBand.PASS,
            thresholds={}
        )
        
        # 클라이언트 생성
        client = HVDCGatewayClient(self.config.base_url, self.config.api_key)
        
        # 워크플로우 실행
        health = client.health_check()
        self.assertEqual(health["status"], "ok")
        
        items = [MRRItem(part_no="TEST-001", qty=1, status=Status.OK)]
        mrr_result = client.create_mrr_draft("PO-2025-001", Site.MIR, items)
        self.assertEqual(mrr_result["po_no"], "PO-2025-001")
        
        eta_result = client.predict_eta("Origin", "Destination", TransportMode.ROAD)
        self.assertEqual(eta_result.risk_level, RiskLevel.LOW)
        
        cost_result = client.estimate_cost(1000, 500, 0.03, 0.06)
        self.assertEqual(cost_result.band, CostBand.PASS)

def run_integration_tests():
    """통합 테스트 실행"""
    print("🧪 HVDC Gateway Integration Test Suite")
    print("=" * 50)
    
    # 테스트 스위트 구성
    test_classes = [
        TestHVDCGatewayClient,
        TestHVDCGatewayIntegration,
        TestGatewayEndToEnd
    ]
    
    total_tests = 0
    total_failures = 0
    
    for test_class in test_classes:
        print(f"\n📋 Running {test_class.__name__}...")
        
        suite = unittest.TestLoader().loadTestsFromTestCase(test_class)
        runner = unittest.TextTestRunner(verbosity=1, stream=sys.stdout)
        result = runner.run(suite)
        
        total_tests += result.testsRun
        total_failures += len(result.failures) + len(result.errors)
        
        if result.failures:
            print(f"❌ Failures: {len(result.failures)}")
        if result.errors:
            print(f"❌ Errors: {len(result.errors)}")
        if result.wasSuccessful():
            print("✅ All tests passed!")
    
    print(f"\n" + "=" * 50)
    print(f"📊 Test Summary:")
    print(f"   Total Tests: {total_tests}")
    print(f"   Failures: {total_failures}")
    print(f"   Success Rate: {((total_tests - total_failures) / total_tests * 100):.1f}%")
    
    if total_failures == 0:
        print("🎉 All integration tests passed!")
        return True
    else:
        print("❌ Some tests failed. Check output above.")
        return False

if __name__ == "__main__":
    success = run_integration_tests()
    sys.exit(0 if success else 1)

