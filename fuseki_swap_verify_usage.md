# fuseki_swap_verify.py - Usage Manual

This document explains how to use the `fuseki_swap_verify.py` tool (CLI or API) to perform a safe staging->production swap of RDF data in Apache Jena Fuseki.

## Overview
`fuseki_swap_verify.py` implements:
1. Upload TTL content to a staging graph.
2. Run validation checks (triple count, ASK/SELECT queries).
3. Backup current production graph.
4. Atomically swap staging into production (INSERT FROM staging, DROP staging).
5. On failure, rollback from backup.

This usage file assumes Fuseki is reachable at `http://localhost:3030` and dataset name is `dataset`.

## CLI usage (example)
```bash
python3 fuseki_swap_verify.py \
  --ttl-file ./deployments/patch_20250817.ttl \
  --fuseki-url http://localhost:3030 \
  --dataset dataset \
  --staging-graph http://example.org/graph/staging \
  --prod-graph http://example.org/graph/production \
  --backup-graph http://example.org/graph/backup \
  --ask-queries ./deployments/validation_asks.sparql \
  --force-swap
```

## API usage (via hvdc_api `/fuseki/deploy`)
POST JSON to `http://<hvdc_api_host>:5002/fuseki/deploy`:
```json
{
  "ttl_content": "@prefix ex: <http://example.org/hvdc#> . ex:INV-0001 ex:invoiceNumber \"INV-0001\" .",
  "actor": "admin",
  "staging_graph": "http://example.org/graph/staging",
  "prod_graph": "http://example.org/graph/production"
}
```

## Recommended validation queries
Create a file `validation_asks.sparql` with several ASK queries, e.g.:
```sparql
ASK WHERE {
  GRAPH <http://example.org/graph/staging> {
    ?inv a <http://example.org/hvdc#Invoice> .
  }
}
ASK WHERE {
  GRAPH <http://example.org/graph/staging> {
    ?e <http://www.w3.org/ns/prov#wasDerivedFrom> ?src .
  }
}
```
Run at least 10-20 validation queries that check key identifiers, PROV links, and expected shapes.

## Operational tips
* Always create a backup of production graph prior to swap (the tool does this automatically).
* Failures must notify the on-call engineer (e.g. via webhook/Slack).
* Enforce timeouts and LIMITs for validation queries to avoid long-running queries.
* Secure Fuseki endpoints with TLS and authentication (Shiro or reverse-proxy).
* See Fuseki docs for Graph Store Protocol and upload methods. (Fuseki docs: https://jena.apache.org/documentation/fuseki2/). citeturn0search4

## References
* Apache Jena Fuseki documentation. citeturn0search4
* NIST SP800-92 log management guidance (for audit practices). citeturn0search5
* W3C PROV-O for provenance modeling. citeturn0search3
