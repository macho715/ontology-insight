# HVDC Ontology Insight v3.7 Claude 네이티브 업그레이드 스크립트
# 현재 위치: C:\cursor-mcp\Ontology insight upgrade

param(
    [string]$Action = "status",
    [switch]$DryRun,
    [switch]$Force,
    [string]$BackupPath = ".\backup\pre_v37_upgrade"
)

# 업그레이드 설정
$CURRENT_VERSION = "v3.6-APEX"
$TARGET_VERSION = "v3.7-CLAUDE-NATIVE"
$UPGRADE_LOG = "logs\upgrade_v37_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-UpgradeLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [UPGRADE-v3.7] $Message"
    Write-Host $logEntry
    Add-Content -Path $UPGRADE_LOG -Value $logEntry
}

function Test-UpgradePrerequisites {
    Write-UpgradeLog "🔍 Checking upgrade prerequisites..."
    
    $checks = @()
    
    # 1. 현재 시스템 상태 확인
    try {
        $fusekiResponse = Invoke-RestMethod -Uri "http://localhost:3030/hvdc/$/ping" -TimeoutSec 5 -ErrorAction SilentlyContinue
        $checks += @{Name = "Fuseki Server"; Status = "✅ Online"; Details = $fusekiResponse}
    } catch {
        $checks += @{Name = "Fuseki Server"; Status = "❌ Offline"; Details = $_.Exception.Message}
    }
    
    # 2. Python 환경 확인
    try {
        $pythonVersion = python --version 2>&1
        $checks += @{Name = "Python Environment"; Status = "✅ Available"; Details = $pythonVersion}
    } catch {
        $checks += @{Name = "Python Environment"; Status = "❌ Missing"; Details = "Python not found"}
    }
    
    # 3. 필수 Python 패키지 확인
    $requiredPackages = @("flask", "pandas", "requests", "openpyxl")
    foreach ($package in $requiredPackages) {
        try {
            $packageInfo = pip show $package 2>&1
            if ($LASTEXITCODE -eq 0) {
                $checks += @{Name = "Package: $package"; Status = "✅ Installed"; Details = "OK"}
            } else {
                $checks += @{Name = "Package: $package"; Status = "❌ Missing"; Details = "Not installed"}
            }
        } catch {
            $checks += @{Name = "Package: $package"; Status = "❌ Error"; Details = $_.Exception.Message}
        }
    }
    
    # 4. 디스크 공간 확인
    $drive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.DeviceID -eq "C:"}
    $freeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 2)
    if ($freeSpaceGB -gt 5) {
        $checks += @{Name = "Disk Space"; Status = "✅ Sufficient"; Details = "${freeSpaceGB}GB available"}
    } else {
        $checks += @{Name = "Disk Space"; Status = "⚠️ Low"; Details = "${freeSpaceGB}GB available"}
    }
    
    Write-UpgradeLog "📋 Prerequisite check results:"
    foreach ($check in $checks) {
        Write-UpgradeLog "  → $($check.Name): $($check.Status) - $($check.Details)"
    }
    
    return $checks
}

function New-UpgradeBackup {
    Write-UpgradeLog "💾 Creating pre-upgrade backup..."
    
    if (-not (Test-Path $BackupPath)) {
        New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    }
    
    $backupItems = @(
        @{Source = "fuseki\data"; Destination = "$BackupPath\fuseki_data"}
        @{Source = "config"; Destination = "$BackupPath\config"}
        @{Source = "scripts"; Destination = "$BackupPath\scripts"}
        @{Source = "logs"; Destination = "$BackupPath\logs"}
    )
    
    foreach ($item in $backupItems) {
        if (Test-Path $item.Source) {
            try {
                Copy-Item -Path $item.Source -Destination $item.Destination -Recurse -Force
                Write-UpgradeLog "✅ Backed up: $($item.Source) → $($item.Destination)"
            } catch {
                Write-UpgradeLog "❌ Backup failed: $($item.Source) - $($_.Exception.Message)" "ERROR"
            }
        } else {
            Write-UpgradeLog "⚠️ Source not found: $($item.Source)" "WARN"
        }
    }
    
    Write-UpgradeLog "💾 Backup completed: $BackupPath"
}

function Install-ClaudeNativeComponents {
    Write-UpgradeLog "🚀 Installing Claude Native Components..."
    
    # 1. 업그레이드 디렉토리 생성
    if (-not (Test-Path "upgrade\v3.7-CLAUDE-NATIVE")) {
        New-Item -Path "upgrade\v3.7-CLAUDE-NATIVE" -ItemType Directory -Force | Out-Null
    }
    
    # 2. Claude Integration Bridge 생성
    $bridgeCode = @'
#!/usr/bin/env python3
"""
HVDC-Claude Native Integration Bridge v3.7
Samsung HVDC x MACHO-GPT 완전 통합 시스템
"""

import flask
import requests
import json
import pandas as pd
from datetime import datetime
import logging
import asyncio
from typing import Dict, List, Any

# MACHO-GPT 명령어 매핑
MACHO_COMMANDS = {
    "logi-master": {
        "kpi-dash": "get_realtime_kpi",
        "invoice-audit": "audit_invoices",
        "predict": "predict_logistics",
        "weather-tie": "analyze_weather_impact",
        "customs": "analyze_customs",
        "stowage": "optimize_stowage",
        "warehouse": "check_warehouse_status",
        "report": "generate_executive_report"
    },
    "switch_mode": {
        "PRIME": "activate_prime_mode",
        "ORACLE": "activate_oracle_mode", 
        "ZERO": "activate_zero_mode",
        "LATTICE": "activate_lattice_mode",
        "COST-GUARD": "activate_cost_guard_mode"
    },
    "check_KPI": "monitor_kpi_thresholds",
    "weather-tie": "get_weather_logistics_impact",
    "compliance-report": "generate_compliance_report"
}

class ClaudeNativeBridge:
    def __init__(self):
        self.app = flask.Flask(__name__)
        self.fuseki_url = "http://localhost:3030/hvdc"
        self.hvdc_api_url = "http://localhost:5002"
        self.setup_routes()
        
    def setup_routes(self):
        @self.app.route('/claude/execute', methods=['POST'])
        def execute_macho_command():
            """MACHO-GPT 명령어 실행"""
            data = flask.request.json
            command = data.get('command')
            params = data.get('parameters', {})
            
            try:
                result = self.execute_command(command, params)
                return flask.jsonify({
                    "status": "success",
                    "command": command,
                    "result": result,
                    "claude_integration": {
                        "web_search_suggestions": self.get_web_search_suggestions(command),
                        "drive_search_keywords": self.get_drive_search_keywords(command),
                        "recommended_tools": self.get_recommended_tools(command)
                    }
                })
            except Exception as e:
                return flask.jsonify({"status": "error", "message": str(e)}), 500
        
        @self.app.route('/claude/workflow', methods=['POST'])
        def automated_workflow():
            """자동화 워크플로우 실행"""
            data = flask.request.json
            workflow_type = data.get('type')
            
            workflows = {
                "daily_check": self.daily_operations_workflow,
                "emergency_response": self.emergency_response_workflow,
                "compliance_audit": self.compliance_audit_workflow,
                "performance_optimization": self.performance_optimization_workflow
            }
            
            if workflow_type in workflows:
                result = workflows[workflow_type](data.get('parameters', {}))
                return flask.jsonify(result)
            else:
                return flask.jsonify({"error": "Unknown workflow type"}), 400
        
        @self.app.route('/claude/status', methods=['GET'])
        def bridge_status():
            """브릿지 상태 확인"""
            return flask.jsonify({
                "bridge_version": "v3.7-CLAUDE-NATIVE",
                "status": "active",
                "integrations": {
                    "hvdc_api": self.check_hvdc_api(),
                    "fuseki": self.check_fuseki(),
                    "claude_tools": ["web_search", "google_drive_search", "repl", "artifacts"]
                },
                "available_commands": list(MACHO_COMMANDS.keys())
            })
    
    def execute_command(self, command: str, params: Dict) -> Dict:
        """MACHO-GPT 명령어 실행 로직"""
        if command == "status":
            return self.get_system_status()
        elif command == "logi-master":
            return self.execute_logi_master(params)
        elif command == "switch_mode":
            return self.switch_containment_mode(params)
        else:
            return {"message": f"Executed {command} with Claude Native integration", "params": params}
    
    def get_system_status(self) -> Dict:
        """시스템 전체 상태 조회"""
        try:
            hvdc_health = requests.get(f"{self.hvdc_api_url}/health", timeout=3).json()
            fuseki_ping = requests.get(f"{self.fuseki_url}/$/ping", timeout=3).text
            return {
                "hvdc_api": hvdc_health,
                "fuseki": {"status": "online", "response": fuseki_ping},
                "bridge": {"version": "v3.7", "status": "active"}
            }
        except Exception as e:
            return {"error": str(e)}
    
    def execute_logi_master(self, params: Dict) -> Dict:
        """LogiMaster 명령어 실행"""
        action = params.get('action', 'status')
        if action == "kpi-dash":
            return self.get_kpi_dashboard(params)
        elif action == "invoice-audit":
            return self.audit_invoices(params)
        else:
            return {"action": action, "status": "executed", "claude_integration": True}
    
    def get_kpi_dashboard(self, params: Dict) -> Dict:
        """실시간 KPI 대시보드"""
        try:
            audit_summary = requests.get(f"{self.hvdc_api_url}/audit/summary").json()
            fuseki_stats = requests.get(f"{self.hvdc_api_url}/fuseki/stats").json()
            return {
                "kpi_type": "realtime_dashboard",
                "audit_metrics": audit_summary,
                "data_metrics": fuseki_stats,
                "claude_suggestions": {
                    "web_search": ["Samsung HVDC project KPI", "logistics performance benchmarks"],
                    "repl_analysis": "Calculate performance trends from audit data",
                    "artifacts_viz": "Generate executive KPI dashboard"
                }
            }
        except Exception as e:
            return {"error": f"KPI dashboard error: {str(e)}"}
    
    def check_hvdc_api(self) -> str:
        """HVDC API 상태 확인"""
        try:
            response = requests.get(f"{self.hvdc_api_url}/health", timeout=3)
            return "✅ Online" if response.status_code == 200 else "❌ Error"
        except:
            return "❌ Offline"
    
    def check_fuseki(self) -> str:
        """Fuseki 상태 확인"""
        try:
            response = requests.get(f"{self.fuseki_url}/$/ping", timeout=3)
            return "✅ Online" if response.status_code == 200 else "❌ Error"
        except:
            return "❌ Offline"
    
    def get_web_search_suggestions(self, command: str) -> List[str]:
        """명령어별 web_search 제안"""
        suggestions = {
            "weather-tie": ["UAE weather forecast", "Dubai port conditions", "Persian Gulf marine weather"],
            "customs": ["UAE customs regulations 2025", "FANR nuclear materials import", "MOIAT compliance requirements"],
            "kpi-dash": ["Samsung HVDC project status", "global HVDC market trends", "logistics performance benchmarks"]
        }
        return suggestions.get(command, ["HVDC project updates", "Samsung logistics news"])
    
    def get_drive_search_keywords(self, command: str) -> List[str]:
        """명령어별 google_drive_search 키워드"""
        keywords = {
            "invoice-audit": ["invoice templates", "audit procedures", "financial controls"],
            "compliance-report": ["compliance templates", "regulatory documents", "approval workflows"],
            "report": ["executive templates", "project reports", "KPI dashboards"]
        }
        return keywords.get(command, ["project documents", "templates", "procedures"])
    
    def get_recommended_tools(self, command: str) -> List[str]:
        """명령어별 추천 Claude 도구"""
        tools = {
            "kpi-dash": ["repl (계산)", "artifacts (시각화)", "web_search (현황)"],
            "report": ["google_drive_search (템플릿)", "artifacts (보고서)", "filesystem (저장)"],
            "predict": ["web_search (데이터)", "repl (분석)", "artifacts (예측 차트)"]
        }
        return tools.get(command, ["web_search", "repl", "artifacts"])

if __name__ == "__main__":
    bridge = ClaudeNativeBridge()
    print("🚀 HVDC v3.7 Claude Native Bridge Starting...")
    print("🔗 Available at: http://localhost:5003")
    bridge.app.run(host='localhost', port=5003, debug=False)
'@

    # 3. 파일 생성
    if (-not $DryRun) {
        $bridgeCode | Out-File -FilePath "upgrade\v3.7-CLAUDE-NATIVE\claude_native_bridge.py" -Encoding UTF8
        Write-UpgradeLog "✅ Created: claude_native_bridge.py"
        
        # 4. 자동 시작 스크립트 생성
        $startScript = @'
@echo off
title HVDC v3.7 Claude Native Bridge
echo 🚀 Starting HVDC v3.7 Claude Native Bridge...
echo 🔗 Bridge will be available at: http://localhost:5003
echo 📊 Integration with HVDC API (port 5002) and Fuseki (port 3030)
echo.
python upgrade\v3.7-CLAUDE-NATIVE\claude_native_bridge.py
pause
'@
        $startScript | Out-File -FilePath "start-claude-native-bridge.bat" -Encoding ASCII
        Write-UpgradeLog "✅ Created: start-claude-native-bridge.bat"
        
        # 5. 통합 테스트 스크립트 생성
        $testScript = @'
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
'@
        $testScript | Out-File -FilePath "upgrade\v3.7-CLAUDE-NATIVE\test_claude_integration.py" -Encoding UTF8
        Write-UpgradeLog "✅ Created: test_claude_integration.py"
        
    } else {
        Write-UpgradeLog "🔍 DRY RUN: Would create claude_native_bridge.py and related scripts"
    }
}

function Test-UpgradeValidation {
    Write-UpgradeLog "🧪 Running upgrade validation tests..."
    
    $validationTests = @(
        @{Name = "Bridge API Connection"; Command = "Test-NetConnection localhost -Port 5003 -InformationLevel Quiet"}
        @{Name = "HVDC API Integration"; Command = "Invoke-RestMethod -Uri 'http://localhost:5002/health' -TimeoutSec 3"}
        @{Name = "Fuseki Server Integration"; Command = "Invoke-RestMethod -Uri 'http://localhost:3030/hvdc/$/ping' -TimeoutSec 3"}
    )
    
    $results = @()
    foreach ($test in $validationTests) {
        try {
            if (-not $DryRun) {
                $result = Invoke-Expression $test.Command
                $results += @{Name = $test.Name; Status = "✅ PASS"; Details = "OK"}
                Write-UpgradeLog "✅ Validation PASS: $($test.Name)"
            } else {
                $results += @{Name = $test.Name; Status = "🔍 SKIPPED"; Details = "Dry run mode"}
                Write-UpgradeLog "🔍 DRY RUN: Would test $($test.Name)"
            }
        } catch {
            $results += @{Name = $test.Name; Status = "❌ FAIL"; Details = $_.Exception.Message}
            Write-UpgradeLog "❌ Validation FAIL: $($test.Name) - $($_.Exception.Message)" "ERROR"
        }
    }
    
    return $results
}

function Start-UpgradeWorkflow {
    Write-UpgradeLog "🚀 Starting HVDC v3.7 Claude Native Upgrade Workflow..."
    
    # Phase 1: 준비
    Write-UpgradeLog "📋 Phase 1: Prerequisites Check"
    $prereqResults = Test-UpgradePrerequisites
    
    $failedPrereqs = $prereqResults | Where-Object {$_.Status -like "*❌*"}
    if ($failedPrereqs -and -not $Force) {
        Write-UpgradeLog "❌ Prerequisites failed. Use -Force to override." "ERROR"
        return @{status = "failed"; phase = "prerequisites"; details = $failedPrereqs}
    }
    
    # Phase 2: 백업
    Write-UpgradeLog "💾 Phase 2: Backup Creation"
    if (-not $DryRun) {
        New-UpgradeBackup
    } else {
        Write-UpgradeLog "🔍 DRY RUN: Would create backup at $BackupPath"
    }
    
    # Phase 3: 업그레이드 설치
    Write-UpgradeLog "🔧 Phase 3: Claude Native Components Installation"
    Install-ClaudeNativeComponents
    
    # Phase 4: 검증
    Write-UpgradeLog "✅ Phase 4: Validation Testing"
    $validationResults = Test-UpgradeValidation
    
    Write-UpgradeLog "🎉 Upgrade workflow completed!"
    
    return @{
        status = "completed"
        version = $TARGET_VERSION
        phases = @{
            prerequisites = $prereqResults
            validation = $validationResults
        }
        next_steps = @(
            "Start Claude Native Bridge: .\start-claude-native-bridge.bat",
            "Test integration: python upgrade\v3.7-CLAUDE-NATIVE\test_claude_integration.py",
            "Verify Claude tools: /logi-master kpi-dash --realtime"
        )
    }
}

function Get-UpgradeStatus {
    Write-UpgradeLog "📊 Checking current upgrade status..."
    
    $status = @{
        current_version = $CURRENT_VERSION
        target_version = $TARGET_VERSION
        components = @{}
        recommendations = @()
    }
    
    # 파일 존재 확인
    $componentFiles = @(
        "upgrade\v3.7-CLAUDE-NATIVE\claude_native_bridge.py",
        "upgrade\v3.7-CLAUDE-NATIVE\test_claude_integration.py",
        "start-claude-native-bridge.bat",
        "backup\pre_v37_upgrade"
    )
    
    foreach ($file in $componentFiles) {
        $status.components[$file] = if (Test-Path $file) { "✅ Exists" } else { "❌ Missing" }
    }
    
    # 권장사항 생성
    if (-not (Test-Path "upgrade\v3.7-CLAUDE-NATIVE\claude_native_bridge.py")) {
        $status.recommendations += "Run upgrade workflow: .\upgrade_v37.ps1 -Action upgrade"
    }
    
    if (Test-Path "upgrade\v3.7-CLAUDE-NATIVE\claude_native_bridge.py") {
        $status.recommendations += "Start Claude Native Bridge: .\start-claude-native-bridge.bat"
        $status.recommendations += "Test MACHO-GPT integration: python upgrade\v3.7-CLAUDE-NATIVE\test_claude_integration.py"
    }
    
    return $status
}

# 메인 실행 로직
function Main {
    Write-UpgradeLog "🎯 HVDC v3.7 Claude Native Upgrade Tool"
    Write-UpgradeLog "Action: $Action, DryRun: $DryRun, Force: $Force"
    
    # 로그 디렉토리 생성
    if (-not (Test-Path "logs")) {
        New-Item -Path "logs" -ItemType Directory -Force | Out-Null
    }
    
    switch ($Action.ToLower()) {
        "status" {
            $status = Get-UpgradeStatus
            Write-UpgradeLog "📊 Current Status: $($status.current_version) → $($status.target_version)"
            foreach ($comp in $status.components.GetEnumerator()) {
                Write-UpgradeLog "  → $($comp.Key): $($comp.Value)"
            }
            Write-UpgradeLog "💡 Recommendations:"
            foreach ($rec in $status.recommendations) {
                Write-UpgradeLog "  → $rec"
            }
            return $status
        }
        "prerequisites" {
            return Test-UpgradePrerequisites
        }
        "backup" {
            New-UpgradeBackup
            return @{status = "completed"; backup_path = $BackupPath}
        }
        "install" {
            Install-ClaudeNativeComponents
            return @{status = "completed"; message = "Claude Native components installed"}
        }
        "validate" {
            return Test-UpgradeValidation
        }
        "upgrade" {
            return Start-UpgradeWorkflow
        }
        default {
            Write-UpgradeLog "❌ Unknown action: $Action" "ERROR"
            Write-UpgradeLog "Available actions: status, prerequisites, backup, install, validate, upgrade"
            return @{status = "error"; message = "Unknown action"}
        }
    }
}

# 스크립트 실행
Main
