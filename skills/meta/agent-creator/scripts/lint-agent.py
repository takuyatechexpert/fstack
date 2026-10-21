#!/usr/bin/env python3
"""Claude Code エージェント定義ファイル(.claude/agents/*.md)のリントスクリプト。

Usage:
    python3 lint-agent.py <agent-file-path>
    python3 lint-agent.py ~/.claude/agents/architect.md

Exit codes:
    0: エラーなし（警告・情報のみ）
    1: エラーあり
"""

import json
import re
import sys
from pathlib import Path

# --- 定数 ---

VALID_FIELDS = {
    "name", "description", "tools", "disallowedTools", "model", "maxTurns",
    "permissionMode", "skills", "mcpServers", "memory", "background",
    "isolation", "hooks", "effort",
}

COMMON_TYPOS = {
    "max_turns": "maxTurns",
    "allowed_tools": "tools",
    "disallowed_tools": "disallowedTools",
    "permissions": "permissionMode",
    "permission_mode": "permissionMode",
    "mcp_servers": "mcpServers",
    "allowedTools": "tools",
    "Models": "model",
    "Tool": "tools",
    "desc": "description",
    "maxturns": "maxTurns",
}

VALID_MODELS = {"haiku", "sonnet", "opus", "fable", "inherit"}
MODEL_ID_PATTERN = re.compile(r"^claude-[\w-]+-\d")

# 低 → 高の順。公式の options はレベル名のみなので整数は受け付けない
VALID_EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"]

VALID_PERMISSION_MODES = {"default", "acceptEdits", "dontAsk", "bypassPermissions", "plan"}

VALID_MEMORY_SCOPES = {"user", "project", "local"}

BUILTIN_TOOLS = {
    "Read", "Write", "Edit", "Bash", "Glob", "Grep",
    "WebFetch", "WebSearch", "Agent", "Skill", "NotebookEdit",
}

# tools に書くと MCP ツール群全体を許可する、公知の MCP サーバー名。
# ここに無い名前は W006 で警告する（タイプミス検出のため）。プロジェクト固有の MCP を使う場合は追記する。
KNOWN_MCP_SERVERS = {
    "chrome-devtools", "github", "slack", "playwright", "sentry", "postgres",
}

# Agent(name1, name2) パターン
AGENT_TOOL_PATTERN = re.compile(r"^Agent\([\w, -]+\)$")

NAME_PATTERN = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


# --- メッセージ ---

class Issue:
    def __init__(self, code: str, level: str, message: str):
        self.code = code
        self.level = level
        self.message = message

    def __str__(self):
        return f"[{self.code}] {self.level}: {self.message}"

    def to_dict(self):
        return {"code": self.code, "level": self.level, "message": self.message}


# --- YAML パーサー（簡易版: PyYAML 不要） ---

def parse_frontmatter(content: str):
    """YAML フロントマターを簡易パースする。PyYAML に依存しない。"""
    lines = content.split("\n")

    # --- で始まるか確認
    if not lines or lines[0].strip() != "---":
        return None, None, "フロントマターの開始 `---` がありません"

    # 2つ目の --- を探す
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        return None, None, "フロントマターの終了 `---` がありません"

    yaml_lines = lines[1:end_idx]
    body = "\n".join(lines[end_idx + 1:]).strip()

    # 簡易 YAML パース（トップレベルの key: value のみ）
    fields = {}
    current_key = None
    for line in yaml_lines:
        if not line.strip() or line.strip().startswith("#"):
            continue

        # トップレベルの key: value
        match = re.match(r"^(\w+)\s*:\s*(.*)", line)
        if match:
            key = match.group(1)
            value = match.group(2).strip()
            # クオートを除去
            if value and value[0] in ('"', "'") and value[-1] == value[0]:
                value = value[1:-1]
            fields[key] = value
            current_key = key
        elif current_key and line.startswith(("  ", "\t", "    - ")):
            # ネストされた値（hooks, skills 等）はキーの存在だけ記録
            pass
        else:
            return None, None, f"YAML パースエラー: `{line.strip()}`"

    return fields, body, None


def parse_tool_list(tools_str: str) -> list[str]:
    """ツールリスト文字列をパースする。"""
    if not tools_str:
        return []
    return [t.strip() for t in tools_str.split(",") if t.strip()]


# --- バリデーション ---

def lint(filepath: str) -> list[Issue]:
    issues = []
    path = Path(filepath)

    if not path.exists():
        issues.append(Issue("E000", "ERROR", f"ファイルが存在しません: {filepath}"))
        return issues

    if not path.suffix == ".md":
        issues.append(Issue("E000", "ERROR", "エージェント定義ファイルは .md である必要があります"))
        return issues

    content = path.read_text(encoding="utf-8")

    # Phase 1: フロントマターのパース
    fields, body, parse_error = parse_frontmatter(content)
    if parse_error:
        if "開始" in parse_error or "終了" in parse_error:
            issues.append(Issue("E001", "ERROR", parse_error))
        else:
            issues.append(Issue("E002", "ERROR", parse_error))
        return issues  # パースできない場合は以降のチェック不可

    # Phase 2: 必須フィールド
    if "name" not in fields:
        issues.append(Issue("E003", "ERROR", "`name` フィールドが存在しません"))
    if "description" not in fields:
        issues.append(Issue("E004", "ERROR", "`description` フィールドが存在しません"))

    # Phase 3: name の形式
    name = fields.get("name", "")
    if name and not NAME_PATTERN.match(name):
        issues.append(Issue("E005", "ERROR",
            f"`name` に無効な文字が含まれています: `{name}` "
            f"(小文字・数字・ハイフンのみ使用可)"))

    # Phase 4: 未知フィールド（サイレント失敗の検出）
    for key in fields:
        if key not in VALID_FIELDS:
            suggestion = COMMON_TYPOS.get(key, "")
            msg = f"未知のフィールド `{key}` が存在します（サイレントに無視されます）"
            if suggestion:
                msg += f" → `{suggestion}` の誤りですか？"
            issues.append(Issue("W001", "WARN", msg))

    # Phase 5: enum 値の検証
    model = fields.get("model", "")
    if model and model not in VALID_MODELS and not MODEL_ID_PATTERN.match(model):
        issues.append(Issue("W002", "WARN",
            f"`model` の値 `{model}` は無効です "
            f"(有効値: {', '.join(sorted(VALID_MODELS))} またはフルモデルID)"))

    perm_mode = fields.get("permissionMode", "")
    if perm_mode and perm_mode not in VALID_PERMISSION_MODES:
        issues.append(Issue("W003", "WARN",
            f"`permissionMode` の値 `{perm_mode}` は無効です "
            f"(有効値: {', '.join(sorted(VALID_PERMISSION_MODES))})"))

    memory = fields.get("memory", "")
    if memory and memory not in VALID_MEMORY_SCOPES:
        issues.append(Issue("W004", "WARN",
            f"`memory` の値 `{memory}` は無効です "
            f"(有効値: {', '.join(sorted(VALID_MEMORY_SCOPES))})"))

    effort = fields.get("effort", "")
    if effort and effort not in VALID_EFFORT_LEVELS:
        issues.append(Issue("W011", "WARN",
            f"`effort` の値 `{effort}` は無効です "
            f"(有効値: {', '.join(VALID_EFFORT_LEVELS)})"))

    # Phase 6: maxTurns の型チェック
    max_turns = fields.get("maxTurns", "")
    if max_turns:
        try:
            val = int(max_turns)
            if val <= 0:
                issues.append(Issue("W005", "WARN",
                    f"`maxTurns` は正の整数である必要があります (現在値: {max_turns})"))
        except ValueError:
            issues.append(Issue("W005", "WARN",
                f"`maxTurns` は正の整数である必要があります (現在値: `{max_turns}`)"))

    # Phase 7: ツール名の検証
    for field_name, warn_code in [("tools", "W006"), ("disallowedTools", "W007")]:
        tools_str = fields.get(field_name, "")
        if tools_str:
            tools = parse_tool_list(tools_str)
            for tool in tools:
                # Agent(name) パターンは特別扱い
                if AGENT_TOOL_PATTERN.match(tool):
                    continue
                # 既知の MCP サーバー名は MCP ツール群全体の許可指定として正当
                if tool in KNOWN_MCP_SERVERS:
                    continue
                if tool not in BUILTIN_TOOLS:
                    issues.append(Issue(warn_code, "WARN",
                        f"`{field_name}` に未知のツール名 `{tool}` があります "
                        f"(組み込みツール名か MCP サーバー名を確認してください)"))

    # Phase 8: tools と disallowedTools の矛盾
    tools_set = set(parse_tool_list(fields.get("tools", "")))
    disallowed_set = set(parse_tool_list(fields.get("disallowedTools", "")))
    overlap = tools_set & disallowed_set
    if overlap:
        issues.append(Issue("W008", "WARN",
            f"`tools` と `disallowedTools` の両方に含まれるツール: {', '.join(sorted(overlap))}"))

    # Phase 9: description のクオート確認（フロントマター内のコロン）
    desc = fields.get("description", "")
    if desc and ":" in desc:
        # フロントマター原文を確認
        for line in content.split("\n"):
            if line.startswith("description:"):
                value_part = line[len("description:"):].strip()
                if value_part and value_part[0] not in ('"', "'"):
                    issues.append(Issue("W009", "WARN",
                        "`description` にコロンが含まれていますが、値がクオートされていません "
                        "(YAML パースエラーの原因になります)"))
                break

    # Phase 10: maxTurns 未設定の警告
    if "maxTurns" not in fields:
        issues.append(Issue("W010", "WARN",
            "`maxTurns` が未設定です（安全装置として設定を推奨します）"))

    # Phase 11: 情報レベル
    if body is not None and not body:
        issues.append(Issue("I001", "INFO",
            "本文（システムプロンプト）が空です"))

    if desc and len(desc) < 50:
        issues.append(Issue("I002", "INFO",
            f"`description` が短すぎます ({len(desc)}文字 / 推奨: 50文字以上)"))

    return issues


# --- メイン ---

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 lint-agent.py <agent-file-path>", file=sys.stderr)
        sys.exit(2)

    filepath = sys.argv[1]
    output_format = "text"
    if "--json" in sys.argv:
        output_format = "json"

    issues = lint(filepath)

    if output_format == "json":
        result = {
            "file": filepath,
            "issues": [i.to_dict() for i in issues],
            "summary": {
                "errors": sum(1 for i in issues if i.level == "ERROR"),
                "warnings": sum(1 for i in issues if i.level == "WARN"),
                "info": sum(1 for i in issues if i.level == "INFO"),
            }
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if not issues:
            print(f"✅ {filepath}: リント通過（問題なし）")
        else:
            errors = [i for i in issues if i.level == "ERROR"]
            warnings = [i for i in issues if i.level == "WARN"]
            infos = [i for i in issues if i.level == "INFO"]

            print(f"📋 {filepath}: {len(errors)} errors, {len(warnings)} warnings, {len(infos)} info\n")

            for issue in issues:
                icon = {"ERROR": "❌", "WARN": "⚠️", "INFO": "ℹ️"}.get(issue.level, "?")
                print(f"  {icon} {issue}")

    has_errors = any(i.level == "ERROR" for i in issues)
    sys.exit(1 if has_errors else 0)


if __name__ == "__main__":
    main()
