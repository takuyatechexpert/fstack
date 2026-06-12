---
name: pending-reviews
description: GitHubで自分がレビュワーとしてアサインされており、かつapprovedが必要数に達していないPRを一覧取得するスキル。ユーザーが「レビュー待ちのPR」「自分がレビュワーのPR」「pending reviews」「レビューすべきPR」と言ったときに使用する。
model: haiku
---

# レビュー待ちPR一覧取得スキル

GitHubで自分がレビュワーとしてアサインされており、かつapproveが必要数未満のオープンPRを一覧取得する。

## ワークフロー

### Phase 0: ユーザー情報の取得

```bash
GITHUB_USERNAME=$(gh api user -q .login)
```

以降のPhaseでは `$GITHUB_USERNAME` を使用する。

### 1. レビュー待ちPRの検索

`search_pull_requests` を使用して、レビューリクエストされているPRを検索する。

**検索クエリ:**
```
review-requested:{GITHUB_USERNAME} is:open draft:false
```

さらに、すでにレビュー済みだがまだマージされていないPRも対象にするため、以下も検索する:
```
reviewed-by:{GITHUB_USERNAME} is:open draft:false
```

両方の結果をマージし、重複を排除する。

### 2. 各PRのレビュー状態を確認

検索結果の各PRに対して、`pull_request_read` (method: `get_reviews`) でレビュー一覧を取得する。

**approve数のカウントルール:**
- `state` が `APPROVED` のレビューをカウント
- 同一ユーザーが複数回approveしている場合、そのユーザーの最新のレビューのみを有効とする
  - 例: ユーザーAが approve → request changes → approve した場合、最新の approve を採用
- つまり「ユニークユーザーによる最新レビューがAPPROVEDであるもの」の数を数える

### 3. フィルタリング

以下の条件でフィルタリングする:
- approve数が **1未満** のPRのみを残す（デフォルト閾値: 1。プロジェクトで2 approve必須の場合は `CLAUDE.md` に `approve_threshold: 2` を記載して調整可能）
- **draft PRは除外する**

### 4. 結果の出力

以下の形式で結果を表示する:

```
## レビュー待ちPR一覧

| # | リポジトリ | PR | approve数 | 作成者 | 更新日 |
|---|---|---|---|---|---|
| 1 | {owner}/{repo} | [#{番号} {タイトル}]({URL}) | {approve数}/1 | @{作成者} | {更新日} |
| 2 | ... | ... | ... | ... | ... |

合計: {N}件
```

PRがない場合:
```
## レビュー待ちPR一覧

レビュー待ちのPRはありません。
```

## 使用例

```
/pending-reviews
レビュー待ちのPRを見せて
自分がレビュワーのPR一覧
```

## 注意事項

- GitHub Search APIはインデックスの遅延により、直近の変更が即座に反映されないことがある
- PRの数が多い場合、レビュー状態の取得に時間がかかる場合がある
- 特定のorgに絞り込む場合は検索クエリに `org:{org_name}` を追加する
