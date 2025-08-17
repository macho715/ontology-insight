#!/bin/bash
# HVDC Ontology Insight - Fuseki Server Start
cd ".\fuseki\apache-jena-fuseki-4.10.0"
echo "Starting Fuseki server for HVDC dataset..."
echo "Web UI: http://localhost:3030/hvdc"
echo "SPARQL Endpoint: http://localhost:3030/hvdc/sparql"
echo
./fuseki-server --tdb2 --loc ./data/tdb-hvdc --update /hvdc
