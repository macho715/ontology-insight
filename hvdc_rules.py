# hvdc_rules.py
from typing import List, Dict, Any
import pandas as pd
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# CostGuard: 비교 대상 컬럼명은 'INVOICE_VALUE'와 'STD_RATE' 등 사용자 환경에 맞게 조정 필요
def run_costguard(df_items: pd.DataFrame, std_rate_table: Dict[str, float], currency: str = "USD") -> List[Dict[str,Any]]:
    """
    df_items: item-level DataFrame with columns including ['SOURCE_FILE','HVDC_CODE','INVOICE_VALUE','QTY','UNIT_PRICE']
    std_rate_table: dict mapping item_key -> standard unit price (in same currency)
    returns: list of alerts {case_id, item, draft_rate, std_rate, delta_pct, severity, evidence}
    """
    alerts = []
    for idx, row in df_items.iterrows():
        key = row.get("HVDC_CODE") or row.get("DESCRIPTION") or None
        if key is None:
            continue
        draft_price = None
        if pd.notna(row.get("UNIT_PRICE")):
            draft_price = float(row.get("UNIT_PRICE"))
        elif pd.notna(row.get("INVOICE_VALUE")) and pd.notna(row.get("QTY")) and float(row.get("QTY"))>0:
            draft_price = float(row.get("INVOICE_VALUE")) / float(row.get("QTY"))
        std = std_rate_table.get(key)
        if std and draft_price:
            delta_pct = (draft_price - std) / std * 100.0
            severity = "PASS"
            if abs(delta_pct) <= 2.0:
                severity = "PASS"
            elif abs(delta_pct) <= 5.0:
                severity = "WARN"
            elif abs(delta_pct) <= 10.0:
                severity = "HIGH"
            else:
                severity = "CRITICAL"
            alerts.append({
                "case_id": row.get("LOGICAL_SOURCE"),
                "hvdc_code": key,
                "draft_rate": round(draft_price,2),
                "std_rate": round(std,2),
                "delta_pct": round(delta_pct,2),
                "severity": severity,
                "evidence": {
                    "source_file": row.get("SOURCE_FILE"),
                    "trace": row.get("EXTRACTION_TRACE"),
                    "row_index": int(row.get("ROW_INDEX")) if pd.notna(row.get("ROW_INDEX")) else None
                }
            })
    return alerts

# HS Risk: 간단한 heuristic (실무에선 HS RISK 라이브러리나 규칙 DB 연동 권장)
def run_hs_risk(df_items: pd.DataFrame, high_risk_hs_prefixes: List[str]=None) -> List[Dict[str,Any]]:
    alerts = []
    high_risk_hs_prefixes = high_risk_hs_prefixes or ["85","73","84"]  # 예시
    for idx, row in df_items.iterrows():
        hs = str(row.get("HS_CODE","")).strip()
        if not hs:
            continue
        for pref in high_risk_hs_prefixes:
            if hs.startswith(pref):
                alerts.append({
                    "case_id": row.get("LOGICAL_SOURCE"),
                    "hvdc_code": row.get("HVDC_CODE"),
                    "hs_code": hs,
                    "risk_score": 0.8,  # heuristic
                    "severity": "HIGH",
                    "evidence": {
                        "source_file": row.get("SOURCE_FILE"),
                        "trace": row.get("EXTRACTION_TRACE"),
                    }
                })
                break
    return alerts

# CertChk: 필수 증명서 체크(예: MOIAT, FANR)
def run_cert_check(df_items: pd.DataFrame, required_certs: List[str]=None) -> List[Dict[str,Any]]:
    required_certs = required_certs or ["MOIAT","FANR"]
    alerts = []
    # assume df has column 'CERTS' with comma-separated cert names (or separate metadata source)
    for idx, row in df_items.iterrows():
        certs_raw = row.get("CERTS","") or ""
        certs = [c.strip().upper() for c in str(certs_raw).split(",") if c.strip()]
        missing = [c for c in required_certs if c not in certs]
        if missing:
            alerts.append({
                "case_id": row.get("LOGICAL_SOURCE"),
                "hvdc_code": row.get("HVDC_CODE"),
                "missing_certs": missing,
                "severity": "CRITICAL",
                "evidence": {
                    "source_file": row.get("SOURCE_FILE"),
                    "trace": row.get("EXTRACTION_TRACE"),
                }
            })
    return alerts

# Aggregator
def run_all_rules(df_items: pd.DataFrame, std_rate_table: Dict[str,float], hs_prefixes: List[str], required_certs: List[str]) -> Dict[str, Any]:
    cost_alerts = run_costguard(df_items, std_rate_table)
    hs_alerts = run_hs_risk(df_items, hs_prefixes)
    cert_alerts = run_cert_check(df_items, required_certs)
    return {
        "cost_alerts": cost_alerts,
        "hs_alerts": hs_alerts,
        "cert_alerts": cert_alerts,
        "summary": {
            "cost_count": len(cost_alerts),
            "hs_count": len(hs_alerts),
            "cert_count": len(cert_alerts)
        }
    }
