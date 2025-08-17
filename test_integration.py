#!/usr/bin/env python3
"""
HVDC 통합 시스템 테스트
비즈니스 룰 엔진 + Fuseki 배포 + NLQ 쿼리 통합 검증
"""

import pandas as pd
from hvdc_rules import run_all_rules
from fuseki_swap_verify import FusekiSwapManager
from nlq_to_sparql import generate_sparql, safe_execute_workflow
import json

def test_business_rules():
    """비즈니스 룰 엔진 테스트"""
    print("🔧 비즈니스 룰 엔진 테스트...")
    
    # 테스트 데이터 생성
    test_data = pd.DataFrame({
        'HVDC_CODE': ['HVDC-ADOPT-SCT-0001', 'HVDC-ADOPT-SCT-0002'],
        'INVOICE_VALUE': [1050.0, 720.0],  # 표준가격 대비 편차 있음
        'QTY': [1, 1],
        'UNIT_PRICE': [1050.0, 720.0],
        'HS_CODE': ['8504.40.90', '8544.60.90'],  # 85로 시작하는 고위험 코드
        'CERTS': 'MOIAT,FANR',
        'SOURCE_FILE': 'integration_test.xlsx',
        'LOGICAL_SOURCE': 'INTEGRATION_TEST',
        'EXTRACTION_TRACE': 'test_trace',
        'ROW_INDEX': [1, 2]
    })
    
    std_rates = {'HVDC-ADOPT-SCT-0001': 1000.0, 'HVDC-ADOPT-SCT-0002': 750.0}
    hs_prefixes = ['85']
    required_certs = ['MOIAT', 'FANR']
    
    result = run_all_rules(test_data, std_rates, hs_prefixes, required_certs)
    
    print(f"✅ CostGuard 알림: {len(result['cost_alerts'])}개")
    for alert in result['cost_alerts']:
        print(f"   - {alert['hvdc_code']}: {alert['delta_pct']}% 편차 ({alert['severity']})")
    
    print(f"✅ HS Risk 알림: {len(result['hs_alerts'])}개")
    for alert in result['hs_alerts']:
        print(f"   - {alert['hs_code']}: {alert['severity']} 위험")
    
    print(f"✅ CertChk 알림: {len(result['cert_alerts'])}개")
    print(f"📊 전체 요약: {result['summary']}")
    
    return result

def test_fuseki_system():
    """Fuseki 스테이징 시스템 테스트"""
    print("\n🚀 Fuseki 스테이징 시스템 테스트...")
    
    manager = FusekiSwapManager()
    
    # 헬스체크
    if not manager.check_fuseki_health():
        print("❌ Fuseki 서버 접근 불가")
        return False
    
    # 그래프 통계 조회
    stats = {}
    graphs = [
        ("STAGING", manager.staging_graph),
        ("BACKUP", manager.backup_graph),
        ("OFCO", manager.production_graphs[0]),
        ("DSV", manager.production_graphs[1]),
        ("PKGS", manager.production_graphs[2]),
        ("EXTRACTED", manager.production_graphs[3])
    ]
    
    for name, graph_uri in graphs:
        count = manager.get_triple_count(graph_uri)
        stats[name] = count
        print(f"   {name}: {count:,} triples")
    
    # 스테이징 검증 테스트 (빈 스테이징)
    validation = manager.validate_staging_data()
    print(f"📋 스테이징 검증 결과: {validation['overall_status']}")
    
    return stats

def test_nlq_queries():
    """NLQ→SPARQL 변환 시스템 테스트"""
    print("\n🔍 NLQ→SPARQL 변환 시스템 테스트...")
    
    test_queries = [
        "Show invoices where BOE != CIPL for SHPT NO 0049",
        "List all HVDC codes",
        "Invoice risk analysis",
        "Cost deviation analysis",
        "HS Code risk analysis for controlled items"
    ]
    
    results = []
    for query in test_queries:
        print(f"\n📝 쿼리: {query}")
        result = safe_execute_workflow(query)
        
        if "error" in result:
            print(f"❌ 오류: {result['error']}")
        else:
            print(f"✅ 의도: {result['intent']}")
            print(f"📋 설명: {result['description']}")
            if result.get('validation', {}).get('warnings'):
                print(f"⚠️  경고: {result['validation']['warnings']}")
        
        results.append(result)
    
    return results

def test_end_to_end_integration():
    """전체 시스템 통합 테스트"""
    print("\n🎯 전체 시스템 통합 테스트...")
    
    # 1. 비즈니스 룰 실행
    rules_result = test_business_rules()
    
    # 2. Fuseki 시스템 상태 확인
    fuseki_stats = test_fuseki_system()
    
    # 3. NLQ 쿼리 변환 테스트
    nlq_results = test_nlq_queries()
    
    # 통합 결과 요약
    print("\n📊 통합 테스트 결과 요약:")
    print("=" * 50)
    
    # 비즈니스 룰 요약
    total_alerts = (rules_result['summary']['cost_count'] + 
                   rules_result['summary']['hs_count'] + 
                   rules_result['summary']['cert_count'])
    print(f"🔧 비즈니스 룰: {total_alerts}개 알림 생성")
    
    # Fuseki 상태 요약
    total_triples = sum(count for count in fuseki_stats.values() if count > 0)
    print(f"🚀 Fuseki 시스템: {total_triples:,}개 트리플 관리 중")
    
    # NLQ 쿼리 성공률
    successful_nlq = sum(1 for r in nlq_results if "error" not in r)
    print(f"🔍 NLQ 변환: {successful_nlq}/{len(nlq_results)} 쿼리 성공")
    
    # 전체 시스템 상태
    system_healthy = (
        total_alerts > 0 and  # 룰이 정상 작동
        total_triples > 0 and  # Fuseki에 데이터 존재
        successful_nlq >= len(nlq_results) * 0.8  # NLQ 80% 이상 성공
    )
    
    status = "✅ HEALTHY" if system_healthy else "⚠️ PARTIAL"
    print(f"\n🎯 전체 시스템 상태: {status}")
    
    return {
        "rules_result": rules_result,
        "fuseki_stats": fuseki_stats,
        "nlq_results": nlq_results,
        "system_healthy": system_healthy
    }

if __name__ == "__main__":
    print("🏥 HVDC 통합 시스템 테스트 시작")
    print("=" * 60)
    
    try:
        integration_result = test_end_to_end_integration()
        
        # JSON 결과 저장
        with open("artifacts/integration_test_results.json", "w", encoding="utf-8") as f:
            # pandas DataFrame은 JSON 직렬화가 안되므로 제외
            serializable_result = {
                "timestamp": pd.Timestamp.now().isoformat(),
                "fuseki_stats": integration_result["fuseki_stats"],
                "nlq_success_count": sum(1 for r in integration_result["nlq_results"] if "error" not in r),
                "total_nlq_queries": len(integration_result["nlq_results"]),
                "rules_summary": integration_result["rules_result"]["summary"],
                "system_healthy": integration_result["system_healthy"]
            }
            json.dump(serializable_result, f, indent=2, ensure_ascii=False)
        
        print(f"\n📄 상세 결과 저장됨: artifacts/integration_test_results.json")
        
    except Exception as e:
        print(f"❌ 통합 테스트 오류: {e}")
        import traceback
        traceback.print_exc()
