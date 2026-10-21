#!/bin/bash
# test-check-implementation-routing.sh: check-implementation-routing.sh を仕様ベースで検証する
#
# 契約（design-contract §4 impl-2「hooks/check-implementation-routing.sh」・tester / §5）:
#   - Edit/Write/NotebookEdit の対象が、その編集で git 作業ツリーの変更集合を増やすときだけ判定する。
#     既に変更済み・未追跡のファイル、ignore 対象、リポジトリ外のパス、git 管理外の cwd、
#     cwd 欠落 → reminder なし。
#   - 変更ファイル数 N（HEAD との diff と未追跡の和集合）に対し、編集後の M=N+1 が
#     5 の倍数（THRESHOLD_FILES=5 → 5 / 10 / 15 …）に達した 1 回だけ、直近ウィンドウに
#     solo-with-verifier / orchestra-of-agents の痕跡がなければ stderr に reminder を出す。
#   - reminder は [implementation-task-routing] で始まり、M・次の再表示（M+5）・対象ファイルを含む。
#   - 相対の file_path は cwd 基準で解決する。対象ファイルの判定は literal pathspec（glob 文字を
#     含むパスが別のファイルに一致しない）。NotebookEdit は tool_input.notebook_path を対象にする。
#   - N は NUL 区切りで数える（空白だけ・改行を含む名前も 1 件）。check-ignore がエラーなら何もしない。
#   - FSTACK_ROUTING_WINDOW_SEC でウィンドウ（既定 1800 秒）を override 可能。
#   - jqless（jq 解決失敗）→ no-op。すべての経路で exit 0（非ブロッキング）。
#
# 隔離方針:
#   skills.log は一時 HOME（TMPHOME）+ FSTACK_LOG_DIR に置く。一時 git リポジトリは TMPHOME とは
#   別の mktemp -d に作る（TMPHOME 配下だと skills.log が未追跡として数えられ N がずれる）。
#   リポジトリは pwd -P で解決した実パスを cwd / file_path に使う（/tmp → /private/tmp 差の回避）。
#   git は HOME / XDG_CONFIG_HOME を TMPHOME に向けて実行し、実 HOME のグローバル設定を読まない・変えない。
#   継承した git の環境変数は冒頭で外す（git hook / pre-commit の中から実行しても実リポジトリを触らない）。
#   一時ディレクトリは既存 test と同じく OS の一時領域回収に委ねる（rm での明示削除はしない）。
# タイムスタンプはローカル時刻で生成（hook が date +%s / date -j -f をローカルで扱うため）。

TEST_NAME="check-implementation-routing"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$HOOKS_DIR/check-implementation-routing.sh"
REMINDER_MARK="[implementation-task-routing]"

# 継承した git の環境変数を外す。セットアップの git と hook の実行の両方に効く
# （GIT_DIR / GIT_INDEX_FILE 等が残っていると、一時リポジトリでなく呼び出し元のリポジトリを操作してしまう。
#  pathspec 系が残っていると check-ignore 等の挙動が変わる）
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT \
  GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
export GIT_CONFIG_NOSYSTEM=1
# HOME を変えても GIT_CONFIG_GLOBAL で指定された実設定（core.excludesFile 等）を読まないよう固定する
export GIT_CONFIG_GLOBAL=/dev/null

# epoch → "YYYY-MM-DD HH:MM:SS"（macOS: -r / Linux: -d @）
fmt_ts() {
  date -r "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

# 一時リポジトリ用の git。グローバル設定・署名・hooks の影響を受けず、実 HOME の設定も書き換えない
tgit() {
  HOME="$TMPHOME" XDG_CONFIG_HOME="$TMPHOME/.config" git -C "$REPO" \
    -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1
}

# 一時 HOME と初期コミット済みの一時リポジトリを用意する。
# skills.log は無関係な skill の痕跡だけを置く（ログはあるが実装スキルの起動痕跡はない状態）。
# 初期コミット: .gitignore（*.gen.ts を ignore）と追跡ファイル t1.ts〜t10.ts・a.ts・sub/s.ts・nb.ipynb。
# $1 = 変更する追跡ファイル数（t1.ts から順に）  $2 = 未追跡ファイル数（u1.ts から順に。省略時 0）
setup_case() {
  local mod="$1" untracked="${2:-0}" i
  TMPHOME=$(mktemp -d /tmp/fstack-routehome-XXXXXX)
  LOGDIR="$TMPHOME/.claude/logs"
  mkdir -p "$LOGDIR"
  SKILLS_LOG="$LOGDIR/skills.log"
  printf '[%s] [SKILL] todo | list\n' "$(fmt_ts "$(date +%s)")" > "$SKILLS_LOG"
  REPO=$(cd "$(mktemp -d /tmp/fstack-routerepo-XXXXXX)" && pwd -P)
  tgit init -q
  printf '*.gen.ts\n' > "$REPO/.gitignore"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    printf 'v1\n' > "$REPO/t$i.ts"
  done
  mkdir -p "$REPO/sub"
  printf 'v1\n' > "$REPO/a.ts"
  printf 'v1\n' > "$REPO/sub/s.ts"
  printf 'v1\n' > "$REPO/nb.ipynb"
  tgit add -A
  tgit commit -q -m init
  i=1
  while [ "$i" -le "$mod" ]; do
    printf 'v2\n' >> "$REPO/t$i.ts"
    i=$((i + 1))
  done
  i=1
  while [ "$i" -le "$untracked" ]; do
    printf 'new\n' > "$REPO/u$i.ts"
    i=$((i + 1))
  done
}

# $1 = tool_name  $2 = file_path  $3 = cwd（引数を省くと cwd キーを持たない payload）
mk_payload() {
  if [ "$#" -ge 3 ]; then
    jq -n --arg t "$1" --arg p "$2" --arg c "$3" '{tool_name:$t,tool_input:{file_path:$p},cwd:$c}'
  else
    jq -n --arg t "$1" --arg p "$2" '{tool_name:$t,tool_input:{file_path:$p}}'
  fi
}

# NotebookEdit の payload（tool_input は notebook_path だけを持つ）。$1 = notebook_path  $2 = cwd
mk_notebook_payload() {
  jq -n --arg p "$1" --arg c "$2" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p},cwd:$c}'
}

# PAYLOAD を hook に流す。$1 = FSTACK_ROUTING_WINDOW_SEC（空なら未設定）。OUTTXT / ERRTXT / RC を設定する。
# プロセスの CWD は REPO にする（payload の cwd ではなくプロセス CWD に頼る実装を cwd 欠落ケースで検出するため）
run_routing() {
  local win="$1" outf errf
  outf=$(mktemp /tmp/fstack-routeout-XXXXXX)
  errf=$(mktemp /tmp/fstack-routeerr-XXXXXX)
  if [ -n "$win" ]; then
    ( cd "$REPO" && HOME="$TMPHOME" XDG_CONFIG_HOME="$TMPHOME/.config" FSTACK_LOG_DIR="$LOGDIR" \
        FSTACK_ROUTING_WINDOW_SEC="$win" bash "$HOOK" >"$outf" 2>"$errf" <<<"$PAYLOAD" ); RC=$?
  else
    ( cd "$REPO" && HOME="$TMPHOME" XDG_CONFIG_HOME="$TMPHOME/.config" FSTACK_LOG_DIR="$LOGDIR" \
        bash "$HOOK" >"$outf" 2>"$errf" <<<"$PAYLOAD" ); RC=$?
  fi
  OUTTXT=$(cat "$outf")
  ERRTXT=$(cat "$errf")
}

# reminder 本文の「<数> ファイル」の数を出現順に空白区切りで echo する（先頭 = M、続いて次の再表示 M+5）
file_counts() {
  printf '%s\n' "$1" | grep -oE '[0-9]+ *ファイル' | grep -oE '^[0-9]+' | tr '\n' ' ' | sed 's/ $//'
}

# --- ケース1: 変更 3 件 + 未変更の追跡ファイルへの Edit（M=4）→ reminder なし ---
setup_case 3
PAYLOAD=$(mk_payload Edit "$REPO/t10.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "M=4: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "M=4（変更 3 + 未変更の追跡ファイルへの Edit）: 5 未満なので reminder を出さない"

# --- ケース2: 変更 4 件 + 新規パスへの Write（M=5）→ stderr に reminder ---
setup_case 4
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
run_routing ""
COUNTS=$(file_counts "$ERRTXT")
assert_eq "0" "$RC" "M=5: exit 0（非ブロッキング）"
assert_eq "$REMINDER_MARK" "${ERRTXT:0:${#REMINDER_MARK}}" "M=5（変更 4 + 新規パスへの Write）: stderr の reminder がマーカーで始まる"
assert_empty "$OUTTXT" "M=5: reminder は stderr だけに出し stdout には何も出さない"
assert_eq "5" "${COUNTS%% *}" "M=5: reminder 本文の件数が編集後の 5（編集前の 4 ではない）"
assert_contains " $COUNTS " " 10 " "M=5: 次の再表示が 10 ファイルであることを示す"
assert_contains "$ERRTXT" "$REPO/new.ts" "M=5: reminder に対象ファイルのパスを含む"

# --- ケース3: 変更 5 件 + 既に変更済みのファイルへの Edit → reminder なし（再表示しない）---
setup_case 5
PAYLOAD=$(mk_payload Edit "$REPO/t1.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "既変更ファイルへの Edit: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "既変更ファイルへの Edit（変更 5 のまま）: 変更集合が増えないので再表示しない"

# --- ケース4: 変更 9 件 + 新規パス（M=10）→ reminder あり ---
setup_case 9
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
run_routing ""
COUNTS=$(file_counts "$ERRTXT")
assert_eq "0" "$RC" "M=10: exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "M=10（変更 9 + 新規パス）: 次の 5 の倍数に達したので reminder を出す"
assert_eq "10" "${COUNTS%% *}" "M=10: reminder 本文の件数が 10"
assert_contains " $COUNTS " " 15 " "M=10: 次の再表示が 15 ファイルであることを示す"

# --- ケース5: 変更 5 件 + 新規パス（M=6）→ reminder なし ---
setup_case 5
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "M=6: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "M=6（変更 5 + 新規パス）: 5 の倍数でないので reminder を出さない"

# --- ケース6: M=5 だが直近に orchestra の痕跡あり → reminder なし ---
setup_case 4
printf '[%s] [SKILL] orchestra-of-agents | wave 1\n' "$(fmt_ts "$(date +%s)")" > "$SKILLS_LOG"
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "M=5 + 痕跡あり: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "M=5 + 直近に orchestra-of-agents の痕跡あり: reminder を出さない"

# --- ケース7: 未追跡も数える（追跡済み変更 2 + 未追跡 2 + 新規パス → M=5）→ reminder あり ---
setup_case 2 2
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
run_routing ""
COUNTS=$(file_counts "$ERRTXT")
assert_eq "0" "$RC" "未追跡込み M=5: exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "追跡済み変更 2 + 未追跡 2 + 新規パス: 未追跡も数えて M=5 で reminder を出す"
assert_eq "5" "${COUNTS%% *}" "未追跡込み M=5: reminder 本文の件数が 5"

# --- ケース8: ignore 対象パスへの Write（変更 4 件の状態で）→ reminder なし ---
setup_case 4
PAYLOAD=$(mk_payload Write "$REPO/out.gen.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "ignore 対象への Write: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "ignore 対象（*.gen.ts）への Write: 変更集合が増えないので reminder を出さない"

# --- ケース9: リポジトリ外の絶対パスへの Write（変更 4 件の状態で）→ reminder なし ---
setup_case 4
OUTSIDE=$(cd "$(mktemp -d /tmp/fstack-routeoutside-XXXXXX)" && pwd -P)
PAYLOAD=$(mk_payload Write "$OUTSIDE/x.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "リポジトリ外への Write: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "リポジトリ外の絶対パスへの Write: reminder を出さない"

# --- ケース10: git 管理外の cwd → reminder なし ---
setup_case 4
NONGIT=$(cd "$(mktemp -d /tmp/fstack-routenongit-XXXXXX)" && pwd -P)
PAYLOAD=$(mk_payload Write "$NONGIT/a.ts" "$NONGIT")
run_routing ""
assert_eq "0" "$RC" "git 管理外の cwd: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "git 管理外の cwd: 何もしない（reminder を出さない）"

# --- ケース11: cwd 欠落（変更 4 件 + 新規パス。プロセス CWD は REPO）→ reminder なし ---
setup_case 4
PAYLOAD=$(mk_payload Write "$REPO/new.ts")
run_routing ""
assert_eq "0" "$RC" "cwd 欠落: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "cwd 欠落: プロセス CWD にフォールバックせず何もしない"

# --- ケース12: FSTACK_ROUTING_WINDOW_SEC override がしきい値に反映される（M=5 の状態で）---
# 10 分（600 秒）前の solo 痕跡を置く。
setup_case 4
printf '[%s] [SKILL] solo-with-verifier | task\n' "$(fmt_ts $(($(date +%s) - 600)))" > "$SKILLS_LOG"
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
# 既定（1800 秒）では 600 秒前は範囲内 → reminder なし
run_routing ""
assert_eq "0" "$RC" "override前(既定1800): exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "override前(既定1800): 10分前の痕跡は範囲内 → reminder なし"
# window=60 に絞ると 600 秒前は範囲外 → reminder あり（override 反映）
run_routing "60"
assert_eq "0" "$RC" "override後: 非ブロッキングなので exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "FSTACK_ROUTING_WINDOW_SEC=60: しきい値が反映され範囲外 → reminder"

# --- ケース13: jqless（M=5・痕跡なし）→ 非ブロッキング advisory のため exit 0 継続（no-op）---
setup_case 4
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
printf '%s' "$PAYLOAD" > "$TMPHOME/p.json"
SHIM=$(make_jqless_bin)
ERRF=$(mktemp /tmp/fstack-routejqless-XXXXXX)
( cd "$REPO" && PATH="$SHIM" HOME="$TMPHOME" XDG_CONFIG_HOME="$TMPHOME/.config" FSTACK_LOG_DIR="$LOGDIR" \
    /bin/bash "$HOOK" < "$TMPHOME/p.json" >/dev/null 2>"$ERRF" ); RC=$?
ERRTXT=$(cat "$ERRF")
assert_eq "0" "$RC" "jqless: 非ブロッキング advisory → exit 0 で継続"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "jqless: 解析不能のため no-op（reminder 出さない）"

# ===== 修正ループ1 追加ケース =====
# 既変更の判定は N=4 で見る（判定が消えると M=5 として reminder が出るので退行を検出できる）

# --- ケース14: N=4 で既に変更済みの追跡ファイルを Edit → reminder なし ---
setup_case 4
PAYLOAD=$(mk_payload Edit "$REPO/t1.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "N=4 + 既変更の追跡ファイルへの Edit: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "N=4 + 既変更の追跡ファイルへの Edit: 変更集合が増えないので M=5 として数えない"

# --- ケース15: N=4 で既存の未追跡ファイルを Write → reminder なし ---
setup_case 3 1
PAYLOAD=$(mk_payload Write "$REPO/u1.ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "N=4 + 既存の未追跡ファイルへの Write: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "N=4（変更 3 + 未追跡 1）+ 既存の未追跡ファイルへの Write: 変更集合が増えないので M=5 として数えない"

# --- ケース16: 相対の file_path は cwd 基準で解決する（cwd = sub/、sub/s.ts が変更済みで N=4）→ reminder なし ---
setup_case 3
printf 'v2\n' >> "$REPO/sub/s.ts"
PAYLOAD=$(mk_payload Edit "s.ts" "$REPO/sub")
run_routing ""
assert_eq "0" "$RC" "相対パス: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "相対パス s.ts（cwd=sub/）: 既変更の sub/s.ts と解決し、N=4 のまま reminder を出さない"

# --- ケース17: literal pathspec（a.ts が変更済みで N=4、新規パス [ab].ts への Write → M=5）→ reminder あり ---
setup_case 3
printf 'v2\n' >> "$REPO/a.ts"
PAYLOAD=$(mk_payload Write "$REPO/[ab].ts" "$REPO")
run_routing ""
assert_eq "0" "$RC" "literal pathspec: exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "新規パス [ab].ts: glob として既変更の a.ts に一致させず、新規として M=5 で reminder を出す"

# --- ケース18: NotebookEdit は tool_input.notebook_path を対象にする（N=4 + 未変更の追跡ノートブック → M=5）→ reminder あり ---
setup_case 4
PAYLOAD=$(mk_notebook_payload "$REPO/nb.ipynb" "$REPO")
run_routing ""
assert_eq "0" "$RC" "NotebookEdit: exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "NotebookEdit（notebook_path のみ）M=5: reminder を出す"
assert_contains "$ERRTXT" "$REPO/nb.ipynb" "NotebookEdit: reminder に notebook_path の対象パスを含む"

# ===== 修正ループ2 追加ケース =====

# --- ケース19: 相対の新規パス（cwd = sub/、N=4）への Write → M=5 で reminder あり ---
setup_case 4
PAYLOAD=$(mk_payload Write "new.ts" "$REPO/sub")
run_routing ""
assert_eq "0" "$RC" "相対の新規パス: exit 0"
assert_contains "$ERRTXT" "$REMINDER_MARK" "相対の新規パス new.ts（cwd=sub/）: 相対パスも判定対象にし、M=5 で reminder を出す"

# --- ケース20: 件数は NUL 区切りで数える（空白だけの名前・途中に改行を含む名前を含む N=4）→ M=5 で reminder あり ---
setup_case 2
printf 'x\n' > "$REPO/ "
printf 'x\n' > "$REPO/"$'a\nb.ts'
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
run_routing ""
COUNTS=$(file_counts "$ERRTXT")
assert_eq "0" "$RC" "NUL 区切りの件数: exit 0"
assert_eq "5" "${COUNTS%% *}" "変更 2 + 未追跡の「 」と「a<改行>b.ts」+ 新規パス: どちらの名前も 1 件と数え、M=5 で reminder を出す"

# --- ケース21: check-ignore のエラー（hook の実行時だけ GIT_LITERAL_PATHSPECS=1 で rc=128）→ reminder なし ---
# M=5 になる状態で、エラーを「ignore 対象外」として扱わず exit 0 することを見る
setup_case 4
PAYLOAD=$(mk_payload Write "$REPO/new.ts" "$REPO")
GIT_LITERAL_PATHSPECS=1 run_routing ""
assert_eq "0" "$RC" "check-ignore エラー: exit 0"
assert_not_contains "$ERRTXT" "$REMINDER_MARK" "check-ignore が rc=128（M=5 の状態）: エラーを ignore 対象外と扱わず reminder を出さない"

finish
