# fstack

> Claude Code を個人の開発生産性エンジンに変える、実戦検証済みの AI スキルコレクション

> **Note for English speakers:** The skill, rule, and agent instructions in this repository are written in Japanese. Claude reads and follows them regardless of the language you converse in, but be aware the prompt content itself is Japanese when reviewing or customizing it.

## 特徴

- **Batteries Included** — コードレビュー、テスト、セッション管理、並列実装をすぐに使える
- **Battle-Tested** — 実業務で数ヶ月間、日常的に使用・改善されてきたスキルのみを収録
- **Composable** — 各スキルは独立して使えるが、組み合わせることで真価を発揮
- **Lightweight** — 外部依存ゼロ。シンボリックリンクとマークダウンとシェルスクリプトだけ

## クイックスタート

```bash
git clone https://github.com/YOUR_ORG/fstack.git
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
| Review | review-all-pending | レビュー待ち PR を並列で一括レビュー、結果を `reviews/` に出力 | `/review-all-pending` |
| Test | spec-driven-test | 仕様駆動テスト。対象の仕様分析 → テストケース設計 → 実装 | `/spec-driven-test` |
| Build | build-planner | 実装着手前の設計・計画書作成・実装規模の粒度判定。後段の実装スキルへ引き渡し | `/build-planner` |
| Build | orchestra-of-agents | 並列実装。agent teams による Wave 方式の実装・テスト・レビュー | `/orchestra-of-agents` |
| Build | solo-with-verifier | 軽量実装。Implementer + Verifier の2エージェント反復で小〜中規模修正の品質を担保 | `/solo-with-verifier` |
| Meta | my-skill-creator | スキル新規作成・更新・ベンチマーク・説明文最適化を一貫サポート | `/my-skill-creator` |
| Meta | skill-auditor | 既存スキルの健康診断・改善計画策定・Step 単位実行 | `/skill-auditor` |
| Meta | agent-creator | カスタムエージェント (`.claude/agents/*.md`) の作成・更新・リント | `/agent-creator` |
| Meta | review-hooks | hooks 設定のレビュー・最適化・`settings.json` 更新 | `/review-hooks` |

## ルール

ルールは `~/.claude/rules/` から Claude Code が自動的に読み込みます。fstack は既存ルールとの衝突を避けるため `fstack-` プレフィックス付きでインストールします。

| ルール | 説明 |
|--------|------|
| design-principles | SRP, DRY, クリーンアーキテクチャ, DDD, TDD, 命名規則 |
| git-workflow | コミットメッセージ規約、ブランチ戦略、PR テンプレート、コンフリクト対応 |
| testing | TDD サイクル、カバレッジ目標、検証手段、テストケース設計、モック方針 |
| implementation-flow | 実装タスクの規模別の進め方（単独実装 / solo-with-verifier / orchestra-of-agents）、スコープとテストの範囲、検証体制を足す判断 |
| work-discipline | バグ修正の3ステップ（現状修正→根本原因→再発防止）、横展開の徹底（grep で全箇所洗い出し）、変更前の確認（既存同種ファイル・既存コード検索・並行編集確認） |
| security | シークレット管理、スキル開発時の認証情報ハンドリング、OWASP Top 10 |
| context-management | セッション引き継ぎ（150K トークン付近で `/handover`）、ツール使用方針（並列実行・委譲基準）、サブエージェント同時 spawn 上限、deferred tools / ToolSearch |
| memory | Auto Memory（構造化メモリ）の4種運用と crystallize との境界 |
| plan-mode | Plan Mode の発動基準・ワークフロー・並列実装系スキルとの棲み分け |
| document-writing | 人が読む文書（資料・議事録・PR説明・レポート）の構成原則、網羅より取捨選択、発見可能性の担保 |
| file-operations | 破壊的操作の取扱い原則（コアエンジニア向け） |

## エージェント

| エージェント | 説明 |
|-------------|------|
| architect | 読み取り専用の設計分析エージェント。既存コードの構造分析、変更影響範囲の評価、実装方針の提案を行う（コード変更は一切しない） |
| db-schema-investigator | 読み取り専用の DB スキーマ調査エージェント。テーブル定義・カラムの型/桁/制約を create だけでなく後続の変更まで追い、実 DB で裏取りして根拠付きで報告する（コード変更は一切しない） |

### Eval ワークフロー

スキル評価・ベンチマーク比較は Anthropic 公式の [skill-creator plugin](https://github.com/anthropics/claude-code-plugins) に含まれる analyzer / comparator / grader エージェントを利用してください。fstack では独自に再実装せず、上流のプラグインに委ねる方針です。

```
~/.claude/settings.json の enabledPlugins に追加:
"skill-creator@claude-plugins-official": true
```

## オプション: Hooks

`hooks/` 配下に実戦投入済みの hook を同梱しています（opt-in）。利用者が `~/.claude/settings.json` で必要なものだけ wire up します。

### セキュリティ系

| Hook | 用途 |
|---|---|
| `validate-bash.sh` | Bash の危険パターン（パイプ経由のシェル実行・任意コード実行・curl 詳細トレース・set -x 等）をブロック |
| `check-secret-patterns.sh` | `git commit/push` 時にプロジェクト直下の `.claude/secret-patterns.txt` で定義したパターンを git の内容（commit=index／push=HEAD ツリー。全履歴は非対象）に対して検査。deny 理由は `<file>:<line> (pattern #<n>)` のみでシークレット値も pattern 文字列も出さない。jq 不在・parse 失敗・作業ディレクトリ/git root 解決不能（空 CWD 含む）時は exit 2 で fail-closed |
| `validate-file-write.sh` | `.env` / SSH 鍵 / 証明書 / `settings.json` / crontab 等の機密ファイル書き込みを deny/ask |
| `mask-secrets.sh` | API キー・トークン・JWT・AWS キー等のリテラル値を `[MASKED]` に置換（パイプ用ユーティリティ・JSON 構造は保持） |
| `mask-mcp-output.sh` | MCP ツール出力に混入したシークレットを LLM コンテキスト到達前にマスク（マスカー不在時は fail-closed でレスポンスを秘匿） |

### コンテキスト管理系

| Hook | 用途 |
|---|---|
| `bootstrap-env.sh` | `SessionStart` で DB / 主要言語 / フレームワーク / Makefile 等を `additionalContext` に注入。24h キャッシュ |
| `pre-compact-handover.sh` | 自動圧縮直前に handover 実行を強く指示 |
| `post-compact-warning.sh` | 自動圧縮後に handover 実行を強く指示・ログ記録 |

### コード品質系

| Hook | 用途 |
|---|---|
| `check-debug-code.sh` | JS/TS の `console.log` / `debugger` 残存検出（検出時は stderr 警告 + exit 2、ブロックはしない）。警告は行番号のみで行内容は出さない |
| `pre-commit-lint.sh` + `lint/` | `git commit` 時に多言語 lint を SRP 分離 dispatcher で実行（js/php/python/rust）。`lint/config.json` でプロジェクト別 override。lint 失敗時は deny でブロック。jq 不在・parse 失敗・作業ディレクトリ/git root/`lint/` 解決不能時は exit 2 で fail-closed |
| `check-implementation-routing.sh` | コードファイルの編集で git 作業ツリーの変更ファイル数が 5 / 10 / 15… に達し、直近 30 分に実装スキル（solo-with-verifier / orchestra-of-agents）の起動痕跡がないときだけ stderr に reminder（blocking しない・git 管理外では何もしない）。Claude のコンテキストには入らないなどの制約は hooks/README.md を参照 |

### ログ系

| Hook | 用途 |
|---|---|
| `skill-log.sh` | スキル使用ログを `~/.claude/logs/skills.log` に追記する簡易ユーティリティ |
| `log-knowledge-read.sh` | `CLAUDE_KNOWLEDGE_DIR`（デフォルト `~/knowledge`）配下の Read を `~/.claude/logs/knowledge.log` に記録 |

ログ先・キャッシュ先・reminder 時間窓などは環境変数（`FSTACK_LOG_DIR` / `FSTACK_CACHE_DIR` / `FSTACK_ROUTING_WINDOW_SEC` / `CLAUDE_KNOWLEDGE_DIR`）で上書きできます。詳細・設定例・共通ライブラリの公開契約は [hooks/README.md](hooks/README.md) を参照。

## ドキュメント

| ドキュメント | 説明 |
|-------------|------|
| [docs/claude5-migration-guide.md](docs/claude5-migration-guide.md) | Opus 4.7 → Claude 5 系（Opus 5.5 / Fable 5.1 など）で変わった挙動と fstack での対応、これからスキル・ルールを書くときの推奨（effort の付け方・検証指示・スコープの除外指示） |
| [docs/prompt-migration-guide.md](docs/prompt-migration-guide.md) | Opus 4.6 → 4.7 時点の記録。当時の挙動変化と、4.7 でプロンプト・スキル・ルールを書くときの実務ガイド。次のモデル更新で既存資産を再調整する際の観点（挙動差の洗い出し・優先度判定・落とし穴）の参照テンプレートとしても使える |

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

`--skills` / `--categories` によるフィルタが作用するのは **スキルのインストールのみ** です。ルール（`fstack-` プレフィックス付き）とエージェントはフィルタ指定の有無にかかわらず常にインストールされます。

## ロードマップ

### v0.2.0

- [x] review-all-pending 追加
- [x] meta カテゴリ新設（my-skill-creator / skill-auditor / agent-creator / review-hooks）
- [x] 実戦投入済み hook 群を追加（bootstrap-env / pre-compact-handover / post-compact-warning / check-debug-code / pre-commit-lint / validate-file-write / mask-mcp-output / skill-log / check-implementation-routing / log-knowledge-read）
- [ ] hook-digest 追加（依存スクリプトの汎用化要）
- [ ] migrate, vuln-watch, slack の追加検討
- [ ] fstack.json 設定対応
- [ ] eval ワークフロー: Anthropic 公式 skill-creator plugin への薄いラッパー（独自再実装はしない方針）

### v0.3.0

- コミュニティスキルの投稿・インストール機能
- repo-scanner / tech-lead の汎用化
- ドキュメントサイト

## ライセンス

[MIT](LICENSE)
