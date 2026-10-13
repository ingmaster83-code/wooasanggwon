"""brand_match.py - 상호명 → 브랜드 매칭(공용)."""
import re

from brands import BRANDS

_ALIASES = []          # (별칭, 브랜드) — 긴 별칭 우선
for _b, _al in BRANDS.items():
    for _a in _al:
        a = re.sub(r"[^0-9a-z가-힣]", "", _a.lower())
        if a:
            _ALIASES.append((a, _b))
_ALIASES.sort(key=lambda x: -len(x[0]))
_PAREN = re.compile(r"\(.*?\)")
_NON = re.compile(r"[^0-9a-z가-힣]")


def norm(name):
    return _NON.sub("", _PAREN.sub("", (name or "").lower()))


def match(name, branch=""):
    """상호명(과 지점명)으로 브랜드를 찾는다. 없으면 None."""
    n = norm(name)
    if len(n) < 2:
        return None
    full = n + norm(branch)
    for a, b in _ALIASES:
        if n.startswith(a):
            if len(a) <= 3:
                rest = n[len(a):]
                if not (rest == "" or rest.endswith("점") or branch):
                    continue
            return b
    return None
