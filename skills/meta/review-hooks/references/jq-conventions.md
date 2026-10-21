# フックコマンドの共通仕様

- **jq パス**: `/opt/homebrew/bin/jq`（hooks 実行環境は PATH が最小限のため絶対パス必須）
- **`now` の記法**: `[(now | strftime("%Y-%m-%d %H:%M:%S"))]` と必ず括弧で囲む（`,` より `|` の優先度が高いため）
- **ログ出力先**: `~/.claude/logs/` 配下に集約
- **タイムアウト**: ログ用途なら `5` 秒で十分
- **PATH**: hook 内でコマンドを実行する場合は絶対パスを指定する

## SessionStart テンプレート

```json
"SessionStart": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "mkdir -p ~/.claude/logs && /opt/homebrew/bin/jq -r '[(now | strftime(\"%Y-%m-%d %H:%M:%S\")), (.source // \"\"), (.model // \"\")] | \"[\" + .[0] + \"] [SESSION_START] source:\" + .[1] + \" model:\" + .[2]' >> ~/.claude/logs/sessions.log",
        "timeout": 5
      }
    ]
  }
]
```

## PostToolUse (matcher で絞り込み) テンプレート

```json
"PostToolUse": [
  {
    "matcher": "mcp__github__.*|mcp__slack__.*",
    "hooks": [
      {
        "type": "command",
        "command": "mkdir -p ~/.claude/logs && /opt/homebrew/bin/jq -r '[(now | strftime(\"%Y-%m-%d %H:%M:%S\")), .tool_name, (.tool_input | tostring)] | \"[\" + .[0] + \"] [MCP] \" + .[1] + \" | \" + .[2]' >> ~/.claude/logs/mcp-tools.log",
        "timeout": 5
      }
    ]
  }
]
```

## UserPromptSubmit テスト入力

```bash
echo '{"session_id":"test","prompt":"test"}' | /opt/homebrew/bin/jq -r '[(now | strftime("%Y-%m-%d %H:%M:%S")), (.session_id // ""), .prompt] | "[" + .[0] + "] [PROMPT] " + .[1] + " | " + .[2]'
```

## SessionStart テスト入力

```bash
echo '{"session_id":"test","source":"resume","model":"claude-opus-5-5"}' | /opt/homebrew/bin/jq -r '[(now | strftime("%Y-%m-%d %H:%M:%S")), (.source // ""), (.model // "")] | "[" + .[0] + "] [SESSION_START] source:" + .[1] + " model:" + .[2]'
```
