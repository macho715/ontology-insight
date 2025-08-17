@echo off
REM HVDC Ontology Insight - Fuseki Server Start
cd /d ".\fuseki\apache-jena-fuseki-4.10.0"
echo Starting Fuseki server for HVDC dataset...
echo Web UI: http://localhost:3030/hvdc
echo SPARQL Endpoint: http://localhost:3030/hvdc/sparql
echo.
fuseki-server.bat --tdb2 --loc .\data\tdb-hvdc --update /hvdc
