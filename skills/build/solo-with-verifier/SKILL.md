---
name: solo-with-verifier
description: "Generator-Verifier パターンによる軽量実装スキル。Implementer（実装＋テスト）と Verifier（仕様適合・テスト品質・rules遵守・検証コマンド）の2エージェントを最大3反復させ、1〜3ファイル・1〜3タスクの小〜中規模修正で実装の正しさ・テスト網羅性・クリーンコードを担保する。orchestra-of-agents の軽量版。**MUST: Edit/Write/NotebookEdit を伴う実装系の依頼を受けたら、typo・1行修正・コメント変更のみの極小スコープ以外はすべて本スキルを起動すること。「コピペ流用だから」「他リポジトリの実装をなぞるだけだから」「自分でやった方が早い」のような理由で直接実装に逃げない。** ユーザーが「修正して」「直して」「追加して」「実装して」「リファクタして」「ペアプロモードで」「solo-with-verifier」と言ったとき、またはコード変更を伴う依頼を受けたときに使用する。以下では起動しない: 5タスク以上・複数モジュール横断の中〜大規模実装（orchestra-of-agents）、実装着手前の設計・計画書化のみ（build-planner）、typo/1行修正/コメント変更のみの極小スコープ、PRレビュー単発（review-pr）、テスト単発（spec-driven-test）。"
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

スキル起動時に **同一メッセージ内で以下を並列 Read** する。要約・メモリからの再現禁止。サブエージェント spawn 時は、参照表記の `${CLAUDE_SKILL_DIR}` を**展開済みの絶対パスに解決してから渡し**、サブエージェント自身に Read させる（サブエージェント側では環境変数が未定義になり Read が失敗するため）。

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
| タスク数 | 1〜3 | 5以上（4タスクはグレーゾーン → 下記参照） |
| 依存関係 | 単純（直列・独立） | Wave設計が必要 |
| 影響範囲 | 単一モジュール内 | 複数モジュール横断 |
| 設計判断 | 既存パターンに沿う | アーキテクチャ選択を要する |

**いずれか1つでも右側に明確に該当したら orchestra-of-agents を提案** し、ユーザーに切替を確認する。

**4タスクのグレーゾーン**: 粒度判定の SSOT である build-planner のルーブリックに従う。依存が直列なら本スキルの反復で吸収し、独立性が高く並列化が活きる/複数モジュール横断でレビューが要るなら orchestra-of-agents に倒す。

#### Why: 軽量版は早期OK・脱線・テスト追従の3つのリスクがある。スコープが膨らんだ瞬間にそれらのリスクが顕在化するため、境界を明確にしておく。

### Phase 2: 受け入れ基準の確定

タスク委任の **5点セット**（意図・制約・受け入れ基準・関連ファイル・検証手段）をこの場で明文化し、以降のフェーズで Implementer / Verifier に渡す共通の契約書とする。

**実行ごとのユニーク run ディレクトリ**を生成し、その中の `acceptance.md` にテンプレートを保存する。固定パスを使うと、複数の solo-with-verifier 実行（特に別セッションでの同時並行）が同一ファイルを上書きし合い、別タスクの基準を読む競合が起きるため、必ず `mktemp -d` でユニーク化する。

保存先は、ハーネスが scratchpad ディレクトリを提示していればその配下を優先し（権限プロンプト不要）、無ければ `/tmp` 配下に作る。

```bash
# scratchpad を提示するハーネスではそこを、無ければ /tmp を基点にする
BASE="${CLAUDE_SCRATCHPAD_DIR:-/tmp/solo-with-verifier}"
mkdir -p "$BASE"
RUNDIR=$(mktemp -d "$BASE/run.XXXXXX")
# 受け入れ基準テンプレートを "$RUNDIR/acceptance.md" に保存する
```

ここで決まった **`$RUNDIR/acceptance.md` のパスを、後続の Phase 3 / 4 / 5 で受け入れ基準ファイルとして使う**（サブエージェントには毎回このパスを明示的に渡す）。

> **後始末**: run ディレクトリはスクラッチ領域（scratchpad / `/tmp`）に作るため明示削除はしない。`rm`/`rmdir` はフックでブロックされるので後始末に使わない。

テンプレートの中身（5点セット + スコープ外 + その Why）は `references/acceptance-template.md` を Read し、`$RUNDIR/acceptance.md` に書き込む。スコープ外を明示するのは、Verifier が新規変更以外のリファクタ要求まで指摘して修正ループが空転するのを防ぐため。

### Phase 3: Implementer 実行

Agent tool で `general-purpose` サブエージェントを spawn し、`references/implementer-prompt.md` のパスと **Phase 2 で生成した `$RUNDIR/acceptance.md` のパス**を明示的に渡す（固定パスを前提にしない）。

**Implementer の責務:**
1. TDD サイクル: テストを先に書いて **RED を確認** → 実装 → GREEN → REFACTOR
2. `rules/testing.md` の検証手段テーブルからプロジェクトに応じたコマンドを選んでセルフ実行
3. 完了報告（変更ファイル一覧・実行した検証コマンドとその結果・RED 確認の証跡）

#### Why: Implementer 側でも `RED 確認` を必須化することで、テストが実装に追従するだけのものになる劣化を防ぐ。

### Phase 4: Verifier 実行

Agent tool で `general-purpose` サブエージェントを別途 spawn し、`references/verifier-prompt.md`（「参照ファイル」節の絶対パス）＋**Phase 2 で生成した `$RUNDIR/acceptance.md` のパス**（受け入れ基準）＋Phase 3 の変更ファイル一覧を明示的に渡す（固定パスを前提にしない）。

**Verifier の責務（4観点）:** ① 仕様適合（受け入れ基準を満たすか）② テスト品質（実装追従でないか）③ rules 遵守（`references/rules-checklist.md`）④ 検証コマンドの独立再実行。各観点に**具体的根拠**（実行コマンド・参照行・引用）が揃えば `OK`、1つでも指摘ありか根拠が薄ければ `needs_fix`（判定詳細は `verifier-prompt.md`）。

#### Why: 「特に問題なし」のような甘い早期 OK を防ぐため、4観点それぞれで根拠を求める。

### Phase 5: ループ判定

| Verifier 判定 | 反復回数 | アクション |
|---|---|---|
| OK | 任意 | 完了。最終レポート → Phase 6 へ |
| needs_fix | 1〜2回目 | Implementer に差し戻し（指摘内容付き）→ Phase 3 へ戻る |
| needs_fix | 3回目 | **エスカレーション**: ユーザーに「orchestra-of-agents へ昇格を提案」と通知して停止 |

差し戻し時は、**同一 run の `$RUNDIR/acceptance.md` をそのまま使い回す（新規に run ディレクトリや受け入れ基準ファイルを生成しない）**。受け入れ基準ファイルを変更せず、Verifier の指摘リストだけを Implementer に追加で渡す（スコープ拡張を防ぐ）。

#### Why: 反復上限を設けないと無限ループする。3回で収束しないということは、Phase 1 のスコープ判定が誤っていた可能性が高く、より重厚な orchestra へ持ち上げるのが正解。

### Phase 6: 完了ログ記録

`references/log-tags.md` のタグ表に従い `~/.claude/hooks/skill-log.sh solo-with-verifier <TAG> "<message>"` で記録する（実行時間は Phase 1 開始時の `date +%s` から算出）。

---

## 出力フォーマット（最終レポート）

Phase 5 で OK 判定に達したら、`references/report-format.md` の型で完了レポートを出力する。

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
