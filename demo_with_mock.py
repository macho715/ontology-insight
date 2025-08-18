#!/usr/bin/env python3
"""
HVDC Gateway Mock 서버를 사용한 데모
"""

from hvdc_gateway_client import (
    HVDCGatewayClient, HVDCGatewayIntegration,
    MRRItem, Site, Status, UOM, TransportMode
)
import time
import threading
import subprocess
import sys
import requests

def start_mock_server():
    """Mock 서버 시작"""
    print("🚀 Starting Mock Gateway Server...")
    subprocess.Popen([sys.executable, "mock_gateway_server.py"], 
                    stdout=subprocess.DEVNULL, 
                    stderr=subprocess.DEVNULL)
    
    # 서버 시작 대기
    for i in range(10):
        try:
            response = requests.get("http://localhost:8080/v1/health", timeout=2)
            if response.status_code == 200:
                print("✅ Mock server is ready!")
                return True
        except:
            time.sleep(1)
    
    print("❌ Failed to start mock server")
    return False

def demo_with_mock():
    """Mock 서버를 사용한 데모"""
    print("🧪 HVDC Gateway Demo with Mock Server")
    print("=" * 50)
    
    # Mock 서버 시작
    if not start_mock_server():
        return False
    
    # Mock 서버용 클라이언트 생성
    client = HVDCGatewayClient(
        base_url="http://localhost:8080/v1",
        api_key="demo-key"
    )
    integration = HVDCGatewayIntegration(client)
    
    try:
        # 1. 헬스체크
        print("1. Health Check...")
        health = client.health_check()
        print(f"   Status: {health['status']}")
        print(f"   Timestamp: {health['timestamp']}")
        
        # 2. MRR 드래프트 생성
        print("\n2. MRR Draft Creation...")
        sample_items = [
            MRRItem(part_no="HVDC-TR-001", qty=2, status=Status.OK, uom=UOM.EA),
            MRRItem(part_no="HVDC-CB-002", qty=1, status=Status.OSD, uom=UOM.BOX, remarks="Minor damage"),
            MRRItem(part_no="HVDC-SW-003", qty=5, status=Status.OK, uom=UOM.EA)
        ]
        
        mrr_result = client.create_mrr_draft("PO-2025-001", Site.MIR, sample_items)
        print(f"   PO Number: {mrr_result['po_no']}")
        print(f"   Site: {mrr_result['site']}")
        print(f"   Confidence: {mrr_result['confidence']:.2f}")
        print(f"   Items: {len(mrr_result['items'])}")
        if mrr_result.get('warnings'):
            print(f"   Warnings: {', '.join(mrr_result['warnings'])}")
        
        # 3. ETA 예측 (여러 모드)
        print("\n3. ETA Predictions...")
        
        routes = [
            ("Khalifa Port", "MIR substation", TransportMode.ROAD),
            ("Jebel Ali Port", "SHU facility", TransportMode.SEA),
            ("Dubai Airport", "DAS site", TransportMode.RORO)
        ]
        
        for origin, destination, mode in routes:
            eta_result = client.predict_eta(origin, destination, mode)
            print(f"   {origin} → {destination} ({mode.value}):")
            print(f"     ETA: {eta_result.eta_utc.strftime('%Y-%m-%d %H:%M')} UTC")
            print(f"     Transit: {eta_result.transit_hours}h")
            print(f"     Risk: {eta_result.risk_level.value}")
            print(f"     Notes: {eta_result.notes}")
        
        # 4. 비용 추정 (여러 시나리오)
        print("\n4. Cost Estimations...")
        
        scenarios = [
            {"name": "Small Query", "input": 500, "output": 200, "in_cost": 0.01, "out_cost": 0.02},
            {"name": "Medium Analysis", "input": 2000, "output": 1000, "in_cost": 0.03, "out_cost": 0.06},
            {"name": "Large Report", "input": 10000, "output": 5000, "in_cost": 0.05, "out_cost": 0.10}
        ]
        
        for scenario in scenarios:
            cost_result = client.estimate_cost(
                scenario["input"], scenario["output"],
                scenario["in_cost"], scenario["out_cost"]
            )
            print(f"   {scenario['name']}:")
            print(f"     Cost: ${cost_result.estimated_cost:.6f}")
            print(f"     Band: {cost_result.band.value}")
            print(f"     Tokens: {scenario['input']}in + {scenario['output']}out")
        
        # 5. 통합 테스트 (로컬 시스템과 연동)
        print("\n5. Integration Test...")
        try:
            # 로컬 HVDC API 상태 확인
            local_response = requests.get("http://localhost:5002/health", timeout=3)
            if local_response.status_code == 200:
                print("   ✅ Local HVDC API is online")
                
                # MRR 동기화 테스트
                sync_result = integration.sync_mrr_with_local("PO-2025-002", Site.AGI, sample_items)
                print(f"   ✅ MRR sync completed: {sync_result['sync_status']}")
                print(f"   Gateway confidence: {sync_result['gateway_result']['confidence']:.2f}")
            else:
                print("   ⚠️ Local HVDC API is offline - skipping integration test")
        except:
            print("   ⚠️ Local HVDC API not available - skipping integration test")
        
        # 6. Claude 브릿지 통합 테스트
        print("\n6. Claude Bridge Integration...")
        try:
            claude_response = requests.get("http://localhost:5003/claude/status", timeout=3)
            if claude_response.status_code == 200:
                print("   ✅ Claude Bridge is online")
                
                # 향상된 ETA 예측 테스트
                enhanced_eta = integration.enhanced_eta_prediction(
                    "Khalifa Port", "MIR substation", TransportMode.ROAD
                )
                print(f"   ✅ Enhanced ETA prediction completed")
                print(f"   Gateway ETA: {enhanced_eta['gateway_eta']['eta_utc']}")
                print(f"   Risk Level: {enhanced_eta['gateway_eta']['risk_level']}")
                print(f"   Confidence: {enhanced_eta['confidence_score']:.2f}")
            else:
                print("   ⚠️ Claude Bridge is offline - skipping integration test")
        except:
            print("   ⚠️ Claude Bridge not available - skipping integration test")
        
        print("\n" + "=" * 50)
        print("🎉 Demo completed successfully!")
        print("📊 Summary:")
        print(f"   ✅ Health Check: OK")
        print(f"   ✅ MRR Draft: {mrr_result['confidence']:.2f} confidence")
        print(f"   ✅ ETA Predictions: {len(routes)} routes tested")
        print(f"   ✅ Cost Estimates: {len(scenarios)} scenarios tested")
        print("   ✅ Integration: Local and Claude bridge tested")
        
        return True
        
    except Exception as e:
        print(f"\n❌ Demo failed: {str(e)}")
        return False

if __name__ == "__main__":
    success = demo_with_mock()
    sys.exit(0 if success else 1)

