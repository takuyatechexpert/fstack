#!/bin/bash
# hooks 共通ライブラリ — jq パス解決・deny/ask JSON 発行・GNU/BSD コマンド差の吸収を集約する。
#
# 責務: 各 hook から source して使う「関数の定義のみ」を提供する。
#   - このファイルは source しても一切出力せず exit もしない（副作用なし）。
#   - 呼び出し側は自身の実体ディレクトリを解決してから `. "$dir/lib/common.sh"` する
#     （symlink 運用の鶏卵問題対策。ブートストラップ手順は README.md / 各 hook 冒頭を参照）。
#
# 移植方針: OS 判定（uname）ではなくコマンドの成否で分岐する feature-detect。
#   macOS(BSD) と Linux(GNU) のどちらでも同じ関数呼び出しで正しい値を返す。

# --- stdin ---------------------------------------------------------------

# stdin を一度だけ読んで echo する。呼び出し側は `INPUT=$(fstack_read_input)` として
# 以後は "$INPUT" を jq に渡す。jq を2回呼んで stdin を二重消費するバグの再発防止。
fstack_read_input() {
  cat
}

# --- jq -------------------------------------------------------------------

# jq が PATH 上にあれば rc=0。副作用なし。
fstack_have_jq() {
  command -v jq >/dev/null 2>&1
}

# command -v で解決した jq を「実行」する（exec ではない。プロセス置換で hook 本体が
# 消えるのを避ける）。全 hook は絶対パス直書きでなくこれを使う。
fstack_jq() {
  local _jq
  _jq=$(command -v jq) || return 127
  "$_jq" "$@"
}

# --- deny/ask JSON（PreToolUse 安全系）-----------------------------------
#
# 呼び出し規約: emit 系は関数内で exit する。必ず hook のトップレベルで直呼びすること。
#   `reason=$(fstack_emit_deny ...)` のようにコマンド置換内で呼ぶとサブシェルだけが
#   終了し、hook 本体が続行してしまう（＝ブロックが効かない）。

# permissionDecision:"deny" の hookSpecificOutput を stdout に出して exit 0。
# reason は --arg 経由で常に JSON エスケープする（" や \ を含んでも安全）。
# jq が失敗した場合（不在で rc=127 等）は JSON 無し + exit 0 の fail-open を避け、
# stderr + exit 2 へ縮退して fail-closed を保つ。
fstack_emit_deny() {
  fstack_jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }' || {
    printf 'BLOCKED (jq unavailable): %s\n' "$1" >&2
    exit 2
  }
  exit 0
}

# permissionDecision:"ask" 版。jq 失敗時は安全側に倒し exit 2（確認を強制ブロックへ縮退）。
fstack_emit_ask() {
  fstack_jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }' || {
    printf 'BLOCKED (jq unavailable): %s\n' "$1" >&2
    exit 2
  }
  exit 0
}

# --- 移植コマンド（GNU/BSD 差の吸収。feature-detect = コマンドの成否で分岐）--------

# "YYYY-MM-DD HH:MM:SS" を epoch 秒に変換して echo する。
# macOS(BSD): date -j -f / Linux(GNU): date -d。どちらも失敗したら 0 を echo（rc は 0）。
fstack_epoch_from_datetime() {
  local dt="$1" epoch
  # BSD date を先に試す（GNU では -j が不正オプションで失敗し、次の分岐へ落ちる）
  if epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$dt" +%s 2>/dev/null); then
    printf '%s' "$epoch"
    return 0
  fi
  if epoch=$(date -d "$dt" +%s 2>/dev/null); then
    printf '%s' "$epoch"
    return 0
  fi
  printf '0'
  return 0
}

# ファイルの mtime を epoch 秒で echo する。
# macOS(BSD): stat -f %m / Linux(GNU): stat -c %Y。失敗時 0。
fstack_file_mtime() {
  local f="$1" mt
  if mt=$(stat -f %m "$f" 2>/dev/null); then
    printf '%s' "$mt"
    return 0
  fi
  if mt=$(stat -c %Y "$f" 2>/dev/null); then
    printf '%s' "$mt"
    return 0
  fi
  printf '0'
  return 0
}

# stdin を読んで md5 の16進ダイジェストを echo する。
# macOS(BSD): md5（ハッシュのみ出力）/ Linux(GNU): md5sum（先頭フィールドがハッシュ）。
fstack_md5_hex() {
  local out
  if command -v md5 >/dev/null 2>&1; then
    md5
  elif command -v md5sum >/dev/null 2>&1; then
    out=$(md5sum) && printf '%s' "${out%% *}"
  else
    printf '0'
  fi
}

# --- パス -----------------------------------------------------------------

# ログ出力先ディレクトリ。FSTACK_LOG_DIR で override 可（既定 ~/.claude/logs）。
fstack_log_dir() {
  printf '%s' "${FSTACK_LOG_DIR:-$HOME/.claude/logs}"
}
