#!/usr/bin/env bash
# test-setup-e2e.sh: setup のエンドツーエンド動作を仕様ベースで検証する（設計契約 T10）
#
# 契約（design-contract T1/T2/T9a/T9b）:
#   T2  dry-run 完全化: 非対話（stdin /dev/null）でも一切プロンプトせず、knowledge/log を含め
#       [dry-run] 予定だけを出力し、実ファイル/実 symlink を作らない。既存衝突は状態別に報告する。
#       create_link の dry-run 4分岐（再リンク / 退避して上書き / スキップ / 新規）を網羅する。
#   T1  --force の破壊的削除撤廃: 既存実体は rm -rf ではなく `.fstack-bak.*` へ mv 退避され、
#       元パスに新しい symlink が張られる（内容が退避先で復元可能なことまで検証）。
#   T9a フィルタスコープ: --skills は skills のみに作用し、rules は無条件でインストールされる。
#   T9b claude hard fail 緩和: claude CLI 未検出でも exit 1 せず warn に留める（git のみ必須）。
#
# 偽陽性排除の要点（Codex レビュー反映）:
#   dry-run テストは「[dry-run] を含む」だけでは旧実装（プロンプトを出す版）でも通ってしまう。
#   そこで (a) knowledge/log 固有の dry-run 文言が出ること、(b) 対話プロンプト由来の文字列
#   （「非対話環境のため」「スキップしました」「選択してください」等）が一切出ないこと、
#   (c) CLAUDE.md・knowledge・logs・settings.json の実体が作られないこと、を具体値で assert する。
#
# 隔離方針（契約 architect 指摘11/3）:
#   全ケース `--global` + `HOME` override で実 HOME を汚さない
#   （--global は TARGET_DIR="$HOME/.claude" なので HOME 差し替えで完全隔離できる）。
#   全 setup 呼び出しに `< /dev/null` を付け、非対話パス（read/ask_yn の hang 回避）に倒す。
#   一時ディレクトリは mktemp -d 配下に作り、既存 test（test-validate-bash.sh）と同じく
#   OS の一時領域回収に委ねる（プロジェクト規約により rm での明示削除はしない）。

TEST_NAME="setup-e2e"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SETUP="$REPO_ROOT/setup"
TMPROOT=$(mktemp -d /tmp/fstack-setup-e2e-XXXXXX)
# mktemp 失敗ガード: 空だと以降の HOME/PATH override が /.claude を対象にする事故になる
: "${TMPROOT:?TMPROOT (mktemp -d) failed — 中断する}"

# 新しい隔離 HOME ディレクトリを作って echo する（テストごとに独立させる）。
# 空文字を返すと HOME="" で setup が走ってしまうため、生成失敗時は即座に落とす。
fresh_home() {
  local d
  d=$(mktemp -d "$TMPROOT/home-XXXXXX") || return 1
  [ -n "$d" ] || return 1
  printf '%s' "$d"
}

# claude だけを除いた PATH shim を作って echo する（git 等の必須コマンドは残す）。
# この環境には実 claude CLI が存在するため、単純な PATH 制限では claude を除去できない。
make_bin_without_claude() {
  local shim t p
  shim=$(mktemp -d "$TMPROOT/nobin-claude-XXXXXX") || return 1
  [ -n "$shim" ] || return 1
  for t in cat grep egrep sed git dirname basename readlink head tail date tr sort wc env bash sh find mkdir ln mv cp rm mktemp cut awk gh printf ls; do
    p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$shim/$t" 2>/dev/null
  done
  printf '%s' "$shim"
}

# パスが symlink なら "link"、通常実体なら "file"、無ければ "absent" を echo
path_kind() {
  if [ -L "$1" ]; then echo "link"
  elif [ -e "$1" ]; then echo "file"
  else echo "absent"
  fi
}

# =============================================================================
# T2-(1): dry-run はプロンプトを出さず、knowledge/log を含め予定だけを出し、実体を作らない
#   旧実装（dry-run 中も ask_yn を叩く版）なら「非対話環境のため」「スキップしました」が出るため落ちる
# =============================================================================
H1=$(fresh_home); : "${H1:?fresh_home failed}"
OUT=$(HOME="$H1" bash "$SETUP" --global --dry-run < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "dry-run: stdin /dev/null でも hang せず exit 0 で完走する"
assert_contains "$OUT" "[dry-run]" "dry-run: [dry-run] 行を出力する"
assert_contains "$OUT" "No changes were made" "dry-run: 変更なしメッセージで完了する"
# knowledge/log 固有の dry-run 文言（弱いアサート回避の核）
assert_contains "$OUT" "[dry-run] ナレッジベース" "dry-run: ナレッジベースは予定のみを [dry-run] で出す"
assert_contains "$OUT" "[dry-run] ログ収集" "dry-run: ログ収集は予定のみを [dry-run] で出す"
# 対話プロンプト由来の文字列が一切出ないこと（旧実装検出）
assert_not_contains "$OUT" "非対話環境のため" "dry-run: ask_yn/read の非対話フォールバックに到達しない"
assert_not_contains "$OUT" "スキップしました" "dry-run: knowledge/log の『スキップしました』を出さない（return が ask_yn より前）"
assert_not_contains "$OUT" "セットアップしますか" "dry-run: y/n 確認プロンプトを出さない"
assert_not_contains "$OUT" "選択してください" "dry-run: CLAUDE.md の選択プロンプトを出さない"
# 実体を一切作らない
CREATED_LINKS=$(find "$H1/.claude" -type l 2>/dev/null)
assert_empty "$CREATED_LINKS" "dry-run: 実 symlink を1つも作らない"
assert_eq "absent" "$(path_kind "$H1/.claude/skills/handover")" "dry-run: skills/handover の実体を作らない"
assert_eq "absent" "$(path_kind "$H1/.claude/CLAUDE.md")" "dry-run: CLAUDE.md を作らない"
assert_eq "absent" "$(path_kind "$H1/.claude/knowledge")" "dry-run: knowledge ディレクトリを作らない"
assert_eq "absent" "$(path_kind "$H1/.claude/logs")" "dry-run: logs ディレクトリを作らない"
assert_eq "absent" "$(path_kind "$H1/.claude/settings.json")" "dry-run: settings.json を作らない"

# =============================================================================
# T2-(2): dry-run 分岐カバレッジ — 既存 fstack symlink は「再リンク」と報告する
# =============================================================================
H2=$(fresh_home); : "${H2:?fresh_home failed}"
mkdir -p "$H2/.claude/rules"
ln -s "$REPO_ROOT/rules/testing.md" "$H2/.claude/rules/fstack-testing.md"
OUT=$(HOME="$H2" bash "$SETUP" --global --dry-run < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "dry-run 再リンク: exit 0"
assert_contains "$OUT" "再リンク" "dry-run 再リンク: 既存 fstack symlink は『再リンク』と報告する"

# =============================================================================
# T2-(3): dry-run 分岐カバレッジ — 他人の実体あり + FORCE なしは「スキップ（既存）」で報告し、書き換えない
# =============================================================================
H3=$(fresh_home); : "${H3:?fresh_home failed}"
mkdir -p "$H3/.claude/rules"
printf 'user-owned content\n' > "$H3/.claude/rules/fstack-testing.md"
OUT=$(HOME="$H3" bash "$SETUP" --global --dry-run < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "dry-run 衝突: exit 0"
assert_contains "$OUT" "スキップ（既存" "dry-run 衝突: 既存衝突を『スキップ（既存）』で報告する"
assert_eq "file" "$(path_kind "$H3/.claude/rules/fstack-testing.md")" "dry-run 衝突: 既存実体を symlink 化しない"
assert_eq "user-owned content" "$(cat "$H3/.claude/rules/fstack-testing.md")" "dry-run 衝突: 既存ファイルの内容を書き換えない"

# =============================================================================
# T2-(4): dry-run 分岐カバレッジ — 他人の実体あり + FORCE は「退避して上書き」を報告するが実退避はしない
# =============================================================================
H4=$(fresh_home); : "${H4:?fresh_home failed}"
mkdir -p "$H4/.claude/rules"
printf 'REAL-FILE\n' > "$H4/.claude/rules/fstack-testing.md"
OUT=$(HOME="$H4" bash "$SETUP" --global --dry-run --force < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "dry-run+force: exit 0"
assert_contains "$OUT" "既存を退避して上書き（--force）" "dry-run+force: 退避して上書き予定を報告する"
DRY_BAK=$(find "$H4/.claude/rules" -name 'fstack-testing.md.fstack-bak.*' 2>/dev/null)
assert_empty "$DRY_BAK" "dry-run+force: 実際にはバックアップを作らない（予定表示のみ）"
assert_eq "file" "$(path_kind "$H4/.claude/rules/fstack-testing.md")" "dry-run+force: 既存を symlink 化しない"
assert_eq "REAL-FILE" "$(cat "$H4/.claude/rules/fstack-testing.md")" "dry-run+force: 既存内容を変えない"

# =============================================================================
# T1: --force で既存実体が .fstack-bak.* に退避され、元パスが symlink になる（rm されない）
# =============================================================================
H5=$(fresh_home); : "${H5:?fresh_home failed}"
mkdir -p "$H5/.claude/rules"
printf 'ORIGINAL-REAL-FILE\n' > "$H5/.claude/rules/fstack-testing.md"
OUT=$(HOME="$H5" bash "$SETUP" --global --force < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "force: exit 0"
BACKUP=$(find "$H5/.claude/rules" -name 'fstack-testing.md.fstack-bak.*' 2>/dev/null | head -1)
assert_nonempty "$BACKUP" "force: 既存実体が .fstack-bak.* に退避される（rm -rf されない）"
if [ -n "$BACKUP" ]; then BACKUP_BODY=$(cat "$BACKUP"); else BACKUP_BODY=""; fi
assert_eq "ORIGINAL-REAL-FILE" "$BACKUP_BODY" "force: 退避ファイルの内容が元と一致する（mv 退避で復元可能）"
assert_eq "link" "$(path_kind "$H5/.claude/rules/fstack-testing.md")" "force: 元パスが新しい symlink になる"
assert_contains "$OUT" "既存を退避しました" "force: 退避先パスを warn で表示する"

# =============================================================================
# T9a: --skills フィルタは skills のみ絞り込み、rules は無条件でインストールされる
# =============================================================================
H6=$(fresh_home); : "${H6:?fresh_home failed}"
OUT=$(HOME="$H6" bash "$SETUP" --global --skills handover < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "skills filter: exit 0"
assert_eq "link" "$(path_kind "$H6/.claude/skills/handover")" "skills filter: 指定した handover はインストールされる"
assert_eq "absent" "$(path_kind "$H6/.claude/skills/review-pr")" "skills filter: フィルタ外の review-pr は除外される"
assert_eq "link" "$(path_kind "$H6/.claude/rules/fstack-testing.md")" "skills filter: rules はフィルタに関係なく無条件で入る"

# =============================================================================
# T9b: claude CLI 未検出でも hard fail せず（exit 1 しない）warn に留める
# =============================================================================
H7=$(fresh_home); : "${H7:?fresh_home failed}"
SHIM=$(make_bin_without_claude); : "${SHIM:?make_bin_without_claude failed}"
OUT=$(HOME="$H7" PATH="$SHIM" bash "$SETUP" --global --dry-run < /dev/null 2>&1); RC=$?
assert_eq "0" "$RC" "claude 未検出: hard fail せず exit 0"
assert_contains "$OUT" "claude CLI not found" "claude 未検出: error で落とさず warn を出す"
assert_not_contains "$OUT" "git is required" "claude 未検出: git は shim にあるため必須エラーは出ない"

finish
