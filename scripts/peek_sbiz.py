import csv, io, sys, zipfile, collections
sys.stdout.reconfigure(encoding="utf-8")
z = zipfile.ZipFile("data/raw/sbiz_202606.zip")
infos = z.infolist()
print("파일", len(infos), "합계 해제크기", sum(i.file_size for i in infos) // 1_000_000, "MB")
def nm(i):
    try:
        return i.filename.encode("cp437").decode("utf-8")
    except Exception:
        try:
            return i.filename.encode("cp437").decode("cp949")
        except Exception:
            return i.filename
for i in infos[:6]:
    print(" ", nm(i), i.file_size // 1_000_000, "MB")
first = infos[0]
with z.open(first) as f:
    rd = csv.reader(io.TextIOWrapper(f, encoding="utf-8", newline=""))
    head = next(rd)
    print("컬럼", len(head), head)
    rows = [next(rd) for _ in range(5)]
for r in rows[:2]:
    print(dict(zip(head, r)))
