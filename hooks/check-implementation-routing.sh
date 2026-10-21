#!/usr/bin/env bash
# check-implementation-routing.sh
#
# Edit/Write/NotebookEdit の前に「この編集で git 作業ツリーの変更ファイル数がいくつになるか」
# を見て、当初の見積りより影響範囲が広がっていそうなときだけ stderr で reminder を出す
# （blocking はしない）。
#
# 設計意図:
#   旧版は「直近 30 分に solo-with-verifier / orchestra-of-agents の起動痕跡がなければ
#   毎回警告」だった。これは実装スキルの必須化を前提にした挙動で、rules/implementation-flow.md
#   が推奨へ緩和された（Claude 5 系は自己検証がモデル側に入り、検証体制は規模・リスクで足す）
#   現在はノイズになる。代わりに同ルールの「迷ったら単独で着手し、影響範囲が想定より広いと
#   分かった時点でスキルに切り替える」の「広がった時点」を検出する役割にした。
#
#   状態ファイルは持たず、git 作業ツリーの変更ファイル数（追跡済みの変更 + 未追跡の新規）を
#   実測値にする。編集対象が既に変更済み・未追跡・ignore 対象なら件数は増えないので黙る。
#   編集後の件数 M が THRESHOLD_FILES（5。rules の「5 タスク以上」を変更ファイル数で近似）以上かつその倍数の
#   ときだけ判定に進むため、reminder は 5 / 10 / 15 ファイルをまたぐ編集の 1 回だけ出る。
#   hook から呼ぶ git はすべて --no-optional-locks を付け、ユーザーの git 操作と
#   index.lock を取り合わない。
#
# 関連: rules/implementation-flow.md
#
# 非ブロッキング advisory のため set -euo pipefail は使わない。
# set -e 下だと grep/date 等の非ゼロ終了で誤って hook が落ち、reminder だけの
# 想定を超えて編集を妨げるリスクがあるため、best-effort continue を明示的に保つ。

# --- lib ブートストラップ: 実体ディレクトリを解決して lib/common.sh を source ---
# symlink 運用でも実体位置の lib/ を辿れるよう POSIX ポータブルに解決（readlink -f 非依存）。
# 本 hook は非ブロッキング advisory のため、lib/jq 解決失敗は best-effort で exit 0 continue。
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
FSTACK_HOOKS_DIR=""
if [ -n "$_self" ]; then
  FSTACK_HOOKS_DIR=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd || printf '')
fi
_fstack_lib_loaded=0
if [ -n "$FSTACK_HOOKS_DIR" ] && [ -f "$FSTACK_HOOKS_DIR/lib/common.sh" ]; then
  # shellcheck source=/dev/null
  if . "$FSTACK_HOOKS_DIR/lib/common.sh"; then _fstack_lib_loaded=1; fi
fi
# lib 未ロード or jq 不在なら advisory を諦めて素通り（ブロックしないのが正しい挙動）
if [ "$_fstack_lib_loaded" != 1 ] || ! fstack_have_jq; then
  exit 0
fi

# 30 分（1800 秒）のしきい値は FSTACK_ROUTING_WINDOW_SEC で上書き可
ROUTING_WINDOW_SEC="${FSTACK_ROUTING_WINDOW_SEC:-1800}"
# reminder を出す変更ファイル数の刻み（5 / 10 / 15 …）。5 ファイル。rules の「5 タスク以上」を変更ファイル数で近似したもの
THRESHOLD_FILES=5

INPUT=$(fstack_read_input)
TOOL_NAME=$(fstack_jq -r '.tool_name // ""' <<<"$INPUT")

case "$TOOL_NAME" in
  Edit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac

# 編集対象パス（NotebookEdit は notebook_path）。相対パスは cwd 基準で解決し、
# 除外判定と git の判定に同じパスを使う
FILE_PATH=$(fstack_jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$INPUT")
CWD=$(fstack_jq -r '.cwd // ""' <<<"$INPUT")
case "$FILE_PATH" in
  '' | /*) ;;
  *) [ -n "$CWD" ] && FILE_PATH="$CWD/$FILE_PATH" ;;
esac

# 編集対象パスをチェック — メタ系・設定系・ノート系・履歴系は除外
case "$FILE_PATH" in
  */.claude/* | */MEMORY.md | */memory/*.md | */.todo/* \
    | */handovers/* | */knowledge/*.md | */docs/*.md | */README*.md \
    | */CLAUDE.md | */prompts/*.md | */runs/*.md | */design/*.md \
    | */ONBOARDING*.md | */CHANGELOG.md | *.json | *.yaml | *.yml \
    | *.toml | *.lock | *.txt | *.ndjson | *.jsonl | *.log | *.env*)
    exit 0
    ;;
esac
[ -n "$FILE_PATH" ] || exit 0

# scope の実測は git 作業ツリーで行う。cwd が無い・git 管理外なら測れないので判定しない
{ [ -n "$CWD" ] && [ -d "$CWD" ]; } || exit 0
command -v git >/dev/null 2>&1 || exit 0
ROOT=$(git --no-optional-locks -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$ROOT" ] || exit 0

# この編集で変更集合が増えるかを判定する。失敗（リポジトリ外のパス等）→ 判定しない。
# 出力あり（既に変更済み・未追跡）や ignore 対象は件数が増えないので黙る。
# ユーザー設定 status.showUntrackedFiles=no だと未追跡が出力に出ないため明示する。
# --literal-pathspecs: `[id].tsx` や `*` を含むパスを glob として別ファイルに一致させない。
# check-ignore は引数を glob 展開せずパス文字列として判定し、literal 指定は magic 非対応の
# エラーになるため付けない。終了コードは 0=ignore 対象 / 1=対象外 / それ以外=エラー。
TARGET_STATUS=$(git --no-optional-locks --literal-pathspecs -C "$ROOT" status --porcelain --untracked-files=normal -- "$FILE_PATH" 2>/dev/null) || exit 0
[ -z "$TARGET_STATUS" ] || exit 0
git --no-optional-locks -C "$ROOT" check-ignore -q -- "$FILE_PATH" 2>/dev/null
case $? in
  1) ;;
  *) exit 0 ;;
esac

# 現在の変更ファイル数 N（追跡済みの変更 + 未追跡の新規）。HEAD が無い等で diff が失敗しても空扱い。
# NUL 区切りで数え、空白だけの名前や改行を含む名前も 1 件とする。sort と tr は LC_ALL=C で
# バイト単位に扱う（UTF-8 ロケールの tr は不正なバイト列で途中終了し、件数が少なくなる）
CHANGED_COUNT=$(
  {
    git --no-optional-locks -C "$ROOT" diff --name-only -z HEAD 2>/dev/null
    git --no-optional-locks -C "$ROOT" ls-files -z --others --exclude-standard 2>/dev/null
  } | LC_ALL=C sort -zu | LC_ALL=C tr -cd '\000' | wc -c
)
CHANGED_COUNT=${CHANGED_COUNT//[[:space:]]/}
case "$CHANGED_COUNT" in
  '' | *[!0-9]*) exit 0 ;;
esac

# 編集後の件数 M = N + 1。閾値未満、または閾値の倍数でないときは黙る
# （状態ファイルなしで、5 / 10 / 15 をまたぐ編集の 1 回だけ発火させる）
AFTER_COUNT=$((CHANGED_COUNT + 1))
[ "$AFTER_COUNT" -ge "$THRESHOLD_FILES" ] || exit 0
[ $((AFTER_COUNT % THRESHOLD_FILES)) -eq 0 ] || exit 0

SKILLS_LOG="$HOME/.claude/logs/skills.log"
if [ ! -f "$SKILLS_LOG" ]; then
  # ログがなければスキップ
  exit 0
fi

# 直近 ROUTING_WINDOW_SEC 秒以内に solo-with-verifier / orchestra-of-agents 起動があるかチェック
NOW=$(date +%s)
THRESHOLD=$((NOW - ROUTING_WINDOW_SEC))

RECENT_TRIGGER=0
# skills.log フォーマット: [YYYY-MM-DD HH:MM:SS] [SKILL] <name> | <args>
# tail で末尾 200 行に絞り、新しい順に確認
while IFS= read -r line; do
  TS_STR=$(awk -F'[][]' '{print $2}' <<<"$line")
  [ -z "$TS_STR" ] && continue
  LINE_TS=$(fstack_epoch_from_datetime "$TS_STR")
  [ "$LINE_TS" -lt "$THRESHOLD" ] && continue
  if grep -qE "solo-with-verifier|orchestra-of-agents" <<<"$line"; then
    RECENT_TRIGGER=1
    break
  fi
done < <(tail -200 "$SKILLS_LOG")

if [ "$RECENT_TRIGGER" -eq 1 ]; then
  exit 0
fi

# 警告: stderr に reminder（blocking しない）
cat >&2 <<EOF
[implementation-task-routing] この編集で作業ツリーの変更が ${AFTER_COUNT} ファイルに達し、直近 30 分以内に
solo-with-verifier / orchestra-of-agents の起動痕跡がありません。

当初の見積りより影響範囲が広がっている可能性があります（rules/implementation-flow.md）。

  - 依存があり直列的            → 単独継続で OK。検証コマンドは実行する
  - 独立性が高く並列化が活きる  → /orchestra-of-agents
  - 共通基盤・認証・課金に触る  → 検証体制を足す（/solo-with-verifier / /orchestra-of-agents）

（reminder です。単独継続で問題なければ無視して続行可能。次は変更が
  $((AFTER_COUNT + THRESHOLD_FILES)) ファイルに達したときに再表示されます）
対象ファイル: $FILE_PATH
EOF

exit 0
