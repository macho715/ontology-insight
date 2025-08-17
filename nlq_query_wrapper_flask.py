#!/usr/bin/env python3
# nlq_query_wrapper_flask.py
# Flask wrapper exposing /nlq-query endpoint that uses nlq_to_sparql.generate_sparql and safe execution flow.
import os
import json
import requests
from flask import Flask, request, jsonify
from nlq_to_sparql import generate_sparql

app = Flask(__name__)

SPARQL_ENDPOINT = os.environ.get("SPARQL_ENDPOINT", "http://localhost:3030/hvdc/sparql")
TIMEOUT = int(os.environ.get("SPARQL_TIMEOUT", "30"))
MAX_ROWS = int(os.environ.get("SPARQL_MAX_ROWS", "1000"))

def run_sparql(query: str):
    headers = {"Accept":"application/sparql-results+json"}
    resp = requests.post(SPARQL_ENDPOINT, data={'query': query}, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()

def ensure_limit(query: str) -> str:
    if "LIMIT" in query.upper():
        return query
    return query + f"\nLIMIT {MAX_ROWS}"

def ask_dry_run_from_select(select_query: str) -> bool:
    # Simple ASK query to check if any data exists
    try:
        # Extract basic graph pattern for ASK query
        if "GRAPH ?g" in select_query:
            # For graph-based queries, just check if any triples exist in graphs
            ask_q = """
            PREFIX ex: <http://samsung.com/project-logistics#>
            ASK WHERE {
                GRAPH ?g { ?s ?p ?o }
            }
            """
        else:
            # For simple queries, check if any triples exist
            ask_q = "ASK WHERE { ?s ?p ?o }"
        
        app.logger.info(f"Running ASK query: {ask_q}")
        res = run_sparql(ask_q)
        result = res.get("boolean", False)
        app.logger.info(f"ASK query result: {result}")
        return result
    except Exception as e:
        app.logger.error("ASK dry-run error: %s", e)
        return False

@app.route("/nlq-query", methods=["POST"])
def nlq_query():
    try:
        payload = request.get_json(force=True) or {}
        q = payload.get("q") or payload.get("query")
        if not q:
            return jsonify({"error":"missing 'q' parameter", "received": payload}), 400
        
        app.logger.info(f"Processing NLQ query: {q}")
    except Exception as e:
        return jsonify({"error": f"JSON parsing failed: {str(e)}"}), 400
    gen = generate_sparql(q)
    if gen.get("error"):
        return jsonify({"error":"unsupported intent", "details": gen}), 400
    sparql = gen["sparql"]
    sparql_checked = ensure_limit(sparql)
    # ASK dry-run
    ok = ask_dry_run_from_select(sparql_checked)
    if not ok:
        return jsonify({"error":"dry-run failed or no matching data"}), 422
    try:
        res = run_sparql(sparql_checked)
        return jsonify({"status":"ok","data":res})
    except requests.HTTPError as e:
        return jsonify({"error":"sparql execution failed","detail": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("NLQ_PORT", "5010")))
