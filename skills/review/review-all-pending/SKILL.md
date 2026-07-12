---
name: review-all-pending
description: "レビュー待ちPRを一括で自動レビューし、結果をカレントディレクトリにmdファイルとして保存するスキル。pending-reviewsとreview-prを組み合わせ、各PRに対してサブエージェントを使って並列レビューを実行する。10件超の場合は10件単位のチャンクでループ処理する。ユーザーが「全部レビューして」「一括レビュー」「review all」「pending全部レビュー」「まとめてレビュー」と言ったときに使用する。以下では起動しない: 特定のPRを1つだけレビューする場合（review-prを使用）、レビュー待ち一覧の確認のみで実レビュー不要な場合（pending-reviewsを使用）。"
---

# レビュー待ちPR一括レビュースキル

`pending-reviews` で取得したレビュー待ち PR を、`review-pr` のレビュー基準で一括レビューし、結果をカレントディレクトリの `reviews/` に markdown として保存する。

## 参照ファイル（毎回 Read）

- **出力フォーマット定義**: `${CLAUDE_SKILL_DIR}/references/output-format.md`

各 PR レビュー md・`index.md` サマリーのテンプレートと、1 行目 SUMMARY コメントの仕様がここで定義されている。Phase 3 前に Read する。

## 前提

- コード系 PR のレビューは `/review-pr` に委譲（worktree 管理含む）。`/review-pr` は `git worktree add` で PR ブランチを展開するため、対象リポジトリがローカルに取得済み（clone 済み）であることが前提
- レビュー結果は **カレントディレクトリ** の `reviews/` に保存

## コンテキスト保護の基本ルール

レビュー結果は数百行になりうる。本スキルはメインコンテキストへの取り込みを防ぐために以下を徹底する。

1. **サブエージェントはレビュー本文を Write で出力ファイルに書く**
2. **サブエージェントの返却値は 1 行のみ**: `DONE|...` または `ERROR|...`
3. **メイン側で md 全文を Read しない**。集計は `grep` で 1 行目の SUMMARY コメントを抽出する

## ワークフロー

### Phase 1: レビュー待ち PR 一覧の取得

**使用ツール**: `Skill` (`/pending-reviews`)

`/pending-reviews` を呼び出す。フィルタリング（レビュワーアサイン確認・approve 数が閾値未満・draft 除外）は pending-reviews 側で完結するため（approve の閾値は pending-reviews のデフォルト 1・`approve_threshold` で調整可）、ここで検索クエリを直接叩かない。返却された PR 一覧（リポジトリ・PR 番号・タイトル・URL・作成者）を以降の入力として使う。

ユーザーが明示的に件数指定した場合（例: 「10 件だけ」）は先頭 N 件に絞る。

### Phase 2: PR の分類

| 種別 | リポジトリ | レビュー方式 |
|------|-----------|------------|
| **コード系** | アプリ/サービスコードを含むリポジトリ | `/review-pr` でフルレビュー |
| **ドキュメント系** | 設計書・仕様書・試験項目書など Markdown 中心のリポジトリ | 差分ベースの軽量レビュー |

分類の判断基準: リポジトリにアプリケーション/サービスのソースコードが含まれる場合はコード系。設計書・仕様書・試験項目書などの Markdown 中心のリポジトリのみドキュメント系として扱う。

### Phase 3: 並列レビュー実行

**使用ツール**: `Agent` (`run_in_background: true`), `Bash`

開始前に `mkdir -p reviews` で出力先を準備する。

#### 実行構造（2 階層ループ）

```
外側: 10件チャンク（直列） ← overload/rate limit 回避
  内側: 5件バッチ（並列）   ← サブエージェント並列実行
```

**起動順序**（N 件の PR を処理する場合）:

1. N を 10 件ずつチャンク化（例: 27 件 → `[10, 10, 7]`）
2. 各チャンク内を 5 件ずつバッチに分ける（例: 10 件なら `[5, 5]`、7 件なら `[5, 2]`）
3. **1 バッチの全完了を待ってから次バッチ**を起動する
4. **1 チャンクの全完了を待ってから次チャンク**へ進む
5. 各チャンク完了時に中間進捗を 1 行報告（例: `チャンク 1/3 完了: 10件レビュー済み`）
6. 全チャンク完了後に Phase 4（サマリー生成）を 1 回だけ実行

**バッチ並列起動の具体手順**: バッチ 5 件を起動する場合、**同一メッセージ内で Agent tool を 5 回呼び出し**、すべて `run_in_background: true` を指定する。

**完了検知**: サブエージェント ID を記録し通知ベースで待つ。どうしてもポーリングが必要な場合は `Read` で `reviews/{repo}_PR{number}.md` の末尾 5 行のみ確認する（`limit` パラメータを使用し、全文 Read を避ける）。

#### バッチ完了後の検証

各バッチ完了後に以下を実行する。

```bash
# 書き出し漏れ検出（1行目 SUMMARY がないファイル）
grep -L '^<!-- SUMMARY:' reviews/*.md

# DONE/ERROR 行の合計件数が投入 PR 数と一致するか確認
# （メイン側で DONE/ERROR を配列に蓄積しておき、件数突合）
```

欠落があれば該当 PR の再レビュー、または `ERROR` として記録する。

#### 各サブエージェントへ渡すパラメータ

```
- owner: {owner}
- repo: {repo}
- PR番号: {number}
- PRタイトル: {title}
- PR URL: {url}
- レビュー種別: code | docs
- 出力ファイルパス: {cwd}/reviews/{repo}_PR{number}.md
- 出力フォーマット参照: ${CLAUDE_SKILL_DIR}/references/output-format.md
```

#### サブエージェント共通ルール（指示に必ず含める）

- **1 行目に `<!-- SUMMARY: MUST={N} SHOULD={N} NITS={N} QUESTION={N} TOTAL={N} -->` を入れる**（`index.md` 生成の grep 依存のため必須。output-format.md 準拠）
- レビュー本文は output-format.md のテンプレートに従って `Write`（メインに返さない）
- **書き出し完了後、以下 1 行のみを stdout に返す**:
  ```
  DONE|{repo}|{PR番号}|{MUST数}|{SHOULD数}|{NITS数}|{QUESTION数}|{総指摘数}
  ```
  エラー時: `ERROR|{repo}|{PR番号}|{エラー概要}`

#### サブエージェントの処理（コード系）

1. `Skill` で `/review-pr` を実行し、PR URL を渡す
2. `/review-pr` は結果を会話中に出力するため、その出力内容を output-format.md のテンプレートに整形し直して `Write` する（1 行目 SUMMARY 必須）
3. DONE 行を返却

#### サブエージェントの処理（ドキュメント系）

1. `mcp__github__pull_request_read` で PR 情報を取得:
   - `get`: PR 概要
   - `get_files`: 変更ファイル一覧
   - `get_diff`: 差分
2. レビュー観点（後述）で差分をレビュー
3. output-format.md のテンプレートに従い `Write`（1 行目 SUMMARY 必須）
4. DONE 行を返却

### Phase 4: サマリーファイル生成

**使用ツール**: `Bash` (grep), `Write`

全バッチ完了後、`reviews/index.md` を生成する。

```bash
# 各ファイルの 1 行目サマリーを抽出
grep -m1 '^<!-- SUMMARY:' reviews/*.md

# SUMMARY 件数が処理件数と一致することを確認
grep -c '^<!-- SUMMARY:' reviews/*.md | awk -F: '{s+=$2} END {print s}'
```

1. 上記 grep 結果を output-format.md の `index.md` テンプレートに埋める
2. DONE 行の集計と突合する
3. md ファイル全文は Read しない
4. `ERROR` を受信した PR も `index.md` の表に 1 行追加する（「状態」列に `エラー` と記入）

## レビュー観点

### コード系

`/review-pr` に完全委譲。チェックリスト・影響範囲ルールは review-pr の references/ を参照。

### ドキュメント系

1. **記載漏れ** (MUST) — 必須セクション（概要、リクエスト/レスポンス定義等）の欠落
2. **整合性** (MUST) — パラメータ名・型・パスの不一致
3. **関連PR対応** (SHOULD) — 関連するコードPRとの整合性
4. **記述の正確性** (SHOULD) — 曖昧な記述・矛盾
5. **フォーマット** (NITS) — 体裁・表記ゆれ

## eval 方針

本スキルは実 PR（生きた GitHub 状態）を対象とするため、出力品質の静的 eval は設けない。モック fixture で `reviews/*.md` 生成を検証してもレビュー本体は `/review-pr` 側のロジックであり、本スキルの責務（分割・並列・集計）の劣化検出には寄与しない。トリガー精度は `evals/trigger-eval.json` で担保する。

## ログ記録

> スキル起動ログは PostToolUse (Skill) hook が自動記録するため手動記録不要。

- 成功時: `~/.claude/hooks/skill-log.sh review-all-pending REVIEW-ALL "{実行時間}s {N}件レビュー完了 (MUST指摘あり: {M}件)"`
- 部分エラー時: `~/.claude/hooks/skill-log.sh review-all-pending REVIEW-ALL "{実行時間}s {N}件中{M}件完了, {K}件エラー"`
- エラー時: `~/.claude/hooks/skill-log.sh review-all-pending ERROR "{エラー内容}"`

実行時間はスキル開始時に `date +%s` で取得した開始時刻からログ書き込み時点までの経過秒を記録する。

## Pitfalls

- **`/review-pr` の出力は会話向け** — 会話に出力される内容を、サブエージェント内で output-format.md 準拠に整形して `Write` する必要がある。そのまま終了すると md が作られない
- **1 行目 SUMMARY コメントの欠落** — `reviews/index.md` 生成は grep 依存のため、欠落すると集計が壊れる。サブエージェント指示に必ず含め、バッチ完了後に `grep -L '^<!-- SUMMARY:' reviews/*.md` で検証する
- **並列数は 5・バッチ待機必須** — 全件同時起動するとリソース逼迫が起きる。バッチ完了を待ってから次バッチを起動する
- **10 件超はチャンク分割** — `[10, 10, 7]` 方式で直列に回す。1 チャンクが終わるまで次チャンクの起動を待つ
