# Audit Checklist（計測方法）

**基準の原典**: `~/.claude/skills/my-skill-creator/references/skill-standards.md`
本ファイルは基準を**再記述しない**。基準に対応する「計測コマンド・判定閾値・レポート出力フォーマット」のみを定義する。
基準自体を変更したい場合は `skill-standards.md` を編集すること。

Phase 1 では `skill-standards.md` を必ず Read した上で、本ファイルの手順に従って計測する。

---

## 計測項目と手順

### A. 構造・サイズ

| 項目 | 計測コマンド | 判定 |
|---|---|---|
| SKILL.md 行数 | `wc -l ~/.claude/skills/{name}/SKILL.md` | ≤300: ✓ / 301〜500: ⚠ / >500: ✗ |
| SKILL.md トークン | `bash ~/.claude/skills/my-skill-creator/scripts/count-tokens.sh ~/.claude/skills/{name}/SKILL.md` | ≤3000: ✓ / 3001〜5000: ⚠ / >5000: ✗ |
| references 最大行数 | `wc -l ~/.claude/skills/{name}/references/*.md` | ≤500/file: ✓ / >500: ⚠（分割検討） |
| scripts/ assets/ 配置 | `ls ~/.claude/skills/{name}/` | インライン肥大していないか目視 |

### B. description（トリガー設計）

| 項目 | 判定方法 |
|---|---|
| 1文化可能か | description をそのまま読み「〜も〜も〜も」が3つ以上ないか |
| トリガー網羅 | カジュアル言い換え（例: 「〜したい」「〜確認したい」「〜して」）が複数あるか |
| NOT 条件の明記 | 「以下では起動しない: ...」または同等の除外記述があるか |
| Recall/Precision 予測 | `evals/trigger-eval.json` があるか。なければ Step 3 で作成（目標 ≥90%） |

### C. 責務・設計原則

| 項目 | 判定方法 |
|---|---|
| 1スキル = 1責務 | B-1 と連動。SKILL.md 全体を読み、複数の独立ドメインが混在していないか |
| Phase 構成の明確さ | 番号付け・各 Phase の責務独立・主観判断（モード判定等）がスクリプト化されているか |
| DRY（共通フロー） | 複数モード間で処理重複がないか、共通化できていないか |

### D. 品質保証

| 項目 | 計測・判定方法 |
|---|---|
| eval 基盤（**必須**） | `ls ~/.claude/skills/{name}/evals/*.json` で確認。なし→✗（**Step 1 で強制構築**） |
| eval アサーション強度 | `expectations.json` を読み、見出し存在のみの trivially pass になっていないか |
| ベースライン記録 | 過去の pass_rate が `design/IMPROVEMENT-PLAN.md` 等に記録されているか |
| Pitfalls セクション | SKILL.md に存在するか。各項目に「症状 / Why / ルール」があるか。実体験ベースか（一般論のみなら ⚠） |
| ログ記録 | `skill-log.sh` 呼び出しが各分岐に入っているか。単一タグで済ませていないか |
| 出力フォーマット定義 | 定型出力のテンプレートが定義されているか |

### E-pre. セキュリティ（認証情報ハンドリング）

認証情報がトランスクリプトに平文で露出するリスクを検査する。原則は `~/.claude/rules/fstack-security.md`（fstack 配布時）または `~/.claude/rules/security.md` の「スキル内認証情報ハンドリング原則」を参照。

| 項目 | 計測コマンド | 判定 |
|---|---|---|
| ハードコード検査 | `grep -rEi '(api[_-]?key\|token\|secret)[[:space:]]*[:=][[:space:]]*["\x27][A-Za-z0-9._-]{8,}' ~/.claude/skills/{name}/` | マッチあり→✗ |
| echo/printf で secret 変数 | `grep -rEn '(echo\|printf)[^\|;&]*\$\{?[A-Z_]*(TOKEN\|KEY\|SECRET\|PASSWORD)' ~/.claude/skills/{name}/` | マッチあり→✗（hook で止まるが設計上もNG） |
| curl -v / --trace 使用 | `grep -rEn 'curl[^\|;&]*(-v\b\|--verbose\|--trace)' ~/.claude/skills/{name}/` | マッチあり→✗ |
| Bash層 vs Python層 | SKILL.md を読み、認証情報を Bash で `$VAR` 参照している箇所 | 存在→⚠（Python化検討） |
| 優先順位適合 | MCP > Python subprocess > Bash `$VAR` 参照 の順で使われているか | 逆行→⚠ |

### E. 保守性

| 項目 | 判定方法 |
|---|---|
| design/ 健全性 | `ls ~/.claude/skills/{name}/design/` で SPEC 等の実装済み仕様書が残っていないか |
| 参照整合性 | SKILL.md の references/ パスがすべて実在するか |
| "why" の説明 | 設計原則から MUST ではなく理由が書かれているか |

---

## レポート出力フォーマット

Phase 1 完了時に以下の形式でユーザーに提示する。各項目の**根拠**（なぜその判定になったか）は `skill-standards.md` の該当セクションを引用する形で書く。

```markdown
## 健康診断レポート: {skill-name}

### メトリクス
| カテゴリ | 項目 | 基準 | 実測 | 判定 |
|---|---|---|---|---|
| 構造 | SKILL.md 行数 | ≤500 | {N} | {✓/⚠/✗} |
| 構造 | SKILL.md トークン | ≤5000 | {N} | {✓/⚠/✗} |
| 構造 | references 最大行数 | ≤500 | {N} | {✓/⚠/✗} |
| description | 1文化可能 | Yes | {Y/N} | {✓/✗} |
| description | トリガー網羅 | カジュアル+NOT | {観察} | {✓/⚠/✗} |
| 責務 | 1責務 | Yes | {観察} | {✓/⚠/✗} |
| 品質 | eval 基盤 | あり | {有無} | {✓/✗} |
| 品質 | Pitfalls | 実体験ベース | {観察} | {✓/⚠/✗} |
| 品質 | ログ粒度 | 分岐ごと | {観察} | {✓/⚠/✗} |
| 保守 | design 健全性 | SPEC残存なし | {観察} | {✓/⚠/✗} |

### 所見（Why 込み）
- ...
  - 根拠: `skill-standards.md` L{行} 「...」

### 推奨 Step（優先度順）
- 🔴 Step 1: eval 基盤構築（必須）
- 🔴 Step 2: {最優先の改善}
- 🟡 Step 3: ...
- 🟢 Step 4: ...
```
