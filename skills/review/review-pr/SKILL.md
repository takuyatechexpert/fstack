---
name: review-pr
description: PRをレビューするスキル。git worktreeを使いPRブランチのソースコード全体を読み込み、プロジェクトの方針・特性・アーキテクチャを把握した上で最適なレビューを行う。変更漏れ・影響範囲もチェックする。ユーザーが「PRレビューして」「PR #123 をレビュー」「このPRをチェックして」「レビューお願い」と言ったとき、またはGitHub PR URLを指定したときに使用する。/review-prコマンドでも起動可能。
---

# PR Review

worktreeでPRブランチ全体にアクセスし、プロジェクトの方針・特性を把握した上でレビューする。

## 複数PR指定時

各PRを**個別のサブエージェント**で並列レビューする。サブエージェントには:
- 本スキルのワークフロー全体（Phase 1〜7）を忠実に実行させる
- Phase 6 の出力フォーマット全文・レビュー優先度一覧を含める
- プロジェクト固有チェックリスト（`.claude/review-checklist.md`）がある場合、サブエージェント自身にReadさせる（要約して渡さない）

## ワークフロー

### Phase 1: PR概要把握

PR番号またはURLから `pull_request_read` で以下を取得:
- PR概要（タイトル、説明、head/baseブランチ名）
- 変更ファイル一覧

PR番号のみの場合は `git remote get-url origin` からowner/repoを取得。

### Phase 2: worktree作成

```bash
git fetch origin {head_branch}
git worktree add /tmp/review-pr-{PR番号} origin/{head_branch}
```

以降のPhaseでは `/tmp/review-pr-{PR番号}` をルートとしてファイルを読む。

### Phase 3: プロジェクト特性の把握と差分分析

#### 3-1: プロジェクト特性の把握

worktree内で以下を確認:
1. **プロジェクト設定**: CLAUDE.md、README.md、`.claude/` 配下からルール・方針を把握
2. **ディレクトリ構造**: Glob/lsでアーキテクチャパターン（DDD, Clean Architecture, MVC等）を特定
3. **技術スタック判定**: `package.json`、`composer.json`等から特定
4. **既存コードのパターン**: 変更ファイル周辺の既存ファイルから命名規則・実装パターンを理解
5. **プロジェクト固有チェックリスト**: `.claude/review-checklist.md` が存在すればReadで読み込む

#### 3-2: 差分の分析とファイル分類

```bash
cd /tmp/review-pr-{PR番号}
git diff origin/{base_branch}...HEAD --name-only
git diff origin/{base_branch}...HEAD
```

変更ファイルをプロジェクトのアーキテクチャに応じたカテゴリに分類する。

### Phase 4: コードレビュー（worktree内）

Phase 3-1で把握したプロジェクト特性・方針・ルールに基づいてレビューする。

- プロジェクト固有チェックリスト（`.claude/review-checklist.md`）がある場合、該当項目を適用
- 既存パターンとの一貫性確認
- 変更ファイル全文のRead
- import先の実装確認
- ディレクトリ構造のGlob検証

### Phase 5: 影響範囲・変更漏れチェック（worktree内）

**このPhaseがworktreeフローの最大の価値。** 変更ファイルから連鎖的に関連ファイルをチェックする。

変更ファイルからGrepで利用箇所を連鎖検索し、影響範囲を特定する:
- 変更されたクラス・関数・メソッドの利用箇所をGrep
- 変更されたインターフェース・型定義の実装箇所をGrep
- 変更されたエクスポートの利用箇所をGrep
- Globでディレクトリ整合性確認
- Readで関連ファイルの実装を確認

### Phase 6: レビュー結果の出力

```
## PRレビュー: #{PR番号} {PRタイトル}

### 概要
- 変更ファイル数: N件 / 変更行数: +X / -Y
- 変更カテゴリ: {該当するもの}

### 指摘事項
#### {重要度}: {カテゴリ}
- **ファイル**: `{パス}:{行番号}`
- **内容**: {指摘内容}
- **理由**: {該当するルール}

### 変更漏れの可能性
### 影響範囲
### 良い点
### 総評
```

**重要度**: MUST（修正必須）/ SHOULD（改善推奨）/ NITS（軽微、任意）/ QUESTION（確認事項）

### Phase 7: クリーンアップ

成功・失敗問わず `git worktree remove /tmp/review-pr-{PR番号}` を実行。残っている場合は `--force` で強制削除。

## 落とし穴

- **worktree残留**: 前回のレビューでクリーンアップに失敗したworktreeが残っていると作成時にエラーになる。Phase 2 開始時に既存worktreeの存在を確認し、あれば先に削除する
- **base_branchの未fetch**: `git diff origin/{base_branch}...HEAD` は base_branch がローカルにfetchされていないと正しい差分が取れない。diff前に `git fetch origin {base_branch}` も実行する
- **サブエージェントへのチェックリスト要約**: チェックリストを要約してサブエージェントに渡すと項目が欠落し精度が落ちる。必ずサブエージェント自身にReadさせる

## レビュー観点の優先度

1. **アーキテクチャ違反** (MUST) - アーキテクチャパターンからの逸脱、責務の混在
2. **コーディングルール違反** (MUST) - プロジェクト固有のルール違反
3. **パフォーマンス問題** (MUST/SHOULD) - ウォーターフォール、バンドル肥大、不要な再レンダー等
4. **変更漏れ** (MUST/SHOULD) - 対応する変更が欠落
5. **命名規則違反** (SHOULD) - プロジェクトの命名パターンからの逸脱
6. **テスト品質** (SHOULD) - テスト方針との不整合、カバレッジ不足
7. **影響範囲の注意** (QUESTION) - 変更が他に波及する可能性
8. **その他改善** (NITS) - 読みやすさ、ベストプラクティス
