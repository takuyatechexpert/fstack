---
name: orchestra-of-agents
description: "agent teamsを使った並列実装・レビューワークフロースキル。Wave方式で依存関係を考慮した並列実装、testerが仕様ベーステスト（/spec-driven-test）を作成、構成に応じたレビュー体制（標準:クロスレビュー+横断レビュー / 最小:ダイレクトレビュー+総合判断）で品質を担保する。複数ファイル・複数モジュールにまたがる中〜大規模の新機能実装（概ね5タスク以上）を対象とする。**MUST: 5タスク以上または横断的変更を伴う実装依頼を受けたら、本スキルを起動すること。1〜3タスクなら solo-with-verifier、極小スコープなら直接実装と機械的に切り分け、「自分でやった方が早い」で直接実装に逃げない。** ユーザーが「実装して」「〜を作って」「orchestra」「チーム実装」「orchestra-of-agents」「並列実装」「並列で実装」「エージェントチーム」「チームで作って」と言ったときに使用する。以下では起動しない: 1〜3タスクの小〜中規模修正（solo-with-verifier が担当）、実装着手前の設計のみ（build-planner）、単一ファイル修正・typo・小規模バグ修正、PRレビュー単発（review-pr）、テスト単発（spec-driven-test）、設計相談・調査のみ、設定変更1行・依存更新などの小修正。"
---

# orchestra-of-agents

agent teams による並列実装・テスト・レビューワークフロー。

## 参照ファイル（スキル起動時に並列 Read）

同一メッセージ内で並列 Read する（メモリからの再現ではなく最新ファイルを正とする）。パスは `${CLAUDE_SKILL_DIR}/references/` 配下。サブエージェントへ渡す際は `${CLAUDE_SKILL_DIR}` を展開済みの絶対パスに解決してから渡す（サブエージェントは環境変数を解決できない）。

- `agent-prompts.md` — 各エージェントの spawn プロンプト・報告フォーマット
- `design-contract.md` — Wave 0 契約書の項目・手順・Why の詳細
- `conductor-playbook.md` — conductor 運用詳細（実体検証・メッセージ規律・コミットルール・harness 適応・クリーンアップ）
- `standard-workflow.md` / `minimal-workflow.md` — 選択した構成のみ

> **前提（harness 適応）**: 本スキルと references が使う agent teams API 名（`TeamCreate` / `TeamDelete` 等）が現行のツール一覧に無い場合は、**name 付きの Agent spawn + `SendMessage` + Task 系ツール**（`TaskCreate` / `TaskUpdate` 等）に読み替える。チーム生成＝name 付き Agent の起動、チーム解体＝各エージェントへの `shutdown_request` 送信として対応する。

## 構成の選択

タスク数で選択する。実装規模が小さくてもレビューとテストの厚みは維持する（最小構成は reviewer が厚く、spawn 総数はむしろ標準より多い）。

| 条件 | 構成 | spawn 内訳（+ conductor 兼任） | レビュー体制 |
|------|------|-------------------------------|-------------|
| 6タスク以上 | 標準構成 | 4体 = impl×2 + tester + reviewer-c | クロスレビュー + 横断レビュー |
| 5タスク以下 | 最小構成 | 5体 = impl×1 + tester + reviewer×3（a / b / leader） | ダイレクトレビュー + 総合判断 |

conductor はオーケストレーター自身が兼任する（別エージェントとして spawn しない）。

## 標準構成（6タスク以上）

| エージェント | 役割 | allowed_tools |
|---|---|---|
| conductor | タスク分析・分割・Wave 管理・節目報告・調整介入・実体検証・集中コミット | Read, Glob, Grep, SendMessage, Task系, Bash（検証・git・運用） |
| impl-1 / impl-2 | 基盤・API 実装 → ページ実装 → クロスレビュー | 制限なし |
| tester | 仕様ベーステスト作成（/spec-driven-test）+ スモーク実行 | 制限なし |
| reviewer-c | 横断レビュー + テスト品質確認 | Read, Glob, Grep, SendMessage, Write |

- **最低3タスク同時ルール**: Wave 1・2 とも3並列以上で impl の手空きをなくす
- impl は原則 **2名固定**。Wave 2 が **15ファイル超/impl** の場合のみ impl-3 を Wave 2 から追加可

```
Wave 0: conductor が設計契約書を作成                            ← 設計合意
Wave 1: impl-1(基盤) + impl-2(API) + tester(テスト作成)        ← 3並列
Wave 2: impl-1(応用A) + impl-2(応用B)                          ← 2並列
Wave 2.5: tester がビルド＋起動スモークテスト → conductor に報告 ← 統合検証
Wave 3: クロスレビュー + reviewer-c(横断レビュー)                ← 3並列
Wave 4: 最終判断 + 修正ループ（最大3回）
```

## 最小構成（5タスク以下）

conductor（兼任）+ impl-1, tester, reviewer-a, reviewer-b, reviewer-leader の計5体。**同時 spawn 上限 4 体**のため reviewer-leader は Wave 3 で遅延 spawn する。

```
Wave 0: conductor が設計契約書を作成                                  ← 設計合意
Wave 1: impl-1(実装) + tester(テスト作成)                             ← 2並列
Wave 2: reviewer-a(実装レビュー) + reviewer-b(テストレビュー+実行)     ← 2並列・直接引き渡し
Wave 2.5: tester がビルド＋起動スモークテスト → conductor に報告       ← 統合検証
Wave 3: reviewer-leader(総合判断) → 直接差し戻し or OK                ← 節目報告
```

レビューフェーズ（Wave 2-3）は**直接引き渡し**方式（reviewer ↔ impl の直接質問可、conductor には節目報告）。

## Wave 0: 設計契約（全構成共通）

Wave 1 前に conductor が**インターフェース契約書**を作成する（型レベルでなくセマンティクスレベルの合意）。詳細は `design-contract.md`。骨子:

1. **検証環境健全性ゲート** — 既存テスト・依存サービスが緑であることを確認してから着手
2. 契約書を `/tmp/orchestra-{team-name}/design-contract.md` に保存。必須項目: **Base commit SHA / エンティティ関係図 / モジュール境界の API / データフロー / 共有型の定義場所 / 呼び出し元・消費者の網羅リスト / 文字列トークンの正規語彙 / コミット順序 / ファイル割当表（1ファイル=1impl）**
3. **architect レビュー**（最大2回。プロンプトは agent-prompts.md）→ 反映後、impl spawn 時に契約書パスの参照を義務付ける

## Wave 2.5: 統合スモークテスト（全構成共通）

Wave 2 完了後に **tester** がビルド＋テスト実行（ビルド5分・起動30秒、リトライ最大2回）。結果は agent-prompts.md のフォーマットで conductor に節目報告し、**失敗時は conductor が suspected_owner の impl に差し戻す**（tester は実装コードを修正しない）。

## Wave 3 判定基準（全構成共通）

次の 4 条件を**すべて満たした場合のみ `OK`**。1 つでも欠ければ `needs_fix` として修正ループへ。

1. **reviewer フラグ** — 全 reviewer が `OK`
2. **blocking 指摘** — severity=blocking が **0 件**
3. **スモーク** — Wave 2.5 が `pass`（またはスキップ理由が妥当）
4. **別モデルレビュー（条件付き必須）** — 状態機械・遷移ガード / 権限・認可 / セキュリティ敏感処理（パス操作・入力検証・シェル実行・シリアライズ）/ CLI verb・公開 API 等の外部契約、に触れる変更では、別モデルによるレビューが可能な MCP/CLI があればそれでレビューし **MUST 指摘 0 件（または全件解消）**であること（別モデルが MUST 級の見逃しを捕捉した実績あり）。非該当なら任意（推奨）

判定根拠は `review-final.md` に記録し、修正ループでは対象ファイル・担当 impl・指摘をリスト化して差し戻す。

## 共通ルール（要点 — Why・実例・詳細は conductor-playbook.md）

- **conductor は演奏しない**: Edit/Write なし。Bash は検証・git・運用のみ（実装コードの編集・生成には使わない）
- **実体検証**: 報告を鵜呑みにしない。Wave ごとに `git status`、最終判定前に test/typecheck/lint を自身で実行して裏取り。中断→再開時はフル検証から
- **メッセージ規律**: 裁定は「これが最終裁定」と参照付きで明示 / 指示末尾は `Next: <動詞> <対象>` の 1 行 / idle 停滞 2 回で conductor が技術判断を投入
- **コミットは conductor の専権**: 並列 add/commit は index 衝突するため全員 git 書き込み禁止。push 禁止ブランチ判定 → stray 点検 → diff 確認 → ユーザー承認後 commit
- **ファイル編集権**: 1 ファイル = 1 impl（契約書の割当表）。テスト編集は tester の専権、impl は SendMessage で修正依頼（仕様の番人は tester）
- **tester への指示**: 既存テストパス + 外部データサンプルを必ず含める（推測は偽失敗で空転する）
- **並列 spawn**: 1 メッセージ内で複数 Task 呼び出し。同時上限 4 体、5 体目は遅延 spawn
- **harness 適応**: Agent Teams API がなければ name 付き Agent spawn + SendMessage に読み替え。teammate は永続、Wave ごとの再 spawn はしない
- **改善提案の拾い上げ**: 最終 OK 後、review-final.md の非ブロッキング項目を Issue 化提案（ユーザー承認制。手順は各 workflow の Wave 3.5 / 4.5）
- **クリーンアップ**: shutdown → 実行ログを `/tmp/orchestra-{team-name}/{YYYY-MM-DD}-{task-slug}.md` に保存（run-log-template.md）
- **エスカレーション**: 修正ループ 3 回超 / architect レビュー 2 回超 → ユーザーへ

## ログ記録

起動ログは PostToolUse (Skill) hook が自動記録（手動 START 不要）。`~/.claude/hooks/skill-log.sh orchestra <TAG> "<message>"`:
`IMPL_DONE` "{slug} wave={N} {elapsed}s" / `TEST` "{slug} pass={N} fail={N}" / `REVIEW_DONE` "{slug} result={ok|needs_fix} loop={N}" / `END` "{slug} {total}s" / `ERROR` "{内容}"。実行時間は開始時の `date +%s` から計算する。

## Pitfalls（ハマりどころ）

### 1. tester に実データを渡し忘れる
仕様から JSON 構造を推測し実 API と乖離 → テスト偽失敗で修正ループが空転。**対策**: 指示に既存テストパス＋実データサンプルを必ず含める。

### 2. impl がテストを直接修正する
「テストが間違い」と判断して tester を迂回すると仕様ドリフトが起きる。**対策**: テスト編集は tester 専権。impl は SendMessage で依頼する。

### 3. Wave 切り替え時のストール
指示送信後に idle のまま未着手になる。**対策**: TaskList で pending（owner なし）を定期確認し再送。監視は定期ポーリングより Bash の `sleep` ループが実効的。

### 4. タスクボード全消失
TaskList / TaskGet が Task not found を返し全消失することがある（原因不明）。**対策**: 復元しない。「成果物の真実は working tree」の原則で `git status` により実体を照合し、SendMessage 駆動にフォールバックして続行する。

### 5. 未 spawn の reviewer 宛にレビュー依頼
宛先不在でメッセージが消失する。**対策**: conductor は依頼先 reviewer の spawn 完了を確認してから「依頼を送ってよい」と指示する。

### 6. dist ビルド + vitest の全テスト二重実行
デフォルト include が `dist/**/*.test.js` も拾い二重実行される（時間ほぼ倍増）。**対策**: `include: ['src/**/*.test.ts']` を明示。設定修正は tester が conductor に逸脱報告して承認を得る。

### 7. 静的解析ベースラインの解釈ずれ
ベースラインのあるリポジトリで「エラー 0」基準は合格不能。**対策**: 契約書に「**新規発生エラー 0（変更前後の差分）で判定**」と明記し全員の基準を揃える。
