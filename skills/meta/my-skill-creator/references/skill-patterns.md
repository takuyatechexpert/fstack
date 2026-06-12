# 既存スキルのパターン参照

## スキルパターン一覧

| パターン | 例 |
|---|---|
| 単純なワークフロー | `pending-reviews`（一覧取得して返すだけ） |
| Phase ベースの複雑なワークフロー | `orchestra-of-agents`（Wave 設計 → 並列実装 → レビュー） |
| references/ 付き | `review-pr`（チェックリスト・ルール）、`orchestra-of-agents`（Wave テンプレート） |
| オーケストレーション | ダッシュボード系スキル（他スキルをサブエージェントで並列実行） |
| PTC（並列データ収集） | `dashboard/scripts/gather.py` 型（ThreadPoolExecutor で複数API並列呼び出し → JSON返却） |
| 外部連携（GitHub/Slack） | リリース通知スキル・マイルストーン確認スキル等 |

---

## 既存スキルのリファクタリング（SKILL.md が 500行超の場合）

1. **分離候補を特定**: プロンプト全文、テンプレート、フォーマット定義、チェックリスト等
2. **references/ にファイルを作成**: 意味単位でファイルを分ける（1ファイル1関心事）
3. **SKILL.md を書き換え**: 冒頭に「参照ファイル」セクションを追加し、本文は骨格だけに
4. **重複排除**: 複数モードで共通の処理は1箇所に書き、他は「{X}と同じ」で参照

**実績例:** 682行のスキルを SKILL.md 158行 + references/ 3ファイル（417行）に分割。SKILL.md は「いつ・何を Read するか」だけにし、本体は references/ に移動することで、毎セッション必ず読み込まれる SKILL.md を軽量に保てる。

---

## references/ への参照パターン

SKILL.md 冒頭の「参照ファイル」セクションに絶対パスで明示する:

```markdown
## 参照ファイル

実行時に必ず Read で読み込むこと。要約やメモリからの再現は禁止。

- **eval ワークフロー**: `${CLAUDE_SKILL_DIR}/references/eval-workflow.md`
- **説明文最適化**: `${CLAUDE_SKILL_DIR}/references/description-optimizer.md`
```

**重要:** サブエージェントに references の内容を渡す場合、要約せずファイルパスを渡してサブエージェント自身に Read させる。

---

## 分離基準

| 分離候補のコンテンツ | 例 |
|---|---|
| サブエージェントに渡すプロンプト集 | `agent-prompts.md` |
| 表示テンプレート・フォーマット定義 | `dashboard-templates.md` |
| 詳細なチェックリスト・ルール | `review-checklist.md` |
| データ仕様・ログフォーマット定義 | `log-and-context.md` |
| テスト・eval ワークフロー | `eval-workflow.md` |
| 説明文最適化手順 | `description-optimizer.md` |

**判断基準:**
- SKILL.md のワークフロー理解に**不要な詳細**は references/ へ
- SKILL.md には**オーケストレーションの骨格**だけを残す
