# hvdc_api.py
from flask import Flask, request, jsonify
from hvdc_one_line import hvdc_one_line  # 기존 패치된 함수 사용
# 자동 HVDCIntegrationEngine import (프로젝트 구조 적응형)
HVDCIntegrationEngine = None
try:
    # 1차: 언더스코어 버전 시도
    from hvdc_integration_demo import HVDCIntegrationEngine
except ImportError:
    try:
        # 2차: 하이픈 버전 시도 (importlib 사용)
        import importlib.util
        import sys
        spec = importlib.util.spec_from_file_location("hvdc_integration_demo", "hvdc-integration-demo.py")
        if spec and spec.loader:
            hvdc_module = importlib.util.module_from_spec(spec)
            sys.modules["hvdc_integration_demo"] = hvdc_module
            spec.loader.exec_module(hvdc_module)
            HVDCIntegrationEngine = hvdc_module.HVDCIntegrationEngine
    except Exception:
        # 3차: 파일 존재 확인 및 로깅
        import os
        files_found = []
        for fname in ["hvdc_integration_demo.py", "hvdc-integration-demo.py"]:
            if os.path.exists(fname):
                files_found.append(fname)
        if files_found:
            logging.warning(f"HVDCIntegrationEngine import failed but files found: {files_found}")
        else:
            logging.info("HVDCIntegrationEngine not available - running in standalone mode")
        HVDCIntegrationEngine = None

from hvdc_rules import run_all_rules
from audit_logger import write_audit
from audit_ndjson_and_hash import append_event, write_hash_meta
from fuseki_swap_verify import FusekiSwapManager
import pandas as pd
import os
import json
import logging
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)

app = Flask(__name__)

# Attempt to instantiate engine if available
engine = None
if HVDCIntegrationEngine:
    try:
        engine = HVDCIntegrationEngine()
    except Exception as e:
        logging.warning("HVDCIntegrationEngine instantiation failed: %s", e)
        engine = None

# Simple in-memory std_rate_table for demo (실무: DB/CSV/서비스 연동)
STD_RATE_TABLE = {
    "HVDC-ADOPT-SCT-0001": 1000.00,
    "HVDC-ADOPT-SCT-0002": 750.00
}
HS_PREFIXES = ["85","73","84"]
REQUIRED_CERTS = ["MOIAT","FANR"]

@app.route("/health")
def health():
    ok = True
    if engine and hasattr(engine, "check_fuseki_health"):
        try:
            ok = engine.check_fuseki_health()
        except Exception:
            ok = False
    return jsonify({"ok": ok})

@app.route("/ingest", methods=["POST"])
def ingest():
    """
    Payload:
    - files: multipart upload OR {"path": "/mnt/data/uploaded.xlsx"} in JSON
    - actor: username (optional)
    - min_conf: optional
    """
    actor = request.json.get("actor") if request.is_json else request.form.get("actor","system")
    min_conf = float(request.json.get("min_conf",0.6)) if request.is_json else float(request.form.get("min_conf",0.6))
    trace_log = f"artifacts/extraction_trace_{int(pd.Timestamp.now().timestamp())}.csv"
    # accept path or file
    if request.is_json and request.json.get("path"):
        path = request.json.get("path")
        df = hvdc_one_line(path)
    else:
        # check file upload
        if 'file' not in request.files:
            return jsonify({"error":"No file provided"}), 400
        f = request.files['file']
        saved = os.path.join("uploads", f.filename)
        os.makedirs("uploads", exist_ok=True)
        f.save(saved)
        df = hvdc_one_line(saved)

    # Enhanced audit logging with NDJSON + hash integrity
    risk_level = "MEDIUM" if len(df) > 100 else "LOW"  # 대량 데이터는 중위험
    
    # Traditional audit log
    write_audit("ingest", actor, {"rows": len(df), "trace_log": trace_log}, 
                risk_level=risk_level, compliance_tags=["HVDC", "DATA_PROCESSING"])
    
    # NDJSON audit event with NIST compliance
    ndjson_event = {
        "action": "ingest",
        "actor": actor,
        "case_id": f"INGEST_{int(pd.Timestamp.now().timestamp())}",
        "detail": {
            "rows": len(df),
            "trace_log": trace_log,
            "file_source": request.json.get("path") if request.is_json else "upload",
            "extraction_method": "hvdc_one_line"
        },
        "severity": "INFO" if risk_level == "LOW" else "WARN",
        "tags": ["ingest", "automated", "hvdc"],
        "risk_level": risk_level
    }
    
    # Append to NDJSON audit log
    append_success = append_event(ndjson_event)
    if append_success:
        # Update hash metadata for integrity
        write_hash_meta()
        logging.info("✅ NDJSON audit event recorded with hash integrity")

    # Enhanced Fuseki staging deployment with validation
    try:
        if engine and hasattr(engine, "build_ttl_from_df"):
            # Generate TTL from extracted data
            ttl_content = engine.build_ttl_from_df(df)
            
            # Use FusekiSwapManager for safe deployment
            fuseki_manager = FusekiSwapManager()
            target_graph = "http://samsung.com/graph/EXTRACTED"
            
            logging.info("🚀 Starting safe Fuseki deployment...")
            deployment_result = fuseki_manager.deploy_with_validation(ttl_content, target_graph)
            
            # Enhanced audit logging for deployment
            deployment_event = {
                "action": "fuseki_deployment",
                "actor": actor,
                "case_id": ndjson_event["case_id"],
                "detail": {
                    "target_graph": target_graph,
                    "deployment_status": deployment_result["status"],
                    "steps_completed": list(deployment_result["steps"].keys()),
                    "triple_count": deployment_result.get("steps", {}).get("staging_upload", {}).get("triple_count", 0)
                },
                "severity": "INFO" if deployment_result["status"] == "SUCCESS" else "ERROR",
                "tags": ["fuseki", "deployment", "staging"],
                "risk_level": "HIGH"
            }
            
            append_event(deployment_event)
            write_hash_meta()
            
            # Traditional audit log
            write_audit("ingest_upload", actor, {
                "deployment_status": deployment_result["status"],
                "target_graph": target_graph,
                "validation_passed": deployment_result.get("steps", {}).get("validation", {}).get("overall_status") == "PASS"
            }, risk_level="HIGH", compliance_tags=["HVDC", "FUSEKI_UPLOAD"])
            
            if deployment_result["status"] == "SUCCESS":
                logging.info("✅ Safe Fuseki deployment completed successfully")
            else:
                logging.error(f"❌ Fuseki deployment failed: {deployment_result}")
                
    except Exception as e:
        logging.warning("Enhanced staging upload failed: %s", e)
        
        # Log deployment failure
        failure_event = {
            "action": "fuseki_deployment_error",
            "actor": actor,
            "case_id": ndjson_event["case_id"],
            "detail": {"error": str(e)},
            "severity": "ERROR",
            "tags": ["fuseki", "deployment", "error"],
            "risk_level": "CRITICAL"
        }
        append_event(failure_event)
        write_hash_meta()

    # Return small summary + link to trace log path
    return jsonify({"rows": len(df), "trace_log": trace_log})

@app.route("/evidence/<case_id>", methods=["GET"])
def evidence(case_id):
    """
    Return extraction traces for a logical source (case_id), plus optional SPARQL triple summary
    """
    # Read latest extraction traces (simple CSV scan)
    traces = []
    if os.path.isdir("artifacts"):
        for p in sorted([p for p in os.listdir("artifacts") if p.startswith("extraction_trace")]): 
            df = pd.read_csv(os.path.join("artifacts", p), dtype=str, keep_default_na=False)
            df_sel = df[df.get("LOGICAL_SOURCE")==case_id] if "LOGICAL_SOURCE" in df.columns else df[df.get("LOGICAL_SOURCE")==case_id]
            if not df_sel.empty:
                traces.append({"file": p, "rows": df_sel.to_dict(orient="records")})
    # Try SPARQL summary (if engine supports)
    triples = None
    if engine and hasattr(engine, 'query_fuseki'):
        try:
            sparql = f"""
            SELECT ?s ?p ?o WHERE {{ GRAPH ?g {{ ?s ?p ?o . FILTER(CONTAINS(STR(?s), \"{case_id}\")) }} }} LIMIT 500
            """
            triples = engine.query_fuseki(sparql)
        except Exception as e:
            triples = {"error": str(e)}

    return jsonify({"case_id": case_id, "traces": traces, "triples": triples})

@app.route("/run-rules", methods=["POST"])
def run_rules():
    """
    POST payload:
      {"case_ids": ["SAMPLE1","SAMPLE2"], "actor": "user1"}
    or {"trace_log": "artifacts/extraction_trace_...csv"} to run on specific trace file.
    """
    payload = request.json or {}
    actor = payload.get("actor","system")
    case_ids = payload.get("case_ids", [])
    trace_log = payload.get("trace_log", None)

    # build df from traces if trace_log given
    df_all = pd.DataFrame()
    if trace_log:
        df_all = pd.read_csv(trace_log, dtype=str, keep_default_na=False)
    else:
        # gather traces for given case_ids
        rows = []
        if os.path.isdir("artifacts"):
            for fname in os.listdir("artifacts"):
                if fname.startswith("extraction_trace"):
                    tmp = pd.read_csv(os.path.join("artifacts", fname), dtype=str, keep_default_na=False)
                    tmp_sel = tmp[tmp["LOGICAL_SOURCE"].isin(case_ids)] if case_ids and "LOGICAL_SOURCE" in tmp.columns else tmp
                    if not tmp_sel.empty:
                        rows.append(tmp_sel)
        if rows:
            df_all = pd.concat(rows, ignore_index=True)

    if df_all.empty:
        return jsonify({"error":"no data found to run rules"}), 400

    # run rules
    rules_result = run_all_rules(df_all, std_rate_table=STD_RATE_TABLE, hs_prefixes=HS_PREFIXES, required_certs=REQUIRED_CERTS)
    # 룰 실행 결과에 따른 위험도 결정
    summary = rules_result.get("summary", {})
    critical_count = summary.get("cost_count", 0) + summary.get("hs_count", 0) + summary.get("cert_count", 0)
    risk_level = "CRITICAL" if critical_count > 5 else "HIGH" if critical_count > 0 else "LOW"
    
    write_audit("run_rules", actor, {"cases": case_ids, "summary": summary}, 
                risk_level=risk_level, compliance_tags=["HVDC", "BUSINESS_RULES", "FANR", "MOIAT"])
    return jsonify(rules_result)

@app.route("/nlq", methods=["POST"])
def nlq():
    """
    Very small NLQ -> SPARQL POC
    payload: {"q":"Show invoices where BOE != CIPL for SHPT NO 0049"}
    """
    q = (request.json or {}).get("q","")
    q_low = q.lower()
    if "boe" in q_low and "cipl" in q_low:
        sparql = """
        PREFIX ex: <http://samsung.com/project-logistics#>
        SELECT ?invoice ?cipl ?boe WHERE {
          GRAPH ?g {
            ?invoice ex:invoiceNumber ?invNo .
            ?cipl ex:relatedInvoice ?invoice .
            OPTIONAL { ?boe ex:relatedInvoice ?invoice . }
            FILTER (!BOUND(?boe) || ?boe != ?cipl)
          }
        } LIMIT 200
        """
        if engine and hasattr(engine, 'query_fuseki'):
            res = engine.query_fuseki(sparql)
            return jsonify(res)
        else:
            return jsonify({"error":"SPARQL engine not available"}), 500
    return jsonify({"error":"unsupported NLQ"}), 400

@app.route("/audit/summary", methods=["GET"])
def audit_summary():
    """
    감사 로그 요약 정보 조회
    Query params: hours (기본 24시간)
    """
    from audit_logger import get_audit_summary
    
    hours = int(request.args.get("hours", 24))
    summary = get_audit_summary(hours)
    return jsonify(summary)

@app.route("/audit/verify", methods=["POST"])
def audit_verify():
    """
    감사 로그 무결성 검증
    """
    from audit_logger import verify_audit_integrity
    
    actor = request.json.get("actor", "system") if request.is_json else "system"
    verification_result = verify_audit_integrity()
    
    # 검증 작업도 감사 로그에 기록
    write_audit("audit_verify", actor, verification_result, 
                risk_level="HIGH", compliance_tags=["AUDIT", "SECURITY"])
    
    return jsonify(verification_result)

@app.route("/fuseki/deploy", methods=["POST"])
def fuseki_deploy():
    """
    Safe Fuseki deployment with staging → validation → swap
    """
    try:
        payload = request.json or {}
        actor = payload.get("actor", "system")
        ttl_content = payload.get("ttl_content", "")
        target_graph = payload.get("target_graph", "http://samsung.com/graph/EXTRACTED")
        
        if not ttl_content:
            return jsonify({"error": "ttl_content required"}), 400
        
        # Deploy with validation
        fuseki_manager = FusekiSwapManager()
        result = fuseki_manager.deploy_with_validation(ttl_content, target_graph)
        
        # Audit the deployment request
        write_audit("fuseki_deploy_api", actor, {
            "target_graph": target_graph,
            "status": result["status"],
            "ttl_size_bytes": len(ttl_content.encode('utf-8'))
        }, risk_level="HIGH", compliance_tags=["FUSEKI", "DEPLOYMENT"])
        
        return jsonify(result)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/fuseki/stats", methods=["GET"])
def fuseki_stats():
    """
    Get Fuseki graph statistics
    """
    try:
        fuseki_manager = FusekiSwapManager()
        
        if not fuseki_manager.check_fuseki_health():
            return jsonify({"error": "Fuseki server not available"}), 503
        
        graphs = {
            "staging": fuseki_manager.staging_graph,
            "backup": fuseki_manager.backup_graph,
            **{f"production_{i}": graph for i, graph in enumerate(fuseki_manager.production_graphs)}
        }
        
        stats = {}
        for name, graph_uri in graphs.items():
            count = fuseki_manager.get_triple_count(graph_uri)
            stats[name] = {
                "graph_uri": graph_uri,
                "triple_count": count,
                "status": "OK" if count >= 0 else "ERROR"
            }
        
        return jsonify({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "graphs": stats,
            "total_triples": sum(s["triple_count"] for s in stats.values() if s["triple_count"] > 0)
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/fuseki/validate", methods=["POST"])
def fuseki_validate():
    """
    Validate staging data without deployment
    """
    try:
        fuseki_manager = FusekiSwapManager()
        validation_result = fuseki_manager.validate_staging_data()
        
        actor = request.json.get("actor", "system") if request.is_json else "system"
        write_audit("fuseki_validate", actor, validation_result,
                   risk_level="MEDIUM", compliance_tags=["FUSEKI", "VALIDATION"])
        
        return jsonify(validation_result)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__=="__main__":
    app.run(host="0.0.0.0", port=5002, debug=False)
