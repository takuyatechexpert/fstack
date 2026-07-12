#!/bin/bash
# T1: check-secret-patterns.sh の再現テスト
#
# 契約（design-contract §4 T1 / §2 PreToolUse）:
#   - ERE で secret-patterns.txt のパターン（例: {24,} 量指定子）を検出できること
#   - deny 理由にシークレット値そのものを含めないこと（トランスクリプト焼き付き防止）
#   - deny 時は permissionDecision:"deny" + exit 0
#   - クリーンなファイルでは exit 0・出力なし
#
# 基準版 (46938a3) は grep -n（BRE）のため {24,} が literal 扱いになり検出できず、
# また検出時にマッチ行内容を deny 理由へ焼き付ける。

TEST_NAME="check-secret-patterns"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/check-secret-patterns.sh"

# hook を起動する。payload の .cwd とプロセス CWD の両方を temp repo に向ける。
# （基準版は stdin を二重読みして .cwd が空になり、プロセス CWD にフォールバックするため
#  両方を揃えないと現行・修正版のどちらでも同じ temp repo を対象にできない）
run_hook() {
  # $1: git リポジトリ（作業ディレクトリ）
  printf '{"tool_input":{"command":"git commit -m test"},"cwd":"%s"}' "$1" > "$1/payload.json"
  ( cd "$1" && bash "$HOOK" < "$1/payload.json" )
}

# コマンド文字列を差し替えて起動する版
run_hook_cmd() {
  # $1: 作業ディレクトリ  $2: tool_input.command
  printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$2" "$1" > "$1/payload.json"
  ( cd "$1" && bash "$HOOK" < "$1/payload.json" )
}

# command と .cwd を独立に指定して起動する版（プロセス CWD も .cwd に合わせる）
run_hook_full() {
  # $1: payload 置き場（書込可 dir）  $2: tool_input.command  $3: .cwd 値
  printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$2" "$3" > "$1/payload.json"
  ( cd "$3" && bash "$HOOK" < "$1/payload.json" )
}

# パターンファイルと対象ファイルを持つ git リポジトリを用意する
setup_repo() {
  # $1: secret-patterns.txt の中身  $2: 対象ファイル名  $3: 対象ファイルの中身
  local work
  work=$(mktemp -d /tmp/fstack-secpat-XXXXXX)
  git -C "$work" init -q
  git -C "$work" config user.email t@example.com
  git -C "$work" config user.name tester
  mkdir -p "$work/.claude"
  printf '%s\n' "$1" > "$work/.claude/secret-patterns.txt"
  printf '%s\n' "$3" > "$work/$2"
  git -C "$work" add -A >/dev/null 2>&1
  printf '%s' "$work"
}

decision_of() {
  [ -z "$1" ] && { echo "none"; return; }
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

# --- ケース1: ERE 量指定子 {24,} でシークレットを検出し deny する ---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
OUT=$(run_hook "$WORK" 2>/dev/null); RC=$?
assert_eq "0" "$RC" "ERE検出: exit 0 で返る"
assert_eq "deny" "$(decision_of "$OUT")" "ERE検出: permissionDecision が deny（基準版は BRE で {24,} を検出できず none → RED）"

# --- ケース2: deny 理由にシークレット値を焼き付けない ---
# パターンとマッチ値が別物になるフィクスチャ（値の一意サフィックスが出力に出ないことを検証）。
# 基準版は BRE で MYSEKRET_[A-Za-z0-9]* を検出でき、マッチ行（＝値）を deny 理由へ焼き付ける。
WORK=$(setup_repo 'MYSEKRET_[A-Za-z0-9]*' 'creds.ts' 'const t = "MYSEKRET_TESTDUMMYABCDEF123456";')
OUT=$(run_hook "$WORK" 2>/dev/null); RC=$?
assert_eq "deny" "$(decision_of "$OUT")" "値焼き付き: 検出され deny になる（アンカー・基準版でも検出する）"
assert_not_contains "$OUT" "TESTDUMMYABCDEF123456" "値焼き付き: deny 理由にシークレット値が含まれない（基準版はマッチ行を焼き付け → RED）"

# --- ケース3: クリーンなファイルでは deny せず exit 0 ---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'clean.ts' 'const greeting = "hello world";')
OUT=$(run_hook "$WORK" 2>/dev/null); RC=$?
assert_eq "0" "$RC" "クリーン: exit 0"
assert_eq "none" "$(decision_of "$OUT")" "クリーン: deny を出さない"

# ===== 修正ループ1 追加ケース（契約 §10 C1 / A1・A2・A3・A5・A6）=====

# --- C1-6: deny 理由に pattern 文字列を含めない（A3: `<file>:<line> (pattern #<n>)` 形式）---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
OUT=$(run_hook "$WORK" 2>/dev/null)
assert_eq "deny" "$(decision_of "$OUT")" "C1-6: 検出され deny になる（アンカー）"
assert_not_contains "$OUT" '{24,}' "C1-6: deny 理由に pattern 文字列を含めない"
assert_contains "$OUT" "pattern #" "C1-6: 新形式 (pattern #<n>) で表記される"

# --- C1-8: `git -c x=y commit` 型のオプション挟みを検出する（A6）---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
OUT=$(run_hook_cmd "$WORK" 'git -c user.name=x commit -m test' 2>/dev/null)
assert_eq "deny" "$(decision_of "$OUT")" "C1-8: 単一オプション挟み git -c a=b commit を検出して deny"

# C1-8b: 複数 -c 挟みも検出する（A6 網羅）
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
OUT=$(run_hook_cmd "$WORK" 'git -c a=b -c c=d commit -m test' 2>/dev/null)
assert_eq "deny" "$(decision_of "$OUT")" "C1-8b: 複数オプション挟み git -c a=b -c c=d commit を検出して deny"

# C1-8c: git log 系は commit/push でないので誤検出しない（regex 拡張の false-positive ガード）
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
OUT=$(run_hook_cmd "$WORK" 'git log --oneline commit-graph' 2>/dev/null)
assert_eq "none" "$(decision_of "$OUT")" "C1-8c: git log（commit-graph 含む）は検出せず素通り"

# --- C1-4: stage 後に working tree をクリーン化しても index の内容で deny（A1）---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
printf 'const k = "clean value";\n' > "$WORK/leak.ts"   # working tree はクリーン、index にシークレット残存
OUT=$(run_hook "$WORK" 2>/dev/null)
assert_eq "deny" "$(decision_of "$OUT")" "C1-4: index スキャンで staged シークレットを検出（working tree バイパス不可）"

# --- C1-3a: jq 不在なら exit 2 + stderr（A2: fail-open にしない）---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
printf '{"tool_input":{"command":"git commit -m test"},"cwd":"%s"}' "$WORK" > "$WORK/p.json"
ERRF="$WORK/jqerr"
SHIM=$(make_jqless_bin)
( cd "$WORK" && PATH="$SHIM" /bin/bash "$HOOK" < "$WORK/p.json" >/dev/null 2>"$ERRF" ); RC=$?
assert_eq "2" "$RC" "C1-3a: jq 不在で exit 2（PreToolUse ブロッキングエラー）"
assert_nonempty "$(cat "$ERRF")" "C1-3a: jq 不在で stderr にメッセージが出る"

# --- C1-7: 空 CWD で無限ループせず fail-closed（§11 L6-1 が §10 A5 を上書き → exit 2）---
NONGIT=$(mktemp -d /tmp/fstack-nongit-XXXXXX)
printf '{"tool_input":{"command":"git commit -m test"},"cwd":""}' > "$NONGIT/payload.json"
ERRF="$NONGIT/err"
( cd "$NONGIT" && bash "$HOOK" < "$NONGIT/payload.json" >/dev/null 2>"$ERRF" ) &
hookpid=$!
( sleep 5; kill -9 "$hookpid" 2>/dev/null ) &
killerpid=$!
wait "$hookpid" 2>/dev/null; RC=$?
kill "$killerpid" 2>/dev/null; wait "$killerpid" 2>/dev/null
assert_eq "2" "$RC" "C1-7: 空 CWD は fail-closed で exit 2（137=ハング検知なら FAIL・L6-1）"
assert_nonempty "$(cat "$ERRF")" "C1-7: 空 CWD で stderr にメッセージが出る"

# --- L7-5: commit 検出だがリポジトリ解決不能なら fail-closed（exit 2, L6-1）---
NONGIT=$(mktemp -d /tmp/fstack-nonrepo-XXXXXX)   # .git を持たない dir
printf '{"tool_input":{"command":"git commit -m test"},"cwd":"%s"}' "$NONGIT" > "$NONGIT/payload.json"
ERRF="$NONGIT/err"
( cd "$NONGIT" && bash "$HOOK" < "$NONGIT/payload.json" >/dev/null 2>"$ERRF" ); RC=$?
assert_eq "2" "$RC" "L7-5: commit 検出 + repo 解決不能で exit 2（従来 exit 0 素通りを廃止）"
assert_nonempty "$(cat "$ERRF")" "L7-5: repo 解決不能で stderr にメッセージが出る"

# --- L7-4: `git -C <repo> commit` を別 cwd から実行 → 対象 repo の index で deny（L6-2）---
WORK=$(setup_repo 'xx_fake_[A-Za-z0-9]{24,}' 'leak.ts' 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";')
OTHER=$(mktemp -d /tmp/fstack-othercwd-XXXXXX)   # 対象 repo とは無関係な dir
OUT=$(run_hook_full "$OTHER" "git -C $WORK commit -m test" "$OTHER" 2>/dev/null)
assert_eq "deny" "$(decision_of "$OUT")" "L7-4: git -C <repo> を別 cwd から実行しても対象 repo の index で deny"

# --- M4-3: 相対 `git -C <relative>` が解決不能 → fail-closed exit 2 かつハングなし（M3）---
NONGIT=$(mktemp -d /tmp/fstack-relc-XXXXXX)
printf '{"tool_input":{"command":"git -C does-not-exist-sub commit -m test"},"cwd":"%s"}' "$NONGIT" > "$NONGIT/p.json"
ERRF="$NONGIT/err"
( cd "$NONGIT" && bash "$HOOK" < "$NONGIT/p.json" >/dev/null 2>"$ERRF" ) &
hookpid=$!
( sleep 5; kill -9 "$hookpid" 2>/dev/null ) &
killerpid=$!
wait "$hookpid" 2>/dev/null; RC=$?
kill "$killerpid" 2>/dev/null; wait "$killerpid" 2>/dev/null
assert_eq "2" "$RC" "M4-3: 相対 -C 解決不能で exit 2（137=ハングなら FAIL）"
assert_nonempty "$(cat "$ERRF")" "M4-3: 相対 -C 解決不能で stderr にメッセージ"

# --- M4-4a: 相対 `git -C <relative>` が解決可能 → 対象 repo の index で deny（M3 正規化）---
PARENT=$(mktemp -d /tmp/fstack-relok-XXXXXX)
mkdir -p "$PARENT/repo/.claude"
git -C "$PARENT/repo" init -q
git -C "$PARENT/repo" config user.email t@example.com
git -C "$PARENT/repo" config user.name tester
printf 'xx_fake_[A-Za-z0-9]{24,}\n' > "$PARENT/repo/.claude/secret-patterns.txt"
printf 'const k = "xx_fake_TESTDUMMYAAAABBBBCCCCDDDD";\n' > "$PARENT/repo/leak.ts"
git -C "$PARENT/repo" add -A >/dev/null 2>&1
OUT=$(run_hook_full "$PARENT" "git -C repo commit -m test" "$PARENT" 2>/dev/null)
assert_eq "deny" "$(decision_of "$OUT")" "M4-4a: 相対 -C（repo が cwd のサブディレクトリ）で deny"

# --- M4-4b: クォート付き `git -C \"repo\"` → 未対応形として fail-closed exit 2（fail-open にしない）---
# トークナイザは引用符を除去しないため cd 解決に失敗する = 安全側に倒れることを担保する
QP="$PARENT/pq.json"
printf '{"tool_input":{"command":"git -C \\"repo\\" commit -m test"},"cwd":"%s"}' "$PARENT" > "$QP"
ERRF="$PARENT/qerr"
( cd "$PARENT" && bash "$HOOK" < "$QP" >/dev/null 2>"$ERRF" ); RC=$?
assert_eq "2" "$RC" "M4-4b: クォート付き -C は未対応→fail-closed exit 2（silent bypass しない）"

finish
