#!/usr/bin/env python3
"""
process_sbiz.py - 소상공인시장진흥공단 상가(상권)정보 zip(시도별 CSV 16개, 약 240만 점포)을 집계해 _rawdata/ 에 저장한다.

출력(시도별 JSON `_rawdata/sb_{시도}.json` = {"dong": [...], "sg": [...], "biz": [...], "bld": [...]}, 전국 `_rawdata/sb_national.json`, `sb_meta.json`)
  dong : 법정동 단위 {do, sg, dong, n, big:[[대분류,n]], mid:[[중분류,n]≤12], sml:[[소분류,n]≤30], bld:[[건물명,n]≤8], adm:[행정동 ≤3]}
  sg   : 시군구 단위 {do, sg, n, big, mid, sml≤40, dongs:[[동,n]≤40], bld:[[건물명,동,n]≤10], nd(동 수)}
  biz  : 시군구×소분류(점포 BIZ_MIN 이상) {do, sg, sml, mid, big, n, share(시군구 내 비중 %), rank(시군구 내 소분류 순위), dongs:[[동,n]≤15], names:[대표 상호 샘플≤0]}
  bld  : 입점 점포 BLD_MIN 이상인 건물 {do, sg, dong, name, n, road, big:[[대분류,n]], sml:[[소분류,n]≤8], st:[[상호, 층, 소분류]≤STORE_MAX]}
전국: 소분류·대분류별 시도 분포.
점포 단위 개별 페이지는 만들지 않는다(약 240만 건). 상호명은 공개된 사업자 상호이며 건물 페이지의 입점 목록에만 쓴다.
"""
import csv, io, json, re, sys, time, zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "_rawdata"
SGG = json.loads((ROOT / "scripts" / "sgg_names.json").read_text(encoding="utf-8"))
csv.field_size_limit(1 << 20)
sys.path.insert(0, str(Path(__file__).parent))      # python -I 는 스크립트 폴더를 경로에 넣지 않는다
from brand_match import match as brand_match         # noqa: E402

BRAND_MIN = 60              # 브랜드 페이지를 만드는 최소 전국 매장 수
BRAND_CAT_SHARE = 0.6       # 대표 업종 비중이 이보다 낮으면(입점 매장 이름이 섞인 이름) 브랜드에서 뺀다
BRAND_SG_MIN = 3            # 브랜드×시군구 페이지 최소 매장 수
CAT_OVERRIDE = {"KFC": "버거"}   # 공단 분류가 부정확한 브랜드의 표시 업종

DO_MAP = {"서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주", "대전광역시": "대전", "울산광역시": "울산",
          "세종특별자치시": "세종", "경기도": "경기", "강원특별자치도": "강원", "강원도": "강원", "충청북도": "충북", "충청남도": "충남", "전북특별자치도": "전북",
          "전라북도": "전북", "전라남도": "전남", "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주"}
CODE_DO = {"11": "서울", "26": "부산", "27": "대구", "28": "인천", "29": "광주", "30": "대전", "31": "울산", "36": "세종", "41": "경기", "42": "강원", "43": "충북", "44": "충남",
           "45": "전북", "46": "전남", "47": "경북", "48": "경남", "50": "제주", "51": "강원", "52": "전북"}
_names = defaultdict(set)
for _code, (_do, _sg) in SGG.items():
    _names[_sg].add(_do)
NAME_DO = {k: next(iter(v)) for k, v in _names.items() if len(v) == 1}     # 시군구 이름이 전국에서 유일하면 시도를 이름으로 정한다(신규 코드 대응)
MID_FIX = {"법무관련": "법무 관련 서비스", "장례식장": "장례식장·묘지", "비알코올": "비알코올 음료점"}      # 원본에서 잘린 중분류 이름 복원
GENERIC_BLD = {"명칭없음", "없음", "일부", "우측", "좌측", "우측호", "좌측호", "상가", "상가동", "상가건물", "근린생활시설", "근린생활", "근생", "근린상가", "주상복합", "상가주택", "아파트", "단독", "단독주택", "창고", "공장", "건물", "본관", "별관", "신관", "구관", "무명", "미상", "해당없음", "상가호"}


def fix_mid(m):
    m = (m or "").strip()
    return MID_FIX.get(m, m)


def good_bld(name):
    n = name.strip()
    return len(n) >= 3 and n not in GENERIC_BLD and not re.fullmatch(r"[0-9\-\s]+", n)


BIZ_MIN = 20
BLD_MIN = 8
STORE_MAX = 120
MIN_STORES = 1_500_000      # 이보다 적으면 수집 실패로 보고 중단


def sg_name(code, raw):
    """시군구코드 → 다른 사이트와 같은 표기(sgg_names.json); 없으면 원본에서 공백 제거(예: '수원시 장안구' → '수원시장안구')."""
    if code in SGG:
        return SGG[code][1]
    return (raw or "").replace(" ", "")


GWANGJU_GU = {"동구", "서구", "남구", "북구", "광산구"}


def merged_do(raw_do, sg):
    """통합특별시 표기(전남광주통합특별시 등)와 신규 코드 시군구: 광주 5개 구만 광주, 나머지는 전남."""
    if raw_do == "전남광주통합특별시":
        return "광주" if sg in GWANGJU_GU else "전남"
    return DO_MAP.get(raw_do, raw_do)


def top(counter, n):
    return [[k, v] for k, v in counter.most_common(n)]


def main():
    t0 = time.time()
    zname = sorted(RAW.glob("sbiz_*.zip"))[-1]
    z = zipfile.ZipFile(zname)
    period = re.search(r"(\d{6})", zname.name).group(1)
    dong = defaultdict(lambda: {"n": 0, "big": Counter(), "mid": Counter(), "sml": Counter(), "bld": Counter(), "adm": Counter()})
    sg = defaultdict(lambda: {"n": 0, "big": Counter(), "mid": Counter(), "sml": Counter(), "dong": Counter(), "bld": Counter()})
    sml_dong = defaultdict(Counter)                  # (do, sg, sml) -> Counter(dong)
    sml_meta = {}                                    # sml -> (mid, big)
    bld = defaultdict(lambda: {"stores": [], "road": "", "big": Counter(), "sml": Counter()})
    nat_sml = defaultdict(Counter)                   # sml -> Counter(do)
    br_n = Counter()                                 # 브랜드 -> 전국 매장 수
    br_cat = defaultdict(Counter)                    # 브랜드 -> 소분류 분포
    br_do = defaultdict(Counter)                     # 브랜드 -> 시도 분포
    br_sg = defaultdict(Counter)                     # 브랜드 -> (do, sg) 분포
    br_dong = defaultdict(Counter)                   # 브랜드 -> (do, sg, dong) 분포
    dong_br = defaultdict(Counter)                   # (do, sg, dong) -> 브랜드 분포
    sg_br = defaultdict(Counter)                     # (do, sg) -> 브랜드 분포
    total = 0
    for info in z.infolist():
        if not info.filename.endswith(".csv"):
            continue
        with z.open(info) as f:
            rd = csv.reader(io.TextIOWrapper(f, encoding="utf-8", newline=""))
            head = next(rd)
            ix = {h: i for i, h in enumerate(head)}
            iname, ibr = ix["상호명"], ix["지점명"]
            ib, im, is_ = ix["상권업종대분류명"], ix["상권업종중분류명"], ix["상권업종소분류명"]
            ido, isgc, isgn, iadm, ildong = ix["시도명"], ix["시군구코드"], ix["시군구명"], ix["행정동명"], ix["법정동명"]
            ibld, ifl, iroad = ix["건물명"], ix["층정보"], ix["도로명주소"]
            n = 0
            for r in rd:
                if len(r) < len(head):
                    continue
                # 시군구코드로 시도 표기를 다른 사이트와 맞춘다(전남광주 통합 파일 대응). 코드가 신규라 매핑에 없으면 앞 2자리로 시도를 정한다
                s = sg_name(r[isgc], r[isgn])
                do = SGG[r[isgc]][0] if r[isgc] in SGG else NAME_DO.get(s) or CODE_DO.get(r[isgc][:2]) or merged_do(r[ido], s)
                d = r[ildong] or r[iadm]
                if not d or not s:
                    continue
                n += 1
                big, mid, sml = r[ib], fix_mid(r[im]), r[is_]
                sml_meta.setdefault(sml, (mid, big))
                a = dong[(do, s, d)]
                a["n"] += 1
                a["big"][big] += 1
                a["mid"][mid] += 1
                a["sml"][sml] += 1
                if r[iadm]:
                    a["adm"][r[iadm]] += 1
                b = sg[(do, s)]
                b["n"] += 1
                b["big"][big] += 1
                b["mid"][mid] += 1
                b["sml"][sml] += 1
                b["dong"][d] += 1
                sml_dong[(do, s, sml)][d] += 1
                nat_sml[sml][do] += 1
                bb = brand_match(r[iname], r[ibr])
                if bb:
                    br_n[bb] += 1
                    br_cat[bb][sml] += 1
                    br_do[bb][do] += 1
                    br_sg[bb][(do, s)] += 1
                    br_dong[bb][(do, s, d)] += 1
                    dong_br[(do, s, d)][bb] += 1
                    sg_br[(do, s)][bb] += 1
                bn = r[ibld].strip()
                if bn and good_bld(bn):
                    a["bld"][bn] += 1
                    b["bld"][(bn, d)] += 1
                    e = bld[(do, s, d, bn)]
                    e["big"][big] += 1
                    e["sml"][sml] += 1
                    if not e["road"]:
                        e["road"] = r[iroad]
                    nm = (r[iname] + (" " + r[ibr] if r[ibr] else "")).strip()
                    if len(e["stores"]) < 400:
                        e["stores"].append([nm, r[ifl], sml])
            total += n
            print(f"  {info.filename[-22:]}: {n:,}건 ({time.time() - t0:.0f}s)", flush=True)
    print(f"점포 {total:,}건 / 법정동 {len(dong):,} / 시군구 {len(sg)} / 건물(이름 있음) {len(bld):,}", flush=True)
    if total < MIN_STORES:
        raise SystemExit(f"점포가 {total:,}건뿐입니다(최소 {MIN_STORES:,}). 수집 실패로 보여 중단합니다.")

    kept = {}
    for b, n in br_n.items():
        cat, cn = br_cat[b].most_common(1)[0]
        if n >= BRAND_MIN and cn / n >= BRAND_CAT_SHARE:
            kept[b] = CAT_OVERRIDE.get(b, cat)
    print(f"브랜드 {len(br_n)}개 매칭 → 페이지 대상 {len(kept)}개 (매장 {sum(br_n[b] for b in kept):,})", flush=True)

    out = defaultdict(lambda: {"dong": [], "sg": [], "biz": [], "bld": []})
    for (do, s, d), a in dong.items():
        out[do]["dong"].append({"do": do, "sg": s, "dong": d, "n": a["n"], "big": top(a["big"], 10), "mid": top(a["mid"], 12), "sml": top(a["sml"], 30), "bld": top(a["bld"], 8), "adm": [k for k, _ in a["adm"].most_common(3)],
                              "brands": [[b, c] for b, c in dong_br[(do, s, d)].most_common(30) if b in kept][:10]})
    for (do, s), b in sg.items():
        out[do]["sg"].append({"do": do, "sg": s, "n": b["n"], "nd": len(b["dong"]), "big": top(b["big"], 10), "mid": top(b["mid"], 15), "sml": top(b["sml"], 40),
                              "dongs": top(b["dong"], 40), "bld": [[k[0], k[1], v] for k, v in b["bld"].most_common(10)],
                              "brands": [[bb, c] for bb, c in sg_br[(do, s)].most_common(40) if bb in kept][:15]})
        ranks = {k: i + 1 for i, (k, _) in enumerate(b["sml"].most_common())}
        for sml, cnt in b["sml"].items():
            if cnt >= BIZ_MIN:
                mid, big = sml_meta[sml]
                out[do]["biz"].append({"do": do, "sg": s, "sml": sml, "mid": mid, "big": big, "n": cnt, "share": round(100 * cnt / b["n"], 2), "rank": ranks[sml],
                                       "dongs": top(sml_dong[(do, s, sml)], 15)})
    nb = 0
    for (do, s, d, bn), e in bld.items():
        n = len(e["stores"]) if len(e["stores"]) < 400 else sum(e["sml"].values())
        n = sum(e["sml"].values())
        if n < BLD_MIN:
            continue
        stores = sorted(e["stores"], key=lambda x: (x[1] == "", x[1], x[0]))[:STORE_MAX]
        out[do]["bld"].append({"do": do, "sg": s, "dong": d, "name": bn, "n": n, "road": e["road"], "big": top(e["big"], 6), "sml": top(e["sml"], 8), "st": stores})
        nb += 1

    OUT.mkdir(exist_ok=True)
    for old in OUT.glob("sb_*.json"):
        old.unlink()
    for do, v in out.items():
        for k in v:
            v[k].sort(key=lambda r: (r.get("sg", ""), r.get("dong", ""), r.get("sml", ""), r.get("name", "")))
        (OUT / f"sb_{do}.json").write_text(json.dumps(v, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    brands_out, bxsg = [], []
    for b, cat in kept.items():
        mid, big = sml_meta.get(cat, ("", ""))
        brands_out.append({"name": b, "cat": cat, "mid": mid, "big": big, "n": br_n[b], "nsg": len(br_sg[b]),
                           "do": [[d, c] for d, c in br_do[b].most_common()],
                           "sgTop": [[d, g, c] for (d, g), c in br_sg[b].most_common(30)],
                           "dongTop": [[d, g, dn, c] for (d, g, dn), c in br_dong[b].most_common(20)]})
    kept_set = set(kept)
    by_bsg = defaultdict(lambda: defaultdict(Counter))
    for b in kept_set:
        for (d, g, dn), c in br_dong[b].items():
            by_bsg[b][(d, g)][dn] += c
    for b in kept_set:
        for (d, g), c in br_sg[b].items():
            if c >= BRAND_SG_MIN:
                bxsg.append({"brand": b, "do": d, "sg": g, "n": c, "dongs": top(by_bsg[b][(d, g)], 12)})
    brands_out.sort(key=lambda x: -x["n"])
    (OUT / "sb_brand.json").write_text(json.dumps({"brands": brands_out, "bxsg": bxsg}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"브랜드 페이지 {len(brands_out)} / 브랜드×시군구 {len(bxsg):,}", flush=True)

    nat = {"sml": {k: [[d, c] for d, c in v.most_common()] for k, v in nat_sml.items()}, "meta": {k: list(v) for k, v in sml_meta.items()}}
    (OUT / "sb_national.json").write_text(json.dumps(nat, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    (OUT / "sb_meta.json").write_text(json.dumps({"period": period, "stores": total, "dong": len(dong), "sg": len(sg), "bld": nb}), encoding="utf-8")
    sz = sum(f.stat().st_size for f in OUT.glob("sb_*.json")) / 1e6
    print(f"완료: 동 {len(dong):,} / 시군구 {len(sg)} / 업종×시군구 {sum(len(v['biz']) for v in out.values()):,} / 건물 {nb:,} / {sz:.1f}MB / {time.time() - t0:.0f}s", flush=True)


if __name__ == "__main__":
    main()
