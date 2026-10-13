"""count_brands.py - brands.py 의 브랜드별 매칭 점포 수·대표 업종·상호 샘플을 점검한다(오탐 검토용)."""
import csv, io, sys, zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
sys.stdout.reconfigure(encoding="utf-8")
from brand_match import match  # noqa: E402

ROOT = Path(__file__).parent.parent
csv.field_size_limit(1 << 20)
z = zipfile.ZipFile(sorted((ROOT / "data" / "raw").glob("sbiz_*.zip"))[-1])
cnt = Counter()
cats = defaultdict(Counter)
samples = defaultdict(list)
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
            b = match(r[ix["상호명"]], r[ix["지점명"]])
            if b:
                cnt[b] += 1
                cats[b][r[ix["상권업종소분류명"]]] += 1
                if len(samples[b]) < 4 and (cnt[b] % 37 == 1):
                    samples[b].append(r[ix["상호명"]])
tot = sum(cnt.values())
print("매칭 점포", tot, "브랜드", len(cnt))
for b, c in cnt.most_common():
    top = cats[b].most_common(2)
    print(f"{b:14s} {c:6d}  {top[0][0]}({top[0][1]}) {'/' + top[1][0] + '(' + str(top[1][1]) + ')' if len(top) > 1 else ''}  {samples[b][:3]}")
