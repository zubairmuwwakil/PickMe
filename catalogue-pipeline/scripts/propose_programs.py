#!/usr/bin/env python3
"""
Proposes cardId -> program for the Stage C promoter, and — more importantly — separates the
candidates whose rewards currency HAS NO programId ENUM VALUE.

WHY THE THIRD BUCKET IS THE POINT

programId is a closed enum of 22 values, 16 Canadian plus the six US programs Stage A seeded
(chaseUltimateRewards, amexMembershipRewardsUs, citiThankYou, capitalOneMiles, discoverCashback,
bofaPreferredRewards). Those cover the issuers' own proprietary currencies. They do not cover
what the US market actually consists of: co-brands. Delta SkyMiles, AAdvantage, JetBlue TrueBlue,
Alaska/Atmos, Hyatt, IHG, Avios, Emirates Skywards — plus a long tail of store cards.

Forcing those onto an existing enum value would be a lie with a schema's authority behind it: a
Delta card mapped to amexMembershipRewardsUs is not "approximately right", it values the card in
a currency it does not earn. So they land in `needsEnumValue` with the real currency named, and
extending the enum becomes an explicit decision with a count attached rather than a silent
default.

  scripts/propose_programs.py --market US
  scripts/propose_programs.py --market CA

Writes card-programs.proposed.json (three buckets). Review it, then move the entries you accept
into card-programs.json, which is what promote_drafts.py actually reads. Two files on purpose:
a generated proposal is not the same artefact as an accepted mapping, and conflating them means
a re-run silently overwrites your review.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "catalogue-pipeline"
QUEUE = PIPELINE / "card-research-queue.json"
SCHEMA = ROOT / "contracts" / "schema" / "card-catalogue.schema.json"

# Co-brand currencies that DO have an enum value. Checked first: "Chase Marriott" is a Chase card
# but it does not earn Ultimate Rewards.
ENUM_COBRAND = [
    (r"marriott|ritz-?carlton|bonvoy", "marriottBonvoy", "point"),
    (r"\baeroplan\b", "aeroplan", "point"),
]

# Co-brand currencies with NO enum value. The value is the real currency's name, carried into the
# proposal so the enum decision is made against facts rather than a count of "others".
MISSING_ENUM_COBRAND = [
    (r"delta|skymiles", "Delta SkyMiles"),
    (r"aadvantage|american airlines", "AAdvantage"),
    (r"jetblue", "JetBlue TrueBlue"),
    (r"alaska|atmos", "Alaska Mileage Plan / Atmos"),
    (r"hawaiian", "Hawaiian Miles"),
    (r"emirates|skywards", "Emirates Skywards"),
    (r"frontier", "Frontier Miles"),
    (r"free spirit|spirit airlines", "Spirit Free Spirit"),
    (r"aer lingus|british airways|iberia|avios", "Avios"),
    (r"united|mileageplus", "United MileagePlus"),
    (r"southwest|rapid rewards", "Southwest Rapid Rewards"),
    (r"\bhyatt\b", "World of Hyatt"),
    (r"\bihg\b", "IHG One Rewards"),
    (r"hilton|honors", "Hilton Honors"),
    (r"wyndham", "Wyndham Rewards"),
    (r"choice privileges", "Choice Privileges"),
    (r"disney", "Disney Rewards"),
    (r"cathay", "Cathay Asia Miles"),
    (r"carnival|celebrity|princess|royal caribbean", "Cruise-line loyalty"),
    (r"amazon", "Amazon Rewards (US) — distinct from the CA amazonRewards entry"),
    (r"paypal|venmo", "PayPal / Venmo cashback"),
    (r"costco", "Costco Cash Rewards"),
    (r"kohl|sam's club|sears|walgreens|\bgap\b|athleta|banana republic|nordstrom|target|bj's",
     "Store-specific rewards"),
    (r"harley|verizon|carecredit|aarp|\bnhl\b|morgan stanley|robinhood|\bsofi\b",
     "Brand-specific rewards"),
]

# Issuer-proprietary rules, applied only when no co-brand matched. Ordered: cashback tokens are
# checked before the issuer's points program, because "Capital One Quicksilver Cash Rewards" is a
# cashback card from an issuer whose flagship currency is miles.
ISSUER_RULES = {
    "Discover": [(r".", "discoverCashback", "usd")],
    "Chase": [
        (r"freedom|ink business cash", "chaseUltimateRewards", "point"),
        (r"sapphire|\bink\b", "chaseUltimateRewards", "point"),
    ],
    "Citi": [(r"custom cash|double cash|dividend|rewards\+|strata|prestige|premier|secured",
              "citiThankYou", "point")],
    "Capital One": [
        (r"quicksilver|savor|spark cash|platinum|journey|secured", "cashback", "usd"),
        (r"venture|spark miles", "capitalOneMiles", "point"),
    ],
    "Bank of America": [
        (r"customized cash|unlimited cash|cash rewards", "bofaPreferredRewards", "usd"),
        (r"travel rewards|premium rewards|bankamericard", "bofaPreferredRewards", "point"),
    ],
    "American Express": [
        (r"blue cash|cash magnet|business cash|simplycash|graphite", "cashback", "usd"),
        (r"gold|green|platinum|everyday|blue business plus|\bblue\b", "amexMembershipRewardsUs", "point"),
    ],
}

CASHBACK_FALLBACK = r"cash ?back|cash rewards"


def classify(name: str, issuer: str, market: str):
    s = (name or "").lower()

    for pat, pid, unit in ENUM_COBRAND:
        if re.search(pat, s):
            return ("proposed", {"programId": pid, "unit": unit, "basis": f"co-brand: {pat}"})

    for pat, currency in MISSING_ENUM_COBRAND:
        if re.search(pat, s):
            return ("needsEnumValue", {"currency": currency, "basis": f"co-brand: {pat}"})

    for pat, pid, unit in ISSUER_RULES.get(issuer, []):
        if re.search(pat, s):
            return ("proposed", {"programId": pid, "unit": unit, "basis": f"{issuer} family: {pat}"})

    if re.search(CASHBACK_FALLBACK, s):
        unit = "usd" if market == "US" else "cad"
        return ("proposed", {"programId": "cashback", "unit": unit, "basis": "name says cash back"})

    return ("unmapped", {"basis": "no signal in issuer or name"})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--market", required=True, choices=["US", "CA"])
    args = ap.parse_args()

    queue = json.loads(QUEUE.read_text())["queue"]
    aliases = json.loads((PIPELINE / "issuer-aliases.json").read_text())["aliases"].get(args.market, {})
    valid = set(json.loads(SCHEMA.read_text())["$defs"]["programId"]["enum"])

    buckets = {"proposed": {}, "needsEnumValue": {}, "unmapped": {}}
    seen = set()
    for e in queue:
        if e.get("country") != args.market:
            continue
        cid = e.get("cardId")
        if not cid or cid == "<batch>" or cid in seen:
            continue
        seen.add(cid)
        issuer = aliases.get(e.get("issuer"), e.get("issuer"))
        bucket, payload = classify(e.get("officialName"), issuer, args.market)
        if bucket == "proposed" and payload["programId"] not in valid:
            bucket, payload = "needsEnumValue", {"currency": payload["programId"],
                                                 "basis": "rule produced a non-enum programId"}
        payload["officialName"] = e.get("officialName")
        payload["issuer"] = issuer
        buckets[bucket][cid] = payload

    out = PIPELINE / f"card-programs.proposed.{args.market.lower()}.json"
    out.write_text(json.dumps(buckets, indent=2, sort_keys=True) + "\n")

    total = sum(len(v) for v in buckets.values())
    print(f"{args.market}: {total} candidates")
    for k, v in buckets.items():
        print(f"  {k:<16} {len(v)}")
    print("\n  proposed by programId:")
    for pid, n in Counter(v["programId"] for v in buckets["proposed"].values()).most_common():
        print(f"    {pid:<26} {n}")
    print("\n  needsEnumValue by currency:")
    for cur, n in Counter(v["currency"] for v in buckets["needsEnumValue"].values()).most_common():
        print(f"    {cur[:48]:<50} {n}")
    print(f"\nwritten to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
