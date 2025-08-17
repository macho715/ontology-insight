#!/usr/bin/env python3
"""
HVDC Integration Demo - hvdc_one_line() + Fuseki SPARQL 연동
OFCO/DSV/PKGS/기성 → HVDC CODE 추출 → TTL 생성 → Fuseki 업로드
"""

import pandas as pd
from pathlib import Path
import json
from typing import Dict, List, Set
from hvdc_one_line import hvdc_one_line, test_patterns, create_sample_excel
import requests
from datetime import datetime

class HVDCIntegrationEngine:
    """HVDC CODE 추출 → 온톨로지 생성 → Fuseki 연동"""
    
    def __init__(self, fuseki_base_url: str = "http://localhost:3030"):
        self.fuseki_base_url = fuseki_base_url
        self.dataset = "hvdc"
        self.namespace = "http://samsung.com/project-logistics#"
        
        # Fuseki 엔드포인트들
        self.ping_url = f"{fuseki_base_url}/$/ping"
        self.sparql_url = f"{fuseki_base_url}/{self.dataset}/sparql"  
        self.update_url = f"{fuseki_base_url}/{self.dataset}/update"
        self.data_url = f"{fuseki_base_url}/{self.dataset}/data"
        
    def check_fuseki_health(self) -> bool:
        """Fuseki 서버 상태 확인"""
        try:
            response = requests.get(self.ping_url, timeout=5)
            if response.status_code == 200:
                print(f"✅ Fuseki server healthy: {response.text.strip()}")
                return True
            else:
                print(f"❌ Fuseki server error: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Fuseki server not accessible: {e}")
            return False
    
    def extract_hvdc_codes_from_sources(self, data_paths: Dict[str, str]) -> Dict[str, pd.DataFrame]:
        """다양한 소스에서 HVDC CODE 추출"""
        results = {}
        
        for source_name, path_pattern in data_paths.items():
            print(f"\n--- Processing {source_name} ---")
            try:
                df = hvdc_one_line(path_pattern)
                if not df.empty:
                    print(f"✅ Extracted {len(df)} HVDC codes from {source_name}")
                    print(f"   Unique codes: {df['HVDC_CODE'].nunique()}")
                    print(f"   Methods: {df['EXTRACT_METHOD'].unique()}")
                    results[source_name] = df
                else:
                    print(f"⚠️  No HVDC codes found in {source_name}")
                    results[source_name] = df
            except Exception as e:
                print(f"❌ Error processing {source_name}: {e}")
                results[source_name] = pd.DataFrame()
        
        return results
    
    def generate_case_triples(self, hvdc_codes: Set[str]) -> str:
        """HVDC CODE들로부터 Case 트리플 생성"""
        triples = []
        
        # 네임스페이스 선언
        triples.append("@prefix ex: <http://samsung.com/project-logistics#> .")
        triples.append("@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .")
        triples.append("@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .")
        triples.append("@prefix owl: <http://www.w3.org/2002/07/owl#> .")
        triples.append("")
        
        # Case 클래스 정의 (기본 온톨로지)
        triples.append("ex:Case a owl:Class ;")
        triples.append('    rdfs:label "Project Case" .')
        triples.append("")
        triples.append("ex:caseNumber a owl:DatatypeProperty ;")
        triples.append("    rdfs:domain ex:Case ;")
        triples.append("    rdfs:range xsd:string .")
        triples.append("")
        
        # 각 HVDC CODE에 대한 Case 인스턴스 생성
        for code in sorted(hvdc_codes):
            if code and code != 'nan':
                # URI 안전 변환
                safe_code = code.replace('-', '_').replace(' ', '_')
                case_uri = f"<ex:Case/{safe_code}>"
                
                triples.append(f"{case_uri} a ex:Case ;")
                triples.append(f'    ex:caseNumber "{code}" ;')
                triples.append(f'    rdfs:label "Case {code}" ;')
                triples.append(f'    ex:extractedDate "{datetime.now().isoformat()}"^^xsd:dateTime ;')
                triples.append(f'    ex:status "EXTRACTED" .')
                triples.append("")
        
        return "\n".join(triples)
    
    def generate_source_link_triples(self, extraction_results: Dict[str, pd.DataFrame]) -> str:
        """소스별 데이터 링크 트리플 생성"""
        triples = []
        
        # DataSource 클래스 정의
        triples.append("ex:DataSource a owl:Class ;")
        triples.append('    rdfs:label "Data Source" .')
        triples.append("")
        triples.append("ex:belongsToCase a owl:ObjectProperty ;")
        triples.append("    rdfs:range ex:Case .")
        triples.append("")
        
        for source_name, df in extraction_results.items():
            if df.empty:
                continue
                
            for idx, row in df.iterrows():
                hvdc_code = row['HVDC_CODE']
                if not hvdc_code or hvdc_code == 'nan':
                    continue
                    
                # 소스 인스턴스 URI
                safe_code = hvdc_code.replace('-', '_').replace(' ', '_')
                source_uri = f"<ex:DataSource/{source_name}_{idx}>"
                case_uri = f"<ex:Case/{safe_code}>"
                
                triples.append(f"{source_uri} a ex:DataSource ;")
                triples.append(f'    rdfs:label "{source_name} extraction {idx}" ;')
                triples.append(f"    ex:belongsToCase {case_uri} ;")
                # Windows 경로의 백슬래시를 슬래시로 변경 (TTL 호환)
                source_file = str(row.get("SOURCE_FILE", "")).replace("\\", "/")
                triples.append(f'    ex:sourceFile "{source_file}" ;')
                triples.append(f'    ex:extractMethod "{row.get("EXTRACT_METHOD", "")}" ;')
                triples.append(f'    ex:confidence "{row.get("CONF", 0.0)}"^^xsd:decimal ;')
                triples.append(f'    ex:logicalSource "{row.get("LOGICAL_SOURCE", "")}" .')
                triples.append("")
        
        return "\n".join(triples)
    
    def upload_ttl_to_fuseki(self, ttl_content: str, graph_name: str = "default") -> bool:
        """TTL 데이터를 Fuseki에 업로드"""
        try:
            if graph_name == "default":
                url = f"{self.data_url}?default"
            else:
                url = f"{self.data_url}?graph={graph_name}"
            
            headers = {"Content-Type": "text/turtle; charset=utf-8"}
            response = requests.post(url, data=ttl_content.encode('utf-8'), headers=headers)
            
            if response.status_code in [200, 201, 204]:
                print(f"✅ TTL uploaded successfully to {graph_name}")
                return True
            else:
                print(f"❌ TTL upload failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ TTL upload error: {e}")
            return False
    
    def query_fuseki(self, sparql_query: str) -> Dict:
        """Fuseki에서 SPARQL 쿼리 실행"""
        try:
            headers = {"Accept": "application/sparql-results+json"}
            data = {"query": sparql_query}
            
            response = requests.post(self.sparql_url, data=data, headers=headers)
            
            if response.status_code == 200:
                return response.json()
            else:
                print(f"❌ SPARQL query failed: {response.status_code} - {response.text}")
                return {}
                
        except Exception as e:
            print(f"❌ SPARQL query error: {e}")
            return {}
    
    def validate_integration(self) -> Dict:
        """통합 결과 검증"""
        validation_queries = {
            "total_triples": "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }",
            "case_count": """
                PREFIX ex: <http://samsung.com/project-logistics#>
                SELECT (COUNT(?case) AS ?count) WHERE { ?case a ex:Case }
            """,
            "data_source_count": """
                PREFIX ex: <http://samsung.com/project-logistics#>
                SELECT (COUNT(?ds) AS ?count) WHERE { ?ds a ex:DataSource }
            """,
            "hvdc_codes": """
                PREFIX ex: <http://samsung.com/project-logistics#>
                SELECT DISTINCT ?code WHERE { 
                    ?case a ex:Case ; ex:caseNumber ?code 
                }
                ORDER BY ?code
            """
        }
        
        results = {}
        for name, query in validation_queries.items():
            result = self.query_fuseki(query)
            if result and 'results' in result:
                if name == "hvdc_codes":
                    codes = [binding['code']['value'] for binding in result['results']['bindings']]
                    results[name] = codes
                else:
                    count = result['results']['bindings'][0]['count']['value'] if result['results']['bindings'] else 0
                    results[name] = int(count)
            else:
                results[name] = None
        
        return results
    
    def run_full_integration(self, data_paths: Dict[str, str]) -> Dict:
        """전체 통합 프로세스 실행"""
        print("=== HVDC Integration Process ===")
        
        # 1. Fuseki 상태 확인
        if not self.check_fuseki_health():
            return {"error": "Fuseki server not available"}
        
        # 2. HVDC CODE 추출
        print("\n=== Step 1: Extract HVDC Codes ===")
        extraction_results = self.extract_hvdc_codes_from_sources(data_paths)
        
        # 3. 모든 고유 HVDC CODE 수집
        all_hvdc_codes = set()
        for df in extraction_results.values():
            if not df.empty:
                codes = df['HVDC_CODE'].dropna().unique()
                all_hvdc_codes.update(codes)
        
        print(f"\n✅ Total unique HVDC codes found: {len(all_hvdc_codes)}")
        print(f"   Codes: {sorted(list(all_hvdc_codes))}")
        
        # 4. Case 트리플 생성
        print("\n=== Step 2: Generate Case Triples ===")
        case_ttl = self.generate_case_triples(all_hvdc_codes)
        
        # 5. 소스 링크 트리플 생성  
        print("\n=== Step 3: Generate Source Link Triples ===")
        link_ttl = self.generate_source_link_triples(extraction_results)
        
        # 6. TTL 파일 저장
        full_ttl = case_ttl + "\n\n" + link_ttl
        ttl_filename = f"hvdc_extracted_{datetime.now().strftime('%Y%m%d_%H%M%S')}.ttl"
        
        with open(ttl_filename, 'w', encoding='utf-8') as f:
            f.write(full_ttl)
        print(f"✅ TTL saved: {ttl_filename}")
        
        # 7. Fuseki 업로드
        print("\n=== Step 4: Upload to Fuseki ===")
        upload_success = self.upload_ttl_to_fuseki(full_ttl, "extracted")
        
        # 8. 검증
        print("\n=== Step 5: Validate Integration ===")
        validation_results = self.validate_integration()
        
        return {
            "extraction_results": extraction_results,
            "hvdc_codes": list(all_hvdc_codes),
            "ttl_filename": ttl_filename,
            "upload_success": upload_success,
            "validation": validation_results
        }

def demo_integration():
    """통합 데모 실행"""
    # 샘플 데이터 생성
    print("=== Creating Sample Data ===")
    create_sample_excel()
    
    # 통합 엔진 초기화
    engine = HVDCIntegrationEngine()
    
    # 데이터 소스 경로 설정
    data_paths = {
        "OFCO": "sample_data/OFCO*.xlsx",
        "DSV": "sample_data/DSV*.xlsx", 
        "PKGS": "sample_data/PKGS*.xlsx"
    }
    
    # 전체 통합 실행
    results = engine.run_full_integration(data_paths)
    
    # 결과 출력
    print("\n=== Integration Results ===")
    if "error" in results:
        print(f"❌ Integration failed: {results['error']}")
    else:
        print(f"✅ Extracted HVDC codes: {len(results['hvdc_codes'])}")
        print(f"✅ TTL file: {results['ttl_filename']}")
        print(f"✅ Upload success: {results['upload_success']}")
        
        if results['validation']:
            val = results['validation']
            print(f"✅ Total triples: {val.get('total_triples', 'N/A')}")
            print(f"✅ Cases created: {val.get('case_count', 'N/A')}")
            print(f"✅ Data sources: {val.get('data_source_count', 'N/A')}")
            
            if val.get('hvdc_codes'):
                print(f"✅ HVDC codes in Fuseki: {val['hvdc_codes']}")

if __name__ == "__main__":
    # 패턴 테스트
    test_patterns()
    
    print("\n" + "="*60)
    
    # 통합 데모 실행
    try:
        demo_integration()
    except ImportError as e:
        print(f"Missing dependencies: {e}")
        print("Install with: pip install pandas openpyxl requests")
    except Exception as e:
        print(f"Demo error: {e}")
        print("Make sure Fuseki server is running on localhost:3030")
