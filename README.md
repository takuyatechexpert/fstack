# fstack

> Claude Code を個人の開発生産性エンジンに変える、実戦検証済みの AI スキルコレクション

## 特徴

- **Batteries Included** — コードレビュー、テスト、セッション管理、並列実装をすぐに使える
- **Battle-Tested** — 実業務で数ヶ月間、日常的に使用・改善されてきたスキルのみを収録
- **Composable** — 各スキルは独立して使えるが、組み合わせることで真価を発揮
- **Lightweight** — 外部依存ゼロ。シンボリックリンクとマークダウンとシェルスクリプトだけ

## クイックスタート

```bash
git clone https://github.com/your-org/fstack.git
cd fstack
./setup
```

setup スクリプトは fstack から `~/.claude/` へシンボリックリンクを作成します。既存の設定はそのまま保持されます。

## スキル

| カテゴリ | スキル | 説明 | コマンド |
|---------|--------|------|---------|
| Core | handover | セッション引き継ぎ。コンテキスト劣化を防ぎ、次セッションへスムーズに移行 | `/handover` |
| Core | crystallize | ナレッジ蒸留。ログとメモリを分析し、繰り返すパターンを知識に昇華 | `/crystallize` |
| Review | review-pr | PR レビュー。git worktree でブランチ全体を読み込み、プロジェクト方針に基づくフルレビュー | `/review-pr` |
| Review | pending-reviews | レビュー待ち PR の一覧取得 | `/pending-reviews` |
| Test | spec-driven-test | 仕様駆動テスト。対象の仕様分析 → テストケース設計 → 実装 | `/spec-driven-test` |
| Build | orchestra-of-agents | 並列実装。agent teams による Wave 方式の実装・テスト・レビュー | `/orchestra-of-agents` |

## ルール

ルールは `~/.claude/rules/` から Claude Code が自動的に読み込みます。fstack は既存ルールとの衝突を避けるため `fstack-` プレフィックス付きでインストールします。

| ルール | 説明 |
|--------|------|
| design-principles | SRP, DRY, クリーンアーキテクチャ, DDD, TDD, 命名規則 |
| git-workflow | コミットメッセージ規約、ブランチ戦略、PR テンプレート、コンフリクト対応 |
| testing | TDD サイクル、カバレッジ目標、テストケース設計、モック方針 |
| security | シークレット管理、入力バリデーション、OWASP Top 10 チェックリスト |
| context-management | セッション引き継ぎタイミング、コンテキスト節約テクニック |

## エージェント

| エージェント | 説明 |
|-------------|------|
| architect | 読み取り専用の設計分析エージェント。既存コードの構造分析、変更影響範囲の評価、実装方針の提案を行う（コード変更は一切しない） |

## カスタマイズ

### ルールの無効化

シンボリックリンクを削除するだけです:

```bash
rm ~/.claude/rules/fstack-testing.md
```

### プロジェクト単位の上書き

プロジェクトルートに `CLAUDE.md` や `.claude/rules/` を作成すれば、そのリポジトリでのみ fstack ルールを上書き・拡張できます。

### 独自スキルの追加

`~/.claude/skills/` に同じ `SKILL.md` 形式でスキルディレクトリを配置してください。詳しくは [ARCHITECTURE.md](ARCHITECTURE.md) を参照。

## アンインストール

```bash
./setup --uninstall
```

fstack のシンボリックリンクのみ削除します。既存の `~/.claude/` 設定には一切触れません。

## setup の主なオプション

```bash
./setup                          # グローバルインストール（デフォルト）
./setup --local                  # カレントプロジェクトの .claude/ にインストール
./setup --categories review,test # カテゴリを指定してインストール
./setup --skills review-pr       # スキルを指定してインストール
./setup --dry-run                # 実行内容のプレビュー（変更なし）
./setup --force                  # 既存リンクを上書き
./setup --uninstall              # アンインストール
```

## ロードマップ

### v0.2.0

- migrate, review-all-pending, vuln-watch, slack, agent-creator, my-skill-creator の追加
- fstack.json 設定対応
- eval フレームワーク

### v0.3.0

- コミュニティスキルの投稿・インストール機能
- repo-scanner / tech-lead の汎用化
- ドキュメントサイト

## ライセンス

[MIT](LICENSE)
