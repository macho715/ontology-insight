#!/bin/bash
# HVDC Ontology Insight - Batch Processor (Linux/Mac)
# 배치 데이터 처리 및 보고서 생성

set -e

# Configuration
FUSEKI_URL="http://localhost:3030/hvdc"
QUERIES_DIR="./queries"
RESULTS_DIR="./results"
TTL_FILE="triples.ttl"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== HVDC Batch Processor ===${NC}"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Function: Check Fuseki server
check_fuseki() {
    echo -e "${YELLOW}Checking Fuseki server...${NC}"
    if curl -s -f "$FUSEKI_URL/sparql" > /dev/null; then
        echo -e "${GREEN}✓ Fuseki server is running${NC}"
    else
        echo -e "${RED}✗ Fuseki server is not accessible${NC}"
        echo -e "${BLUE}Start server: ./start-hvdc-fuseki.sh${NC}"
        exit 1
    fi
}

# Function: Load data
load_data() {
    if [ "$1" = "--reload" ]; then
        echo -e "${YELLOW}Reloading TTL data...${NC}"
        
        # Delete existing data
        curl -s -X DELETE "$FUSEKI_URL/data?default" || echo "No existing data to delete"
        
        # Upload new data
        if [ -f "$TTL_FILE" ]; then
            curl -s -X POST -H "Content-Type: text/turtle" \
                 --data-binary "@$TTL_FILE" \
                 "$FUSEKI_URL/data?default"
            echo -e "${GREEN}✓ TTL data reloaded${NC}"
        else
            echo -e "${RED}✗ TTL file not found: $TTL_FILE${NC}"
            exit 1
        fi
    fi
}

# Function: Execute query
execute_query() {
    local query_file=$1
    local output_format=$2
    local query_name=$(basename "$query_file" .rq)
    local output_file="$RESULTS_DIR/${query_name}_${TIMESTAMP}.$output_format"
    
    echo -e "${YELLOW}Executing: $query_name${NC}"
    
    # Set accept header based on format
    case $output_format in
        "json")
            accept_header="application/sparql-results+json"
            ;;
        "csv")
            accept_header="text/csv"
            ;;
        "xml")
            accept_header="application/sparql-results+xml"
            ;;
        *)
            accept_header="application/sparql-results+json"
            output_format="json"
            ;;
    esac
    
    # Execute query
    if curl -s -H "Accept: $accept_header" \
            --data-urlencode "query@$query_file" \
            "$FUSEKI_URL/sparql" > "$output_file"; then
        
        local file_size=$(du -h "$output_file" | cut -f1)
        echo -e "${GREEN}✓ Results saved: $output_file ($file_size)${NC}"
        
        # Show preview for JSON results
        if [ "$output_format" = "json" ]; then
            local result_count=$(jq -r '.results.bindings | length' "$output_file" 2>/dev/null || echo "0")
            echo -e "${BLUE}  Results: $result_count rows${NC}"
        fi
    else
        echo -e "${RED}✗ Query failed: $query_name${NC}"
        rm -f "$output_file"
    fi
}

# Function: Generate report
generate_report() {
    local report_file="$RESULTS_DIR/hvdc_report_${TIMESTAMP}.html"
    
    echo -e "${YELLOW}Generating HTML report...${NC}"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>HVDC Ontology Insight Report - $TIMESTAMP</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f8ff; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .query-result { background-color: #f9f9f9; padding: 10px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .timestamp { color: #666; font-size: 0.9em; }
        .success { color: #28a745; }
        .error { color: #dc3545; }
    </style>
</head>
<body>
    <div class="header">
        <h1>HVDC Ontology Insight Report</h1>
        <p class="timestamp">Generated: $(date)</p>
        <p>Project: Samsung HVDC ADOPT Logistics Analysis</p>
    </div>
    
    <div class="section">
        <h2>Executive Summary</h2>
        <p>This report contains automated analysis results from the HVDC project logistics knowledge graph.</p>
        <ul>
            <li>Monthly warehouse stock movements</li>
            <li>Case timeline and FINAL_OUT tracking</li>
            <li>Invoice risk analysis</li>
            <li>OOG and HS code risk assessment</li>
        </ul>
    </div>
EOF

    # Process each JSON result file
    for json_file in "$RESULTS_DIR"/*_${TIMESTAMP}.json; do
        if [ -f "$json_file" ]; then
            local query_name=$(basename "$json_file" _${TIMESTAMP}.json)
            local result_count=$(jq -r '.results.bindings | length' "$json_file" 2>/dev/null || echo "0")
            
            cat >> "$report_file" << EOF
    
    <div class="section">
        <h2>$query_name</h2>
        <div class="query-result">
            <p><strong>Results:</strong> $result_count rows</p>
            <p><strong>File:</strong> <a href="$(basename "$json_file")">$(basename "$json_file")</a></p>
        </div>
    </div>
EOF
        fi
    done
    
    cat >> "$report_file" << EOF
    
    <div class="section">
        <h2>Data Sources</h2>
        <ul>
            <li>TTL File: $TTL_FILE</li>
            <li>Fuseki Endpoint: $FUSEKI_URL</li>
            <li>Query Directory: $QUERIES_DIR</li>
        </ul>
    </div>
    
    <div class="section">
        <h2>Next Steps</h2>
        <ul>
            <li>Review invoice risk findings and take corrective action</li>
            <li>Monitor OOG cargo for special handling requirements</li>
            <li>Track FINAL_OUT events for project completion</li>
            <li>Update stock data for accurate warehouse management</li>
        </ul>
    </div>
</body>
</html>
EOF

    echo -e "${GREEN}✓ HTML report generated: $report_file${NC}"
}

# Main execution
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [--reload] [--format json|csv|xml] [--report]"
        echo "  --reload: Reload TTL data before processing"
        echo "  --format: Output format (default: json)"
        echo "  --report: Generate HTML report"
        exit 0
        ;;
    "--reload")
        check_fuseki
        load_data --reload
        shift
        ;;
    *)
        check_fuseki
        ;;
esac

# Parse remaining arguments
OUTPUT_FORMAT="json"
GENERATE_REPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${YELLOW}Processing queries in $OUTPUT_FORMAT format...${NC}"

# Execute all queries
for query_file in "$QUERIES_DIR"/*.rq; do
    if [ -f "$query_file" ]; then
        execute_query "$query_file" "$OUTPUT_FORMAT"
    fi
done

# Generate report if requested
if [ "$GENERATE_REPORT" = true ]; then
    generate_report
fi

echo -e "${GREEN}=== Batch processing completed ===${NC}"
echo -e "${BLUE}Results directory: $RESULTS_DIR${NC}"

# Show summary
echo -e "\n${YELLOW}Summary:${NC}"
ls -la "$RESULTS_DIR"/*_${TIMESTAMP}.* 2>/dev/null | while read line; do
    echo -e "${BLUE}  $line${NC}"
done
