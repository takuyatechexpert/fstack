# Conductor Playbook

conductor（オーケストレーター兼任）の運用詳細。SKILL.md には要点のみ、Why・実例・手順の全量は本ファイルが持つ。

## 役割と Bash の用途境界

タスク分析・分割・Wave 管理・節目報告の受け取り・調整介入・実体検証・集中コミット・最終報告を担当する。

**conductor は Read / Glob / Grep / SendMessage / Task系 / Bash を使用**し、実装編集は impl 系エージェントに委譲する。Edit / Write は allowed_tools により構造的に持たない。**Bash の用途は「検証（git status・テスト実行・スモーク）」「git 操作（集中コミット）」「オーケストレーション運用（契約書等の /tmp への保存・ポーリング・gh issue 作成・stray の退避）」に限り、実装コードの編集・生成（`sed -i` 等での修正巻き取りを含む）には使わない**（Bash は運用のため正式に許可。演奏はしないが、検聴とタクトは振る）。

節目報告ベースで状況を把握し、エスカレーション時のみ介入する。メンバー間の直接通信は全 Wave で許可し、conductor は節目報告と介入判断に集中する。

## 実体検証（報告を鵜呑みにしない）

サブエージェントの完了報告・スモーク報告は**必ず conductor 自身が実体で裏取り**する（報告と実体の乖離が発生することがある）:

- Wave 完了ごとに `git status` + 新規ファイルの存在確認で成果物の実在を確認する
- 最終判定前に検証コマンド（test / typecheck / lint）を **conductor が直接実行**して green を確認する
- セキュリティ敏感な実装では、具体的な攻撃観点（例:「id→path のパストラバーサル」）を明示した攻撃スモークを conductor 自身が実行する（観点を明示すると拾える）
- **ユーザー割込等で中断→再 spawn した場合**、中断前 spawn の成果物が作業ツリーに残存している前提で、git status + フル検証で実体確認してから再開する
- tester の報告が空・summary のみの場合は、フォーマット指定で再要求する（二重チェックで回収した実績あり）

## メッセージ規律

- **裁定メッセージの明示**: 判断を確定・変更するメッセージには「これが最終裁定。過去の◯◯より優先する」と参照付きで書く（古いメッセージの遅延到着による順序交錯で impl が巻き戻る事例がある）
- **Next 行の必須化**: 指示 SendMessage の末尾は `Next: <動詞> <対象>` の 1 行で締める（複数ステップ指示でも末尾は単一動詞。動詞抜けで impl が staged のまま長時間停止する事例がある）
- **介入トリガー**: impl ↔ tester の往復が idle 経由で 2 回停滞したら、conductor が技術判断を投入する。idle 通知は「待機シグナル」ではなく「介入トリガー候補」として扱う

## コミットルール（全構成共通）

git の index は worktree 単位で共有されるため、**並列エージェントによる git add / commit は衝突する**（並列 impl の staged ファイルが別 impl の commit に混入する）。

1. **git 書き込み操作（add / commit）は conductor の専権** — impl / tester / reviewer は一切 git add / commit しない。この「全員 git 禁止 + conductor 集中コミット」で index 衝突を構造的に回避する（worktree 分離も commit baton も不要）
2. **commit 前チェック（必須）**:
   - `git branch --show-current` で **push 禁止ブランチ判定**（`main` / `master` / `develop` / `YYYY-MM-DD` / `*staging*` / `*production*` なら中止し、作業ブランチへ切替 or ユーザー相談）
   - `git status` で **stray ファイル点検** — スモークの残骸等の未追跡ファイルが repo に残っていないか確認。不要物は削除せず別ディレクトリ（システムのゴミ箱等）へ退避する
   - `git diff` / `git diff --cached` で内容確認
3. **コミット順序は契約書の import グラフから導出**する（依存される側が先）
4. **コミット実行はユーザー承認後**（`rules/git-workflow.md` の承認フロー準拠）
5. 例外: impl ごとに worktree を分離した大規模構成でのみ、impl 各自の commit を許可する（index が分離されるため）

## harness 適応

Agent Teams API（`TeamCreate` / `TeamDelete` 等）が存在しない harness では、以下に読み替える:

- `TeamCreate` → 不要（暗黙の単一チーム）。メンバーは **name 付き Agent spawn** で作る
- メンバーへの指示・引き渡し → `SendMessage`（to: name）
- **teammate は永続する** — Wave が変わっても再 spawn せず、SendMessage で次 Wave のタスクを投入する（再 spawn はコンテキスト再構築分のトークンを浪費する）
- `TeamDelete` → 各メンバーへの完了指示（shutdown_request 相当）に読み替える

## SendMessage のタイムアウト・リトライ

- タイムアウト: デフォルト 5 分
- リトライ: 無応答なら 1 回再送 → 2 回目も無応答ならユーザーに手動対応依頼

## 権限外タスクの扱い

hook・permission によりブロックされる操作（削除ブロック、`.env*` への write deny 等）を impl / tester が報告してきた場合、**conductor が同じ操作を再試行しない**（conductor でも同様にブロックされる）。ブロックされた操作は内容と理由を添えて**ユーザーに手動実行を依頼**する。

## Wave 切り替え手順

次 Wave の指示を SendMessage で送信後、各メンバーの idle 通知が来たら `TaskList` で進捗を確認する。タスクが未クレームなら再送する（Wave 切り替え時のストール防止）。継続監視には定期ポーリングより **Bash の `sleep` ループによるポーリング**が実効的。

## 改善提案の拾い上げ（クリーンアップ直前）

最終判定 OK 後、クリーンアップに入る前に `review-final.md` の「改善提案」「軽微な指摘」を確認する。非ブロッキング項目が 1 件以上ある場合、件数と要約をユーザーに提示し「Issue 化しますか？」と確認する。承認されたら GitHub Issue を作成（対象リポジトリは現在の作業対象、`gh issue create` または GitHub MCP）。詳細手順は各 workflow ファイルの「Wave 3.5 / 4.5: 改善提案の拾い上げ」を参照。

## クリーンアップ

1. 全メンバーに `shutdown_request` → `TeamDelete` → 最終レポート表示
2. 実行ログを `/tmp/orchestra-{team-name}/{YYYY-MM-DD}-{task-slug}.md` に保存（テンプレート: `${CLAUDE_SKILL_DIR}/references/run-log-template.md`）
3. `/tmp/orchestra-{team-name}/raw/` の生トレースはそのまま同ディレクトリに残す
4. シャットダウン無応答時: 再送 1 回 → 60 秒待って無応答なら打ち切ってよい（ユーザーに手動対応を依頼し、待ち続けない）

## エスカレーション

- 修正ループ 3 回超 → ユーザーにエスカレーション
- architect レビュー 2 回超で契約書が収束しない → ユーザーに方針確認
