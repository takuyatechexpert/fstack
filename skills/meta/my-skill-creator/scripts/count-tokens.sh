#!/bin/bash
# SKILL.md の行数・トークン概算チェック
# Usage: bash count-tokens.sh <path-to-SKILL.md>

set -euo pipefail

FILE="${1:?Usage: count-tokens.sh <path-to-SKILL.md>}"

if [ ! -f "$FILE" ]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

python3 -c "
import re, sys

text = open(sys.argv[1]).read()
jp = len(re.findall(r'[\u3000-\u9fff\uf900-\ufaff]', text))
en = len(re.findall(r'[a-zA-Z0-9_]+', text))
other = len(text) - jp - sum(len(w) for w in re.findall(r'[a-zA-Z0-9_]+', text))
est = int(jp * 1.5 + en * 1.0 + other * 0.25)
lines = len(text.splitlines())

ok = '✓' if lines <= 500 and est <= 4500 else '✗'
print(f'{ok} 行数: {lines}/500  トークン(概算): ~{est}/5000')

warnings = []
if lines > 500:
    warnings.append(f'  ⚠ 500行超過 ({lines}行)')
if est > 4500:
    warnings.append(f'  ⚠ トークン上限に近い (概算{est}、安全圏は4500以下)')

if warnings:
    print('\n'.join(warnings))
    sys.exit(1)
" "$FILE"
