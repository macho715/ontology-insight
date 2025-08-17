#!/usr/bin/env python3
"""TTL 파일 백슬래시 문제 수정"""

import re

# TTL 파일 읽기
with open('hvdc_extracted_20250817_204248.ttl', 'r', encoding='utf-8') as f:
    content = f.read()

# 백슬래시를 슬래시로 변경
fixed_content = re.sub(r'ex:sourceFile "([^"]*)"', lambda m: f'ex:sourceFile "{m.group(1).replace(chr(92), "/")}"', content)

# 수정된 파일 저장
with open('hvdc_extracted_fixed.ttl', 'w', encoding='utf-8') as f:
    f.write(fixed_content)

print("✅ TTL file fixed: hvdc_extracted_fixed.ttl")
print("Fixed backslashes in file paths for TTL compatibility")
