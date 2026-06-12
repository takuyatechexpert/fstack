# 出力フォーマット

サブエージェントが書き出すmdファイルと、メインエージェントが生成するサマリーのフォーマット定義。

## サマリーファイル (`reviews/index.md`)

```markdown
# レビュー結果サマリー

実行日時: {YYYY-MM-DD HH:MM}
レビュー対象: {N}件

## 一覧

| # | リポジトリ | PR | 指摘数 | MUST | SHOULD | NITS | QUESTION | レビューファイル |
|---|---|---|---|---|---|---|---|---|
| 1 | {repo} | [#{番号} {タイトル}]({PR URL}) | {合計} | {MUST数} | {SHOULD数} | {NITS数} | {QUESTION数} | [{repo}_PR{番号}.md](./{repo}_PR{番号}.md) |

## MUST指摘があるPR

- [{repo} #{番号} {タイトル}](./{repo}_PR{番号}.md) - {MUST指摘の概要}

## 統計

- 総レビュー数: {N}件
- 指摘なし: {M}件
- MUST指摘あり: {K}件
```

## 各PRのレビュー結果 (`reviews/{repo}_PR{番号}.md`)

**1行目に必ず SUMMARY コメントを入れること**（サマリー生成時に Grep で抽出するため）。

> **契約:** 1行目の SUMMARY コメントは `grep -m1 'SUMMARY:' reviews/*.md` で抽出される。行位置・コメント形式・キー名（MUST/SHOULD/NITS/QUESTION/TOTAL）の変更は `index.md` 集計を壊すため禁止。キー追加時は Phase 4 の grep 処理も同時に更新すること。

```markdown
<!-- SUMMARY: MUST={N} SHOULD={N} NITS={N} QUESTION={N} TOTAL={N} -->
# PRレビュー: {repo} #{PR番号} {PRタイトル}

- **PR URL**: {PR URL}
- **作成者**: @{author}
- **ブランチ**: {head_branch} → {base_branch}
- **approve数**: {approve数}/2
- **レビュー日**: {YYYY-MM-DD}

## 概要

- 変更ファイル数: {N}件
- 変更行数: +{X} / -{Y}
- 変更カテゴリ: {カテゴリ一覧}

## PR説明

{PRのbodyをそのまま引用}

## 指摘事項

### {重要度}: {カテゴリ}
- **ファイル**: `{パス}:{行番号}`
- **内容**: {指摘内容}
- **理由**: {該当するルール}

## 変更漏れの可能性

- {変更されるべきだが変更されていないファイル・箇所}

## 影響範囲

- {変更が影響する可能性のある箇所}

## 良い点

- {良い実装のポイント}

## 総評

{全体的なコメント}
```
