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

### Changed

- `setup --force` が既存の実体ファイルを削除せず、タイムスタンプ付きバックアップへ退避してから上書きするようになりました。退避先パスは警告として表示され、復元できます。
- `setup --dry-run` を非対話で完結するようにしました。対話プロンプトを一切出さず、既存リンクとの衝突を含めて実行予定の内容だけを表示します。
- 前提コマンドのうち `claude` CLI が未検出でも `setup` を中断せず警告にとどめるようにしました。必須は `git` のみです。
- hooks が macOS 専用コマンド（`md5` / `stat` / `date` など）に依存しないよう、コマンドの成否で分岐する feature-detect 方式へ統一し、Linux でも同じ挙動になるようにしました。
- hooks のシェバンを `#!/usr/bin/env bash` に統一しました。
- README / ARCHITECTURE をリポジトリの実体（ディレクトリ構成・エージェントのフロントマター記法）に同期しました。
- `--skills` / `--categories` フィルタの適用範囲がスキルのみであること（ルールとエージェントは常にインストールされること）を README に明記しました。

### Fixed

- セキュリティ系 hooks のサイレント故障を修正しました。標準入力の二重読み込みによる無効化、マスク後の JSON 破壊、MCP 出力パース失敗時の素通り（fail-open）、エスケープ JSON の未マスクなど、hook が実質的に機能しなくなるケースを解消しました。
- `validate-bash.sh` / `validate-file-write.sh` / `check-secret-patterns.sh` を fail-closed 化しました。jq 不在・不正 JSON・作業ディレクトリ解決不能などの異常時は素通りせず停止します。
- サブディレクトリや `git -C` 起点、symlink 経由の実行でも hooks が正しく動作するようにしました。
- `setup` を `curl | bash` のような非対話環境で実行しても、同意なしに `settings.json` を書き換えないようにしました。
- 全 SKILL.md のフロントマターを strict YAML でパースできるよう修正しました（description のクォート化）。
