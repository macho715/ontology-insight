@echo off
title HVDC v3.7 Claude Native Bridge
echo ?? Starting HVDC v3.7 Claude Native Bridge...
echo ?? Bridge will be available at: http://localhost:5003
echo ?? Integration with HVDC API (port 5002) and Fuseki (port 3030)
echo.
python upgrade\v3.7-CLAUDE-NATIVE\claude_native_bridge.py
pause
