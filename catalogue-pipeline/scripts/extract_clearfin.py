#!/usr/bin/env python3
"""
Extracts label/value facts from a ClearFin card page's Next.js RSC payload.

ClearFin server-renders each card page as a stream of React-tree JSON chunks
(`self.__next_f.push([1, "..."])`), not a clean data API. The facts we want live
as literal rendered strings inside that tree, in two recurring shapes:

    ["$","dt",...,{"children":"<LABEL>"}] ... ["$","dd",...,{"children":"<VALUE>"}]
    ["$","span",...,{"children":"<LABEL>"}] ... ["$","strong",...,{"children":"<VALUE>"}]

This is RAW extraction only — output is discovery/comparison-grade evidence
(sourceType: comparisonSite / verificationStatus: unverified), never
issuerConfirmed. See card-catalogue.schema.json's sourceType vocabulary and
Phase 6/7 of the sourcing brief. Do not promote anything here into
contracts/card-catalogue.json without independently checking it against the
issuer's own page.

Usage: extract_clearfin.py <page.html> [<page.html> ...]
Writes one JSON object per input file to stdout (as a JSON array).
"""
import json
import re
import sys
from pathlib import Path

LABEL_VALUE_PATTERNS = [
    re.compile(
        r'"children":"(?P<label>[^"]{2,60})"\}\],\["\$","dd",[^\]]*,\{"className":"[^"]*",'
        r'"children":"(?P<value>[^"]{0,200})"',
    ),
    re.compile(
        r'"children":"(?P<label>[^"]{2,60})"\}\],\["\$","strong",[^\]]*,\{"children":"(?P<value>[^"]{0,200})"',
    ),
]

TITLE_PATTERN = re.compile(r'"className":"cardpg-title","children":"(?P<title>[^"]{2,120})"')
ISSUER_PATTERN = re.compile(r'"cardId":"(?P<card_id>[^"]+)","href":"(?P<href>[^"]*)","issuer":"(?P<issuer>[^"]+)"')
CHECKED_PATTERN = re.compile(r'"children":\["Checked ","(?P<date>[0-9-]+)"')
LEDE_PATTERN = re.compile(r'"className":"cardpg-lede","children":"(?P<lede>[^"]{0,300})"')


def decode_rsc(html: str) -> str:
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', html, re.DOTALL)
    full = "".join(chunks)
    return full.encode().decode("unicode_escape", errors="replace")


def extract_one(path: Path) -> dict:
    html = path.read_text(encoding="utf-8", errors="replace")
    decoded = decode_rsc(html)

    facts: dict[str, str] = {}
    for pattern in LABEL_VALUE_PATTERNS:
        for m in pattern.finditer(decoded):
            label = m.group("label").strip()
            value = m.group("value").strip()
            # First match wins — the stat-block pattern appears before repeated nav mentions of
            # the same label further down the page.
            if label and label not in facts:
                facts[label] = value

    title_m = TITLE_PATTERN.search(decoded)
    issuer_m = ISSUER_PATTERN.search(decoded)
    checked_m = CHECKED_PATTERN.search(decoded)
    lede_m = LEDE_PATTERN.search(decoded)

    slug = path.stem
    return {
        "sourceProvider": "clearfin",
        "sourceUrl": f"https://www.clearfin.ca/credit-cards/{slug}",
        "sourceRecordId": slug,
        "sourceType": "comparisonSite",
        "verificationStatus": "unverified",
        "retrievedAt": "2026-08-27",
        "clearfinCheckedDate": checked_m.group("date") if checked_m else None,
        "officialName": title_m.group("title") if title_m else None,
        "issuer": issuer_m.group("issuer") if issuer_m else None,
        "welcomeOfferLede": lede_m.group("lede") if lede_m else None,
        "facts": facts,
    }


def main() -> None:
    paths = [Path(p) for p in sys.argv[1:]]
    if not paths:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    results = [extract_one(p) for p in paths]
    json.dump(results, sys.stdout, indent=2, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
