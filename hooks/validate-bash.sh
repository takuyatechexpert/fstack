#!/bin/bash
# PreToolUse hook: Bash コマンドの事前検証
# パイプ経由の deny 回避、シークレット漏洩、危険パターンを検出する
#
# Usage:
#   ~/.claude/settings.json の PreToolUse > matcher: "Bash" にぶら下げる
#   詳細は同梱の README.md を参照

set -euo pipefail

COMMAND=$(jq -r '.tool_input.command // ""')

deny_with_reason() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

ask_with_reason() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# 1. パイプ経由の deny 回避検出
#    例: echo "rm -rf /" | bash, cat script.sh | sh
if echo "$COMMAND" | grep -qE '\|\s*(bash|sh|zsh|eval)\b'; then
  deny_with_reason "パイプ経由でシェルにコマンドを渡す操作はブロックされています"
fi

# 2. eval による任意コード実行
if echo "$COMMAND" | grep -qE '\beval\b'; then
  deny_with_reason "eval による任意コード実行はブロックされています"
fi

# 3. 環境変数経由のシークレット参照検出
#    例: echo $AWS_SECRET_ACCESS_KEY, printenv SECRET
if echo "$COMMAND" | grep -qEi '\$(AWS_SECRET|AWS_ACCESS|API_KEY|SECRET_KEY|PRIVATE_KEY|TOKEN|PASSWORD|CREDENTIAL)'; then
  deny_with_reason "シークレット環境変数の参照が検出されました"
fi

# 3b. echo/printf 経由でのシークレット変数の出力
#    例: echo $GITHUB_TOKEN, printf "%s" $API_KEY
#    サービス名_TOKEN/KEY/SECRET/PASSWORD 形式の変数も対象
if echo "$COMMAND" | grep -qEi '(echo|printf|cat[[:space:]]+<<<)[^|;&]*\$\{?[A-Z][A-Z0-9_]*(TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL|APIKEY)'; then
  deny_with_reason "echo/printf 経由でのシークレット変数の出力はブロックされています（トランスクリプトに値が露出します）"
fi

# 3c. curl の詳細出力モード（-v / --trace / --trace-ascii）
#    シークレットを含む URL がトレースされるとトランスクリプトに平文で残る
if echo "$COMMAND" | grep -qE '\bcurl\b[^|;&]*(-v\b|--verbose\b|--trace\b|--trace-ascii\b)'; then
  deny_with_reason "curl の詳細出力モード (-v/--trace) はシークレット露出リスクのためブロックされています"
fi

# 3d. set -x / bash -x による実行トレース（変数展開値が露出する）
if echo "$COMMAND" | grep -qE '(^|[[:space:]&;])(set[[:space:]]+-[-a-z]*x|bash[[:space:]]+-x)\b'; then
  deny_with_reason "set -x / bash -x はシークレット変数展開が露出するためブロックされています"
fi

# 3e. curl/wget/http に Authorization Bearer のリテラルトークン直書き
if echo "$COMMAND" | grep -qEi '(Authorization:[[:space:]]*Bearer[[:space:]]+|Authorization:[[:space:]]*Basic[[:space:]]+)[A-Za-z0-9+/=_.-]{16,}'; then
  deny_with_reason "Authorization ヘッダへのトークンリテラル直書きはブロックされています（.env 経由で \$VAR 参照してください）"
fi

# 3f. curl/wget の -d / --data / -F にトークンっぽいリテラル値を直書き
if echo "$COMMAND" | grep -qEi '(-d|--data|--data-raw|--data-urlencode|-F|--form)[[:space:]]+["'\'']?[^"'\'' ]*?(token|apikey|api_key|secret|password|access[_-]?token|client[_-]?secret|auth)=[A-Za-z0-9+/=_.-]{16,}'; then
  deny_with_reason "curl/wget のデータパラメータにトークンリテラルを直書きする操作はブロックされています（.env 経由で \$VAR 参照してください）"
fi

# 3g. URL クエリパラメータへのトークンリテラル直書き
if echo "$COMMAND" | grep -qEi '[?&](apikey|api_key|token|access_token|secret|auth)=[A-Za-z0-9+/=_.-]{16,}'; then
  deny_with_reason "URL クエリパラメータへのトークンリテラル直書きはブロックされています（.env 経由で \$VAR 参照してください）"
fi

# printenv コマンド、または env コマンド単体での環境変数一覧表示を検出
if echo "$COMMAND" | grep -qE '\bprintenv\b'; then
  ask_with_reason "環境変数の一覧表示はシークレット漏洩のリスクがあります"
fi
if echo "$COMMAND" | grep -qE '(^|\s)env\s*$|(^|\s)env\s*\|'; then
  ask_with_reason "環境変数の一覧表示はシークレット漏洩のリスクがあります"
fi

# 4. /dev/tcp 経由の外部通信
if echo "$COMMAND" | grep -qE '/dev/(tcp|udp)/'; then
  deny_with_reason "/dev/tcp 経由の外部通信はブロックされています"
fi

# 5. base64 エンコードによる難読化
if echo "$COMMAND" | grep -qE 'base64\s+(-d|--decode).*\|\s*(bash|sh|zsh)'; then
  deny_with_reason "base64 デコード結果のシェル実行はブロックされています"
fi

# 6. プロセス置換経由の回避
if echo "$COMMAND" | grep -qE '(bash|sh|zsh)\s+<\('; then
  deny_with_reason "プロセス置換経由でのシェル実行はブロックされています"
fi

# 7. history / credentials ファイルの読み取り
if echo "$COMMAND" | grep -qEi '(\.bash_history|\.zsh_history|\.mysql_history|\.psql_history)'; then
  deny_with_reason "シェル履歴ファイルへのアクセスはブロックされています"
fi

# デフォルト: 許可（何も出力しない）
exit 0
