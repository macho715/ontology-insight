# hvdc_one_line.py  (drop-in utility)
from __future__ import annotations
from pathlib import Path
import pandas as pd
import re
from typing import Iterable, Union, Dict, List

# ---- 1) Patterns & header aliases ------------------------------------------
# HVDC-ADOPT-SCT-0001 / HVDC-ADOPT-VENDOR-NAME-REF-NO 등 공백·-·_ 혼용 허용
# 토큰 3~6개, 마지막이 숫자인 형태도 커버 (0001 등)
_HVDC_RX = re.compile(
    r'(?i)\bHVDC(?:[-_ ]+[A-Z0-9]+){2,6}\b'              # 일반형
)
_HVDC_RX_NUMTAIL = re.compile(
    r'(?i)\bHVDC(?:[-_ ]+[A-Z0-9]+){1,5}[-_ ]+\d{3,6}\b' # 숫자 꼬리 선호
)
# 자주 쓰는 헤더 동의어 → 표준 헤더로 매핑
_HEADER_ALIASES: Dict[re.Pattern, str] = {
    re.compile(r'(?i)^\s*hvdc\s*code\s*$'): 'HVDC CODE',
    re.compile(r'(?i)^\s*case\s*(no\.|#)?\s*$'): 'HVDC CODE',
    re.compile(r'(?i)^\s*ref(\.|erence)?\s*no\s*$'): 'REF NO',
    re.compile(r'(?i)^\s*remarks?\s*$'): 'REMARKS',
    re.compile(r'(?i)^\s*description\s*$'): 'DESCRIPTION',
}

# ---- 2) Helpers -------------------------------------------------------------
def _logical_source_name(p: Path) -> str:
    """OFCO ALL INV, OFCO ALL INV.(1), OFCO ALL INV.2 등을 동일 소스로 정규화."""
    stem = p.stem
    # 끝의 (1) / .1 / _1 / - copy / 복사본 등 일반 패턴 제거
    stem = re.sub(r'[\s._-]*(\(\d+\)|\d+|copy|복사본)$', '', stem, flags=re.I)
    return stem.strip().upper()

def _normalize_code(txt: str) -> str:
    """HVDC 코드 표기 표준화: 공백/구분자 -> '-', 대문자, 중복 '-' 축약, 'HVDC-' 접두 유지."""
    s = re.sub(r'\s+', ' ', str(txt or '')).strip().upper()
    s = re.sub(r'[^A-Z0-9]+', '-', s).strip('-')
    if not s.startswith('HVDC-'):
        s = 'HVDC-' + s[4:].lstrip('-') if s.startswith('HVDC') else 'HVDC-' + s
    s = re.sub(r'-{2,}', '-', s)
    return s

def _apply_header_aliases(cols: Iterable[str]) -> List[str]:
    out = []
    for c in cols:
        newc = c
        for rx, canon in _HEADER_ALIASES.items():
            if rx.match(str(c)):
                newc = canon
                break
        out.append(newc)
    return out

def _extract_from_row_strings(values: Iterable[object]) -> str | None:
    # 성능 위해 너무 긴 문자열은 축약
    joined = ' | '.join(str(v) for v in values if pd.notna(v))[:2000]
    m = _HVDC_RX_NUMTAIL.search(joined) or _HVDC_RX.search(joined)
    return _normalize_code(m.group(0)) if m else None

def _read_excel_all_sheets(path: Path) -> Dict[str, pd.DataFrame]:
    # pandas는 sheet_name=None 시 모든 시트를 dict로 반환 (버전별 동일 동작)
    return pd.read_excel(path, sheet_name=None)

def _iter_paths(arg: Union[str, Path, Iterable[Union[str, Path]]]) -> List[Path]:
    """문자열(glob 허용)/경로/리스트 혼용 입력을 모두 Path 리스트로 확장."""
    paths: List[Path] = []
    def _push(pat: str | Path):
        p = Path(pat)
        if any(ch in str(p) for ch in "*?[]"):      # glob 패턴이면 확장
            paths.extend(sorted(Path().glob(str(p))))
        elif p.is_dir():
            paths.extend(sorted(p.rglob("*.xls*"))) # 디렉토리는 엑셀 전부 스캔
        else:
            paths.append(p)
    if isinstance(arg, (str, Path)):
        _push(arg)
    else:
        for item in arg:
            _push(item)
    # 중복 제거
    uniq = []
    seen = set()
    for p in paths:
        if p.exists() and str(p.resolve()) not in seen:
            uniq.append(p)
            seen.add(str(p.resolve()))
    return uniq

# ---- 3) Main: hvdc_one_line -------------------------------------------------
def hvdc_one_line(paths: Union[str, Path, Iterable[Union[str, Path]]]) -> pd.DataFrame:
    """
    다양한 소스(OFCO/DSV/PKGS/기성 등)에서 HVDC CODE를 추출해 단일 DF로 반환.
    - 입력: 파일 경로/디렉토리/글롭 패턴/리스트
    - 출력: 컬럼 [HVDC_CODE, EXTRACT_METHOD, CONF, SOURCE_FILE, LOGICAL_SOURCE, SHEET_NAME, ROW_INDEX]
    """
    rows = []
    for file in _iter_paths(paths):
        logical_src = _logical_source_name(file)
        try:
            book = _read_excel_all_sheets(file)
        except Exception as e:
            rows.append({
                "HVDC_CODE": None, "EXTRACT_METHOD": "ERROR", "CONF": 0.0,
                "SOURCE_FILE": str(file), "LOGICAL_SOURCE": logical_src,
                "SHEET_NAME": None, "ROW_INDEX": None, "ERROR": str(e)[:400]
            })
            continue

        for sheet_name, df in book.items():
            if df is None or df.empty:
                continue
            # 헤더 정규화
            df = df.copy()
            df.columns = _apply_header_aliases(df.columns)
            # 1) 컬럼 직접(최우선 신뢰)
            code_series = None
            if "HVDC CODE" in df.columns:
                code_series = df["HVDC CODE"].astype(str).map(
                    lambda s: _normalize_code(s) if _HVDC_RX.search(str(s)) else None
                )
                for idx, val in code_series.dropna().items():
                    rows.append({
                        "HVDC_CODE": val, "EXTRACT_METHOD": "header:HVDC CODE", "CONF": 0.95,
                        "SOURCE_FILE": str(file), "LOGICAL_SOURCE": logical_src,
                        "SHEET_NAME": str(sheet_name), "ROW_INDEX": int(idx)
                    })
            # 2) 보조 컬럼(REF NO/REMARKS/DESCRIPTION)
            candidates = [c for c in ["REF NO", "REMARKS", "DESCRIPTION"] if c in df.columns]
            if candidates:
                for idx, r in df[candidates].fillna("").astype(str).iterrows():
                    hv = _extract_from_row_strings(r.values)
                    if hv:
                        rows.append({
                            "HVDC_CODE": hv, "EXTRACT_METHOD": f"cols:{'+'.join(candidates)}", "CONF": 0.85,
                            "SOURCE_FILE": str(file), "LOGICAL_SOURCE": logical_src,
                            "SHEET_NAME": str(sheet_name), "ROW_INDEX": int(idx)
                        })
            # 3) 행 전체 문자열(시트 스캔)
            if df.shape[0] <= 5000:  # 너무 크면 생략(성능)
                for idx, r in df.fillna("").astype(str).iterrows():
                    hv = _extract_from_row_strings(r.values)
                    if hv:
                        rows.append({
                            "HVDC_CODE": hv, "EXTRACT_METHOD": "row-scan", "CONF": 0.70,
                            "SOURCE_FILE": str(file), "LOGICAL_SOURCE": logical_src,
                            "SHEET_NAME": str(sheet_name), "ROW_INDEX": int(idx)
                        })

            # 4) 시트명/파일명 추출(최후)
            sheet_hit = _HVDC_RX_NUMTAIL.search(str(sheet_name)) or _HVDC_RX.search(str(sheet_name))
            file_hit  = _HVDC_RX_NUMTAIL.search(file.stem) or _HVDC_RX.search(file.stem)
            if sheet_hit:
                rows.append({
                    "HVDC_CODE": _normalize_code(sheet_hit.group(0)),
                    "EXTRACT_METHOD": "sheet-name", "CONF": 0.60,
                    "SOURCE_FILE": str(file), "LOGICAL_SOURCE": logical_src,
                    "SHEET_NAME": str(sheet_name), "ROW_INDEX": None
                })
            if file_hit:
                rows.append({
                    "HVDC_CODE": _normalize_code(file_hit.group(0)),
                    "EXTRACT_METHOD": "file-name", "CONF": 0.55,
                    "SOURCE_FILE": str(file), "LOGICAL_SOURCE": logical_src,
                    "SHEET_NAME": str(sheet_name), "ROW_INDEX": None
                })

    if not rows:
        return pd.DataFrame(columns=[
            "HVDC_CODE","EXTRACT_METHOD","CONF","SOURCE_FILE","LOGICAL_SOURCE","SHEET_NAME","ROW_INDEX","ERROR"
        ])

    df_all = pd.DataFrame(rows)

    # 우선순위: header > cols > row > sheet > file  (동일(HVDC_CODE, SOURCE_FILE, SHEET, ROW) 중 최상만)
    priority = {"header:HVDC CODE":5, "cols:REF NO+REMARKS+DESCRIPTION":4, "cols:REF NO":4,
                "cols:REMARKS":3, "cols:DESCRIPTION":3, "row-scan":2, "sheet-name":1, "file-name":0, "ERROR":-1}
    df_all["PRI"] = df_all["EXTRACT_METHOD"].map(priority).fillna(1)
    df_all.sort_values(["HVDC_CODE","LOGICAL_SOURCE","SOURCE_FILE","SHEET_NAME","ROW_INDEX","PRI","CONF"],
                       ascending=[True,True,True,True,True,False,False], inplace=True)
    # 같은 위치 중복 제거
    df_all = df_all.drop_duplicates(subset=["HVDC_CODE","SOURCE_FILE","SHEET_NAME","ROW_INDEX"], keep="first")
    # NaN HVDC 제거
    df_all = df_all[df_all["HVDC_CODE"].notna()].reset_index(drop=True)
    return df_all[["HVDC_CODE","EXTRACT_METHOD","CONF","SOURCE_FILE","LOGICAL_SOURCE","SHEET_NAME","ROW_INDEX"]]

# ---- 4) Test & Demo Functions -----------------------------------------------
def test_patterns():
    """정규식 패턴 테스트"""
    test_cases = [
        "HVDC-ADOPT-SCT-0001",
        "HVDC ADOPT SCT 0002", 
        "HVDC_ADOPT_VENDOR_NAME_REF_001",
        "Project HVDC-ADOPT-Phase-1-2024",
        "Invoice for HVDC ADOPT SCT 0003",
        "HVDC ADOPT SIEMENS 2024 001",
        "Random text without code",
        "SCT-0001",  # 불완전 패턴
    ]
    
    print("=== Pattern Testing ===")
    for case in test_cases:
        match_general = _HVDC_RX.search(case)
        match_numtail = _HVDC_RX_NUMTAIL.search(case)
        
        result = "No match"
        if match_numtail:
            result = f"NUMTAIL: {_normalize_code(match_numtail.group(0))}"
        elif match_general:
            result = f"GENERAL: {_normalize_code(match_general.group(0))}"
            
        print(f"'{case}' → {result}")

def create_sample_excel():
    """테스트용 샘플 엑셀 파일 생성"""
    import os
    
    # 샘플 데이터 생성
    sample_data = {
        'OFCO_Sample': {
            'Sheet1': pd.DataFrame({
                'INVOICE NO': ['INV-2024-001', 'INV-2024-002', 'INV-2024-003'],
                'HVDC CODE': ['HVDC-ADOPT-SCT-0001', 'HVDC-ADOPT-SCT-0002', None],
                'AMOUNT': [1000000, 750000, 500000],
                'CURRENCY': ['USD', 'USD', 'USD'],
                'REMARKS': ['For converter equipment', 'HVDC-ADOPT-SCT-0003 cable', 'Control system']
            }),
            'Sheet2': pd.DataFrame({
                'REF NO': ['REF-001', 'HVDC-ADOPT-SCT-0004', 'REF-003'],
                'DESCRIPTION': ['Main transformer', 'Cable system components', 'Protection system'],
                'VALUE': [2000000, 1200000, 800000]
            })
        },
        'DSV_Sample': {
            'Transport': pd.DataFrame({
                'BL NO': ['BL-2024-001', 'BL-2024-002'],
                'CONTAINER': ['CONT-001', 'CONT-002'], 
                'REMARKS': ['HVDC-ADOPT-SCT-0001 equipment', 'Cable for HVDC-ADOPT-SCT-0002'],
                'VESSEL': ['MV SAMSUNG', 'MV HYUNDAI']
            })
        },
        'PKGS_Sample': {
            'Package List': pd.DataFrame({
                'PACKAGE NO': ['PKG-001', 'PKG-002', 'PKG-003'],
                'HVDC CODE': ['HVDC-ADOPT-SCT-0001', 'HVDC-ADOPT-SCT-0002', 'HVDC-ADOPT-SCT-0003'],
                'GROSS WEIGHT': [45000, 28000, 12500],
                'DIMENSIONS': ['12.5m x 4.2m x 5.8m', '8m x 3m x 4m', '6m x 2m x 3m']
            })
        }
    }
    
    # 파일 생성
    os.makedirs('sample_data', exist_ok=True)
    
    for filename, sheets in sample_data.items():
        filepath = f'sample_data/{filename}.xlsx'
        with pd.ExcelWriter(filepath, engine='openpyxl') as writer:
            for sheet_name, df in sheets.items():
                df.to_excel(writer, sheet_name=sheet_name, index=False)
        print(f"Created: {filepath}")
    
    # 파일명 변형 테스트용 복사본도 생성
    import shutil
    shutil.copy('sample_data/OFCO_Sample.xlsx', 'sample_data/OFCO_Sample.(1).xlsx')
    shutil.copy('sample_data/DSV_Sample.xlsx', 'sample_data/DSV_Sample_copy.xlsx')
    
    print("Sample files created in 'sample_data/' directory")

def demo_usage():
    """사용법 데모"""
    print("\n=== Demo Usage ===")
    
    # 샘플 파일 생성
    create_sample_excel()
    
    # 패턴별 테스트
    print("\n1. Single file:")
    result1 = hvdc_one_line('sample_data/PKGS_Sample.xlsx')
    print(result1.to_string())
    
    print("\n2. Glob pattern:")
    result2 = hvdc_one_line('sample_data/OFCO*.xlsx')
    print(result2[['HVDC_CODE', 'EXTRACT_METHOD', 'CONF', 'LOGICAL_SOURCE']].to_string())
    
    print("\n3. Multiple files:")
    result3 = hvdc_one_line(['sample_data/DSV_Sample.xlsx', 'sample_data/PKGS_Sample.xlsx'])
    print(result3[['HVDC_CODE', 'EXTRACT_METHOD', 'LOGICAL_SOURCE']].to_string())
    
    print("\n4. Directory scan:")
    result4 = hvdc_one_line('sample_data/')
    print(f"\nTotal extracted codes: {len(result4)}")
    print(f"Unique HVDC codes: {result4['HVDC_CODE'].nunique()}")
    print(f"Logical sources: {result4['LOGICAL_SOURCE'].unique()}")
    
    # 통계 출력
    print("\n=== Extraction Statistics ===")
    method_stats = result4['EXTRACT_METHOD'].value_counts()
    print("Methods used:")
    for method, count in method_stats.items():
        print(f"  {method}: {count}")
    
    conf_stats = result4.groupby('EXTRACT_METHOD')['CONF'].mean()
    print("\nAverage confidence by method:")
    for method, conf in conf_stats.items():
        print(f"  {method}: {conf:.2f}")

if __name__ == "__main__":
    # 패턴 테스트
    test_patterns()
    
    # 사용법 데모 (pandas가 있는 경우)
    try:
        demo_usage()
    except ImportError:
        print("\nSkipping demo - pandas not available")
        print("Install with: pip install pandas openpyxl")
