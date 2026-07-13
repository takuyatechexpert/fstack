#!/bin/bash
# PreToolUse hook: Bash コマンドの事前検証
# パイプ経由の deny 回避、シークレット漏洩、危険パターンを検出する
#
# Usage:
#   ~/.claude/settings.json の PreToolUse > matcher: "Bash" にぶら下げる
#   詳細は同梱の README.md を参照

set -euo pipefail

# --- lib ブートストラップ（symlink 追跡で実体を解決し lib/common.sh を source）---
# 安全系（ブロック目的）hook のため、実体解決・lib source・jq・JSON parse の
# いずれの失敗も fail-closed（exit 2）。安全系がサイレントに無効化されるのを防ぐ。
_self="$0"
_guard=0
while [ -L "$_self" ]; do
  _guard=$((_guard + 1))
  if [ "$_guard" -gt 40 ]; then _self=""; break; fi
  _dir=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || { _self=""; break; }
  _link=$(readlink "$_self") || { _self=""; break; }
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$_dir/$_link" ;;
  esac
done
SCRIPT_DIR=""
if [ -n "$_self" ]; then
  SCRIPT_DIR=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd || printf '')
fi
if [ -z "$SCRIPT_DIR" ] || [ ! -r "$SCRIPT_DIR/lib/common.sh" ]; then
  echo "[validate-bash] 共通ライブラリ lib/common.sh を解決できません。安全のためブロックします。" >&2
  exit 2
fi
. "$SCRIPT_DIR/lib/common.sh"

# jq 不在は fail-closed
if ! fstack_have_jq; then
  echo "[validate-bash] jq が見つかりません。安全のためブロックします。" >&2
  exit 2
fi

# stdin を一度だけ読み、JSON 妥当性を検証（不正 JSON は fail-closed）
INPUT=$(fstack_read_input)
if ! printf '%s' "$INPUT" | fstack_jq empty >/dev/null 2>&1; then
  echo "[validate-bash] hook 入力の JSON 解析に失敗しました。安全のためブロックします。" >&2
  exit 2
fi

COMMAND=$(printf '%s' "$INPUT" | fstack_jq -r '.tool_input.command // ""')

# 1. パイプ経由の deny 回避検出
#    例: echo "rm -rf /" | bash, cat script.sh | sh
if echo "$COMMAND" | grep -qE '\|\s*(bash|sh|zsh|eval)\b'; then
  fstack_emit_deny "パイプ経由でシェルにコマンドを渡す操作はブロックされています"
fi

# 2. eval による任意コード実行（コマンド語位置のみ deny）
#    コマンド語位置 = 行頭 / ; / & / | / ( / $( / バッククォート / 改行 のいずれか直後。
#    パス（docs/eval/）・オプション（--eval）・部分文字列（eval.py）には誤反応しない。
if echo "$COMMAND" | grep -qE '(^|[;&|(`])[[:space:]]*eval([[:space:]]|$)'; then
  fstack_emit_deny "eval による任意コード実行はブロックされています"
fi

# 3. echo/printf/cat<<< 経由でのシークレット変数の出力
#    例: echo $GITHUB_TOKEN, printf "%s" $API_KEY
#    サービス名_TOKEN/KEY/SECRET/PASSWORD 形式の変数も対象。
#    （.env 経由の $VAR 参照そのもの — curl の URL/ヘッダに $TOKEN を渡す等 — は通す）
if echo "$COMMAND" | grep -qEi '(echo|printf|cat[[:space:]]+<<<)[^|;&]*\$\{?[A-Z][A-Z0-9_]*(TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL|APIKEY)'; then
  fstack_emit_deny "echo/printf 経由でのシークレット変数の出力はブロックされています（トランスクリプトに値が露出します）"
fi

# 3c. curl の詳細出力モード（-v / --trace / --trace-ascii）
#    シークレットを含む URL がトレースされるとトランスクリプトに平文で残る
if echo "$COMMAND" | grep -qE '\bcurl\b[^|;&]*(-v\b|--verbose\b|--trace\b|--trace-ascii\b)'; then
  fstack_emit_deny "curl の詳細出力モード (-v/--trace) はシークレット露出リスクのためブロックされています"
fi

# 3d. set -x / bash -x による実行トレース（変数展開値が露出する）
if echo "$COMMAND" | grep -qE '(^|[[:space:]&;])(set[[:space:]]+-[-a-z]*x|bash[[:space:]]+-x)\b'; then
  fstack_emit_deny "set -x / bash -x はシークレット変数展開が露出するためブロックされています"
fi

# 3e. curl/wget/http に Authorization Bearer のリテラルトークン直書き
if echo "$COMMAND" | grep -qEi '(Authorization:[[:space:]]*Bearer[[:space:]]+|Authorization:[[:space:]]*Basic[[:space:]]+)[A-Za-z0-9+/=_.-]{16,}'; then
  fstack_emit_deny "Authorization ヘッダへのトークンリテラル直書きはブロックされています（.env 経由で \$VAR 参照してください）"
fi

# 3f. curl/wget の -d / --data / -F にトークンっぽいリテラル値を直書き
if echo "$COMMAND" | grep -qEi '(-d|--data|--data-raw|--data-urlencode|-F|--form)[[:space:]]+["'\'']?[^"'\'' ]*?(token|apikey|api_key|secret|password|access[_-]?token|client[_-]?secret|auth)=[A-Za-z0-9+/=_.-]{16,}'; then
  fstack_emit_deny "curl/wget のデータパラメータにトークンリテラルを直書きする操作はブロックされています（.env 経由で \$VAR 参照してください）"
fi

# 3g. URL クエリパラメータへのトークンリテラル直書き
if echo "$COMMAND" | grep -qEi '[?&](apikey|api_key|token|access_token|secret|auth)=[A-Za-z0-9+/=_.-]{16,}'; then
  fstack_emit_deny "URL クエリパラメータへのトークンリテラル直書きはブロックされています（.env 経由で \$VAR 参照してください）"
fi

# printenv コマンド、または env コマンド単体での環境変数一覧表示を検出
if echo "$COMMAND" | grep -qE '\bprintenv\b'; then
  fstack_emit_ask "環境変数の一覧表示はシークレット漏洩のリスクがあります"
fi
if echo "$COMMAND" | grep -qE '(^|\s)env\s*$|(^|\s)env\s*\|'; then
  fstack_emit_ask "環境変数の一覧表示はシークレット漏洩のリスクがあります"
fi

# 4. /dev/tcp 経由の外部通信
if echo "$COMMAND" | grep -qE '/dev/(tcp|udp)/'; then
  fstack_emit_deny "/dev/tcp 経由の外部通信はブロックされています"
fi

# 5. base64 エンコードによる難読化
if echo "$COMMAND" | grep -qE 'base64\s+(-d|--decode).*\|\s*(bash|sh|zsh)'; then
  fstack_emit_deny "base64 デコード結果のシェル実行はブロックされています"
fi

# 6. プロセス置換経由の回避
if echo "$COMMAND" | grep -qE '(bash|sh|zsh)\s+<\('; then
  fstack_emit_deny "プロセス置換経由でのシェル実行はブロックされています"
fi

# 7. history / credentials ファイルの読み取り
if echo "$COMMAND" | grep -qEi '(\.bash_history|\.zsh_history|\.mysql_history|\.psql_history)'; then
  fstack_emit_deny "シェル履歴ファイルへのアクセスはブロックされています"
fi

# デフォルト: 許可（何も出力しない）
exit 0
