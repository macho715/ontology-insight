#!/usr/bin/env python3
"""
OpenAPI 스키마 servers.url 업데이트 도구
ngrok URL로 자동 업데이트
"""

import json
import yaml
import sys
import requests
from datetime import datetime

def get_current_ngrok_url():
    """현재 실행 중인 ngrok 터널 URL 가져오기"""
    try:
        # ngrok 로컬 API에서 터널 정보 가져오기
        response = requests.get("http://127.0.0.1:4040/api/tunnels", timeout=5)
        if response.status_code == 200:
            tunnels = response.json()["tunnels"]
            for tunnel in tunnels:
                if tunnel["proto"] == "https" and "8080" in tunnel["config"]["addr"]:
                    return tunnel["public_url"]
        return None
    except Exception as e:
        print(f"❌ ngrok API 접근 실패: {e}")
        return None

def update_openapi_schema(ngrok_url, output_file="hvdc_gateway_openapi_public.yaml"):
    """OpenAPI 스키마의 servers.url을 ngrok URL로 업데이트"""
    
    # 원본 스키마 (사용자가 제공한 것)
    original_schema = {
        "openapi": "3.1.0",
        "jsonSchemaDialect": "https://json-schema.org/draft/2020-12/schema",
        "info": {
            "title": "HVDC GPT Gateway",
            "version": "1.0.2",
            "description": "Actions-friendly OpenAPI 3.1 schema for HVDC Ontology Insight Gateway.\nEndpoints: health check, MRR draft generation, ETA prediction, and LLM cost estimation."
        },
        "servers": [
            {
                "url": f"{ngrok_url}/v1",
                "description": "Public ngrok tunnel (updated automatically)"
            }
        ],
        "components": {
            "securitySchemes": {
                "ApiKeyAuth": {
                    "type": "apiKey",
                    "in": "header",
                    "name": "X-API-Key"
                }
            },
            "schemas": {
                "MRRItem": {
                    "type": "object",
                    "required": ["part_no", "qty", "status"],
                    "properties": {
                        "part_no": {"type": "string", "description": "Part number"},
                        "qty": {"type": "number", "minimum": 0},
                        "uom": {"type": "string", "enum": ["EA", "BOX", "PAL"]},
                        "status": {"type": "string", "enum": ["OK", "OSD"]},
                        "remarks": {"type": "string"}
                    }
                },
                "MRRDraftRequest": {
                    "type": "object",
                    "required": ["po_no", "site", "items"],
                    "properties": {
                        "po_no": {"type": "string", "description": "Purchase Order number"},
                        "site": {"type": "string", "enum": ["MIR", "SHU", "DAS", "AGI"]},
                        "packing_list_text": {"type": "string", "description": "Raw OCR text from Packing List"},
                        "items": {
                            "type": "array",
                            "items": {"$ref": "#/components/schemas/MRRItem"}
                        }
                    }
                },
                "MRRDraftResponse": {
                    "type": "object",
                    "required": ["po_no", "site", "items", "confidence"],
                    "properties": {
                        "po_no": {"type": "string"},
                        "site": {"type": "string"},
                        "items": {
                            "type": "array",
                            "items": {"$ref": "#/components/schemas/MRRItem"}
                        },
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                        "warnings": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    }
                },
                "EtaRequest": {
                    "type": "object",
                    "required": ["origin", "destination", "mode"],
                    "properties": {
                        "origin": {"type": "string", "example": "Khalifa Port"},
                        "destination": {"type": "string", "example": "MIR substation"},
                        "mode": {"type": "string", "enum": ["SEA", "ROAD", "RORO"]},
                        "departure_utc": {"type": "string", "format": "date-time"}
                    }
                },
                "EtaResponse": {
                    "type": "object",
                    "required": ["eta_utc", "transit_hours"],
                    "properties": {
                        "eta_utc": {"type": "string", "format": "date-time"},
                        "transit_hours": {"type": "number", "minimum": 0},
                        "risk_level": {"type": "string", "enum": ["LOW", "MEDIUM", "HIGH"]},
                        "notes": {"type": "string"}
                    }
                },
                "CostGuardEstimateRequest": {
                    "type": "object",
                    "required": ["input_tokens", "output_tokens", "input_cost_per_1k", "output_cost_per_1k"],
                    "properties": {
                        "input_tokens": {"type": "integer", "minimum": 0},
                        "output_tokens": {"type": "integer", "minimum": 0},
                        "input_cost_per_1k": {"type": "number", "minimum": 0},
                        "output_cost_per_1k": {"type": "number", "minimum": 0}
                    }
                },
                "CostGuardEstimateResponse": {
                    "type": "object",
                    "required": ["estimated_cost", "band"],
                    "properties": {
                        "estimated_cost": {"type": "number", "description": "Estimated total cost in account currency"},
                        "band": {"type": "string", "enum": ["PASS", "WARN", "HIGH", "CRITICAL"]},
                        "thresholds": {
                            "type": "object",
                            "properties": {
                                "pass": {"type": "number", "default": 0.02},
                                "warn": {"type": "number", "default": 0.05},
                                "high": {"type": "number", "default": 0.10}
                            }
                        }
                    }
                }
            }
        },
        "paths": {
            "/health": {
                "get": {
                    "operationId": "healthCheck",
                    "summary": "Health check",
                    "description": "Returns service status and timestamp.",
                    "responses": {
                        "200": {
                            "description": "OK",
                            "content": {
                                "application/json": {
                                    "schema": {
                                        "type": "object",
                                        "required": ["status", "timestamp"],
                                        "properties": {
                                            "status": {"type": "string", "enum": ["ok"]},
                                            "timestamp": {"type": "string", "format": "date-time"}
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            },
            "/mrr/draft": {
                "post": {
                    "operationId": "createMRRDraft",
                    "summary": "Create an MRR draft from packing list text and structured items",
                    "security": [{"ApiKeyAuth": []}],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {
                                "schema": {"$ref": "#/components/schemas/MRRDraftRequest"}
                            }
                        }
                    },
                    "responses": {
                        "200": {
                            "description": "Draft created",
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/MRRDraftResponse"}
                                }
                            }
                        }
                    }
                }
            },
            "/predict/eta": {
                "post": {
                    "operationId": "predictETA",
                    "summary": "Predict ETA and risk level for a consignment",
                    "security": [{"ApiKeyAuth": []}],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {
                                "schema": {"$ref": "#/components/schemas/EtaRequest"}
                            }
                        }
                    },
                    "responses": {
                        "200": {
                            "description": "ETA prediction",
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/EtaResponse"}
                                }
                            }
                        }
                    }
                }
            },
            "/costguard/estimate": {
                "post": {
                    "operationId": "estimateCostGuard",
                    "summary": "Estimate LLM cost and classify by CostGuard thresholds",
                    "security": [{"ApiKeyAuth": []}],
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {
                                "schema": {"$ref": "#/components/schemas/CostGuardEstimateRequest"}
                            }
                        }
                    },
                    "responses": {
                        "200": {
                            "description": "Cost estimate and band",
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/CostGuardEstimateResponse"}
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    # 메타데이터 추가
    original_schema["info"]["x-updated"] = datetime.now().isoformat()
    original_schema["info"]["x-ngrok-url"] = ngrok_url
    
    # YAML 파일로 저장
    with open(output_file, 'w', encoding='utf-8') as f:
        yaml.dump(original_schema, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    print(f"✅ OpenAPI 스키마 업데이트 완료: {output_file}")
    print(f"🔗 Public URL: {ngrok_url}")
    return output_file

def test_public_endpoint(ngrok_url):
    """공개 엔드포인트 테스트"""
    health_url = f"{ngrok_url}/v1/health"
    
    print(f"🧪 공개 엔드포인트 테스트: {health_url}")
    
    try:
        response = requests.get(health_url, timeout=10)
        if response.status_code == 200:
            result = response.json()
            print(f"✅ 헬스체크 성공: {result}")
            return True
        else:
            print(f"❌ 헬스체크 실패: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ 연결 실패: {e}")
        return False

def main():
    print("🌐 HVDC Gateway OpenAPI 스키마 업데이트 도구")
    print("=" * 50)
    
    # ngrok URL 자동 감지
    ngrok_url = get_current_ngrok_url()
    
    if not ngrok_url:
        print("❌ 실행 중인 ngrok 터널을 찾을 수 없습니다.")
        print("💡 다음 명령어로 ngrok을 먼저 실행하세요:")
        print("   ngrok http 8080")
        return False
    
    print(f"🔗 감지된 ngrok URL: {ngrok_url}")
    
    # OpenAPI 스키마 업데이트
    schema_file = update_openapi_schema(ngrok_url)
    
    # 공개 엔드포인트 테스트
    if test_public_endpoint(ngrok_url):
        print("\n🎉 설정 완료!")
        print(f"📋 다음 단계:")
        print(f"1. GPTs Builder에서 Actions 설정")
        print(f"2. 스키마 파일 내용을 복사: {schema_file}")
        print(f"3. API Key 인증 설정: X-API-Key")
        print(f"4. 테스트 실행: healthCheck 작업")
        return True
    else:
        print("\n❌ 설정 실패. ngrok 터널 상태를 확인하세요.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
