# Git ワークフロー

## コミットメッセージ

フォーマット：
```
<Prefix>: <Title> #<Issue Number>
```

例：
- `feat: Add user authentication #123`
- `feat: ユーザー認証を実装 #123`
- `fix: Resolve race condition in queue worker #456`

| Prefix | 用途 |
|--------|------|
| feat | 機能追加・修正 |
| fix | バグ修正 |
| docs | ドキュメント更新 |
| style | フォーマット修正 |
| refactor | リファクタリング |
| perf | パフォーマンス改善 |
| test | テストコードの追加・修正 |
| chore | ビルドツール・依存関係の更新 |
| ci | CI/CD |
| build | ビルドシステム |

### コミット前の確認プロセス

コミット前に必ず以下を実行する：

```bash
git status
git diff
git diff --cached
```

### コミット時の承認フロー

1. コミットメッセージをユーザーに提示する
2. コミット対象ファイル一覧を表示する
3. ユーザーの明示的な承認を待つ
4. 修正要求があれば対応し、再度承認を求める

## ブランチ命名規則

| 種別 | フォーマット | 例 |
|------|------------|-----|
| 機能追加 | `feature/<description>` | `feature/user-auth` |
| バグ修正 | `fix/<description>` | `fix/login-redirect` |
| 緊急修正 | `hotfix/<description>` | `hotfix/security-patch` |

## ブランチの切り元

作業ブランチは原則、最新のデフォルトブランチ（`main` or `develop`）から切る。ブランチ作成前にデフォルトブランチを最新化すること。

```bash
git switch main
git pull origin main
git switch -c feature/user-auth
```

## 禁止事項

- `CLAUDE.md` のコミット・プッシュ禁止（ローカル開発ガイド専用）
- `force push` 禁止（`--force`, `--force-with-lease`, `-f` すべて）
- `git config` の変更禁止（user.name, user.email など）
- 直接マージ禁止（必ず PR 経由）

## push 禁止ブランチ

以下のブランチへの push は絶対に行わない：

- `main`
- `master`
- `develop`

## PR ルール

- タイトルは対応する GitHub Issue のタイトルと一致させる
- レビュワーのアサインを推奨（デフォルト: 1 approve でマージ可。プロジェクトに応じてカスタマイズ）

### PR 説明テンプレート

```markdown
### 概要
* Issue内容の概要を簡潔に記載

### やったこと
* このPRで実装した変更内容を具体的に記載

### やらなかったこと
* このPRで対応しなかった内容（今後の課題など）

### reviewして欲しいこと
* レビュー時に特に確認してほしいポイント

### テスト手順
* リリース時の手動テスト手順
* 事前準備・実行手段・確認方法
```

## GitHub 操作

GitHub に関する操作は **MCP または `gh` コマンドを使用する**（認証の自動処理・APIバージョン互換性・適切なエラーハンドリングのため）。

```bash
gh pr view 123
gh issue view 456
gh issue list --state open
gh pr status
```

## コンフリクト対応

コンフリクトが発生した場合、独断で解決せずユーザーに報告してガイダンスを求める。
