# Claude 5 系（Opus 5.5 / Fable 5.1）向けプロンプト・スキル調整ガイド（Opus 4.7 → Claude 5 系）

> Opus 4.7 前提で書いた fstack のルール・スキルを Claude 5 系に合わせたときの記録と、これからスキル・ルールを書くときの指針。

Claude 5 系は指示しなくても自己検証し、頼まれていない範囲まで手を広げやすく、応答とファイルが前世代より長い。effort の既定値もモデルごとに変わった。Opus 4.7 向けに書いた「実装スキルを必ず起動する」「検証を必ず挟む」「effort を高めに付ける」といった指示は、この世代では過剰検証やコスト増につながる。fstack では検証体制を規模とリスクで足す形に緩め、代わりにスコープとターンの終わり方を明示的に縛った。

Opus 4.6 → 4.7 時点の記録は [prompt-migration-guide.md](prompt-migration-guide.md) にある。そこで扱った deferred tools / Plan Mode / Auto Memory は今も同じように使う。

出典（挙動の記述はこの範囲に限る）:

- Claude Code: [Model configuration](https://code.claude.com/docs/en/model-config) / [Settings](https://code.claude.com/docs/en/settings) / [Subagents](https://code.claude.com/docs/en/sub-agents)
- API: [Effort](https://platform.claude.com/docs/en/build-with-claude/effort)
- プロンプティングガイド: [Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) / [Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5) / [Fable 5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1)

---

## 1. 変わった挙動

### 1.1 effort と thinking

- effort の既定値はモデルで違う。Opus 5.5 / Sonnet 5.5 / Haiku 5.5 は `medium`、Fable 5.1 などその他は `high`。Claude Code では Opus 4.7 の既定は `xhigh`（Model configuration / Effort）
- 同じレベル名でも思考量はモデルで違う。Opus 5.5 は同じ effort でも Opus 5 より 1 ターンあたり多く考える（特に `xhigh` / `max`）。`xhigh` / `max` は品質向上を測れた作業に限る（Opus 5.5 ガイド）
- Fable 5.1 は `xhigh` / `max` で長い成果物を思考内で下書きしがちで、`low` では検索・取得ツールを呼ぶ頻度が下がり記憶で答えやすい（Fable 5.1 ガイド）
- Opus 5.5 / Sonnet 5.5 / Haiku 5.5 / Fable 系は Claude Code で thinking を切れない（`alwaysThinkingEnabled: false` などは効かない）。API でも Opus 5.5 に `thinking: disabled` を送ると 400 になる（Model configuration / Effort）
- Claude Code ではユーザー settings のトップレベル `effortLevel` は Opus 5.5 には効かない。モデル別の指定は `modelSettings` で行う（Model configuration / Settings）
- frontmatter の `effort` は、そのスキル / サブエージェントが動く間セッションの effort を上書きする（環境変数 `CLAUDE_CODE_EFFORT_LEVEL` は上書きしない）。サブエージェントで省略したときの挙動は公式に明記がない（Subagents）

### 1.2 長さと書式

- effort を下げても可視の応答は確実には短くならない。縮むのは思考量で、長さはプロンプトで指示する。ディスクに書くファイルも前世代より長い（Opus 5 ガイド）
- Fable 5.1 は文が長く段落が少ない密な文章に寄り、太字・見出し・リストを前世代より使わない。書式は抑制ルールでなく「使い所の指定」で書き、比喩や飾りで直接表現を置き換えないよう指定する（Fable 5.1 ガイド）

### 1.3 自己検証・スコープ・委譲

- 指示なしで自己検証する。「最後に検証ステップを入れる」「サブエージェントで検証する」のような明示的な検証指示は過剰検証を招き、外しても品質は落ちない（Opus 5 ガイド）
- スコープが広がりやすい（頼まれていない修正・拡張・余計なテストのコミット）。除外指示を入れると未依頼の追加とコミットされるテストが大幅に減り、タスク成功率は変わらない（Opus 5 ガイド / Fable 5.1 ガイド）
- サブエージェントへの委譲が前世代より多い。独立でサイズのある作業に限り、検証には使わず、1 体で足りるなら 1 体にする（Opus 5 ガイド）

### 1.4 ターンの終わり方・編集・要約

- 次の手順を宣言して止まる、依頼済みの範囲で「適用しますか？」と聞いて止まる、が起きる。最後の段落が計画・約束ならその場で実行させる（Fable 5.1 ガイド「Finish the whole task」、Opus 5.5 ガイド「Unattended agentic runs」）
- 小さな変更でもファイル全体を書き直しやすい（Fable 5.1 ガイド）。対象箇所の編集を優先させる
- 要約・引き継ぎでは、試して捨てた案とその理由、ユーザーの決定・制約・好みを発言に近い形で残すよう指定すると効く（Fable 5.1 ガイド「compaction summaries」）

### 1.5 セッション途中のモデル切替

`/model` を途中で切り替えると、モデルごとに別のプロンプトキャッシュを持つため、切替後最初のリクエストは会話全体を非キャッシュで読み直す（Settings）。

---

## 2. fstack での対応

| 挙動 | 対応したファイル | 中身 |
|---|---|---|
| 自己検証が入る | `rules/implementation-flow.md`、`skills/build/` の 3 スキル | 実装スキルの起動を「必須」から「推奨」に緩め、検証体制は規模とリスクで足す（「検証体制を足す判断」） |
| スコープが広がる | `rules/implementation-flow.md`、`templates/CLAUDE.md.template`、`skills/build/orchestra-of-agents/references/agent-prompts.md` | 「スコープとテストの範囲」を必須の節にし、委任プロンプトにも除外指示を入れる |
| 委譲が多い | `rules/context-management.md`、`templates/CLAUDE.md.template` | 委譲の判断基準を「価値が明確なときだけ」に差し替え、同時 spawn 上限を追加 |
| ターンの途中で止まる | `templates/CLAUDE.md.template` | ターンの終わり方の 2 択、状況を聞かれても作業を続ける、自己完結のまとめ |
| ファイル全体を書き直す | `templates/CLAUDE.md.template` | 小〜中規模の変更は対象箇所の Edit |
| 応答・ファイルが長い、書式が減る | `rules/document-writing.md` | 書式の使い所、言葉どおりに書く、長さをタスクに見合わせる |
| effort の既定がモデル別 | `skills/meta/my-skill-creator/references/skill-standards.md`、`skills/meta/agent-creator/`、`agents/*.md` | effort の付け方を差し替え、エージェント lint に `effort` / `fable` と W011 を追加、エージェントに effort を明示 |
| 1M 窓・要約で残すもの | `rules/context-management.md`、`skills/core/handover` | `/handover` の目安を 150K トークンに。引き継ぎに「試して捨てた案」と発言に近い決定・制約を残す |
| モデル依存の書き方 | `rules/context-management.md`、`rules/memory.md`、`rules/plan-mode.md` | 特定モデル（Opus 4.7）を前提にした書き方を、Claude Code の機能としての書き方に直す |
| 必須から推奨への緩和 | `hooks/check-implementation-routing.sh` | reminder の条件を、変更ファイル数が 5 の倍数に達し実装スキルの起動痕跡がないときに変更（stderr のまま。制約は `hooks/README.md`） |

---

## 3. 新規にスキル・ルールを書くときの推奨

### 3.1 effort は省略を基本にする

既定値と frontmatter の挙動は §1.1 参照。

- スキルは省略でセッションの effort を引き継ぐ。Opus 5.5 のセッションで `high` を付けると、下げるつもりでも上がる
- 定型処理は `model` を `haiku` / `sonnet` に固定して軽くするのが先。effort を下げるなら、セッションのモデルの既定より低いレベルを明示する（Fable 5.1 なら `medium`、Opus 5.5 なら `low`。`low` は取得を伴わない単純作業に限る）
- `xhigh` / `max` は eval で品質向上を測れたスキルだけに付ける
- サブエージェントは、effort が品質・コストに効くものを明示する（fstack では `architect` に `high`、`db-schema-investigator` に `medium`）

詳細: `skills/meta/my-skill-creator/references/skill-standards.md`「model / effort の判断軸」

### 3.2 検証の工程を足す指示を書かない

§1.3 参照。走らせるテスト・リンタのコマンド（`rules/testing.md`「検証手段」）は、完了の判断基準として残す。

### 3.3 スコープの除外指示を最初から入れる

§1.3 参照。実装を委任するプロンプトやスキルに `rules/implementation-flow.md`「スコープとテストの範囲」の要点を入れる。

### 3.4 thinking を切る設定・「考えるな」系の指示を書かない

§1.1 参照。思考量は effort で抑える。Opus 5 ガイドは、多くのタスクで thinking オン + 低 effort が同程度のコストで thinking オフを上回るとしている。

### 3.5 長さと書式はプロンプトで指定する

§1.2 参照。人が読む文書は `rules/document-writing.md` に従う。

---

## 4. やらなかったこと

- **無人ループ向けの standing instruction**（Opus 5.5 ガイド「Unattended agentic runs」）— 同ガイドは human-in-the-loop の用途では外すよう書いている。fstack は対話で使う前提なので、ターンの終わり方の 2 択だけをテンプレートに入れた
- **マルチエージェントの時間シグナル**（経過時間・時間予算を毎メッセージに付ける）— ハーネス側の仕組みが要り、ルール・スキルの記述だけでは実現できない
- **前の回答を蒸し返さない指示**（Opus 5.5 ガイド「Thinking instructions in chat system prompts」）— 後の手順で前の誤りが見つかるエージェント作業では外すよう同ガイドが注意しており、fstack の用途（実装・レビュー）と合わない
- **routing hook の出力を Claude に届ける変更** — exit 0 の stderr は Claude に届かない。`hookSpecificOutput.additionalContext` への切替は別の変更とする（`hooks/README.md`）
