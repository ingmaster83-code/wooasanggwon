#!/usr/bin/env python3
"""scaffold_from_land.py - 우아땅값 사이트의 공용 뼈대(CSS·JS·include·개인정보·robots·deploy·기본 레이아웃)를 복사해 우아상권용으로 치환한다(1회성)."""
import re, shutil, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
SRC = Path(r"C:\개인\wooahouse\wooaland")
DST = Path(r"C:\개인\wooahouse\wooasanggwon")

COLORS = {            # 그린 → 바이올렛
    "#15803D": "#6D28D9", "#15803d": "#6D28D9",
    "#22C55E": "#8B5CF6", "#22c55e": "#8B5CF6",
    "#166534": "#5B21B6",
    "#14532D": "#4C1D95", "#14532d": "#4C1D95",
    "#F0FDF4": "#F5F3FF", "#f0fdf4": "#F5F3FF",
    "#DCFCE7": "#EDE9FE", "#dcfce7": "#EDE9FE",
    "#BBF7D0": "#DDD6FE", "#bbf7d0": "#DDD6FE",
    "#86EFAC": "#C4B5FD", "#86efac": "#C4B5FD",
}
TEXT = [("wooaland", "wooasanggwon"), ("우아땅값", "우아상권")]


def conv(text):
    for a, b in COLORS.items():
        text = text.replace(a, b)
    for a, b in TEXT:
        text = text.replace(a, b)
    return text


def copy(rel, convert=True):
    s, d = SRC / rel, DST / rel
    d.parent.mkdir(parents=True, exist_ok=True)
    if convert:
        d.write_text(conv(s.read_text(encoding="utf-8")), encoding="utf-8")
    else:
        shutil.copyfile(s, d)
    print("복사:", rel)


for rel in ["assets/css/main.css", "assets/js/ad-dev-placeholder.js", "assets/js/wooa-sidebar.js", "assets/js/wooa-sites-bar.js",
            "_includes/ad.html", "_includes/faq.html", "privacy/index.html", "robots.txt", "CNAME", "Gemfile", "_layouts/default.html"]:
    copy(rel, convert=not rel.startswith("assets/js"))

p = DST / "_layouts" / "default.html"
s = p.read_text(encoding="utf-8")
s = re.sub(r'\s*<meta name="naver-site-verification"[^>]*/>\n', "\n", s)               # 새 사이트의 값은 사용자에게 받아 넣는다
s = s.replace("우아상권 - 토지·상가 실거래가와 땅값 시세", "우아상권 - 동네 상권분석·업종별 점포 수")
s = s.replace('<span class="logo-icon">🌱</span>', '<span class="logo-icon">🏪</span>')
s = re.sub(r'<nav class="header-nav">.*?</nav>', '''<nav class="header-nav">
      <a href="{{ '/biz/' | relative_url }}">업종</a>
      <a href="{{ '/rank/' | relative_url }}">랭킹</a>
      <a href="{{ '/search/' | relative_url }}">검색</a>
      <a href="https://wooahouse.com">WooaHouse →</a>
    </nav>''', s, count=1, flags=re.S)
s = s.replace("page.layout == 'hub' or page.layout == 'jimok' or page.layout == 'rank' or page.layout == 'kindindex'",
              "page.layout == 'dong' or page.layout == 'sg' or page.layout == 'do' or page.layout == 'biz' or page.layout == 'bizindex' or page.layout == 'building' or page.layout == 'rank'")
i = s.find('<p class="footer-disclaimer">')
j = s.find("</p>", i) + 4
disc = '''<p class="footer-disclaimer">
      점포 정보는 소상공인시장진흥공단 '상가(상권)정보'(공공데이터포털, 분기 갱신)를 법정동·시군구·건물 단위로 집계한 것입니다. 조사 시점 이후 개업·폐업·이전한 점포는 반영되지 않을 수 있습니다.<br>
      업종은 공단의 상권업종 분류(대·중·소분류) 기준이며, 점포 수는 창업·입지 판단을 위한 참고 자료입니다. 임대료·매출·유동인구는 포함하지 않으며 계약 전 현장 확인과 별도 상권 조사를 권장합니다.
    </p>'''
s = s[:i] + disc + s[j:]
s = s.replace('<a href="https://wooagongsi.wooahouse.com">우아공시가</a> ·', '<a href="https://wooagongsi.wooahouse.com">우아공시가</a> ·\n      <a href="https://wooaland.wooahouse.com">우아땅값</a> ·')
p.write_text(s, encoding="utf-8")

r = DST / "privacy" / "index.html"
t = r.read_text(encoding="utf-8")
t = re.sub(r'본 서비스는 [^<]*포함하지 않습니다\.', "본 서비스는 소상공인시장진흥공단 상가(상권)정보(공공데이터포털)를 정리해 제공합니다. 점포 상호·업종·주소·층 등 공개된 사업장 정보이며 개인의 연락처·주민등록번호 등은 포함하지 않습니다.", t)
r.write_text(t, encoding="utf-8")
print("기본 레이아웃 정리 완료")
