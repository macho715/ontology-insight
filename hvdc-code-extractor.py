#!/usr/bin/env python3
"""
HVDC CODE 결손 자동 보강 로직
OFCO/DSV/PAY에서 정규식 추출로 HVDC CODE 생성 및 Case 연결
"""

import re
import json
from typing import Dict, List, Optional, Set
from dataclasses import dataclass
from pathlib import Path

@dataclass
class HVDCCodeMapping:
    """HVDC CODE 매핑 결과"""
    original_value: str
    extracted_code: str
    confidence: float  # 0.0 ~ 1.0
    source_field: str
    method: str  # 'regex_extract', 'business_rule', 'lookup_table'

class HVDCCodeExtractor:
    """HVDC CODE 추출 및 보강 엔진"""
    
    def __init__(self, mapping_config_path: str = "hvdc-code-mapping-v2.6.2.json"):
        """초기화"""
        self.config = self._load_config(mapping_config_path)
        self.vendor_mapping = self.config['business_rules']['hvdc_code_generation']['vendor_mapping']
        self.lookup_table: Dict[str, str] = {}  # PO/Invoice -> HVDC CODE 매핑
        
        # 헤더 정규화 패턴들
        self.header_patterns = [
            re.compile(pattern, re.IGNORECASE) 
            for pattern in self.config['header_normalization']['hvdc_code_patterns']
        ]
        
        self.alt_key_patterns = [
            re.compile(pattern, re.IGNORECASE)
            for pattern in self.config['header_normalization']['alternative_keys']
        ]
        
        # HVDC CODE 추출 패턴
        self.hvdc_extraction_pattern = re.compile(
            self.config['header_normalization']['hvdc_code_extraction']['pattern'],
            re.IGNORECASE
        )
        
        # 확장 패턴들 (더 유연한 매칭)
        self.extended_patterns = [
            re.compile(r'(?i)\bHVDC[-_\s]?[A-Z0-9]+[-_\s]?[A-Z0-9]+[-_\s]?[A-Z0-9]+[-_\s]?\d{3,6}\b'),
            re.compile(r'(?i)\b[A-Z]{3,5}[-_\s]?\d{4}[-_\s]?[A-Z]{2,4}[-_\s]?\d{3,4}\b'),  # SCT-0001 패턴
            re.compile(r'(?i)\bSCT[-_\s]?\d{4}\b'),  # SCT-0001 단독
            re.compile(r'(?i)\bADOPT[-_\s]?[A-Z0-9]+\b')  # ADOPT 관련
        ]

    def _load_config(self, config_path: str) -> Dict:
        """매핑 설정 로드"""
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            # 기본 설정 반환
            return {
                'header_normalization': {
                    'hvdc_code_patterns': [r'(?i)hvdc[\s_-]*code'],
                    'alternative_keys': [r'(?i)case\s*no', r'(?i)ref\s*no'],
                    'hvdc_code_extraction': {'pattern': r'HVDC-[A-Z]+-[A-Z]+-\w+'}
                },
                'business_rules': {
                    'hvdc_code_generation': {
                        'vendor_mapping': {
                            'Samsung Heavy Industries': 'SHI',
                            'LS Cable & System': 'LSC',
                            'Hyundai Electric': 'HE'
                        }
                    }
                }
            }

    def normalize_header(self, header: str) -> str:
        """헤더 정규화"""
        header = header.strip()
        
        # HVDC CODE 패턴 매칭
        for pattern in self.header_patterns:
            if pattern.match(header):
                return 'HVDC CODE'
        
        # 대체 키 패턴 매칭  
        for pattern in self.alt_key_patterns:
            if pattern.match(header):
                return 'ALT_REF'
                
        return header

    def extract_hvdc_code(self, text: str, source_field: str = "") -> Optional[HVDCCodeMapping]:
        """텍스트에서 HVDC CODE 추출"""
        if not text or pd.isna(text):
            return None
            
        text_str = str(text).strip()
        if not text_str:
            return None

        # 1. 정확한 패턴 매칭 (높은 신뢰도)
        match = self.hvdc_extraction_pattern.search(text_str)
        if match:
            code = self._normalize_hvdc_code(match.group(0))
            return HVDCCodeMapping(
                original_value=text_str,
                extracted_code=code,
                confidence=0.95,
                source_field=source_field,
                method='regex_extract'
            )

        # 2. 확장 패턴들 시도 (중간 신뢰도)
        for i, pattern in enumerate(self.extended_patterns):
            match = pattern.search(text_str)
            if match:
                code = self._build_hvdc_code_from_parts(match.group(0))
                confidence = 0.8 - (i * 0.1)  # 패턴 순서에 따라 신뢰도 감소
                return HVDCCodeMapping(
                    original_value=text_str,
                    extracted_code=code,
                    confidence=max(confidence, 0.5),
                    source_field=source_field,
                    method='regex_extract'
                )

        return None

    def _normalize_hvdc_code(self, raw_code: str) -> str:
        """HVDC CODE 정규화"""
        # 공백, 언더스코어를 하이픈으로 통일
        code = re.sub(r'[-_\s]+', '-', raw_code.upper().strip())
        
        # HVDC- 접두사 보장
        if not code.startswith('HVDC-'):
            if code.startswith('ADOPT-') or code.startswith('SCT-'):
                code = 'HVDC-' + code
            else:
                code = 'HVDC-ADOPT-' + code
                
        return code

    def _build_hvdc_code_from_parts(self, raw_match: str) -> str:
        """부분 매칭에서 완전한 HVDC CODE 구성"""
        parts = re.split(r'[-_\s]+', raw_match.upper().strip())
        
        # SCT-0001 패턴 처리
        if len(parts) == 2 and parts[0] == 'SCT' and parts[1].isdigit():
            return f"HVDC-ADOPT-SCT-{parts[1].zfill(4)}"
        
        # ADOPT 관련 처리
        if 'ADOPT' in parts:
            if len(parts) >= 2:
                return f"HVDC-ADOPT-{'-'.join(parts[1:])}"
        
        # 기본 구성
        if not raw_match.upper().startswith('HVDC'):
            return f"HVDC-ADOPT-{raw_match.upper()}"
        
        return self._normalize_hvdc_code(raw_match)

    def generate_business_rule_code(self, supplier: str, ref_value: str) -> HVDCCodeMapping:
        """비즈니스 룰 기반 HVDC CODE 생성"""
        vendor_code = self.vendor_mapping.get(supplier, 'UNK')
        
        # 참조 값에서 숫자 추출
        ref_digits = re.findall(r'\d+', str(ref_value))
        if ref_digits:
            ref_num = ref_digits[-1].zfill(4)  # 마지막 숫자를 4자리로
        else:
            ref_num = '0000'
        
        generated_code = f"HVDC-ADOPT-{vendor_code}-{ref_num}"
        
        return HVDCCodeMapping(
            original_value=f"{supplier}|{ref_value}",
            extracted_code=generated_code,
            confidence=0.7,
            source_field='supplier+ref',
            method='business_rule'
        )

    def build_lookup_table(self, pkgs_data: List[Dict]) -> None:
        """PKGS 데이터에서 조인 테이블 구성"""
        for row in pkgs_data:
            hvdc_code = row.get('HVDC CODE')
            if hvdc_code:
                # PO 번호 매핑
                po_no = row.get('PO NO') or row.get('PO NUMBER')
                if po_no:
                    self.lookup_table[str(po_no)] = hvdc_code
                
                # Invoice 번호 매핑
                inv_no = row.get('INVOICE NO') or row.get('INV NO')
                if inv_no:
                    self.lookup_table[str(inv_no)] = hvdc_code
                
                # Package 번호 매핑
                pkg_no = row.get('PACKAGE NO') or row.get('PKG NO')
                if pkg_no:
                    self.lookup_table[str(pkg_no)] = hvdc_code

    def process_data_source(self, data: List[Dict], source_type: str) -> List[Dict]:
        """데이터 소스별 HVDC CODE 보강 처리"""
        results = []
        
        for row in data:
            enhanced_row = row.copy()
            hvdc_mapping = None
            
            # 1. 기존 HVDC CODE 확인
            existing_code = self._find_existing_hvdc_code(row)
            if existing_code:
                hvdc_mapping = HVDCCodeMapping(
                    original_value=existing_code,
                    extracted_code=existing_code,
                    confidence=1.0,
                    source_field='existing',
                    method='direct'
                )
            else:
                # 2. 조인 테이블 조회
                hvdc_mapping = self._lookup_from_table(row)
                
                # 3. 정규식 추출 시도
                if not hvdc_mapping:
                    hvdc_mapping = self._extract_from_row(row)
                
                # 4. 비즈니스 룰 생성
                if not hvdc_mapping:
                    hvdc_mapping = self._generate_from_business_rules(row)

            # 결과 기록
            if hvdc_mapping:
                enhanced_row['HVDC_CODE_EXTRACTED'] = hvdc_mapping.extracted_code
                enhanced_row['HVDC_CODE_CONFIDENCE'] = hvdc_mapping.confidence
                enhanced_row['HVDC_CODE_METHOD'] = hvdc_mapping.method
                enhanced_row['HVDC_CODE_SOURCE'] = hvdc_mapping.source_field
            else:
                enhanced_row['HVDC_CODE_EXTRACTED'] = 'UNKNOWN-CASE'
                enhanced_row['HVDC_CODE_CONFIDENCE'] = 0.0
                enhanced_row['HVDC_CODE_METHOD'] = 'failed'
                enhanced_row['HVDC_CODE_SOURCE'] = 'none'
            
            results.append(enhanced_row)
        
        return results

    def _find_existing_hvdc_code(self, row: Dict) -> Optional[str]:
        """행에서 기존 HVDC CODE 찾기"""
        for key, value in row.items():
            normalized_key = self.normalize_header(key)
            if normalized_key == 'HVDC CODE' and value:
                return str(value).strip()
        return None

    def _lookup_from_table(self, row: Dict) -> Optional[HVDCCodeMapping]:
        """조인 테이블에서 HVDC CODE 조회"""
        lookup_fields = ['PO NO', 'PO NUMBER', 'INVOICE NO', 'INV NO', 'PACKAGE NO', 'PKG NO']
        
        for field in lookup_fields:
            value = row.get(field)
            if value and str(value) in self.lookup_table:
                return HVDCCodeMapping(
                    original_value=str(value),
                    extracted_code=self.lookup_table[str(value)],
                    confidence=0.9,
                    source_field=field,
                    method='lookup_table'
                )
        return None

    def _extract_from_row(self, row: Dict) -> Optional[HVDCCodeMapping]:
        """행의 모든 필드에서 정규식 추출 시도"""
        for key, value in row.items():
            if value:
                mapping = self.extract_hvdc_code(str(value), key)
                if mapping:
                    return mapping
        return None

    def _generate_from_business_rules(self, row: Dict) -> Optional[HVDCCodeMapping]:
        """비즈니스 룰로 HVDC CODE 생성"""
        supplier = row.get('SUPPLIER') or row.get('VENDOR') or row.get('SUPPLIER NAME')
        ref_value = (row.get('REF NO') or row.get('REFERENCE') or 
                    row.get('INVOICE NO') or row.get('PO NO') or 'AUTO')
        
        if supplier and ref_value:
            return self.generate_business_rule_code(supplier, ref_value)
        
        return None

    def generate_statistics(self, results: List[Dict]) -> Dict:
        """처리 결과 통계 생성"""
        total = len(results)
        if total == 0:
            return {}
        
        method_counts = {}
        confidence_sum = 0
        high_confidence = 0  # >= 0.8
        
        for row in results:
            method = row.get('HVDC_CODE_METHOD', 'unknown')
            method_counts[method] = method_counts.get(method, 0) + 1
            
            confidence = row.get('HVDC_CODE_CONFIDENCE', 0)
            confidence_sum += confidence
            if confidence >= 0.8:
                high_confidence += 1
        
        return {
            'total_records': total,
            'avg_confidence': confidence_sum / total,
            'high_confidence_rate': high_confidence / total,
            'method_distribution': method_counts,
            'success_rate': (total - method_counts.get('failed', 0)) / total
        }

# 사용 예시 및 테스트 함수
def main():
    """메인 실행 함수"""
    extractor = HVDCCodeExtractor()
    
    # 테스트 데이터
    test_cases = [
        {"text": "HVDC-ADOPT-SCT-0001", "expected": "HVDC-ADOPT-SCT-0001"},
        {"text": "SCT-0002 Cable System", "expected": "HVDC-ADOPT-SCT-0002"},
        {"text": "Project ADOPT Phase 1", "expected": "HVDC-ADOPT-PHASE-1"},
        {"text": "Invoice for HVDC_ADOPT_SCT_0003", "expected": "HVDC-ADOPT-SCT-0003"},
        {"text": "Random text without code", "expected": None}
    ]
    
    print("=== HVDC CODE 추출 테스트 ===")
    for i, case in enumerate(test_cases):
        result = extractor.extract_hvdc_code(case["text"], f"test_{i}")
        extracted = result.extracted_code if result else None
        status = "✓" if extracted == case["expected"] else "✗"
        
        print(f"{status} '{case['text']}' → '{extracted}' (confidence: {result.confidence if result else 0:.2f})")

    # 비즈니스 룰 테스트
    print("\n=== 비즈니스 룰 생성 테스트 ===")
    business_rule_result = extractor.generate_business_rule_code("Samsung Heavy Industries", "INV-2024-001")
    print(f"✓ Samsung Heavy Industries + INV-2024-001 → {business_rule_result.extracted_code}")

if __name__ == "__main__":
    # pandas import (필요시)
    try:
        import pandas as pd
    except ImportError:
        # pandas 없으면 간단한 대체 함수
        class pd:
            @staticmethod
            def isna(x):
                return x is None or (isinstance(x, str) and x.strip() == "")
    
    main()
