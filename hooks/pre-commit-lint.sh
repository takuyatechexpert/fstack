#!/bin/bash
# pre-commit-lint.sh — 多言語 lint dispatcher
#
# 責務: git commit 検出 → ステージ済みファイルを言語別に振り分け → 各 handler 呼び出し
# 言語別の lint 実行ロジックは hooks/lint/lint-<lang>.sh に分離（SRP）
# プロジェクト別の override コマンドは hooks/lint/config.json で管理
#
# Hook 入力: PreToolUse(Bash) の JSON (stdin)
# 出力: エラー時のみ {"continue":false,"stopReason":...} を stdout に吐いて exit 1
# 非 git commit コマンドは即 exit 0

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
LINT_DIR="$HOOKS_DIR/lint"
CONFIG_FILE="$LINT_DIR/config.json"

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# git commit 以外は即終了（settings.json の if フィルタで1次ガード、ここで2次ガード）
if ! echo "$cmd" | grep -qE '(^|[[:space:]&;|])git[[:space:]]+(-[^[:space:]]*[[:space:]]+)*commit([[:space:]]|$)'; then
  exit 0
fi

# cwd が取れない or git リポジトリでない場合は no-op
[[ -z "$cwd" ]] && exit 0
cd "$cwd" 2>/dev/null || exit 0
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# ステージ済みファイルを null 区切りで取得（ファイル名に空白等があっても安全）
STAGED=()
while IFS= read -r -d '' f; do
  STAGED+=("$f")
done < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACMR -z)

[[ ${#STAGED[@]} -eq 0 ]] && exit 0

# 言語別に振り分け（絶対パスで格納）
JS_FILES=()
PHP_FILES=()
PY_FILES=()
RS_FILES=()
for f in "${STAGED[@]}"; do
  case "${f##*.}" in
    js|jsx|ts|tsx|mjs|cjs) JS_FILES+=("$ROOT/$f") ;;
    php)                   PHP_FILES+=("$ROOT/$f") ;;
    py)                    PY_FILES+=("$ROOT/$f") ;;
    rs)                    RS_FILES+=("$ROOT/$f") ;;
  esac
done

# config.json から該当プロジェクトの override コマンドを取得
# $ROOT がエントリの path と一致、または path/ で始まる場合にマッチ
get_override() {
  local lang="$1"
  [[ ! -f "$CONFIG_FILE" ]] && return 0
  jq -r --arg root "$ROOT" --arg lang "$lang" '
    .projects[]?
    | select(.path as $p | $root == $p or ($root | startswith($p + "/")))
    | .commands[$lang] // empty
  ' "$CONFIG_FILE" 2>/dev/null | head -1
}

ERRORS=()

# 1 言語分の lint を実行（override 優先、なければ default handler）
run_lang() {
  local lang="$1"; shift
  local files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0

  local override
  override=$(get_override "$lang")

  local output rc
  if [[ -n "$override" ]]; then
    echo "[lint:$lang] override 実行中..." >&2
    output=$(cd "$ROOT" && bash -c "$override" 2>&1); rc=$?
  else
    local handler="$LINT_DIR/lint-$lang.sh"
    [[ ! -x "$handler" ]] && return 0
    echo "[lint:$lang] ${#files[@]} file(s) チェック中..." >&2
    output=$(cd "$ROOT" && "$handler" "${files[@]}" 2>&1); rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    echo "$output" >&2
    ERRORS+=("$lang")
  fi
}

run_lang "js"     "${JS_FILES[@]}"
run_lang "php"    "${PHP_FILES[@]}"
run_lang "python" "${PY_FILES[@]}"
run_lang "rust"   "${RS_FILES[@]}"

if (( ${#ERRORS[@]} > 0 )); then
  reason="Lint エラーがあります (${ERRORS[*]})。コミット前に修正してください。"
  jq -n --arg reason "$reason" '{continue: false, stopReason: $reason}'
  exit 1
fi

exit 0
