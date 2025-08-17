#!/usr/bin/env python3
"""
HVDC Fuseki Staging → Validation → Swap/Rollback System
Implements safe data deployment with triple-count verification and sample ASK queries
Based on Apache Jena Fuseki configuration best practices
"""

import requests
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, List, Optional
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

class FusekiSwapManager:
    """Manages safe staging, validation, and swapping of HVDC data in Fuseki"""
    
    def __init__(self, base_url: str = "http://localhost:3030", dataset: str = "hvdc"):
        self.base_url = base_url
        self.dataset = dataset
        self.ping_url = f"{base_url}/$/ping"
        self.sparql_url = f"{base_url}/{dataset}/sparql"
        self.update_url = f"{base_url}/{dataset}/update"
        self.data_url = f"{base_url}/{dataset}/data"
        
        # Named graphs for staging and production
        self.staging_graph = "http://samsung.com/graph/STAGING"
        self.production_graphs = [
            "http://samsung.com/graph/OFCO",
            "http://samsung.com/graph/DSV", 
            "http://samsung.com/graph/PKGS",
            "http://samsung.com/graph/EXTRACTED"
        ]
        self.backup_graph = "http://samsung.com/graph/BACKUP"
        
    def check_fuseki_health(self) -> bool:
        """Verify Fuseki server is running and accessible"""
        try:
            response = requests.get(self.ping_url, timeout=5)
            if response.status_code == 200:
                logging.info(f"✅ Fuseki server healthy: {response.text.strip()}")
                return True
            else:
                logging.error(f"❌ Fuseki server error: {response.status_code}")
                return False
        except Exception as e:
            logging.error(f"❌ Fuseki server not accessible: {e}")
            return False
    
    def execute_sparql_query(self, query: str) -> Dict[str, Any]:
        """Execute SPARQL SELECT query"""
        try:
            headers = {"Accept": "application/sparql-results+json"}
            data = {"query": query}
            
            response = requests.post(self.sparql_url, data=data, headers=headers, timeout=30)
            
            if response.status_code == 200:
                return response.json()
            else:
                logging.error(f"SPARQL query failed: {response.status_code} - {response.text}")
                return {"error": f"HTTP {response.status_code}"}
        except Exception as e:
            logging.error(f"SPARQL query error: {e}")
            return {"error": str(e)}
    
    def execute_sparql_update(self, update: str) -> bool:
        """Execute SPARQL UPDATE operation"""
        try:
            headers = {"Content-Type": "application/sparql-update"}
            
            response = requests.post(self.update_url, data=update.encode('utf-8'), 
                                   headers=headers, timeout=60)
            
            if response.status_code in [200, 204]:
                return True
            else:
                logging.error(f"SPARQL update failed: {response.status_code} - {response.text}")
                return False
        except Exception as e:
            logging.error(f"SPARQL update error: {e}")
            return False
    
    def upload_ttl_to_graph(self, ttl_content: str, graph_uri: str) -> bool:
        """Upload TTL data to specific named graph"""
        try:
            url = f"{self.data_url}?graph={graph_uri}"
            headers = {"Content-Type": "text/turtle; charset=utf-8"}
            
            response = requests.put(url, data=ttl_content.encode('utf-8'), 
                                  headers=headers, timeout=120)
            
            if response.status_code in [200, 201, 204]:
                logging.info(f"✅ TTL uploaded to graph: {graph_uri}")
                return True
            else:
                logging.error(f"❌ TTL upload failed: {response.status_code} - {response.text}")
                return False
        except Exception as e:
            logging.error(f"❌ TTL upload error: {e}")
            return False
    
    def get_triple_count(self, graph_uri: Optional[str] = None) -> int:
        """Get triple count for specific graph or entire dataset"""
        if graph_uri:
            query = f"""
            SELECT (COUNT(*) AS ?count) WHERE {{
                GRAPH <{graph_uri}> {{ ?s ?p ?o }}
            }}
            """
        else:
            query = "SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }"
        
        result = self.execute_sparql_query(query)
        
        if "error" in result:
            return -1
        
        try:
            bindings = result.get("results", {}).get("bindings", [])
            if bindings:
                return int(bindings[0]["count"]["value"])
        except (KeyError, ValueError, IndexError):
            pass
        
        return -1
    
    def validate_staging_data(self) -> Dict[str, Any]:
        """
        Comprehensive validation of staging data
        Returns validation results with pass/fail status
        """
        validation_results = {
            "overall_status": "PASS",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "checks": {}
        }
        
        # Check 1: Triple count
        staging_count = self.get_triple_count(self.staging_graph)
        validation_results["checks"]["triple_count"] = {
            "status": "PASS" if staging_count > 0 else "FAIL",
            "count": staging_count,
            "message": f"Found {staging_count} triples in staging"
        }
        
        if staging_count <= 0:
            validation_results["overall_status"] = "FAIL"
        
        # Check 2: Required classes exist
        required_classes_query = f"""
        PREFIX ex: <http://samsung.com/project-logistics#>
        SELECT ?class (COUNT(?instance) AS ?count) WHERE {{
            GRAPH <{self.staging_graph}> {{
                ?instance a ?class .
                FILTER(?class IN (ex:Case, ex:CargoItem, ex:Invoice, ex:HSCode))
            }}
        }} GROUP BY ?class
        """
        
        class_result = self.execute_sparql_query(required_classes_query)
        class_counts = {}
        
        if "error" not in class_result:
            for binding in class_result.get("results", {}).get("bindings", []):
                class_uri = binding["class"]["value"]
                count = int(binding["count"]["value"])
                class_name = class_uri.split("#")[-1]
                class_counts[class_name] = count
        
        required_classes = ["Case", "CargoItem", "Invoice", "HSCode"]
        missing_classes = [cls for cls in required_classes if class_counts.get(cls, 0) == 0]
        
        validation_results["checks"]["required_classes"] = {
            "status": "PASS" if not missing_classes else "WARN",
            "class_counts": class_counts,
            "missing_classes": missing_classes,
            "message": f"Found {len(class_counts)} required classes, missing: {missing_classes}"
        }
        
        # Check 3: Data integrity - HVDC codes format
        hvdc_format_query = f"""
        PREFIX ex: <http://samsung.com/project-logistics#>
        SELECT (COUNT(?code) AS ?total) (COUNT(?validCode) AS ?valid) WHERE {{
            GRAPH <{self.staging_graph}> {{
                ?entity ex:hvdcCode ?code .
                OPTIONAL {{
                    ?entity ex:hvdcCode ?validCode .
                    FILTER(REGEX(?validCode, "^HVDC-[A-Z0-9-]+$"))
                }}
            }}
        }}
        """
        
        format_result = self.execute_sparql_query(hvdc_format_query)
        if "error" not in format_result:
            bindings = format_result.get("results", {}).get("bindings", [])
            if bindings:
                total = int(bindings[0]["total"]["value"])
                valid = int(bindings[0]["valid"]["value"])
                
                validation_results["checks"]["hvdc_format"] = {
                    "status": "PASS" if valid == total and total > 0 else "WARN",
                    "total_codes": total,
                    "valid_codes": valid,
                    "message": f"{valid}/{total} HVDC codes have valid format"
                }
        
        # Check 4: Referential integrity - Cases have cargo items
        referential_query = f"""
        PREFIX ex: <http://samsung.com/project-logistics#>
        SELECT (COUNT(DISTINCT ?case) AS ?cases) (COUNT(DISTINCT ?cargo) AS ?cargoItems) WHERE {{
            GRAPH <{self.staging_graph}> {{
                ?case a ex:Case .
                OPTIONAL {{ ?cargo ex:belongsToCase ?case . }}
            }}
        }}
        """
        
        ref_result = self.execute_sparql_query(referential_query)
        if "error" not in ref_result:
            bindings = ref_result.get("results", {}).get("bindings", [])
            if bindings:
                cases = int(bindings[0]["cases"]["value"])
                cargo_items = int(bindings[0]["cargoItems"]["value"])
                
                validation_results["checks"]["referential_integrity"] = {
                    "status": "PASS" if cargo_items > 0 and cases > 0 else "WARN",
                    "cases": cases,
                    "cargo_items": cargo_items,
                    "message": f"Found {cases} cases with {cargo_items} cargo items"
                }
        
        # Determine overall status
        failed_checks = [name for name, check in validation_results["checks"].items() 
                        if check["status"] == "FAIL"]
        
        if failed_checks:
            validation_results["overall_status"] = "FAIL"
            validation_results["failed_checks"] = failed_checks
        
        return validation_results
    
    def create_backup(self) -> bool:
        """Create backup of current production graphs"""
        logging.info("🔄 Creating backup of production data...")
        
        try:
            # Clear backup graph first
            clear_backup = f"DROP SILENT GRAPH <{self.backup_graph}>"
            if not self.execute_sparql_update(clear_backup):
                return False
            
            # Copy all production graphs to backup
            for graph in self.production_graphs:
                copy_query = f"""
                INSERT {{
                    GRAPH <{self.backup_graph}> {{ ?s ?p ?o }}
                }} WHERE {{
                    GRAPH <{graph}> {{ ?s ?p ?o }}
                }}
                """
                
                if not self.execute_sparql_update(copy_query):
                    logging.error(f"Failed to backup graph: {graph}")
                    return False
            
            backup_count = self.get_triple_count(self.backup_graph)
            logging.info(f"✅ Backup created with {backup_count} triples")
            return True
            
        except Exception as e:
            logging.error(f"❌ Backup creation failed: {e}")
            return False
    
    def swap_to_production(self, target_graph: str) -> bool:
        """Swap staging data to specified production graph"""
        logging.info(f"🔄 Swapping staging data to production: {target_graph}")
        
        try:
            # Clear target production graph
            clear_prod = f"DROP SILENT GRAPH <{target_graph}>"
            if not self.execute_sparql_update(clear_prod):
                return False
            
            # Copy staging to production
            swap_query = f"""
            INSERT {{
                GRAPH <{target_graph}> {{ ?s ?p ?o }}
            }} WHERE {{
                GRAPH <{self.staging_graph}> {{ ?s ?p ?o }}
            }}
            """
            
            if not self.execute_sparql_update(swap_query):
                return False
            
            # Verify the swap
            prod_count = self.get_triple_count(target_graph)
            staging_count = self.get_triple_count(self.staging_graph)
            
            if prod_count == staging_count and prod_count > 0:
                logging.info(f"✅ Swap successful: {prod_count} triples in {target_graph}")
                return True
            else:
                logging.error(f"❌ Swap verification failed: staging={staging_count}, prod={prod_count}")
                return False
                
        except Exception as e:
            logging.error(f"❌ Swap operation failed: {e}")
            return False
    
    def rollback_from_backup(self, target_graph: str) -> bool:
        """Rollback production graph from backup"""
        logging.info(f"🔄 Rolling back {target_graph} from backup...")
        
        try:
            # Clear target graph
            clear_target = f"DROP SILENT GRAPH <{target_graph}>"
            if not self.execute_sparql_update(clear_target):
                return False
            
            # Restore from backup
            restore_query = f"""
            INSERT {{
                GRAPH <{target_graph}> {{ ?s ?p ?o }}
            }} WHERE {{
                GRAPH <{self.backup_graph}> {{ ?s ?p ?o }}
            }}
            """
            
            if not self.execute_sparql_update(restore_query):
                return False
            
            restored_count = self.get_triple_count(target_graph)
            logging.info(f"✅ Rollback successful: {restored_count} triples restored")
            return True
            
        except Exception as e:
            logging.error(f"❌ Rollback failed: {e}")
            return False
    
    def clear_staging(self) -> bool:
        """Clear staging graph after successful deployment"""
        clear_query = f"DROP SILENT GRAPH <{self.staging_graph}>"
        return self.execute_sparql_update(clear_query)
    
    def deploy_with_validation(self, ttl_content: str, target_graph: str) -> Dict[str, Any]:
        """
        Complete deployment workflow:
        1. Upload to staging
        2. Validate staging data
        3. Create backup
        4. Swap to production
        5. Verify or rollback
        """
        deployment_result = {
            "status": "FAILED",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "target_graph": target_graph,
            "steps": {}
        }
        
        try:
            # Step 1: Health check
            if not self.check_fuseki_health():
                deployment_result["steps"]["health_check"] = {"status": "FAILED", "error": "Fuseki not accessible"}
                return deployment_result
            
            deployment_result["steps"]["health_check"] = {"status": "SUCCESS"}
            
            # Step 2: Upload to staging
            logging.info("📤 Uploading data to staging...")
            if not self.upload_ttl_to_graph(ttl_content, self.staging_graph):
                deployment_result["steps"]["staging_upload"] = {"status": "FAILED", "error": "Upload failed"}
                return deployment_result
            
            staging_count = self.get_triple_count(self.staging_graph)
            deployment_result["steps"]["staging_upload"] = {
                "status": "SUCCESS", 
                "triple_count": staging_count
            }
            
            # Step 3: Validate staging data
            logging.info("🔍 Validating staging data...")
            validation = self.validate_staging_data()
            deployment_result["steps"]["validation"] = validation
            
            if validation["overall_status"] != "PASS":
                logging.error("❌ Staging validation failed")
                self.clear_staging()
                return deployment_result
            
            # Step 4: Create backup
            logging.info("💾 Creating backup...")
            if not self.create_backup():
                deployment_result["steps"]["backup"] = {"status": "FAILED", "error": "Backup creation failed"}
                self.clear_staging()
                return deployment_result
            
            backup_count = self.get_triple_count(self.backup_graph)
            deployment_result["steps"]["backup"] = {
                "status": "SUCCESS",
                "backup_count": backup_count
            }
            
            # Step 5: Swap to production
            logging.info("🔄 Swapping to production...")
            if not self.swap_to_production(target_graph):
                deployment_result["steps"]["swap"] = {"status": "FAILED", "error": "Swap operation failed"}
                
                # Attempt rollback
                logging.info("🔙 Attempting rollback...")
                rollback_success = self.rollback_from_backup(target_graph)
                deployment_result["steps"]["rollback"] = {
                    "status": "SUCCESS" if rollback_success else "FAILED"
                }
                
                self.clear_staging()
                return deployment_result
            
            prod_count = self.get_triple_count(target_graph)
            deployment_result["steps"]["swap"] = {
                "status": "SUCCESS",
                "production_count": prod_count
            }
            
            # Step 6: Final verification
            if prod_count == staging_count and prod_count > 0:
                deployment_result["status"] = "SUCCESS"
                logging.info("✅ Deployment completed successfully")
                
                # Clean up staging
                self.clear_staging()
                deployment_result["steps"]["cleanup"] = {"status": "SUCCESS"}
            else:
                logging.error("❌ Final verification failed - initiating rollback")
                rollback_success = self.rollback_from_backup(target_graph)
                deployment_result["steps"]["rollback"] = {
                    "status": "SUCCESS" if rollback_success else "FAILED"
                }
                self.clear_staging()
            
            return deployment_result
            
        except Exception as e:
            logging.error(f"❌ Deployment error: {e}")
            deployment_result["steps"]["error"] = {"status": "FAILED", "error": str(e)}
            
            # Attempt cleanup
            self.clear_staging()
            
            return deployment_result

def main():
    """CLI interface for Fuseki swap operations"""
    import argparse
    
    parser = argparse.ArgumentParser(description="HVDC Fuseki Staging & Deployment Manager")
    parser.add_argument("--deploy", type=str, help="Deploy TTL file to production")
    parser.add_argument("--target-graph", type=str, default="http://samsung.com/graph/EXTRACTED",
                       help="Target production graph URI")
    parser.add_argument("--validate-only", action="store_true", help="Only validate staging data")
    parser.add_argument("--backup", action="store_true", help="Create backup of production data")
    parser.add_argument("--rollback", type=str, help="Rollback specified graph from backup")
    parser.add_argument("--clear-staging", action="store_true", help="Clear staging graph")
    parser.add_argument("--stats", action="store_true", help="Show graph statistics")
    
    args = parser.parse_args()
    
    manager = FusekiSwapManager()
    
    if not manager.check_fuseki_health():
        print("❌ Fuseki server not available")
        return 1
    
    if args.deploy:
        ttl_file = Path(args.deploy)
        if not ttl_file.exists():
            print(f"❌ TTL file not found: {ttl_file}")
            return 1
        
        ttl_content = ttl_file.read_text(encoding='utf-8')
        result = manager.deploy_with_validation(ttl_content, args.target_graph)
        
        print(f"📊 Deployment Result: {result['status']}")
        for step, details in result["steps"].items():
            if isinstance(details, dict) and "status" in details:
                status_emoji = "✅" if details["status"] == "SUCCESS" else "❌"
                print(f"  {status_emoji} {step}: {details['status']}")
                if "error" in details:
                    print(f"    Error: {details['error']}")
            else:
                print(f"  📋 {step}: {details}")
        
        return 0 if result["status"] == "SUCCESS" else 1
    
    elif args.validate_only:
        validation = manager.validate_staging_data()
        print(f"🔍 Validation Result: {validation['overall_status']}")
        for check, details in validation["checks"].items():
            status_emoji = "✅" if details["status"] == "PASS" else "⚠️" if details["status"] == "WARN" else "❌"
            print(f"  {status_emoji} {check}: {details['message']}")
        
        return 0 if validation["overall_status"] == "PASS" else 1
    
    elif args.backup:
        success = manager.create_backup()
        return 0 if success else 1
    
    elif args.rollback:
        success = manager.rollback_from_backup(args.rollback)
        return 0 if success else 1
    
    elif args.clear_staging:
        success = manager.clear_staging()
        print("✅ Staging cleared" if success else "❌ Failed to clear staging")
        return 0 if success else 1
    
    elif args.stats:
        graphs = [
            manager.staging_graph,
            manager.backup_graph
        ] + manager.production_graphs
        
        print("📊 Graph Statistics:")
        for graph in graphs:
            count = manager.get_triple_count(graph)
            graph_name = graph.split("/")[-1]
            print(f"  {graph_name}: {count:,} triples")
        
        return 0
    
    else:
        parser.print_help()
        return 0

if __name__ == "__main__":
    exit(main())
