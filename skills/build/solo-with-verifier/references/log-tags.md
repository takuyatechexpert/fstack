# ログタグ

solo-with-verifier の Phase 6（完了ログ記録）で使うタグ一覧。
`~/.claude/hooks/skill-log.sh solo-with-verifier <TAG> "<message>"` で記録する。

| TAG | message 例 |
|---|---|
| `SCOPE_OK` | `{task-slug} files={N} tasks={N}` |
| `IMPL_DONE` | `{task-slug} iter={N} {elapsed}s` |
| `VERIFY` | `{task-slug} iter={N} result={ok|needs_fix}` |
| `END` | `{task-slug} iter={N} {total_elapsed}s` |
| `ESCALATE_SCOPE` | `{task-slug} reason=phase1_oversize` |
| `ESCALATE_LOOP` | `{task-slug} reason=verifier_fail_3x` |
| `ERROR` | `{内容}` |

- 実行時間は Phase 1 開始時に `date +%s` で取得した値から計算する。
- スキル起動ログは PostToolUse (Skill) hook が自動記録するため、START ログは不要。
