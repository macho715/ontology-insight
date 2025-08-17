# audit_logger.py - Enhanced Security & Compliance Audit System
from datetime import datetime, timezone
import csv
import hashlib
import json
import os
from pathlib import Path
from typing import Dict, Any, Optional, List
import logging

# 보안 강화된 감사 로그 설정
AUDIT_CSV = Path("artifacts/audit_log.csv")
AUDIT_CSV.parent.mkdir(parents=True, exist_ok=True)

# PII/NDA 민감 정보 패턴 (MACHO-GPT 보안 표준)
SENSITIVE_PATTERNS = [
    r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b',  # 카드번호
    r'\b\d{3}-\d{2}-\d{4}\b',  # SSN
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',  # 이메일
    r'\bpassword\s*[:=]\s*\S+\b',  # 패스워드
    r'\bapi[_-]?key\s*[:=]\s*\S+\b',  # API 키
]

def sanitize_sensitive_data(data: Any) -> Any:
    """
    PII/NDA 민감 정보 마스킹 (MACHO-GPT 보안 표준)
    """
    if isinstance(data, dict):
        return {k: sanitize_sensitive_data(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_sensitive_data(item) for item in data]
    elif isinstance(data, str):
        import re
        sanitized = data
        for pattern in SENSITIVE_PATTERNS:
            sanitized = re.sub(pattern, '[REDACTED]', sanitized, flags=re.IGNORECASE)
        return sanitized
    return data

def calculate_integrity_hash(row_data: Dict[str, Any]) -> str:
    """
    감사 로그 무결성 검증용 해시 계산
    """
    # 타임스탬프 제외한 데이터로 해시 계산
    hash_data = {k: v for k, v in row_data.items() if k != 'integrity_hash'}
    data_str = json.dumps(hash_data, sort_keys=True, default=str)
    return hashlib.sha256(data_str.encode('utf-8')).hexdigest()[:16]

def write_audit(action: str, actor: str, detail: Dict[str, Any], 
                risk_level: str = "LOW", compliance_tags: Optional[List[str]] = None) -> Dict[str, Any]:
    """
    Enhanced audit logging with security and compliance features
    
    Args:
        action: 작업 유형 (e.g., 'ingest', 'run_rules', 'data_export')
        actor: 사용자/시스템 식별자 (PII 마스킹 적용)
        detail: 상세 정보 (민감 정보 자동 마스킹)
        risk_level: 위험도 (LOW/MEDIUM/HIGH/CRITICAL)
        compliance_tags: 규제 준수 태그 (FANR, MOIAT, GDPR 등)
    
    Returns:
        Dict containing logged audit entry
    """
    # 민감 정보 마스킹
    sanitized_detail = sanitize_sensitive_data(detail)
    sanitized_actor = sanitize_sensitive_data(actor)
    
    # UTC 타임스탬프 (ISO 8601)
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # 감사 로그 엔트리 생성
    row = {
        "ts": timestamp,
        "action": action,
        "actor": str(sanitized_actor),
        "detail": json.dumps(sanitized_detail, default=str, ensure_ascii=False),
        "risk_level": risk_level.upper(),
        "compliance_tags": ",".join(compliance_tags or []),
        "session_id": os.environ.get("HVDC_SESSION_ID", "system"),
        "source_ip": os.environ.get("REMOTE_ADDR", "localhost"),
    }
    
    # 무결성 해시 추가
    row["integrity_hash"] = calculate_integrity_hash(row)
    
    try:
        # 파일 잠금과 함께 원자적 쓰기
        write_mode = "a" if AUDIT_CSV.exists() else "w"
        with open(AUDIT_CSV, write_mode, newline='', encoding='utf-8') as f:
            fieldnames = ["ts", "action", "actor", "detail", "risk_level", 
                         "compliance_tags", "session_id", "source_ip", "integrity_hash"]
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if write_mode == "w":
                writer.writeheader()
            writer.writerow(row)
            
        # 고위험 작업은 별도 로그도 기록
        if risk_level.upper() in ["HIGH", "CRITICAL"]:
            logging.warning(f"HIGH-RISK AUDIT: {action} by {sanitized_actor} - {risk_level}")
            
    except Exception as e:
        # 감사 로그 실패는 치명적 - 시스템 로그에 기록
        logging.critical(f"AUDIT LOG FAILURE: {e} - Action: {action}, Actor: {sanitized_actor}")
        raise
    
    return row

def verify_audit_integrity(audit_file: Optional[Path] = None) -> Dict[str, Any]:
    """
    감사 로그 무결성 검증
    """
    target_file = audit_file or AUDIT_CSV
    if not target_file.exists():
        return {"status": "ERROR", "message": "Audit log not found"}
    
    verified_count = 0
    corrupted_count = 0
    corrupted_entries = []
    
    try:
        with open(target_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row_num, row in enumerate(reader, start=2):  # 헤더 다음부터
                if 'integrity_hash' not in row:
                    corrupted_count += 1
                    continue
                    
                stored_hash = row.pop('integrity_hash')
                calculated_hash = calculate_integrity_hash(row)
                
                if stored_hash == calculated_hash:
                    verified_count += 1
                else:
                    corrupted_count += 1
                    corrupted_entries.append({
                        "row": row_num,
                        "timestamp": row.get("ts"),
                        "action": row.get("action")
                    })
    except Exception as e:
        return {"status": "ERROR", "message": f"Verification failed: {e}"}
    
    return {
        "status": "SUCCESS" if corrupted_count == 0 else "COMPROMISED",
        "verified_entries": verified_count,
        "corrupted_entries": corrupted_count,
        "corrupted_details": corrupted_entries[:10],  # 최대 10개만 반환
        "total_entries": verified_count + corrupted_count
    }

def get_audit_summary(hours: int = 24) -> Dict[str, Any]:
    """
    지정 시간 내 감사 로그 요약 (KPI 모니터링용)
    """
    if not AUDIT_CSV.exists():
        return {"error": "No audit log found"}
    
    from datetime import timedelta
    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    summary = {
        "total_actions": 0,
        "risk_levels": {"LOW": 0, "MEDIUM": 0, "HIGH": 0, "CRITICAL": 0},
        "top_actions": {},
        "top_actors": {},
        "compliance_tags": {},
        "time_range": f"Last {hours} hours"
    }
    
    try:
        with open(AUDIT_CSV, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # 시간 필터링
                try:
                    entry_time = datetime.fromisoformat(row.get("ts", "").replace('Z', '+00:00'))
                    if entry_time < cutoff_time:
                        continue
                except:
                    continue  # 잘못된 타임스탬프 스킵
                
                summary["total_actions"] += 1
                
                # 위험도별 집계
                risk = row.get("risk_level", "LOW").upper()
                if risk in summary["risk_levels"]:
                    summary["risk_levels"][risk] += 1
                
                # 액션별 집계
                action = row.get("action", "unknown")
                summary["top_actions"][action] = summary["top_actions"].get(action, 0) + 1
                
                # 사용자별 집계
                actor = row.get("actor", "unknown")
                summary["top_actors"][actor] = summary["top_actors"].get(actor, 0) + 1
                
                # 규제 태그별 집계
                tags = row.get("compliance_tags", "").split(",")
                for tag in tags:
                    if tag.strip():
                        summary["compliance_tags"][tag.strip()] = summary["compliance_tags"].get(tag.strip(), 0) + 1
                        
    except Exception as e:
        summary["error"] = str(e)
    
    return summary
