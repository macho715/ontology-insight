# nlq_to_sparql.py
"""
POC: NLQ -> SPARQL template mapping for HVDC logistics queries.
- Uses a simple rule-based intent matcher (safe) for known intents like "BOE != CIPL".
- For production, wrap LLM-generated SPARQL with validation and ASK/DRY-RUN before executing.
References: Ontotext NLQ patterns, academic NLQ->SPARQL research.
"""

import re
from typing import Dict, List

def detect_intent(nlq: str) -> str:
    """Intent detection based on keywords and patterns"""
    q = nlq.lower()
    
    # BOE vs CIPL mismatch queries
    if ("boe" in q and "cipl" in q) and ("!=" in q or "mismatch" in q or "different" in q):
        return "boe_cipl_mismatch"
    
    # HVDC code listing
    if "show hvdc codes" in q or "list hvdc" in q or "hvdc codes" in q:
        return "list_hvdc_codes"
    
    # Invoice risk analysis
    if ("invoice" in q and ("risk" in q or "alert" in q or "problem" in q)) or ("high-risk" in q and "invoice" in q) or ("show" in q and "high-risk" in q and "invoice" in q):
        return "invoice_risk_analysis"
    
    # Container stowage queries
    if ("container" in q or "stowage" in q) and ("pressure" in q or "weight" in q):
        return "container_stowage_analysis"
    
    # Cost analysis
    if ("cost" in q or "price" in q) and ("analysis" in q or "deviation" in q or "alert" in q):
        return "cost_analysis"
    
    # HS Code risk
    if ("hs code" in q or "hs-code" in q) and ("risk" in q or "controlled" in q):
        return "hs_code_risk"
    
    return "unknown"

def sanitize_identifier(s: str) -> str:
    """Safe parameter sanitizer - allow alphanum, dash, underscore only"""
    return re.sub(r'[^A-Za-z0-9_\-]', '', s.strip())

def extract_parameters(nlq: str) -> Dict[str, str]:
    """Extract parameters from natural language query"""
    params = {}
    
    # Extract SHPT numbers
    shpt_match = re.search(r'SHPT\s+NO\.?\s*(\d+)', nlq, re.IGNORECASE)
    if shpt_match:
        params['shpt_no'] = sanitize_identifier(shpt_match.group(1))
    
    # Extract case numbers
    case_match = re.search(r'case\s+(\w+[-\w]*)', nlq, re.IGNORECASE)
    if case_match:
        params['case_id'] = sanitize_identifier(case_match.group(1))
    
    # Extract invoice numbers
    inv_match = re.search(r'invoice\s+(\w+[-\w]*)', nlq, re.IGNORECASE)
    if inv_match:
        params['invoice_no'] = sanitize_identifier(inv_match.group(1))
    
    return params

def generate_sparql(nlq: str, params: Dict[str, str] = None) -> Dict[str, str]:
    """Generate SPARQL query from natural language input"""
    intent = detect_intent(nlq)
    params = params or extract_parameters(nlq)
    
    if intent == "boe_cipl_mismatch":
        # Find invoices with BOE and CIPL mismatch or missing counterpart
        filter_clause = ""
        if params.get('shpt_no'):
            filter_clause = f'FILTER(CONTAINS(STR(?invoiceNo), "{params["shpt_no"]}"))'
        
        sparql = f"""
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?invoice ?invoiceNo ?boe ?cipl ?mismatchType WHERE {{
  GRAPH ?g {{
    ?invoice a ex:Invoice ;
             ex:invoiceNumber ?invoiceNo .
    OPTIONAL {{ ?boe ex:relatedInvoice ?invoice . }}
    OPTIONAL {{ ?cipl ex:relatedInvoice ?invoice . }}
    
    BIND(
      IF(BOUND(?boe) && BOUND(?cipl) && ?boe != ?cipl, "VALUE_MISMATCH",
      IF(BOUND(?boe) && !BOUND(?cipl), "MISSING_CIPL",
      IF(!BOUND(?boe) && BOUND(?cipl), "MISSING_BOE", "UNKNOWN")))
      AS ?mismatchType
    )
    
    FILTER(?mismatchType != "UNKNOWN")
    {filter_clause}
  }}
}} LIMIT 100"""
        
        return {"sparql": sparql, "intent": intent, "description": "BOE vs CIPL mismatch analysis"}
    
    elif intent == "list_hvdc_codes":
        sparql = """
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT DISTINCT ?code ?caseNumber ?status WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:caseNumber ?caseNumber ;
          ex:status ?status .
    ?entity ex:belongsToCase ?case ;
            ex:hvdcCode ?code .
  }
} ORDER BY ?code LIMIT 200"""
        
        return {"sparql": sparql, "intent": intent, "description": "List all HVDC codes with case info"}
    
    elif intent == "invoice_risk_analysis":
        sparql = """
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?invoice ?invoiceNo ?riskType ?severity ?amount WHERE {
  GRAPH ?g {
    ?invoice a ex:Invoice ;
             ex:invoiceNumber ?invoiceNo .
    
    # Check for missing VAT/Duty
    OPTIONAL { ?invoice ex:vatAmount ?vatAmount . }
    OPTIONAL { ?invoice ex:dutyAmount ?dutyAmount . }
    OPTIONAL { ?invoice ex:totalAmount ?totalAmount . }
    
    BIND(
      IF(!BOUND(?vatAmount), "MISSING_VAT",
      IF(!BOUND(?dutyAmount), "MISSING_DUTY", 
      IF(?totalAmount < 0, "NEGATIVE_AMOUNT", "OTHER")))
      AS ?riskType
    )
    
    BIND(
      IF(?riskType = "NEGATIVE_AMOUNT", "CRITICAL",
      IF(?riskType IN ("MISSING_VAT", "MISSING_DUTY"), "HIGH", "MEDIUM"))
      AS ?severity
    )
    
    BIND(COALESCE(?totalAmount, 0) AS ?amount)
    FILTER(?riskType != "OTHER")
  }
} ORDER BY DESC(?severity) LIMIT 100"""
        
        return {"sparql": sparql, "intent": intent, "description": "Invoice risk analysis (VAT/Duty/Amount)"}
    
    elif intent == "container_stowage_analysis":
        sparql = """
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?cargo ?cargoLabel ?grossWeightKg ?pressure ?riskLevel WHERE {
  GRAPH ?g {
    ?cargo a ex:CargoItem ;
           rdfs:label ?cargoLabel .
    
    OPTIONAL { ?cargo ex:grossWeightKg ?grossWeightKg }
    OPTIONAL { ?cargo ex:pressure ?pressure }
    OPTIONAL { ?cargo ex:riskLevel ?riskLevel }
    
    # Focus on high-weight or high-pressure items
    FILTER(
      (BOUND(?grossWeightKg) && ?grossWeightKg > 10000) ||
      (BOUND(?pressure) && ?pressure > 3.0) ||
      (BOUND(?riskLevel) && ?riskLevel IN ("HIGH", "CRITICAL"))
    )
  }
} ORDER BY DESC(?grossWeightKg) LIMIT 50"""
        
        return {"sparql": sparql, "intent": intent, "description": "Container stowage analysis (weight/pressure)"}
    
    elif intent == "cost_analysis":
        sparql = """
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?case ?caseNumber ?budgetAmount ?actualAmount ?deviation ?deviationPct WHERE {
  GRAPH ?g {
    ?case a ex:Case ;
          ex:caseNumber ?caseNumber .
    
    OPTIONAL { ?case ex:budgetAmount ?budgetAmount }
    OPTIONAL { ?case ex:actualAmount ?actualAmount }
    
    BIND(?actualAmount - ?budgetAmount AS ?deviation)
    BIND((?deviation / ?budgetAmount) * 100 AS ?deviationPct)
    
    FILTER(BOUND(?budgetAmount) && BOUND(?actualAmount))
    FILTER(ABS(?deviationPct) > 5.0)  # Only significant deviations
  }
} ORDER BY DESC(ABS(?deviationPct)) LIMIT 50"""
        
        return {"sparql": sparql, "intent": intent, "description": "Cost deviation analysis (>5%)"}
    
    elif intent == "hs_code_risk":
        sparql = """
PREFIX ex: <http://samsung.com/project-logistics#>
SELECT ?hsCode ?hsLabel ?riskCategory ?dutyRate ?vatRate ?cargoCount WHERE {
  GRAPH ?g {
    ?hsCodeEntity a ex:HSCode ;
                  ex:hsCode ?hsCode ;
                  rdfs:label ?hsLabel ;
                  ex:riskCategory ?riskCategory ;
                  ex:dutyRate ?dutyRate ;
                  ex:vatRate ?vatRate .
    
    # Count cargo items using this HS code
    {
      SELECT ?hsCodeEntity (COUNT(?cargo) AS ?cargoCount) WHERE {
        ?cargo ex:hasHSCode ?hsCodeEntity .
      } GROUP BY ?hsCodeEntity
    }
    
    FILTER(?riskCategory IN ("CONTROLLED", "HIGH_RISK"))
  }
} ORDER BY DESC(?cargoCount) ?riskCategory LIMIT 30"""
        
        return {"sparql": sparql, "intent": intent, "description": "HS Code risk analysis (controlled/high-risk)"}
    
    else:
        return {
            "error": f"Unsupported intent: {intent}",
            "intent": intent,
            "suggestion": "Try queries like: 'Show invoices where BOE != CIPL', 'List HVDC codes', 'Invoice risk analysis'"
        }

def validate_sparql(sparql: str) -> Dict[str, any]:
    """Basic SPARQL validation (syntax and safety checks)"""
    validation_result = {"valid": True, "warnings": [], "errors": []}
    
    # Check for dangerous operations
    dangerous_patterns = [
        (r'\bDROP\b', "DROP operations not allowed"),
        (r'\bCLEAR\b', "CLEAR operations not allowed"),
        (r'\bINSERT\b', "INSERT operations not allowed"),
        (r'\bDELETE\b', "DELETE operations not allowed"),
        (r'\bCREATE\b', "CREATE operations not allowed"),
        (r'LIMIT\s+(\d+)', "Check LIMIT value"),
    ]
    
    for pattern, message in dangerous_patterns:
        if re.search(pattern, sparql, re.IGNORECASE):
            if "LIMIT" in message:
                match = re.search(r'LIMIT\s+(\d+)', sparql, re.IGNORECASE)
                if match and int(match.group(1)) > 1000:
                    validation_result["warnings"].append(f"Large LIMIT value: {match.group(1)}")
            else:
                validation_result["errors"].append(message)
                validation_result["valid"] = False
    
    # Check for required elements
    if not re.search(r'\bSELECT\b', sparql, re.IGNORECASE):
        validation_result["errors"].append("Only SELECT queries are allowed")
        validation_result["valid"] = False
    
    if not re.search(r'\bLIMIT\b', sparql, re.IGNORECASE):
        validation_result["warnings"].append("Consider adding LIMIT clause for performance")
    
    return validation_result

def safe_execute_workflow(nlq: str, execute_fn=None) -> Dict[str, any]:
    """
    Safe execution workflow:
    1) Generate SPARQL from NLQ
    2) Validate SPARQL
    3) Execute if valid (optional execute_fn)
    """
    
    # Step 1: Generate SPARQL
    sparql_result = generate_sparql(nlq)
    
    if "error" in sparql_result:
        return sparql_result
    
    # Step 2: Validate SPARQL
    validation = validate_sparql(sparql_result["sparql"])
    sparql_result["validation"] = validation
    
    if not validation["valid"]:
        return {
            "error": "SPARQL validation failed",
            "validation_errors": validation["errors"],
            "generated_sparql": sparql_result["sparql"]
        }
    
    # Step 3: Execute if function provided
    if execute_fn and validation["valid"]:
        try:
            execution_result = execute_fn(sparql_result["sparql"])
            sparql_result["results"] = execution_result
        except Exception as e:
            sparql_result["execution_error"] = str(e)
    
    return sparql_result

# Example usage and testing
if __name__ == "__main__":
    test_queries = [
        "Show invoices where BOE != CIPL for SHPT NO 0049",
        "List all HVDC codes",
        "Invoice risk analysis",
        "Container stowage analysis for heavy cargo",
        "Cost deviation analysis",
        "HS Code risk analysis for controlled items"
    ]
    
    print("🔍 NLQ → SPARQL Template Testing")
    print("=" * 50)
    
    for query in test_queries:
        print(f"\n📝 Query: {query}")
        result = safe_execute_workflow(query)
        
        if "error" in result:
            print(f"❌ Error: {result['error']}")
        else:
            print(f"✅ Intent: {result['intent']}")
            print(f"📋 Description: {result['description']}")
            if result.get('validation', {}).get('warnings'):
                print(f"⚠️  Warnings: {result['validation']['warnings']}")
            print(f"🔧 Generated SPARQL:")
            print(result['sparql'][:200] + "..." if len(result['sparql']) > 200 else result['sparql'])
