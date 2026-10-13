"""discover_brands.py - 상호명 앞부분이 전국 여러 시군구에 반복되는 이름(프랜차이즈 후보)을 찾는다. 결과는 사람이 검토해 scripts/brands.py 를 만든다."""
import csv, io, json, re, sys, zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
csv.field_size_limit(1 << 20)
z = zipfile.ZipFile(sorted((ROOT / "data" / "raw").glob("sbiz_*.zip"))[-1])
cnt = Counter()
spread = defaultdict(set)
cat = defaultdict(Counter)
N = 0
for info in z.infolist():
    if not info.filename.endswith(".csv"):
        continue
    with z.open(info) as f:
        rd = csv.reader(io.TextIOWrapper(f, encoding="utf-8", newline=""))
        head = next(rd)
        ix = {h: i for i, h in enumerate(head)}
        for r in rd:
            if len(r) < len(head):
                continue
            nm = re.sub(r"\(.*?\)", "", r[ix["상호명"]])
            nm = re.sub(r"[^0-9A-Za-z가-힣]", "", nm).lower()
            if len(nm) < 2:
                continue
            N += 1
            sgc = r[ix["시군구코드"]]
            sml = r[ix["상권업종소분류명"]]
            for k in range(2, 9):
                if len(nm) < k:
                    break
                p = nm[:k]
                cnt[p] += 1
                if len(spread[p]) < 400:
                    spread[p].add(sgc)
            # 지점명이 따로 있으면 상호명 자체가 브랜드일 가능성이 높다
            if r[ix["지점명"]].strip():
                cnt["§" + nm] += 1
                spread["§" + nm].add(sgc)
                cat["§" + nm][sml] += 1
print("점포", N, "프리픽스", len(cnt))
rows = [(p, c, len(spread[p])) for p, c in cnt.items() if c >= 120 and len(spread[p]) >= 50]
rows.sort(key=lambda x: -x[1])
print("후보", len(rows))
out = [{"p": p, "n": c, "sg": s} for p, c, s in rows[:3500]]
(ROOT / "data" / "brand_candidates.json").write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
for p, c, s in rows[:60]:
    print(p, c, s)
