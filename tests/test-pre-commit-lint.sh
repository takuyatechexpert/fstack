#!/bin/bash
# T3: pre-commit-lint.sh の再現テスト
#
# 契約（design-contract §4 T3 / §2 PreToolUse）:
#   - lint 失敗時は permissionDecision:"deny" 形式 + exit 0（check-secret-patterns と統一）
#   - symlink 経由で起動されても readlink -f で実体を解決し lint/ を見つける
#
# 基準版 (46938a3):
#   - 失敗時に {"continue":false,"stopReason":...} + exit 1 を返す（届かない経路）
#   - HOOKS_DIR を readlink せず dirname "$0" で解決するため、symlink 経由だと
#     lint/ を見つけられず lint が走らない（サイレント故障）
#
# テスト構成（契約 (a)(b)(c) 準拠）:
#   (a) pre-commit-lint.sh と lint/ を実行権限ごと tmp へ cp
#   (b) fail する override を tmp/lint/config.json に書く（リポジトリ config.json は触らない）
#   (c) symlink テストは別ディレクトリから tmp 実体への symlink を張って起動する

TEST_NAME="pre-commit-lint"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

decision_of() {
  [ -z "$1" ] && { echo "none"; return; }
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

# git リポジトリ（ステージ済み .js）と hooks コピー（fail する override 付き）を用意する
# 戻り値をグローバル WORK / ROOT / HOOKSCOPY / PAYLOAD に設定する
setup_lint_env() {
  WORK=$(mktemp -d /tmp/fstack-lintwork-XXXXXX)
  git -C "$WORK" init -q
  git -C "$WORK" config user.email t@example.com
  git -C "$WORK" config user.name tester
  printf 'const x = 1\n' > "$WORK/app.js"
  git -C "$WORK" add -A >/dev/null 2>&1
  ROOT=$(cd "$WORK" && git rev-parse --show-toplevel)

  HOOKSCOPY=$(mktemp -d /tmp/fstack-lintcopy-XXXXXX)
  cp "$HOOKS_DIR/pre-commit-lint.sh" "$HOOKSCOPY/pre-commit-lint.sh"
  chmod +x "$HOOKSCOPY/pre-commit-lint.sh"
  cp -R "$HOOKS_DIR/lint" "$HOOKSCOPY/lint"
  # 対象リポジトリの js を必ず失敗させる override
  printf '{"projects":[{"path":"%s","commands":{"js":"echo NG; exit 1"}}]}\n' "$ROOT" > "$HOOKSCOPY/lint/config.json"

  PAYLOAD=$(printf '{"tool_input":{"command":"git commit -m test"},"cwd":"%s"}' "$ROOT")
}

# --- ケース1: lint 失敗時に permissionDecision:"deny" + exit 0（直接起動）---
setup_lint_env
OUT=$(printf '%s' "$PAYLOAD" | bash "$HOOKSCOPY/pre-commit-lint.sh" 2>/dev/null); RC=$?
assert_eq "0" "$RC" "直接: lint 失敗でも exit 0（基準版は exit 1 → RED）"
assert_eq "deny" "$(decision_of "$OUT")" "直接: permissionDecision=deny（基準版は continue/stopReason → RED）"

# --- ケース2: symlink 経由で起動しても lint dispatcher が動く ---
setup_lint_env
LINKDIR=$(mktemp -d /tmp/fstack-lintlink-XXXXXX)
ln -s "$HOOKSCOPY/pre-commit-lint.sh" "$LINKDIR/pcl.sh"
OUT=$(printf '%s' "$PAYLOAD" | bash "$LINKDIR/pcl.sh" 2>/dev/null); RC=$?
assert_eq "0" "$RC" "symlink: exit 0"
assert_eq "deny" "$(decision_of "$OUT")" "symlink: lint が走り deny になる（基準版は lint/ 未解決で素通り → RED）"

# --- ケース3: 非 git commit コマンドは素通り（exit 0・出力なし）---
setup_lint_env
PAYLOAD_LS=$(printf '{"tool_input":{"command":"ls -la"},"cwd":"%s"}' "$ROOT")
OUT=$(printf '%s' "$PAYLOAD_LS" | bash "$HOOKSCOPY/pre-commit-lint.sh" 2>/dev/null); RC=$?
assert_eq "0" "$RC" "非 commit: exit 0"
assert_empty "$OUT" "非 commit: 出力なし"

# --- C1-3b: jq 不在なら exit 2 + stderr（A2: fail-open にしない）---
setup_lint_env
printf '%s' "$PAYLOAD" > "$WORK/p.json"
ERRF="$WORK/jqerr"
SHIM=$(make_jqless_bin)
( PATH="$SHIM" /bin/bash "$HOOKSCOPY/pre-commit-lint.sh" < "$WORK/p.json" >/dev/null 2>"$ERRF" ); RC=$?
assert_eq "2" "$RC" "C1-3b: jq 不在で exit 2（PreToolUse ブロッキングエラー）"
assert_nonempty "$(cat "$ERRF")" "C1-3b: jq 不在で stderr にメッセージが出る"

# --- L7-6: 実体解決失敗（lint/ が見つからない）→ fail-closed exit 2（L5・サイレント no-op にしない）---
WORK=$(mktemp -d /tmp/fstack-l76work-XXXXXX)
git -C "$WORK" init -q
git -C "$WORK" config user.email t@example.com
git -C "$WORK" config user.name tester
printf 'const x = 1\n' > "$WORK/app.js"
git -C "$WORK" add -A >/dev/null 2>&1
ROOT=$(cd "$WORK" && git rev-parse --show-toplevel)
NOLINT=$(mktemp -d /tmp/fstack-nolint-XXXXXX)
cp "$HOOKS_DIR/pre-commit-lint.sh" "$NOLINT/pre-commit-lint.sh"
chmod +x "$NOLINT/pre-commit-lint.sh"
# lint/ ディレクトリを意図的に配置しない → 解決後も lint/ が見つからない状態
printf '{"tool_input":{"command":"git commit -m test"},"cwd":"%s"}' "$ROOT" > "$WORK/p.json"
ERRF="$WORK/err76"
( bash "$NOLINT/pre-commit-lint.sh" < "$WORK/p.json" >/dev/null 2>"$ERRF" ); RC=$?
assert_eq "2" "$RC" "L7-6: lint/ 実体解決失敗で exit 2（サイレント no-op にしない）"
assert_nonempty "$(cat "$ERRF")" "L7-6: lint/ 実体解決失敗で stderr にメッセージが出る"

# --- M4-2: symlink 循環（A→B→A）経由の起動 → ハングせず fail-closed（M2 循環ガード）---
# 注記: macOS の MAXSYMLINKS(≈32) が hook の循環ガード(40)より先に発火し、実際には
# bash が ELOOP でファイルを開けず exit 126 になる（hook の exit 2 は $0 経由では到達不能）。
# いずれにせよ「ハングしない + 非ゼロ終了（silent pass しない）」という安全特性を検証する。
CYC=$(mktemp -d /tmp/fstack-cyc-XXXXXX)
cp "$HOOKS_DIR/pre-commit-lint.sh" "$CYC/real.sh"; chmod +x "$CYC/real.sh"
cp -R "$HOOKS_DIR/lint" "$CYC/lint"
ln -s "$CYC/B" "$CYC/A"   # A → B
ln -s "$CYC/A" "$CYC/B"   # B → A（循環）
WORK=$(mktemp -d /tmp/fstack-cycw-XXXXXX)
git -C "$WORK" init -q
git -C "$WORK" config user.email t@example.com
git -C "$WORK" config user.name tester
printf 'const x = 1\n' > "$WORK/app.js"
git -C "$WORK" add -A >/dev/null 2>&1
ROOT=$(cd "$WORK" && git rev-parse --show-toplevel)
printf '{"tool_input":{"command":"git commit -m test"},"cwd":"%s"}' "$ROOT" > "$WORK/p.json"
( bash "$CYC/A" < "$WORK/p.json" >/dev/null 2>/dev/null ) &
cycpid=$!
( sleep 5; kill -9 "$cycpid" 2>/dev/null ) &
killerpid=$!
wait "$cycpid" 2>/dev/null; RC=$?
kill "$killerpid" 2>/dev/null; wait "$killerpid" 2>/dev/null
assert_ne "137" "$RC" "M4-2: 循環 symlink でハングしない（137=watchdog kill なら FAIL）"
assert_ne "0" "$RC" "M4-2: 循環 symlink で fail-closed（非ゼロ終了・silent pass しない）"

finish
