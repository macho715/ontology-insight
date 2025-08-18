#!/usr/bin/env python3
"""
HVDC Gateway Configuration & Environment Setup
"""

import os
from typing import Dict, Any
from dataclasses import dataclass

@dataclass
class GatewayConfig:
    """Gateway 설정"""
    base_url: str
    api_key: str
    timeout: int = 30
    max_retries: int = 3
    
    # 로컬 시스템 연동
    local_hvdc_api: str = "http://localhost:5002"
    claude_bridge_api: str = "http://localhost:5003" 
    fuseki_endpoint: str = "http://localhost:3030/hvdc"
    
    # 인증 및 보안
    verify_ssl: bool = True
    user_agent: str = "HVDC-Gateway-Client/1.0.2"
    
    # 로깅
    log_level: str = "INFO"
    log_requests: bool = True
    
    @classmethod
    def from_env(cls) -> 'GatewayConfig':
        """환경변수에서 설정 로드"""
        return cls(
            base_url=os.getenv('HVDC_GATEWAY_URL', 'https://api.hvdc-gateway.example.com/v1'),
            api_key=os.getenv('HVDC_GATEWAY_API_KEY', 'your-api-key-here'),
            timeout=int(os.getenv('HVDC_GATEWAY_TIMEOUT', '30')),
            max_retries=int(os.getenv('HVDC_GATEWAY_RETRIES', '3')),
            verify_ssl=os.getenv('HVDC_GATEWAY_SSL_VERIFY', 'true').lower() == 'true',
            log_level=os.getenv('HVDC_LOG_LEVEL', 'INFO'),
            log_requests=os.getenv('HVDC_LOG_REQUESTS', 'true').lower() == 'true'
        )

# 기본 설정
DEFAULT_CONFIG = GatewayConfig(
    base_url="https://api.hvdc-gateway.example.com/v1",
    api_key="demo-key-for-testing"
)

# 개발 환경 설정
DEV_CONFIG = GatewayConfig(
    base_url="https://dev-api.hvdc-gateway.example.com/v1",
    api_key="dev-api-key",
    verify_ssl=False,
    log_level="DEBUG"
)

# 프로덕션 환경 설정
PROD_CONFIG = GatewayConfig(
    base_url="https://api.hvdc-gateway.example.com/v1",
    api_key=os.getenv('HVDC_PROD_API_KEY', 'REQUIRED'),
    timeout=60,
    max_retries=5,
    log_requests=False
)

def get_config(env: str = "default") -> GatewayConfig:
    """환경별 설정 반환"""
    configs = {
        "default": DEFAULT_CONFIG,
        "dev": DEV_CONFIG,
        "prod": PROD_CONFIG,
        "env": GatewayConfig.from_env()
    }
    return configs.get(env, DEFAULT_CONFIG)

