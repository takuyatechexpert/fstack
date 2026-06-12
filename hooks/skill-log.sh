#!/bin/bash
# Usage: ~/.claude/hooks/skill-log.sh <skill-name> <tag> <message>
# Example: ~/.claude/hooks/skill-log.sh review-pr REVIEW "15s my-repo #123 (MUST:1 SHOULD:2)"
mkdir -p ~/.claude/logs
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] [$2] $3" >> ~/.claude/logs/skills.log
