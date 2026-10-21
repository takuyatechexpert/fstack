#!/usr/bin/env python3
"""review-pr スキルの構造整合性チェック。

reference を編集したら実行する。frontmatter は strict YAML でパースするため
grep では代替できない（キーの重複・インデント崩れは grep を素通りする）。

    python3 design/check_structure.py

変異テスト（このスクリプト自身が壊れを検出できるかの確認）は CHECK_ROOT で
別ディレクトリのコピーを指定して行う。

    CHECK_ROOT=/path/to/mutant python3 design/check_structure.py
"""
import re, sys, os, pathlib

try:
    import yaml
except ImportError:
    print("PyYAML が必要です: pip install pyyaml"); sys.exit(2)

ROOT = pathlib.Path(os.environ.get("CHECK_ROOT", pathlib.Path(__file__).resolve().parent.parent))
REFS = ROOT / "references"
passed, failed = [], []


def check(name, ok, ng_detail="", ok_detail=""):
    d = ok_detail if ok else ng_detail
    (passed if ok else failed).append(f"{name}{(' — ' + d) if d else ''}")


md_files = [ROOT / "SKILL.md"] + sorted(REFS.glob("*.md"))

# 1. frontmatter の strict YAML パース
for f in md_files:
    text = f.read_text(encoding="utf-8")
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end == -1:
            check(f"frontmatter終端 {f.name}", False, "閉じ --- が無い"); continue
        try:
            meta = yaml.safe_load(text[4:end])
            check(f"frontmatter YAML {f.name}", isinstance(meta, dict) or meta is None)
        except yaml.YAMLError as e:
            check(f"frontmatter YAML {f.name}", False, str(e).split("\n")[0])
    else:
        check(f"frontmatter有無 {f.name}", True, ok_detail="frontmatter なし（許容）")

# 2. reference の実在
referenced = set()
for f in md_files:
    referenced |= set(re.findall(r'`([a-z0-9\-]+\.md)`', f.read_text(encoding="utf-8")))
existing = {p.name for p in REFS.glob("*.md")}
EXTERNAL = {"SKILL.md", "CLAUDE.md", "README.md", "TEST_POLICY.md",
            "implementation-flow.md", "context-management.md"}
missing = sorted(referenced - existing - EXTERNAL)
check("reference 実在", not missing,
      ng_detail=f"未解決: {missing}", ok_detail=f"{len(referenced & existing)}件すべて実在")

# 3. オーファン検出
orphans = sorted(existing - referenced)
check("オーファン無し", not orphans, ng_detail=f"孤立: {orphans}")

# 4. /tmp 残存（worktree は .worktrees/ 配下という方針）
for f in md_files:
    hits = [l for l in f.read_text(encoding="utf-8").split("\n")
            if "/tmp/" in l and "でなくリポジトリ内" not in l and "はハーネスの許可" not in l]
    check(f"/tmp 残存なし {f.name}", not hits, ng_detail=f"{len(hits)}件: {hits[:1]}")

# 5. コードフェンスの対応
for f in md_files:
    n = f.read_text(encoding="utf-8").count("```")
    check(f"コードフェンス対応 {f.name}", n % 2 == 0,
          ng_detail=f"``` が {n} 個で奇数", ok_detail=f"{n} 個")

# 6. Pitfall 番号の連続性
nums = [int(m) for m in re.findall(r'^### (\d+)\. ', (ROOT / "SKILL.md").read_text(encoding="utf-8"), re.M)]
check("Pitfall 番号連続", nums == list(range(1, len(nums) + 1)),
      ng_detail=f"実際: {nums}", ok_detail=f"1..{len(nums)}")

# 7. worker カードの必須項目
roster = (REFS / "agent-roster.md").read_text(encoding="utf-8")
cards = re.findall(r'^### (worker\d+|verifier)', roster, re.M)
check("worker カード数", len(cards) == 9, ng_detail=f"{len(cards)}件: {cards}", ok_detail="9件")
for card in re.split(r'^### ', roster, flags=re.M)[1:]:
    name = card.split(" ")[0].split("\n")[0]
    if not name.startswith(("worker", "verifier")):
        continue
    need = ["**model**"] + ([] if name == "verifier" else ["**起動条件**", "**観点**"])
    lack = [k for k in need if k not in card]
    check(f"カード必須項目 {name}", not lack, ng_detail=f"不足: {lack}")

# 8. 共通出力スキーマの category enum が閉じている
CATEGORY_ENUM = ["arch", "perf", "logic", "test", "impact", "spec", "ui", "doc"]
m = re.search(r'^\s*category:\s*(\S.*)$', roster, re.M)
vals = [v.strip() for v in m.group(1).split("|")] if m else []
check("category enum 8値", vals == CATEGORY_ENUM,
      ng_detail=f"実際: {vals}", ok_detail=" | ".join(CATEGORY_ENUM))
check("category enum 閉じ宣言", "他の語を作らない" in roster,
      ng_detail="「他の語を作らない」の明示が無い")
mapping = {w: re.findall(r'`([a-z]+)`', cell)
           for w, cell in re.findall(r'^\| (worker\d+) \| (.+?) \|$', roster, re.M)}
lack = [w for w in (f"worker{i}" for i in range(1, 9))
        if not mapping.get(w) or set(mapping[w]) - set(CATEGORY_ENUM)]
check("category 主担当表", not lack,
      ng_detail=f"未定義/enum外: {lack}", ok_detail="worker1..8 すべて定義")

print(f"\n{'=' * 50}\nPASS {len(passed)} / FAIL {len(failed)}\n{'=' * 50}")
for x in passed:
    print(f"  PASS  {x}")
for x in failed:
    print(f"  FAIL  {x}")
sys.exit(1 if failed else 0)
