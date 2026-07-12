#!/bin/bash
# stdin のテキストからシークレットと思われる値をマスクして stdout に出力
# 用途: 他の hook の jq 出力をパイプして使う
#
# 適用順序が重要:
#   1. JSON 形式（"key": "value"）向けルールを先に適用し、引用符構造を保持したまま
#      値部分だけを [MASKED] に置換する（マスク後も jq empty を通す）
#   2. エスケープ JSON 形式（JSON 文字列内にシリアライズされた JSON。MCP の
#      content[].text 標準形で、\"key\":\"value\" のように引用符がエスケープされた形）
#      の 1 段ネストをマスクする。値内のエスケープシーケンス（\\ や \" 相当）を
#      含む値も終端 \" までまとめてマスクし、隣接フィールドは侵さない。
#      **2 段以上のネスト・値が単独バックスラッシュで終わる形は対象外（既知の制限）**
#   3. 続いてプレーンテキスト向けの値ベースルールを適用する
#
# Usage（パイプ用ユーティリティ）:
#   printf '%s' '{"api_key": "secret_value"}' | /path/to/mask-secrets.sh
#   - mask-mcp-output.sh が自身の実体ディレクトリから本スクリプトを解決して呼ぶ
#   - Option B でインストールした場合は fstack-mask-secrets.sh の名前で配置される

sed -E \
  -e 's/("(api[_-]?[Kk]ey|API[_-]?KEY|access[_-]?[Tt]oken|ACCESS[_-]?TOKEN|secret[_-]?[Kk]ey|SECRET[_-]?KEY|client[_-]?[Ss]ecret|CLIENT[_-]?SECRET|[Pp]assword|PASSWORD|[Pp]asswd|PASSWD|[Pp]wd|PWD|[Tt]oken|TOKEN|[Ss]ecret|SECRET|auth|[Aa]uthorization|AUTHORIZATION)"[[:space:]]*:[[:space:]]*")([^"\\]|\\.){3,}(")/\1[MASKED]\4/g' \
  -e 's/(\\"(api[_-]?[Kk]ey|API[_-]?KEY|access[_-]?[Tt]oken|ACCESS[_-]?TOKEN|secret[_-]?[Kk]ey|SECRET[_-]?KEY|client[_-]?[Ss]ecret|CLIENT[_-]?SECRET|[Pp]assword|PASSWORD|[Pp]asswd|PASSWD|[Pp]wd|PWD|[Tt]oken|TOKEN|[Ss]ecret|SECRET|auth|[Aa]uthorization|AUTHORIZATION)\\"[[:space:]]*:[[:space:]]*\\")(\\\\\\"|\\\\|[^\\"]){3,}(\\")/\1[MASKED]\4/g' \
  -e 's/(api[_-]?key|apiKey|API_KEY|apikey|access[_-]?token|accessToken|ACCESS_TOKEN|secret[_-]?key|secretKey|SECRET_KEY)("?)[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9._-]{8,}/\1\2=[MASKED]/g' \
  -e 's/([Pp]assword|PASSWORD|[Pp]asswd|PASSWD|[Pp]wd|PWD)("?)[[:space:]]*[:=][[:space:]]*"?[^][:space:]"'\'',}{[]{3,}/\1\2=[MASKED]/g' \
  -e 's/Bearer [A-Za-z0-9._-]{10,}/Bearer [MASKED]/g' \
  -e 's/Authorization:[[:space:]]*[A-Za-z0-9._-]{10,}/Authorization: [MASKED]/g' \
  -e 's/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/[MASKED_JWT]/g' \
  -e 's/(^|[[:space:]",:={}(])(sk_live_|sk_test_|sk-)[A-Za-z0-9_-]{10,}/\1\2[MASKED]/g' \
  -e 's/([?&](token|key|secret|api_key|apikey|access_token|auth|apiKey|accessToken)=)[^&"[:space:]]{8,}/\1[MASKED]/g' \
  -e 's/(gh[pousr]_)[A-Za-z0-9]{30,}/\1[MASKED]/g' \
  -e 's/(xox[baprs]-)[A-Za-z0-9-]{10,}/\1[MASKED]/g' \
  -e 's/(AKIA|ASIA)[A-Z0-9]{16}/\1[MASKED_AWS_KEY]/g'
