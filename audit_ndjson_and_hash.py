# audit_ndjson_and_hash.py
"""
HVDC Audit NDJSON + SHA-256 Hash Management
NIST SP800-92 and OWASP logging compliant audit trail system
"""

import json
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import argparse
from typing import Dict, Any, List

AUDIT_PATH = Path("artifacts/audit.ndjson")
HASH_META = Path("artifacts/audit.ndjson.hash.json")

def append_event(event: Dict[str, Any], path: Path = AUDIT_PATH) -> bool:
    """
    Append audit event to NDJSON file (atomic operation)
    
    Args:
        event: Audit event dictionary
        path: Target NDJSON file path
        
    Returns:
        bool: Success status
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        
        # Ensure required fields
        if "ts" not in event:
            event["ts"] = datetime.now(timezone.utc).isoformat()
        if "hash" not in event:
            event["hash"] = None  # Will be calculated later for file integrity
        
        # Sanitize sensitive data (basic PII patterns)
        event = sanitize_event(event)
        
        event_line = json.dumps(event, ensure_ascii=False, separators=(',', ':'))
        
        # Atomic append operation
        with path.open("a", encoding="utf-8") as f:
            f.write(event_line + "\n")
            f.flush()  # Ensure immediate write
        
        return True
    except Exception as e:
        print(f"Error appending event: {e}")
        return False

def sanitize_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Sanitize sensitive information in audit events
    Following OWASP logging guidelines
    """
    import re
    
    sensitive_patterns = {
        r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b': '[CARD_REDACTED]',  # Credit cards
        r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b': '[EMAIL_REDACTED]',  # Emails
        r'\bpassword\s*[:=]\s*\S+\b': 'password=[REDACTED]',  # Passwords
        r'\bapi[_-]?key\s*[:=]\s*\S+\b': 'api_key=[REDACTED]',  # API keys
    }
    
    def sanitize_string(text: str) -> str:
        for pattern, replacement in sensitive_patterns.items():
            text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
        return text
    
    def sanitize_recursive(obj):
        if isinstance(obj, dict):
            return {k: sanitize_recursive(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [sanitize_recursive(item) for item in obj]
        elif isinstance(obj, str):
            return sanitize_string(obj)
        return obj
    
    return sanitize_recursive(event)

def sha256_of_file(path: Path) -> str:
    """Calculate SHA-256 hash of file"""
    h = hashlib.sha256()
    try:
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception as e:
        print(f"Error calculating hash: {e}")
        return ""

def write_hash_meta(path: Path = AUDIT_PATH, meta_out: Path = HASH_META) -> Dict[str, Any]:
    """
    Calculate and write hash metadata for audit file
    
    Returns:
        Dict containing hash metadata
    """
    if not path.exists():
        return {"error": "Audit file does not exist"}
    
    try:
        digest = sha256_of_file(path)
        file_size = path.stat().st_size
        line_count = sum(1 for _ in path.open('r', encoding='utf-8'))
        
        meta = {
            "artifact": str(path),
            "digest": digest,
            "method": "sha256",
            "ts": datetime.now(timezone.utc).isoformat(),
            "file_size_bytes": file_size,
            "line_count": line_count,
            "integrity_version": "1.0"
        }
        
        meta_out.parent.mkdir(parents=True, exist_ok=True)
        with meta_out.open("w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        
        return meta
    except Exception as e:
        return {"error": f"Failed to write hash meta: {e}"}

def verify_hash(path: Path = AUDIT_PATH, meta_path: Path = HASH_META) -> Dict[str, Any]:
    """
    Verify audit file integrity against stored hash
    
    Returns:
        Dict containing verification results
    """
    if not path.exists():
        return {"status": "ERROR", "message": "Audit file not found"}
    
    if not meta_path.exists():
        return {"status": "ERROR", "message": "Hash metadata not found"}
    
    try:
        with meta_path.open("r", encoding="utf-8") as f:
            meta = json.load(f)
        
        expected_hash = meta.get("digest")
        if not expected_hash:
            return {"status": "ERROR", "message": "No hash in metadata"}
        
        current_hash = sha256_of_file(path)
        if not current_hash:
            return {"status": "ERROR", "message": "Failed to calculate current hash"}
        
        is_valid = (expected_hash == current_hash)
        
        result = {
            "status": "SUCCESS" if is_valid else "COMPROMISED",
            "expected_hash": expected_hash,
            "current_hash": current_hash,
            "file_size": path.stat().st_size,
            "meta_timestamp": meta.get("ts"),
            "verification_timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        if not is_valid:
            result["message"] = "File integrity compromised - hash mismatch"
        
        return result
    except Exception as e:
        return {"status": "ERROR", "message": f"Verification failed: {e}"}

def get_audit_stats(path: Path = AUDIT_PATH) -> Dict[str, Any]:
    """Get statistics about audit log file"""
    if not path.exists():
        return {"error": "Audit file not found"}
    
    try:
        stats = {
            "file_size_bytes": path.stat().st_size,
            "file_size_mb": round(path.stat().st_size / 1024 / 1024, 2),
            "last_modified": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).isoformat(),
            "line_count": 0,
            "event_types": {},
            "risk_levels": {},
            "actors": {},
            "time_range": {"earliest": None, "latest": None}
        }
        
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    stats["line_count"] += 1
                    try:
                        event = json.loads(line)
                        
                        # Count event types
                        action = event.get("action", "unknown")
                        stats["event_types"][action] = stats["event_types"].get(action, 0) + 1
                        
                        # Count risk levels
                        severity = event.get("severity", "unknown")
                        stats["risk_levels"][severity] = stats["risk_levels"].get(severity, 0) + 1
                        
                        # Count actors
                        actor = event.get("actor", "unknown")
                        stats["actors"][actor] = stats["actors"].get(actor, 0) + 1
                        
                        # Track time range
                        ts = event.get("ts")
                        if ts:
                            if not stats["time_range"]["earliest"] or ts < stats["time_range"]["earliest"]:
                                stats["time_range"]["earliest"] = ts
                            if not stats["time_range"]["latest"] or ts > stats["time_range"]["latest"]:
                                stats["time_range"]["latest"] = ts
                    except json.JSONDecodeError:
                        continue  # Skip malformed lines
        
        return stats
    except Exception as e:
        return {"error": f"Failed to get stats: {e}"}

def rotate_audit_log(path: Path = AUDIT_PATH, max_size_mb: int = 100) -> bool:
    """
    Rotate audit log if it exceeds size limit
    Creates backup with timestamp and starts new log
    """
    if not path.exists():
        return True
    
    size_mb = path.stat().st_size / 1024 / 1024
    if size_mb < max_size_mb:
        return True
    
    try:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        backup_path = path.with_suffix(f".{timestamp}.ndjson")
        
        # Create final hash for rotated file
        hash_backup_path = backup_path.with_suffix(".hash.json")
        meta = write_hash_meta(path, hash_backup_path)
        
        # Move current file to backup
        path.rename(backup_path)
        
        print(f"Rotated audit log: {backup_path} ({size_mb:.1f}MB)")
        return True
    except Exception as e:
        print(f"Failed to rotate audit log: {e}")
        return False

# CLI interface
def main():
    parser = argparse.ArgumentParser(description="HVDC Audit NDJSON Management")
    parser.add_argument("--append", type=str, help="JSON string to append as event")
    parser.add_argument("--write-hash", action="store_true", help="Calculate and write hash metadata")
    parser.add_argument("--verify", action="store_true", help="Verify file integrity")
    parser.add_argument("--stats", action="store_true", help="Show audit log statistics")
    parser.add_argument("--rotate", action="store_true", help="Rotate log if needed")
    parser.add_argument("--max-size", type=int, default=100, help="Max size in MB for rotation")
    
    args = parser.parse_args()
    
    if args.append:
        try:
            event = json.loads(args.append)
            success = append_event(event)
            if success:
                print("✅ Event appended successfully")
            else:
                print("❌ Failed to append event")
                return 1
        except json.JSONDecodeError as e:
            print(f"❌ Invalid JSON: {e}")
            return 1
    
    if args.write_hash:
        meta = write_hash_meta()
        if "error" in meta:
            print(f"❌ {meta['error']}")
            return 1
        else:
            print("✅ Hash metadata written:")
            print(f"   File: {meta['artifact']}")
            print(f"   Hash: {meta['digest'][:16]}...")
            print(f"   Size: {meta['file_size_bytes']} bytes")
            print(f"   Lines: {meta['line_count']}")
    
    if args.verify:
        result = verify_hash()
        if result["status"] == "SUCCESS":
            print("✅ File integrity verified - no tampering detected")
        elif result["status"] == "COMPROMISED":
            print("🔴 File integrity COMPROMISED - hash mismatch detected!")
            print(f"   Expected: {result['expected_hash'][:16]}...")
            print(f"   Current:  {result['current_hash'][:16]}...")
            return 2
        else:
            print(f"❌ Verification error: {result['message']}")
            return 1
    
    if args.stats:
        stats = get_audit_stats()
        if "error" in stats:
            print(f"❌ {stats['error']}")
            return 1
        else:
            print("📊 Audit Log Statistics:")
            print(f"   File size: {stats['file_size_mb']} MB ({stats['file_size_bytes']} bytes)")
            print(f"   Total events: {stats['line_count']}")
            print(f"   Time range: {stats['time_range']['earliest']} to {stats['time_range']['latest']}")
            print(f"   Event types: {dict(list(stats['event_types'].items())[:5])}")
            print(f"   Risk levels: {stats['risk_levels']}")
            print(f"   Top actors: {dict(list(stats['actors'].items())[:5])}")
    
    if args.rotate:
        success = rotate_audit_log(max_size_mb=args.max_size)
        if success:
            print("✅ Log rotation completed (if needed)")
        else:
            print("❌ Log rotation failed")
            return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
