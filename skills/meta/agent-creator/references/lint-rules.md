# エージェント定義リントルール

## ルール一覧

| ID | カテゴリ | 重要度 | 説明 |
|----|---------|--------|------|
| E001 | 構文 | ERROR | YAML フロントマターが `---` で囲まれていない |
| E002 | 構文 | ERROR | YAML パースエラー |
| E003 | 必須 | ERROR | `name` フィールドが存在しない |
| E004 | 必須 | ERROR | `description` フィールドが存在しない |
| E005 | 形式 | ERROR | `name` に無効な文字（大文字・アンダースコア等） |
| W001 | 未知 | WARN | ホワイトリスト外のフィールドが存在する（サイレント失敗） |
| W002 | 値 | WARN | `model` の値が無効 |
| W003 | 値 | WARN | `permissionMode` の値が無効 |
| W004 | 値 | WARN | `memory` の値が無効 |
| W005 | 型 | WARN | `maxTurns` が正の整数でない |
| W006 | ツール | WARN | `tools` に未知のツール名が含まれている |
| W007 | ツール | WARN | `disallowedTools` に未知のツール名が含まれている |
| W008 | 整合性 | WARN | `tools` と `disallowedTools` に同じツールが含まれている |
| W009 | 構文 | WARN | description にクオートされていないコロンが含まれている |
| W010 | 推奨 | WARN | `maxTurns` が未設定（安全装置なし） |
| W011 | 値 | WARN | `effort` の値が無効 |
| I001 | 情報 | INFO | 本文（システムプロンプト）が空 |
| I002 | 情報 | INFO | `description` が短すぎる（50文字未満） |

---

## 有効フィールド ホワイトリスト

```
name, description, tools, disallowedTools, model, maxTurns,
permissionMode, skills, mcpServers, memory, background,
isolation, hooks, effort
```

これ以外のフィールドは Claude Code に**サイレントに無視される**。

---

## よくあるタイプミス → 正しいフィールド名

| タイプミス | 正しい名前 | 備考 |
|-----------|-----------|------|
| `max_turns` | `maxTurns` | snake_case → camelCase |
| `allowed_tools` | `tools` | 別名ではなく別フィールド |
| `disallowed_tools` | `disallowedTools` | snake_case → camelCase |
| `permissions` | `permissionMode` | 別概念（settings.json の permissions とは異なる） |
| `permission_mode` | `permissionMode` | snake_case → camelCase |
| `max_turns` | `maxTurns` | snake_case → camelCase |
| `mcp_servers` | `mcpServers` | snake_case → camelCase |

---

## 有効なツール名

### 組み込みツール

```
Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch,
Agent, Skill, NotebookEdit
```

### 特殊構文

- `Agent({name1}, {name2})`: spawn 可能なサブエージェントを制限
- MCP サーバー名（例: `github`, `slack`）: MCP ツール全体を許可

---

## 有効な enum 値

### model

```
haiku, sonnet, opus, fable, inherit
```

またはフルモデルID（例: `claude-opus-5-5`, `claude-fable-5-1`, `claude-sonnet-5-5`, `claude-haiku-5-5`）

`opus[1m]` のような `[1m]` 付きエイリアスは**セッションのモデル設定**（`settings.json` の `model` / `/model`）専用で、エージェント frontmatter では使わない。

### effort

```
low, medium, high, xhigh, max
```

左から低 → 高の順。整数は受け付けない（公式の指定値はレベル名のみ）。付けると、そのサブエージェントが動く間だけセッションの effort を上書きする（環境変数 `CLAUDE_CODE_EFFORT_LEVEL` は上書きしない）。

省略時の挙動は公式ドキュメントに明記がない（スキルは「省略 = セッションの effort を引き継ぐ」と明記されている）。セッション既定もモデルで違い、Opus 5.5 / Sonnet 5.5 / Haiku 5.5 は `medium`、Fable 5.1 などその他は `high` なので、effort が品質やコストに効くエージェントは明示する。親が Opus 5.5（既定 `medium`）のとき `high` は effort を**上げる**指定になり、コストが増える。出典: [Sub-agents](https://code.claude.com/docs/en/sub-agents) / [Model configuration](https://code.claude.com/docs/en/model-config)

### permissionMode

```
default, acceptEdits, dontAsk, bypassPermissions, plan
```

### memory

```
user, project, local
```
