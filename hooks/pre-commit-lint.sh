#!/bin/bash
# pre-commit-lint.sh — 多言語 lint dispatcher
#
# 責務: git commit 検出 → ステージ済みファイルを言語別に振り分け → 各 handler 呼び出し
# 言語別の lint 実行ロジックは hooks/lint/lint-<lang>.sh に分離（SRP）
# プロジェクト別の override コマンドは hooks/lint/config.json で管理
#
# Hook 入力: PreToolUse(Bash) の JSON (stdin)
# 出力: lint エラー時のみ permissionDecision:"deny" の JSON を stdout に吐いて exit 0
#       （check-secret-patterns.sh と同形式。exit 0 でないと deny が Claude に届かない）
# 非 git commit コマンドは即 exit 0
#
# 作業起点の解釈（既知の制限）: コマンド先頭の `cd <path> &&` と最初の `git -C <path>` のみ
# 解釈する。サブシェル・変数展開・クォート付きパス等の複雑形は解釈せず .cwd 起点で続行する。

# symlink 運用でも lint/ を実体から解決するため、POSIX ポータブルな symlink 追跡ループで
# 実体位置を求める（readlink -f 非依存。旧 macOS でも lint/ を正しく解決する）
# 循環ガード: 最大40回で打ち切り（mask-mcp-output.sh の _guard と同形。M2）。
# 上限到達・解決失敗は「解決失敗」としてサイレント no-op にせず後段の判定で exit 2 する
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
HOOKS_DIR=""
if [ -n "$_self" ]; then
  HOOKS_DIR=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd || printf '')
fi
if [ -z "$HOOKS_DIR" ]; then
  echo "[pre-commit-lint] hook の実体位置を解決できません（symlink 循環の可能性）。安全のためコミットをブロックします。" >&2
  exit 2
fi
LINT_DIR="$HOOKS_DIR/lint"
CONFIG_FILE="$LINT_DIR/config.json"

# 共通ライブラリを source（安全系のため解決失敗は fail-closed）
if [ ! -r "$HOOKS_DIR/lib/common.sh" ]; then
  echo "[pre-commit-lint] 共通ライブラリ lib/common.sh を解決できません。安全のためコミットをブロックします。" >&2
  exit 2
fi
. "$HOOKS_DIR/lib/common.sh"

# jq 不在は fail-closed（PreToolUse のブロッキングエラー）
if ! fstack_have_jq; then
  echo "[pre-commit-lint] jq が見つかりません。安全のためコミットをブロックします。" >&2
  exit 2
fi

input=$(fstack_read_input)

# JSON parse に失敗したら fail-closed
if ! printf '%s' "$input" | fstack_jq empty >/dev/null 2>&1; then
  echo "[pre-commit-lint] hook 入力の JSON 解析に失敗しました。安全のためブロックします。" >&2
  exit 2
fi

cmd=$(printf '%s' "$input" | fstack_jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$input" | fstack_jq -r '.cwd // ""')

# git commit 以外は即終了（settings.json の if フィルタで1次ガード、ここで2次ガード）
# dash オプションに続く値トークン（-c user.name=x 等）も飛ばし、オプション挟みを検出する
if ! printf '%s' "$cmd" | grep -qE '(^|[[:space:]&;|])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

# 作業起点を決定（L6: 先頭 cd と最初の -C を解釈。複雑形は .cwd 起点で続行）
origin="$cwd"
read -ra _tok <<< "$cmd"
if [ "${_tok[0]:-}" = "cd" ] && [ -n "${_tok[1]:-}" ]; then
  case "${_tok[1]}" in
    /*) origin="${_tok[1]}" ;;
    *)  origin="${origin:+$origin/}${_tok[1]}" ;;
  esac
fi
for ((i = 0; i < ${#_tok[@]}; i++)); do
  if [ "${_tok[$i]}" = "-C" ] && [ -n "${_tok[$((i + 1))]:-}" ]; then
    case "${_tok[$((i + 1))]}" in
      /*) origin="${_tok[$((i + 1))]}" ;;
      *)  origin="${origin:+$origin/}${_tok[$((i + 1))]}" ;;
    esac
    break
  fi
done

# L6-1: commit を検出したのに作業ディレクトリ / git root が解決できなければ fail-closed。
# 従来の exit 0 素通り（空 cwd 含む）を廃止し、サイレントに lint を飛ばさない
if [ -z "$origin" ] || ! cd "$origin" 2>/dev/null; then
  echo "[pre-commit-lint] 作業ディレクトリを解決できません。安全のためコミットをブロックします。" >&2
  exit 2
fi
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "[pre-commit-lint] git リポジトリのルートを解決できません。安全のためコミットをブロックします。" >&2
  exit 2
}

# ステージ済みファイルを null 区切りで取得（ファイル名に空白等があっても安全）
STAGED=()
while IFS= read -r -d '' f; do
  STAGED+=("$f")
done < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACMR -z)

[[ ${#STAGED[@]} -eq 0 ]] && exit 0

# L5: symlink 実体解決に失敗する等で lint/ が見つからない場合、サイレント no-op（未 lint の
# まま commit 通過）にせず fail-closed にする
if [ ! -d "$LINT_DIR" ]; then
  echo "[pre-commit-lint] lint ディレクトリを解決できません ($LINT_DIR)。安全のためコミットをブロックします。" >&2
  exit 2
fi

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
  fstack_jq -r --arg root "$ROOT" --arg lang "$lang" '
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
    # lint 出力（ソース断片を含みうる）を全文露出せず先頭 N 行に要約する（Run1 繰越#1）。
    # deny 判定自体は不変（ERRORS への追加は従来どおり）。
    local head_n=20 total
    total=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
    printf '%s\n' "$output" | head -n "$head_n" >&2
    if [ "$total" -gt "$head_n" ]; then
      printf '… (%d 行省略)\n' "$((total - head_n))" >&2
    fi
    ERRORS+=("$lang")
  fi
}

run_lang "js"     "${JS_FILES[@]}"
run_lang "php"    "${PHP_FILES[@]}"
run_lang "python" "${PY_FILES[@]}"
run_lang "rust"   "${RS_FILES[@]}"

if (( ${#ERRORS[@]} > 0 )); then
  reason="Lint エラーがあります (${ERRORS[*]})。コミット前に修正してください。"
  fstack_emit_deny "$reason"
fi

exit 0
