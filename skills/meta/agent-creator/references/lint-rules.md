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
| I001 | 情報 | INFO | 本文（システムプロンプト）が空 |
| I002 | 情報 | INFO | `description` が短すぎる（50文字未満） |

---

## 有効フィールド ホワイトリスト

```
name, description, tools, disallowedTools, model, maxTurns,
permissionMode, skills, mcpServers, memory, background,
isolation, hooks
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
haiku, sonnet, opus, inherit
```

またはフルモデルID（例: `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`）

### permissionMode

```
default, acceptEdits, dontAsk, bypassPermissions, plan
```

### memory

```
user, project, local
```
