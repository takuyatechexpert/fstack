#!/bin/bash
# test-lib-common.sh: hooks/lib/common.sh の共通関数を直接検証する
#
# 契約（design-contract §1.2 / §5）:
#   - fstack_epoch_from_datetime: 既知日時 → 固定 epoch（TZ=UTC 固定で flaky 回避）。不正入力 → 0（rc=0）
#   - fstack_file_mtime: 存在ファイル → >0、不在 → 0
#   - fstack_md5_hex: stdin を読み md5 16進を echo（既知文字列 → 固定ハッシュ）
#   - fstack_emit_deny / fstack_emit_ask: PreToolUse JSON を stdout に出力し exit 0。
#     reason は JSON エスケープされ、" や \ を含んでも round-trip する
#   - fstack_have_jq: jq が PATH にあれば rc=0
#   - fstack_read_input: stdin を一度読んで echo
#
# 注: lib は副作用なし（source しても出力・exit しない）前提。jqless 経路はここでは扱わない
#     （lib 単体テストは jq 解決前の純関数を直接呼ぶ）。

TEST_NAME="lib-common"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LIBFILE="$HOOKS_DIR/lib/common.sh"

# lib 未作成時は明示 FAIL で締める（cascade を避ける）
if [ ! -f "$LIBFILE" ]; then
  _fail "lib/common.sh の存在" "$LIBFILE が見つからない（impl-1 未完成の可能性）"
  finish
  exit $?
fi

# 副作用なし検証: source 時に何も stdout に出さない
SRC_OUT=$(source "$LIBFILE")
assert_empty "$SRC_OUT" "source: lib を source しても stdout に何も出さない（副作用なし）"

# 以降の関数呼び出しのため本シェルにも読み込む
source "$LIBFILE"

# --- fstack_epoch_from_datetime ---
EP=$(TZ=UTC fstack_epoch_from_datetime "2026-07-12 10:00:00")
assert_eq "1783850400" "$EP" "epoch: 2026-07-12 10:00:00 UTC → 既知 epoch"

EP_BAD=$(fstack_epoch_from_datetime "totally-not-a-date"); RC=$?
assert_eq "0" "$EP_BAD" "epoch: 不正入力 → 0"
assert_eq "0" "$RC" "epoch: 不正入力でも rc=0（best-effort）"

EP_EMPTY=$(fstack_epoch_from_datetime "")
assert_eq "0" "$EP_EMPTY" "epoch: 空文字列 → 0（境界値）"

# --- fstack_file_mtime ---
MT_FILE=$(mktemp /tmp/fstack-mtime-XXXXXX)
MT=$(fstack_file_mtime "$MT_FILE")
if [ "$MT" -gt 0 ] 2>/dev/null; then
  _pass "file_mtime: 存在ファイル → >0"
else
  _fail "file_mtime: 存在ファイル → >0" "got [$MT]"
fi

MT_MISS=$(fstack_file_mtime "/no/such/path/fstack-xyz-123")
assert_eq "0" "$MT_MISS" "file_mtime: 不在ファイル → 0"

# --- fstack_md5_hex（既知文字列 → 固定ハッシュ）---
H_ABC=$(printf 'abc' | fstack_md5_hex)
assert_eq "900150983cd24fb0d6963f7d28e17f72" "$H_ABC" "md5: 'abc'（改行なし）→ 既知ハッシュ"

H_EMPTY=$(printf '' | fstack_md5_hex)
assert_eq "d41d8cd98f00b204e9800998ecf8427e" "$H_EMPTY" "md5: 空文字列 → 既知ハッシュ（境界値）"

# --- fstack_emit_deny ---
REASON='He said "hi" and a backslash \ here'
OUT=$(fstack_emit_deny "$REASON"); RC=$?
assert_eq "0" "$RC" "emit_deny: exit 0"
DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)
assert_eq "deny" "$DEC" "emit_deny: permissionDecision=deny"
EVT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // "none"' 2>/dev/null)
assert_eq "PreToolUse" "$EVT" "emit_deny: hookEventName=PreToolUse"
RSN=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // "none"' 2>/dev/null)
assert_eq "$REASON" "$RSN" "emit_deny: reason が \" と \\ を含んでもエスケープされ round-trip する"

# --- fstack_emit_ask ---
REASON_A='ask? "quote" and \slash'
OUT_A=$(fstack_emit_ask "$REASON_A"); RC=$?
assert_eq "0" "$RC" "emit_ask: exit 0"
DEC_A=$(printf '%s' "$OUT_A" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)
assert_eq "ask" "$DEC_A" "emit_ask: permissionDecision=ask"
EVT_A=$(printf '%s' "$OUT_A" | jq -r '.hookSpecificOutput.hookEventName // "none"' 2>/dev/null)
assert_eq "PreToolUse" "$EVT_A" "emit_ask: hookEventName=PreToolUse"
RSN_A=$(printf '%s' "$OUT_A" | jq -r '.hookSpecificOutput.permissionDecisionReason // "none"' 2>/dev/null)
assert_eq "$REASON_A" "$RSN_A" "emit_ask: reason がエスケープされ round-trip する"

# --- fstack_have_jq ---
if fstack_have_jq; then
  _pass "have_jq: jq が PATH にあれば rc=0"
else
  _fail "have_jq: jq が PATH にあれば rc=0" "jq present but returned nonzero"
fi

# --- fstack_read_input ---
RIN=$(printf 'payload-once' | fstack_read_input)
assert_eq "payload-once" "$RIN" "read_input: stdin を一度読んで echo する"

# --- emit 系の jqless 縮退（fail-open を再導入しない回帰ガード）---
# PATH から jq を外して emit を呼ぶと fstack_jq が rc=127 → stderr + exit 2 に縮退する。
# emit は jq と builtin（printf/exit）のみ使うため shim の mktemp/awk 不在は影響しない。
SHIM=$(make_jqless_bin)

ERRF_D=$(mktemp /tmp/fstack-emitdeny-XXXXXX)
OUT_JD=$( PATH="$SHIM" fstack_emit_deny "test reason" 2>"$ERRF_D" ); RC=$?
assert_eq "2" "$RC" "emit_deny jqless: fail-closed exit 2（安全系 lib が fail-open を再導入しない）"
assert_contains "$(cat "$ERRF_D")" "BLOCKED (jq unavailable)" "emit_deny jqless: stderr に BLOCKED (jq unavailable)"
assert_empty "$OUT_JD" "emit_deny jqless: stdout に JSON を出さない"

ERRF_A=$(mktemp /tmp/fstack-emitask-XXXXXX)
OUT_JA=$( PATH="$SHIM" fstack_emit_ask "test reason" 2>"$ERRF_A" ); RC=$?
assert_eq "2" "$RC" "emit_ask jqless: fail-closed exit 2（ask も安全側にブロックへ縮退）"
assert_contains "$(cat "$ERRF_A")" "BLOCKED (jq unavailable)" "emit_ask jqless: stderr に BLOCKED (jq unavailable)"
assert_empty "$OUT_JA" "emit_ask jqless: stdout に JSON を出さない"

finish
