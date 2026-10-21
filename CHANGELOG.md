# Changelog

このプロジェクトの主要な変更を記録します。フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に準拠し、[Semantic Versioning](https://semver.org/lang/ja/) を採用します。

バージョンタグはまだ発行していないため、これまでの成果はすべて `[Unreleased]` にまとめています。

## [Unreleased]

### Added

- CI ワークフロー（`.github/workflows/ci.yml`）。push / pull request で shellcheck・SKILL.md フロントマターの YAML 検証・エージェント lint・bash テストを実行し、リグレッションを自動で検知します。
- コントリビューションガイド（`CONTRIBUTING.md`）と本 CHANGELOG。
- hooks 共通ライブラリ `hooks/lib/common.sh`。jq のパス解決・deny/ask JSON の発行・GNU/BSD コマンド差の吸収を各 hook から共有します。
- setup のエンドツーエンドテスト。`--dry-run` / `--force` / スキルフィルタ / 前提コマンド不在時の挙動を隔離環境で検証します。
- ナレッジ読み込みログ hook（`log-knowledge-read.sh`）と実装ルーティング確認 hook（`check-implementation-routing.sh`）。
- Claude 5 系（Opus 5.5 / Fable 5.1 など）向けの調整ガイド（`docs/claude5-migration-guide.md`）。変わった挙動と fstack での対応、これからスキル・ルールを書くときの推奨（effort の付け方・検証指示・スコープの除外指示）をまとめました。`docs/prompt-migration-guide.md` は Opus 4.6 → 4.7 時点の記録として残しています。
- `rules/implementation-flow.md` に「スコープとテストの範囲」（必須）と「検証体制を足す判断」を追加しました。頼まれていない修正・拡張・テストのコミットを抑え、検証エージェントを足す条件を規模とリスクで示します。
- CLAUDE.md テンプレートに、依頼の範囲を黙って変えない・ターンを「〜します」で終えない・状況を聞かれても作業を続ける・最後のまとめを自己完結にする・小〜中規模の変更は対象箇所を Edit する、の規律を追加しました。

### Changed

- `setup --force` が既存の実体ファイルを削除せず、タイムスタンプ付きバックアップへ退避してから上書きするようになりました。退避先パスは警告として表示され、復元できます。
- `setup --dry-run` を非対話で完結するようにしました。対話プロンプトを一切出さず、既存リンクとの衝突を含めて実行予定の内容だけを表示します。
- 前提コマンドのうち `claude` CLI が未検出でも `setup` を中断せず警告にとどめるようにしました。必須は `git` のみです。
- hooks が macOS 専用コマンド（`md5` / `stat` / `date` など）に依存しないよう、コマンドの成否で分岐する feature-detect 方式へ統一し、Linux でも同じ挙動になるようにしました。
- hooks のシェバンを `#!/usr/bin/env bash` に統一しました。
- README / ARCHITECTURE をリポジトリの実体（ディレクトリ構成・エージェントのフロントマター記法）に同期しました。
- `--skills` / `--categories` フィルタの適用範囲がスキルのみであること（ルールとエージェントは常にインストールされること）を README に明記しました。
- 実装スキル（solo-with-verifier / orchestra-of-agents）の起動を「必須」から「推奨」に変えました。小〜中規模は単独実装でよく、検証体制は規模とリスクに応じて足します。各スキルの description と build-planner の引き渡し基準もこれに合わせました。
- `check-implementation-routing.sh` が reminder を出す条件を変えました。編集のたびではなく、その編集で git 作業ツリーの変更ファイル数が 5 / 10 / 15… に達し、直近 30 分（`FSTACK_ROUTING_WINDOW_SEC`）に実装スキルの起動痕跡がないときだけ出します。git 管理外では何もしません。
- コンテキスト管理の基準を変えました。`/handover` の目安をコンテキスト使用率 65% から 150K トークン付近（200K トークンに到達させない）に変え、サブエージェント委譲の判断基準を「価値が明確なときだけ」に差し替えて同時 spawn 上限を加えました。handover の引き継ぎ文書には「試して捨てた案」の節と、ユーザーの決定・制約を発言に近い形で残す指示を足しました。
- effort の付け方の基準（`skill-standards.md`）を、モデルごとに既定値が違う前提（Opus 5.5 は `medium`、Fable 5.1 は `high`）で書き直しました。エージェント lint は `effort` フィールドと `fable` モデルを受け付け、無効な `effort` の値を W011（WARN）で知らせます。`architect` に `effort: high`、`db-schema-investigator` に `effort: medium` を明示しました。
- `rules/document-writing.md` に、書式の使い所・言葉どおりに書く・長さをタスクに見合わせる、の原則を足しました。あわせて rules にあった特定モデル（Opus 4.7）を前提にした書き方を、Claude Code の機能としての書き方に直しました。
- review-pr を、PR 内容に応じて選ぶ観点別 worker（最大 8 種）の並列レビューと、verifier による偽陽性チェックの構成に刷新しました。worktree はリポジトリ内の `.worktrees/` に作り、マージ済み PR・submodule・base より遅れたブランチへの対処を加えました。Laravel/DDD・React/Next.js・Flutter・IaC・設計書・試験ドキュメント別のチェックリストを `references/` に分け、`codex` 委譲モード（別途 `review-codex` スキルが必要）を追加しました。

### Fixed

- セキュリティ系 hooks のサイレント故障を修正しました。標準入力の二重読み込みによる無効化、マスク後の JSON 破壊、MCP 出力パース失敗時の素通り（fail-open）、エスケープ JSON の未マスクなど、hook が実質的に機能しなくなるケースを解消しました。
- `validate-bash.sh` / `validate-file-write.sh` / `check-secret-patterns.sh` を fail-closed 化しました。jq 不在・不正 JSON・作業ディレクトリ解決不能などの異常時は素通りせず停止します。
- サブディレクトリや `git -C` 起点、symlink 経由の実行でも hooks が正しく動作するようにしました。
- `setup` を `curl | bash` のような非対話環境で実行しても、同意なしに `settings.json` を書き換えないようにしました。
- 全 SKILL.md のフロントマターを strict YAML でパースできるよう修正しました（description のクォート化）。
