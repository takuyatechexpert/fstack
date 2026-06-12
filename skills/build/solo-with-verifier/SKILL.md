---
name: solo-with-verifier
description: Generator-Verifier パターンによる軽量実装スキル。Implementer（実装＋テスト）と Verifier（仕様適合・テスト品質・rules遵守・検証コマンド）の2エージェントを最大3反復させ、1〜3ファイル・1〜3タスクの小〜中規模修正で実装の正しさ・テスト網羅性・クリーンコードを担保する。orchestra-of-agents の軽量版。ユーザーが「修正して」「直して」「追加して」「実装して」「リファクタして」「ペアプロモードで」「solo-with-verifier」と言ったとき、またはコード変更を伴う依頼を受けたときに使用する。
---

# solo-with-verifier

Generator-Verifier パターン（Anthropic 公式マルチエージェント設計の最もシンプルな形）を採用した軽量実装ワークフロー。
Implementer と Verifier の2エージェントを反復させ、小〜中規模修正でも「自分でやった方が早い」と感じる場面を品質保証付きで処理する。

## 位置付け

| スキル | スコープ | レビュー体制 |
|---|---|---|
| `orchestra-of-agents`（既存） | 5タスク以上の中〜大規模 | クロスレビュー＋横断レビュー |
| **`solo-with-verifier`（本スキル）** | 1〜3タスクの小〜中規模 | Verifier 1名（4観点） |
| 直接実装 | typo 1行修正など | なし（品質保証なし） |

**原則として直接実装は避け、本スキルか orchestra-of-agents のどちらかを必ず通す。**

## 参照ファイル（毎回 Read で読み込む）

スキル起動時に **同一メッセージ内で以下を並列 Read** する。要約・メモリからの再現禁止。サブエージェント spawn 時はファイルパスを渡し、サブエージェント自身に Read させる。

- **Implementer プロンプト**: `${CLAUDE_SKILL_DIR}/references/implementer-prompt.md`
- **Verifier プロンプト**: `${CLAUDE_SKILL_DIR}/references/verifier-prompt.md`
- **rules チェックリスト**: `${CLAUDE_SKILL_DIR}/references/rules-checklist.md`

---

## ワークフロー

### Phase 1: スコープ判定

依頼内容から推定される変更規模を以下の表で判定する。

| 観点 | 本スキル適用 | orchestra-of-agents へ昇格 |
|---|---|---|
| 変更ファイル数 | 1〜3 | 4以上 |
| タスク数 | 1〜3 | 4以上 |
| 依存関係 | 単純（直列・独立） | Wave設計が必要 |
| 影響範囲 | 単一モジュール内 | 複数モジュール横断 |
| 設計判断 | 既存パターンに沿う | アーキテクチャ選択を要する |

**いずれか1つでも右側に該当したら orchestra-of-agents を提案** し、ユーザーに切替を確認する。

#### Why: 軽量版は早期OK・脱線・テスト追従の3つのリスクがある。スコープが膨らんだ瞬間にそれらのリスクが顕在化するため、境界を明確にしておく。

### Phase 2: 受け入れ基準の確定

タスク委任の **5点セット**（意図・制約・受け入れ基準・関連ファイル・検証手段）をこの場で明文化し、以降のフェーズで Implementer / Verifier に渡す共通の契約書とする。

**実行ごとのユニーク run ディレクトリ**を生成し、その中の `acceptance.md` にテンプレートを保存する。固定パスを使うと、複数の solo-with-verifier 実行（特に別セッションでの同時並行）が同一ファイルを上書きし合い、別タスクの基準を読む競合が起きるため、必ず `mktemp -d` でユニーク化する。

```bash
mkdir -p /tmp/solo-with-verifier
RUNDIR=$(mktemp -d /tmp/solo-with-verifier/run.XXXXXX)
# 受け入れ基準テンプレートを "$RUNDIR/acceptance.md" に保存する
```

ここで決まった **`$RUNDIR/acceptance.md` のパスを、後続の Phase 3 / 4 / 5 で受け入れ基準ファイルとして使う**（サブエージェントには毎回このパスを明示的に渡す）。

> **後始末**: run ディレクトリは `/tmp` 配下のスクラッチで OS 再起動時に消えるため、明示削除は不要。

```markdown
## 受け入れ基準（Phase 2 で確定）

### 1. 意図
{何を達成したいか。ビジネス目的・ユーザー価値を1〜3行で}

### 2. 制約
{使ってよい技術・守るべき規約・触ってはいけない範囲}

### 3. 受け入れ基準
{完了と判断する条件をチェックリスト形式で}
- [ ] {基準1}
- [ ] {基準2}

### 4. 関連ファイル（path:line 形式）
- {path/to/file.ext:LL}

### 5. 検証手段
{rules/testing.md の検証手段テーブルから該当コマンドを抜粋}
- 例: `make test` → `make lint`

### スコープ外（Verifier への指示）
{今回触らない範囲・別チケット扱いにする項目}
```

#### Why: Verifier の脱線（スコープ外の指摘）を防ぐため、**何が「完了」かを明示的に固定する**。曖昧なまま走らせると、Verifier は新規変更以外のリファクタ要求まで指摘して修正ループが空転する。

### Phase 3: Implementer 実行

Task tool で `general-purpose` サブエージェントを spawn し、`references/implementer-prompt.md` のパスと **Phase 2 で生成した `$RUNDIR/acceptance.md` のパス**を明示的に渡す（固定パスを前提にしない）。

**Implementer の責務:**
1. TDD サイクル: テストを先に書いて **RED を確認** → 実装 → GREEN → REFACTOR
2. `rules/testing.md` の検証手段テーブルからプロジェクトに応じたコマンドを選んでセルフ実行
3. 完了報告（変更ファイル一覧・実行した検証コマンドとその結果・RED 確認の証跡）

#### Why: Implementer 側でも `RED 確認` を必須化することで、テストが実装に追従するだけのものになる劣化を防ぐ。

### Phase 4: Verifier 実行

Task tool で `general-purpose` サブエージェントを別途 spawn し、`references/verifier-prompt.md` のパスと **Phase 2 で生成した `$RUNDIR/acceptance.md` のパス**（受け入れ基準）＋Phase 3 の実装差分（変更ファイル一覧）を明示的に渡す（固定パスを前提にしない）。

**Verifier の責務（4観点）:**
1. **仕様適合**: Phase 2 の受け入れ基準を満たしているか
2. **テスト品質**: テストが仕様を表現しているか（実装に追従しているだけでないか）
3. **rules遵守**: `references/rules-checklist.md` 記載の rules配下違反チェック
4. **検証コマンド再実行**: Implementer のセルフ実行とは独立に、自分で再実行して結果を確認

**判定基準:**
- 全観点 OK かつ各観点に**具体的根拠**（実行コマンド・参照行・引用）あり → `OK`
- 1つでも具体的指摘あり、または根拠が薄い → `needs_fix`

#### Why: 「特に問題なし」のような甘い指摘での早期OKを防ぐため、4観点それぞれで根拠を求める。

### Phase 5: ループ判定

| Verifier 判定 | 反復回数 | アクション |
|---|---|---|
| OK | 任意 | 完了。最終レポート → Phase 6 へ |
| needs_fix | 1〜2回目 | Implementer に差し戻し（指摘内容付き）→ Phase 3 へ戻る |
| needs_fix | 3回目 | **エスカレーション**: ユーザーに「orchestra-of-agents へ昇格を提案」と通知して停止 |

差し戻し時は、**同一 run の `$RUNDIR/acceptance.md` をそのまま使い回す（新規に run ディレクトリや受け入れ基準ファイルを生成しない）**。受け入れ基準ファイルを変更せず、Verifier の指摘リストだけを Implementer に追加で渡す（スコープ拡張を防ぐ）。

#### Why: 反復上限を設けないと無限ループする。3回で収束しないということは、Phase 1 のスコープ判定が誤っていた可能性が高く、より重厚な orchestra へ持ち上げるのが正解。

### Phase 6: 完了ログ記録

`~/.claude/hooks/skill-log.sh solo-with-verifier <TAG> "<message>"` で記録:

- `SCOPE_OK` "{task-slug} files={N} tasks={N}"
- `IMPL_DONE` "{task-slug} iter={N} {elapsed}s"
- `VERIFY` "{task-slug} iter={N} result={ok|needs_fix}"
- `END` "{task-slug} iter={N} {total_elapsed}s"
- `ESCALATE_SCOPE` "{task-slug} reason=phase1_oversize"
- `ESCALATE_LOOP` "{task-slug} reason=verifier_fail_3x"
- `ERROR` "{内容}"

実行時間は Phase 1 開始時に `date +%s` で取得した値から計算する。

> **Note:** スキル起動ログは PostToolUse (Skill) hook が自動記録するため、START ログは不要。

---

## 出力フォーマット（最終レポート）

```markdown
## solo-with-verifier 完了レポート
### スコープ: 変更ファイル {N}件 / タスク {N}件 / 反復 {N}/3
### 受け入れ基準達成: [x] 基準1 / [x] 基準2 ...
### Implementer サマリ
- 変更ファイル: {file_path:line ...}
- RED 確認: {テスト初回失敗ログ引用}
- 検証コマンド: {make test / make lint / ...}
### Verifier サマリ（4観点・各観点に根拠必須）
1. 仕様適合 / 2. テスト品質 / 3. rules遵守 / 4. 検証コマンド再実行
### 残課題（スコープ外・非ブロッキング指摘）
```

---

## Pitfalls（ハマりどころ）

### 1. Verifier が甘い指摘で早期 OK を出す

**症状**: Verifier が「特に問題なし」「概ね良い」のような曖昧コメントで OK を返し、品質保証が形骸化する。
**Why**: 4観点の判定根拠を求めずに spawn すると、Verifier は最小限の応答を返す傾向がある。
**ルール**: `verifier-prompt.md` で「4観点それぞれに具体的な根拠（実行コマンド・参照行）を出す」「根拠が薄ければ自動 needs_fix」を明示する。Verifier が OK を返したら、報告内に4観点すべての根拠が含まれているかメインエージェントが確認し、欠けていれば Phase 4 を再実行する。

### 2. Implementer がテストを実装に合わせて書く

**症状**: テストが現状の実装挙動をなぞるだけになり、仕様逸脱を検出できなくなる。
**Why**: TDD の RED フェーズを省略すると、実装後にテストを書く流れになり、テストが受け入れ基準ではなく実装に追従する。
**ルール**: Implementer プロンプトに「テスト先行・RED 確認・実装後のテスト追加は禁止」を明示。Implementer は RED 時の失敗出力を報告に必ず含める。Verifier は観点②でこの証跡を必ず確認する。

### 3. Verifier が新規変更以外まで指摘して脱線

**症状**: 既存コードのリファクタ要求や、関連モジュールの設計指摘まで返してきて、本来のスコープが膨らむ。
**Why**: Phase 2 の受け入れ基準が曖昧なまま走らせると、Verifier はレビュー範囲を自己拡張する。
**ルール**: Phase 2 で「触ってはいけない範囲」「今回のスコープ外」を明示。Verifier プロンプトで「スコープ外の指摘は『改善提案』セクションに分離し、ブロッキング扱いしない」を明示する。

---

## エスカレーション条件

以下のいずれかで stop して orchestra-of-agents への切替を提案する:

- Phase 1 でスコープが境界を超えると判定された
- Phase 5 で needs_fix が 3 回連続した
- Phase 4 で「設計判断が必要」と Verifier が報告した
- ユーザーから明示的にスコープ拡張の指示が入った
