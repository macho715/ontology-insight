#!/usr/bin/env python3
"""
HVDC v3.7 Claude Native Integration Test Suite
"""
import requests
import json
import time

def test_bridge_connection():
    """브릿지 연결 테스트"""
    try:
        response = requests.get("http://localhost:5003/claude/status", timeout=5)
        if response.status_code == 200:
            print("✅ Bridge connection: OK")
            return response.json()
        else:
            print(f"❌ Bridge connection failed: {response.status_code}")
            return None
    except Exception as e:
        print(f"❌ Bridge connection error: {str(e)}")
        return None

def test_macho_command():
    """MACHO-GPT 명령어 테스트"""
    try:
        payload = {"command": "status", "parameters": {}}
        response = requests.post("http://localhost:5003/claude/execute", 
                               json=payload, timeout=10)
        if response.status_code == 200:
            print("✅ MACHO command execution: OK")
            return response.json()
        else:
            print(f"❌ MACHO command failed: {response.status_code}")
            return None
    except Exception as e:
        print(f"❌ MACHO command error: {str(e)}")
        return None

def test_logi_master_integration():
    """LogiMaster 통합 테스트"""
    try:
        payload = {
            "command": "logi-master",
            "parameters": {"action": "kpi-dash", "realtime": True}
        }
        response = requests.post("http://localhost:5003/claude/execute",
                               json=payload, timeout=15)
        if response.status_code == 200:
            print("✅ LogiMaster integration: OK")
            return response.json()
        else:
            print(f"❌ LogiMaster integration failed: {response.status_code}")
            return None
    except Exception as e:
        print(f"❌ LogiMaster integration error: {str(e)}")
        return None

if __name__ == "__main__":
    print("🧪 HVDC v3.7 Claude Native Integration Test Suite")
    print("=" * 60)
    
    # 1. 브릿지 연결 테스트
    print("1. Testing Bridge Connection...")
    bridge_status = test_bridge_connection()
    if bridge_status:
        print(f"   Bridge Version: {bridge_status.get('bridge_version', 'unknown')}")
        print(f"   Available Commands: {len(bridge_status.get('available_commands', []))}")
    
    time.sleep(1)
    
    # 2. MACHO 명령어 테스트
    print("\n2. Testing MACHO Command Execution...")
    macho_result = test_macho_command()
    if macho_result:
        print(f"   Command Status: {macho_result.get('status', 'unknown')}")
        claude_integration = macho_result.get('claude_integration', {})
        if claude_integration:
            print(f"   Claude Tools: {len(claude_integration.get('recommended_tools', []))}")
    
    time.sleep(1)
    
    # 3. LogiMaster 통합 테스트
    print("\n3. Testing LogiMaster Integration...")
    logi_result = test_logi_master_integration()
    if logi_result:
        print(f"   Integration Status: {logi_result.get('status', 'unknown')}")
        if 'claude_suggestions' in logi_result.get('result', {}):
            print("   ✅ Claude tool suggestions included")
    
    print("\n" + "=" * 60)
    print("🎯 Integration test completed!")
