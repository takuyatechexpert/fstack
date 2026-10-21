---
name: review-pr
description: "PR レビューの入口スキル。git worktree で PR ブランチ全体を読み、PR 内容に応じて選んだ観点別サブエージェントの並列レビューと偽陽性チェックを経て、プロジェクト方針・アーキテクチャ・変更漏れ・影響範囲まで詳細レビューする。引数先頭に `codex` を付けると Codex CLI に軽量レビューを委譲する。ユーザーが「PRレビューして」「PR #123 をレビュー」「このPRをチェックして」「プルリク確認して」「レビューお願い」と言ったとき、または GitHub PR URL を指定したときに使用する。以下では起動しない: pending-reviews、review-all-pending、行き詰まり時のセカンドオピニオン、技術選定の相談、PR 作成・マージ・テンプレ編集。"
---

# PR Review

worktree で PR ブランチ全体にアクセスし、**PR 内容に応じて選定した複数視点のサブエージェントで並列レビュー → 偽陽性チェックで裏取り → 統合して出力**する。

## 起動モード

引数（ARGUMENTS）の **先頭トークン** で分岐する。

- 先頭が `codex` → **Codex 委譲モード**: `references/modes.md` を Read し、その手順で `review-codex` に委譲する（本スキルの Phase 1〜7 は実行しない）。`review-codex` は別途導入が必要。未導入なら、その旨を伝え `codex` なしの標準モードでの起動を案内して終了する
- それ以外 → **標準モード**: 以降の Phase 1〜7 を実行
- **複数 PR 指定時**（どちらのモードでも）: `references/modes.md` の「複数 PR 指定時」を Read して従う（標準 = PR ごとに個別サブエージェントを並列 spawn / codex = 直列呼び出し）

## 参照リソース

いずれも `~/.claude/skills/review-pr/references/` 配下（エージェントへはこの基準の絶対パスで渡す）。

- **モード詳細（codex 委譲・複数 PR）**: `modes.md` — 該当時に親が Read
- **エージェント起動仕様（worker / verifier の SSOT）**: `agent-roster.md` — Phase 4・5 開始時に親が Read
- **Laravel/DDD**: `review-checklist.md`
- **影響範囲（worker4・技術スタック共通）**: `impact-check-rules.md` — §8〜15 が全スタック共通、§1〜7 は Laravel/DDD 専用
- **仕様適合（worker5）**: `spec-compliance-check.md`
- **UI・アクセシビリティ（worker6）**: `/web-design-guidelines` スキル（別途導入が必要な外部スキル。未導入ならその観点を silent skip せず、理由付きで Phase 6 の概要に記載する）を呼び、Web Interface Guidelines 準拠を確認
- **偽陽性チェック（verifier）**: `false-positive-check.md`
- **出力フォーマット（親・Phase 6）**: `output-format.md`
- **React/Next.js**: **worker2 のみ** `/vercel-react-best-practices` スキル（別途導入が必要な外部スキル。未導入ならその観点を silent skip せず、理由付きで Phase 6 の概要に記載する）を呼ぶ（同スキルの 8 カテゴリはすべて性能観点）。**worker1 は in-repo 規約**（`.cursor/rules/*.mdc` / `CLAUDE.md` / `AGENTS.md` / `.github/copilot-instructions.md` のうち Phase 3 で実在を確定したもの）**+ 既存コードの慣習**、**worker3 は in-repo テスト規約 + 既存テストの前例**を使う（各カードの詳細は `agent-roster.md` が SSOT）
- **Flutter・Dart**: `flutter-checklist.md`（worker1・2・3・5・6 の Flutter 分岐で使用）
- **IaC（worker1・worker2・worker3）**: `iac-checklist.md` — 差分の種類ごとの適用範囲と担当 worker は同ファイル冒頭の表を参照
- **設計書レビュー（worker7）**: `design-doc-checklist.md`
- **試験工程ドキュメント（worker8）**: `test-doc-checklist.md`
- **構造整合性チェック（保守用・レビュー実行時は不要）**: `design/check_structure.py` — reference を編集したら実行する（frontmatter の strict YAML パース・reference 実在・オーファン・コードフェンス・worker カードの必須項目）

## ワークフロー（標準モード・単一 PR）

**役割分担**: 親（オーケストレータ）が Phase 1〜3・6〜7 を担い、Phase 4 で **PR 内容に応じて選定した worker**（ロスター 8 カードから選定。同時 spawn は 6 体まで・超過時は 2 波に分ける）を並列 spawn、Phase 5 で verifier×1 を spawn する。worktree は親が 1 つだけ作り、全 worker / verifier が同一パスを **Read のみで共有**する（書き込みエージェントはいないので worktree isolation 不要）。

### Phase 1: PR 概要・仕様ソース把握

PR 番号または URL から `mcp__github__pull_request_read` を呼び、以下を取得する。

- PR 概要（タイトル、説明本文、head/base ブランチ名）
- 変更ファイル一覧
- **仕様ソース**: PR 説明・タイトル内のリンク Issue（`#番号` / `closes #N` / `refs #N`）・課題管理ツール（Jira / Backlog 等）の URL を拾う。Issue 本文が必要なら `mcp__github__issue_read` で取得し worker5 へ渡す
- **CI チェック結果**: `gh pr checks {PR番号}` で取得する（失敗ジョブがあれば差分分類と併せて worker へ渡す）

PR 番号のみの場合は `git remote get-url origin` から owner/repo を取得する。

### Phase 2: worktree 作成（親が 1 回）

```bash
git fetch origin {head_branch}
git fetch origin {base_branch}
git worktree add .worktrees/review-pr-{PR番号} origin/{head_branch}
```

**作成先は `/tmp` でなくリポジトリ内 `.worktrees/`**（絶対パスは `{repo}/.worktrees/review-pr-{PR番号}`）。`/tmp` はハーネスの許可ディレクトリ外で、worker の Bash / Read が権限拒否される（2026-08-07〜14 に9回発生）。`.worktrees/` は `.git/info/exclude` に登録し、コミット対象の `.gitignore` は触らない。

既存 worktree が残っている場合は先に `git worktree remove --force {repo}/.worktrees/review-pr-{PR番号}` で削除する。以降の Phase は同パスをルートとして読む。

**マージ済み PR では上記の fetch と、後続の `git diff origin/{base}...HEAD` が両方とも失敗する**（head ブランチが削除済み / head が base の祖先になり差分が空）。`refs/pull/` から head を取り、マージコミットの第 1 親との merge-base を base に使う（Pitfall 2 参照）。

**`git worktree add` は submodule を初期化しない。** gitlink のディレクトリが worktree 内で空になるため、そこにある実装は読めない（2026-08-24 の IaC（CDK）PR で `cdk/common/` が空になり、レビュー対象の Aspect が適用される Lambda 4 個の実装が読めず、**worker1 の MUST が誤った前提で立った**）。差分または差分の参照先に submodule が含まれるなら、次のどちらかを実行し、**採った方を Phase 4 で全 worker に明示する**。

```bash
git -C {repo}/.worktrees/review-pr-{PR番号} submodule status   # 空か否かの判定
# 案1: worktree 内で初期化する
git -C {repo}/.worktrees/review-pr-{PR番号} submodule update --init --recursive
# 案2: gitlink が同一なら main checkout 側の実体を読ませる（初期化のコストを避ける）
git -C {repo}/.worktrees/review-pr-{PR番号} ls-tree HEAD {submodule パス}
git -C {repo} ls-tree HEAD {submodule パス}   # 上と同一ハッシュなら main checkout を読んでよい
```

### Phase 3: プロジェクト特性の把握と差分分析（親が 1 回）

**重要**: bootstrap-env hook の `## Summary` はセッション開始時の cwd 基準で worktree とズレる。worktree 内の実ファイルを優先して再確認する。

1. **プロジェクト設定と in-repo 規約**: `CLAUDE.md` / `README.md` / `.claude/` / **`.cursor/rules/`** / **`AGENTS.md`** / **`.github/copilot-instructions.md`** を候補に `ls -a` で実在を確認し、あるものを原典として Read する。**実在したもののパスは Phase 4 で全 worker のサマリに列挙して渡す**（worker1・worker3 の React 分岐ではこれが担当 reference そのものになる）。**`CLAUDE.md` も `.claude/` も無いリポジトリがある** — 2026-08-24 の React フロントエンド PR では規約の原典が `.cursor/rules/*.mdc` 9 本で、そのうちテスト作成規約の `.mdc` の 2 行が採用 SHOULD 2 件の唯一の根拠になった
2. **アーキ / 技術スタック**: Glob と `package.json` / `composer.json` / `pubspec.yaml` で判定 → **worker の担当 reference を決定**（Laravel/DDD / React・Next.js / Flutter・Dart（`pubspec.yaml` あり） / IaC）
3. **DB 種別**（Laravel のみ・他スタックはスキップ）: `config/database.php`（モノレポでアプリがサブディレクトリにある場合はその配下）の `default`、無ければ `.env.example` の `DB_CONNECTION`（`mysql` / `pgsql` / `sqlite`）
4. **index 棚卸し**（Laravel のみ・他スタックはスキップ）: `review-checklist.md` §7「事前確認」と同手順で、差分対象テーブルの index / UNIQUE / FK を一覧化（パフォーマンス指摘の根拠）
5. **差分分析**: `git -C {repo}/.worktrees/review-pr-{PR番号} diff origin/{base_branch}...HEAD` の `--name-only` と全文を取得し、変更ファイルをアーキテクチャに応じて分類（**`cd` と混ぜない** — 権限チェッカーが cwd を追えず承認プロンプトの原因になる）
6. **base との時系列確認**: PR ブランチが base より遅れていると、**worktree（= PR HEAD）からは base 側の前例・規約が一切見えない**。日付関係と「base 側にのみ存在する差分」を先に確認する

   ```bash
   WT={repo}/.worktrees/review-pr-{PR番号}
   git -C "$WT" log -1 --date=short --format='HEAD %cd' HEAD
   git -C "$WT" log -1 --date=short --format='base %cd' origin/{base_branch}
   git -C "$WT" diff --name-status HEAD...origin/{base_branch}   # base 側の追加・変更（merge-base 以降）
   ```

   **「worktree に無い」を「リポジトリに無い」と断定しない。** 2026-08-24 の IaC（CDK）PR では PR ブランチが base より 5 週間遅れており、親が「`cdk/` にテストディレクトリが存在しない」を確定事実として全 worker に配ったが、base には `cdk/test/waf.test.ts`（PR HEAD より 3 週間後に追加）が実在した。**訂正したのは 1 体だけで、別の worker は誤りを引用して伝播させた**。base 側にのみ存在する前例は一覧にして worker へ渡し、**根拠に使う場合は追加日と PR HEAD の前後関係を確認させる**（後に追加された前例は当時の要求として使えない ↔ 逆向きの罠は Pitfall 2 の 2026-08-23 のマージ済み Laravel PR）
7. **原典の解決**: 変更ファイル名・API 番号・画面 ID から設計書の置き場（docs リポジトリ・docs ディレクトリ・Wiki 等。ローカルに clone があればそれ、無ければ `mcp__github__get_file_contents`）の設計書・開発ルールを逆引きし、パス一覧を worker5 / worker7 へ渡す

得られた **プロジェクト特性サマリ（アーキ・技術スタック・DB 種別・index 一覧）と差分分類・in-repo 規約の実在パス一覧・原典パス一覧（worker5 / worker7 用）・base 側にのみ存在するファイルの一覧・submodule の読み先** は Phase 4 で全 worker へ渡す（短い事実のため要約渡し禁止の対象外）。

**偽陽性になりやすい前提は親が先に実コードで潰し、「再確認不要な事実」として Phase 4・5 で配る。** 何が意図された挙動で何がそうでないかを原典（Issue / 設計書）と実コードで確定しておくと、worker が同じ偽陽性に到達しなくなり verifier の裏取りコストも下がる（2026-08-24 の React フロントエンド PR では「キャッシュしたデータを即表示してバックグラウンド再取得する挙動は親 Issue が導入意義として明示的に意図したもの」を先に確定して配り、6 体の誰もこれを問題として指摘しなかった。rejected 0 件を達成した 2026-08-24 の Flutter アプリ PR・2026-08-24 の IaC（CDK）PR も同じ運用）。**ただし親の事実が誤っていると 1 体では止まらず伝播する**（2026-08-24 の IaC（CDK）PR で親の誤りを訂正したのは 5 体中 1 体だけで、別の worker は誤りを引用した）。配る前に必ずコマンドの出力で裏取りする。

### Phase 4: worker 選定 + マルチ視点並列レビュー

**4-1. worker 選定（親）**: `agent-roster.md` を Read し、各 worker カードの**起動条件**を Phase 3 の差分分析・Phase 1 の仕様ソース有無と突合して、起動する worker をピックする。選定原則（**内容のみで判定＝規模で間引かない・迷ったら起動・選定ゼロ禁止・silent skip 禁止＝スキップは理由付きで Phase 6 概要に記載**）は roster「worker 選定原則」に従う。

**4-2. 並列 spawn**: 選定した worker を **単一メッセージ内で並列 spawn** する。各 worker には ① worktree 絶対パス ② 担当観点と読むべき reference 絶対パス ③ Phase 3 のプロジェクト特性サマリ ④ 差分取得方法（`git -C {worktree} diff origin/{base}...HEAD`）⑤ 共通出力スキーマ ⑥ **空振り報告の指示**（`agent-roster.md`「空振り報告」・担当 reference の節名を具体的に列挙して渡す）を渡す（要約渡し禁止 — Pitfall 3）。

各 worker の**観点・起動条件・担当 reference（技術スタック別の差し替え含む）と共通出力スキーマは `agent-roster.md` が SSOT**（ここには再掲しない。親は Phase 4-1 で Read 済みの roster から転記して渡す）。worker は **指摘の発掘** に専念する（採否判定はしない）。指摘ゼロなら空配列を返してよい。

### Phase 5: 偽陽性検証（verifier×1）

起動した全 worker の指摘を 1 つの配列に集約し、**verifier を 1 体 spawn** する。verifier は worker 選定の対象外で**常に実行**する。渡すもの: ① worktree 絶対パス ② 集約した全指摘リスト ③ `false-positive-check.md` と `review-checklist.md`（§7・§9）の絶対パス ④ **親が Phase 3 で確定した事実**（「再確認不要」と明示して渡す。verifier が同じ確認を繰り返すのを防ぐ） ⑤ **worker 間で判定が衝突している論点**（下記）。

指摘リストが長い場合は 1 ファイルに原文のまま連結して**パスを渡す**（要約渡し禁止 — Pitfall 3）。各 worker の「空振り報告」も同じファイルに含める。**指摘化を見送った理由が書かれており、衝突の裁定に使える**。

**worker 間の判定衝突は親が抽出して名指しで渡す。** 同一箇所・同一事象について severity・到達性・scope の判定が割れているものを探し、**独立した節として「衝突している worker と各自の判定」「どちらが正しいかを裁定せよという指示」をセットで**渡す。これをやらないと verifier は 20 件を平坦に処理し、矛盾を「重複」として統合してしまう（軸 7 は同一論点の統合であって矛盾の裁定ではない）。

2026-08-24 の React フロントエンド PR で 2 件発生し、親が名指しで渡した結果 verifier が両方を裁定した — ①ある副作用の到達性で worker2「経路が実在する」（**store の定義行を呼び出しと取り違えた誤り**）vs worker4「latent」vs worker5「指摘化を見送り」→ 後 2 者が正しい ②ガード条件の解釈で worker2「常に true で死コード」vs worker4「意図通り機能する」→ **同一観察からの逆推論**で worker4 が誤り。**親が Phase 3 で核心の構造を独立に確定していたため、裁定の根拠を渡すコストがゼロだった**。

verifier は各指摘を worktree の実コードで裏取りし、`confirmed` / `downgraded` / `rejected` / `merged` を判定する（手順は `false-positive-check.md`）。採用されるのは **confirmed と downgraded のみ**。

### Phase 6: レビュー結果の出力（親）

`references/output-format.md` を Read し、verifier が採用した指摘（confirmed / downgraded）のみを、同ファイルの **出力テンプレート・書き方ルール・コメント提案の書き方・レビュー観点の優先度** に従って整形する。**読み手はコードを頭に入れていない**前提で書き、テンプレート（コメント提案を含む）は worker 数・PR 規模によらず省略不可。

**空振り報告の集計**: 全 worker の「空振り報告」を節ごとに 1 枚へまとめる（hit / 空振り / 未確認）。**「未確認」と、原典と衝突していた節・スタック非該当だった節は次回のスキル修正候補**なので、レビュー出力とは別に記録して残す。レビュー本文には含めない（読み手はレビュイーであり、スキルの実効性測定は別の関心事）。

**セルフレビュー**: 出力ドラフト後、`review-checklist.md`「9. セルフレビュー」を Read して全項目を通す（verifier とは別に、親視点で **読みやすさ・粒度** を最終確認。Laravel/DDD 以外でも共通適用）。**特に §9-4「コメント提案の網羅確認」は出力ゲートとして必ず通す**（1件でも欠けたら差し戻す）。

### Phase 7: クリーンアップ

成功・失敗を問わず `git worktree remove {repo}/.worktrees/review-pr-{PR番号}` を実行する。残存時は `--force` で強制削除する。

worktree を消す前に、Phase 4・5 で spawn した worker / verifier がまだ動いていないかを `ListAgents` で確認し、残っていれば `TaskStop` で止めてから完了報告する。放置するとレビュー完了後も走り続け、ユーザーが手動で止めることになる（2026-09-24 に 3 回、累計 40 回）。

## Pitfalls（落とし穴）

実体験ベースのみ採用。各項目は **症状 / Why / ルール** で記述する。

### 1. worktree 残留でレビュー開始直後に失敗する

- **症状**: Phase 2 の `git worktree add` が直前レビューの残骸でエラーになる
- **Why**: Phase 7 のクリーンアップは途中失敗（プロセス kill / 親のクラッシュ）で飛ぶことがあり、残留は `git worktree list` でしか気付けない
- **ルール**: Phase 2 開始時に `git worktree list | grep review-pr-{N}` で確認 → あれば `remove --force` してから add する

### 2. base_branch 未 fetch / マージ済み PR で差分が空になる

- **症状**: `git diff origin/{base_branch}...HEAD` が空 / develop 全履歴などの異常な差分になる。あるいは Phase 2 の `git fetch origin {head_branch}` が `couldn't find remote ref` で落ちる
- **Why**: 原因が 2 つある。①ローカルの `origin/{base_branch}` ref が古く merge-base が誤った位置になる ②**PR が既にマージ済み**で、head ブランチが削除されており、かつ head が base の祖先になっている（`...` は merge-base 起点のため差分がゼロになる）
- **ルール**: Phase 2 で base / head の両方を必ず fetch。差分が空または不自然に大きい場合は再 fetch。**マージ済み PR では下記 2 段階で真の分岐点を求める**（2026-08-23 のマージ済み Laravel PR で発生）

```bash
git fetch origin pull/{PR番号}/head:refs/heads/pr-{PR番号}-head
MC=$(gh pr view {PR番号} --json mergeCommit --jq '.mergeCommit.oid')
git fetch origin "$MC"
BASE=$(git merge-base "$MC^1" pr-{PR番号}-head)   # これが真の分岐点
git worktree add .worktrees/review-pr-{PR番号} pr-{PR番号}-head
```

  以降 worker へ渡す差分取得は `git -C {worktree} diff {BASE} HEAD` とする（`origin/{base}...HEAD` は使わない）。Phase 7 では `git branch -D pr-{PR番号}-head` も併せて実行する。

### 3. サブエージェントへチェックリストを要約渡しすると項目欠落する

- **症状**: 「Laravel/DDD のはずなのに DTO 命名チェックが抜けている」等の品質劣化
- **Why**: 要約渡しは Claude の解釈ステップが入り、長いチェックリストほど丸められて項目が消える
- **ルール**: 本文展開せず **絶対パスを渡して worker 自身に Read させる**（Phase 3 の短い事実サマリのみ要約可）

### 4. verifier を省略して偽陽性が混入する

- **症状**: 行番号ズレ・ルール誤適用の MUST・破綻した代替案がそのまま PR コメントに出る
- **Why**: worker は発掘特化で採否判定をしない。偽陽性は 1 件でもレビュー全体の信頼を損なう
- **ルール**: verifier は **指摘件数に関わらず必ず通す**。confirmed / downgraded のみ採用し、rejected は出力しない（件数だけ総評に残す）

### 5. worker / verifier に worktree を書き換えさせる

- **症状**: 並列レビュー中に worktree のファイルが変わり、別 worker の行番号がズレる
- **Why**: 全員が同一 worktree を共有しており、1 体でも Edit/Write すると他の読み取りが不整合になる
- **ルール**: worker / verifier には **Read 専用**を明示（Edit/Write/NotebookEdit させない）。修正提案はコード片の提示に留める

### 6. 規模を理由に worker を全省略すると観点とテンプレを取りこぼす

- **症状**: 小さい PR で worker を省いて親が直接レビューすると、各指摘の「コメント提案」が落ちる
- **Why**: 「小さい PR＝観点も少ない」は誤った前提。テンプレを自力で再構成すると、分量の重い「コメント提案」を付録扱いしてスキップしがち
- **ルール**: **規模による worker 省略・インライン縮退は行わない**。間引きは Phase 4-1 の内容ベース選定のみ（最低 1 体は必ず spawn）。**Phase 6 テンプレ（コメント提案を含む）は worker 数によらず省略不可**。出力前に §9-4 の網羅ゲートを必ず通す

### 7. worker / verifier が報告を返さず idle になり、結果が丸ごと落ちる

- **症状**: 成果を出したエージェントが本文を返さず idle 通知だけを送ってくる。親が気付かないと、その worker の指摘がゼロ件として扱われる（verifier で起きるとレビュー全体が成立しない）
- **Why**: エージェントは作業完了と親への報告を別ステップとして扱う。完了＝報告済みではない
- **これは稀な事象ではない。実測で 5 レビュー中 5 レビュー・計 13 体で発生している** — 2026-08-23 の設計書 PR（worker4・verifier）/ 2026-08-23 のマージ済み Laravel PR（verifier）/ 2026-08-24 の Flutter アプリ PR（worker4・worker5・verifier）/ 2026-08-24 の IaC（CDK）PR（worker1）/ 2026-08-24 の React フロントエンド PR（**worker1・worker3・worker4・worker5・worker6 + verifier = 6 体中 5 体**。本文を SendMessage で送ったのは worker2 だけだった）。**verifier は 5 件中 4 件で発生**した。発生を前提に運用する
- **プロンプトに警告文を足す対処は効かない**（2026-08-24 の Flutter アプリ PR で verifier のプロンプトに「完了しましただけの返答では判定結果が丸ごと失われる」と明示したうえで発生した）。**警告文の追加で解決しようとしないこと**

**ルール（この順に実行する）**

1. Phase 4-2 / Phase 5 で spawn した全エージェントについて、**本文を受け取ったかを名前で照合してから次の Phase に進む**
2. 欠けていれば**まずトランスクリプトから回収する**（下記コマンド）。同期的に終わり待ち時間ゼロで、実測 3/3 で完全な報告が残っていた
3. トランスクリプトにも報告が無い場合のみ `SendMessage` で「作業のやり直しは不要。既に得た結果をそのまま指定形式で送れ」と再要求する

**再要求を後段に置く理由**: 2026-08-23 のマージ済み Laravel PR では再要求が効かないまま、トランスクリプトには 18,993 文字の完全な判定結果が残っていた。2026-08-24 の Flutter アプリ PR でも verifier の 20,037 文字はトランスクリプトから回収した（worker 2 体は再要求も効いたが、待ち時間はトランスクリプト回収のほうが短い）。**再要求は往復コストがあり、かつ失敗した実績がある。** トランスクリプトは失敗した実績が無い。

```bash
# セッション ID を知らなくてよい: 直近更新の subagents ディレクトリが現在のセッション
D=$(ls -td ~/.claude/projects/*/*/subagents 2>/dev/null | head -1)
ls "$D"   # agent-a{名前}-{hash}.jsonl が並ぶ。名前は spawn 時に付けた name

# 報告経路は 2 つある。両方を見ること（片方だけでは 0 件になる）
# (1) 最終 assistant テキストに書いた場合
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$D"/agent-a{名前}-*.jsonl
# (2) SendMessage で親に送った場合
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | select(.name=="SendMessage") | .input.message' "$D"/agent-a{名前}-*.jsonl
```

**経路はエージェントごとに違う。** 2026-08-24 の IaC（CDK）PR では worker1 が (1)、worker2〜5 が (2) だった。(1) だけを叩いて 0 件だったのを「報告が無い」と誤読しないこと。

回収した本文は**そのまま worker / verifier の報告として扱ってよい**（作業自体は完了しており、届いていないのは報告だけ）。ただし再送版に追記が入ることがあるため、両方受け取った場合は再送版を優先する（2026-08-24 の Flutter アプリ PR の worker4 は再送版にのみ「この表記変更は仕様書の要求」という判定の決め手が入っていた。2026-08-24 の IaC（CDK）PR では 3 体とも追記ゼロで完全一致だった）。

**回収できたら到着を待たずに先へ進んでよい。** 2026-08-24 の IaC（CDK）PR では idle 後に回収した 5 体のうち、真に報告を送っていなかったのは 1 体だけで、残り 4 体は数十秒〜2 分後にメッセージが届いた。**「未達」と「まだ届いていないだけ」は待つ前には区別できない**ので、待って切り分けようとせず回収して進める。

## ログ記録

スキル起動ログは PostToolUse (Skill) hook が自動記録するため、SKILL.md 内で `skill-log.sh` を手動実行しない。指摘件数等の集計ログが必要になったら本セクションにタグ設計を復活させる。
