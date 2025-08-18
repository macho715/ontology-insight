#!/usr/bin/env python3
"""
HVDC Gateway Mock Server
실제 Gateway API를 시뮬레이션하는 Mock 서버
"""

from flask import Flask, request, jsonify
from datetime import datetime, timezone, timedelta
import json
import logging
import random

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Mock 데이터
SAMPLE_SITES = ["MIR", "SHU", "DAS", "AGI"]
SAMPLE_PARTS = [
    "HVDC-TR-001", "HVDC-CB-002", "HVDC-SW-003", 
    "HVDC-CT-004", "HVDC-RC-005", "HVDC-IF-006"
]

@app.route('/v1/health', methods=['GET'])
def health_check():
    """헬스체크 엔드포인트"""
    return jsonify({
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat()
    })

@app.route('/v1/mrr/draft', methods=['POST'])
def create_mrr_draft():
    """MRR 드래프트 생성"""
    data = request.json
    
    # 입력 검증
    if not data or not data.get('po_no') or not data.get('site'):
        return jsonify({"error": "Missing required fields"}), 400
    
    # Mock 응답 생성
    confidence = round(random.uniform(0.85, 0.98), 2)
    warnings = []
    
    if confidence < 0.90:
        warnings.append("Low OCR confidence detected")
    
    response = {
        "po_no": data['po_no'],
        "site": data['site'],
        "items": data.get('items', []),
        "confidence": confidence,
        "warnings": warnings
    }
    
    logger.info(f"✅ MRR draft created for PO {data['po_no']}, confidence: {confidence}")
    return jsonify(response)

@app.route('/v1/predict/eta', methods=['POST'])
def predict_eta():
    """ETA 예측"""
    data = request.json
    
    # 입력 검증
    if not data or not data.get('origin') or not data.get('destination'):
        return jsonify({"error": "Missing required fields"}), 400
    
    # Mock ETA 계산
    mode = data.get('mode', 'ROAD')
    base_hours = {
        'SEA': random.uniform(120, 200),  # 5-8일
        'ROAD': random.uniform(24, 72),   # 1-3일
        'RORO': random.uniform(48, 120)   # 2-5일
    }
    
    transit_hours = round(base_hours.get(mode, 48), 1)
    eta_utc = datetime.now(timezone.utc) + timedelta(hours=transit_hours)
    
    # 위험도 결정
    if transit_hours > 100:
        risk_level = "HIGH"
        notes = "Extended transit time due to weather conditions"
    elif transit_hours > 50:
        risk_level = "MEDIUM"
        notes = "Moderate delays expected"
    else:
        risk_level = "LOW"
        notes = "Normal transit conditions"
    
    response = {
        "eta_utc": eta_utc.isoformat(),
        "transit_hours": transit_hours,
        "risk_level": risk_level,
        "notes": notes
    }
    
    logger.info(f"✅ ETA predicted: {eta_utc.strftime('%Y-%m-%d %H:%M')} ({transit_hours}h, {risk_level})")
    return jsonify(response)

@app.route('/v1/costguard/estimate', methods=['POST'])
def estimate_cost():
    """비용 추정"""
    data = request.json
    
    # 입력 검증
    required_fields = ['input_tokens', 'output_tokens', 'input_cost_per_1k', 'output_cost_per_1k']
    if not data or not all(field in data for field in required_fields):
        return jsonify({"error": "Missing required fields"}), 400
    
    # 비용 계산
    input_cost = (data['input_tokens'] / 1000) * data['input_cost_per_1k']
    output_cost = (data['output_tokens'] / 1000) * data['output_cost_per_1k']
    total_cost = round(input_cost + output_cost, 6)
    
    # 밴드 결정
    thresholds = {
        "pass": 0.02,
        "warn": 0.05, 
        "high": 0.10
    }
    
    if total_cost <= thresholds["pass"]:
        band = "PASS"
    elif total_cost <= thresholds["warn"]:
        band = "WARN"
    elif total_cost <= thresholds["high"]:
        band = "HIGH"
    else:
        band = "CRITICAL"
    
    response = {
        "estimated_cost": total_cost,
        "band": band,
        "thresholds": thresholds
    }
    
    logger.info(f"✅ Cost estimated: ${total_cost:.6f} ({band})")
    return jsonify(response)

@app.route('/v1/admin/status', methods=['GET'])
def admin_status():
    """관리자 상태 확인"""
    return jsonify({
        "server": "HVDC Gateway Mock Server",
        "version": "1.0.2",
        "status": "active",
        "endpoints": [
            "/v1/health",
            "/v1/mrr/draft", 
            "/v1/predict/eta",
            "/v1/costguard/estimate"
        ],
        "timestamp": datetime.now(timezone.utc).isoformat()
    })

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

def main():
    print("🚀 HVDC Gateway Mock Server Starting...")
    print("📍 Available endpoints:")
    print("   GET  /v1/health - Health check")
    print("   POST /v1/mrr/draft - Create MRR draft")
    print("   POST /v1/predict/eta - Predict ETA")
    print("   POST /v1/costguard/estimate - Estimate cost")
    print("   GET  /v1/admin/status - Server status")
    print()
    print("🔗 Server will be available at: http://localhost:8080")
    print("💡 Use this URL in your Gateway client configuration")
    print()
    
    app.run(host='localhost', port=8080, debug=False)

if __name__ == "__main__":
    main()

