# フックイベント一覧（Claude Code 公式ドキュメント準拠）

| イベント | 発火タイミング | ブロック可否 | ログ用途 |
|---|---|---|---|
| `SessionStart` | セッション開始・再開時 | No | 使用モデル・起動方法の記録 |
| `InstructionsLoaded` | CLAUDE.md 読み込み時 | No | どの指示ファイルが読まれたか |
| `UserPromptSubmit` | プロンプト送信前 | Yes | ユーザー入力の全記録 |
| `PreToolUse` | ツール実行前 | Yes | ツール実行前の監査・ブロック |
| `PermissionRequest` | 権限ダイアログ表示時 | Yes | 権限リクエストの記録・自動承認 |
| `PostToolUse` | ツール実行成功後 | No | ツール使用パターンの分析 |
| `PostToolUseFailure` | ツール実行失敗後 | No | エラーの構造化ログ |
| `Notification` | 通知送信時 | No | 通知の記録 |
| `SubagentStart` | サブエージェント起動時 | No | エージェント使用状況の追跡 |
| `SubagentStop` | サブエージェント終了時 | No | エージェント完了・失敗の追跡 |
| `Stop` | Claude 応答完了時 | Yes | transcript_path の取得 |
| `TeammateIdle` | Agent Team メンバーがアイドル時 | Yes | チームメイト状態の監視 |
| `TaskCompleted` | タスク完了マーク時 | Yes | タスク完了の記録 |
| `ConfigChange` | 設定ファイル変更時 | Yes | 設定変更の監査ログ |
| `WorktreeCreate` | worktree 作成時 | Yes | worktree 作成の記録 |
| `WorktreeRemove` | worktree 削除時 | No | worktree 削除の記録 |
| `PreCompact` | コンテキスト圧縮前 | No | 圧縮タイミングの記録 |
| `SessionEnd` | セッション終了時 | No | セッション終了の記録 |
