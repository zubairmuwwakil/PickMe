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
import os
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
    (r"aadvantage|american airlines", "aaAdvantage", "point"),
    (r"alaska|atmos|hawaiian", "atmosRewards", "point"),
    (r"aer lingus|british airways|iberia|\bavios\b|qatar airways|privilege club", "avios", "point"),
    (r"cathay", "cathayAsiaMiles", "point"),
    (r"delta|skymiles", "deltaSkyMiles", "point"),
    (r"disney", "disneyRewards", "usd"),
    (r"free spirit|spirit airlines", "spiritFreeSpirit", "point"),
]

# Co-brand currencies with NO enum value. The value is the real currency's name, carried into the
# proposal so the enum decision is made against facts rather than a count of "others".
MISSING_ENUM_COBRAND = [
    # Airlines
    (r"jetblue", "JetBlue TrueBlue"),
    (r"emirates|skywards", "Emirates Skywards"),
    (r"frontier", "Frontier Miles"),
    (r"united|mileageplus", "United MileagePlus"),
    (r"southwest|rapid rewards", "Southwest Rapid Rewards"),
    (r"air france|klm|flying blue", "Air France-KLM Flying Blue"),
    (r"allways rewards|allegiant", "Allegiant Allways Rewards"),
    (r"breeze easy|breezepoints", "BreezePoints"),
    (r"miles & more", "Miles & More"),
    (r"avianca|lifemiles", "Avianca LifeMiles"),
    (r"latam pass|latam airlines", "LATAM Pass Miles"),
    (r"tap miles&go|tap air portugal", "TAP Miles&Go"),
    # Hotels & Lodging
    (r"\bhyatt\b", "World of Hyatt"),
    (r"\bihg\b", "IHG One Rewards"),
    (r"hilton|honors", "Hilton Honors"),
    (r"wyndham", "Wyndham Rewards"),
    (r"choice privileges", "Choice Privileges"),
    (r"capital vacations", "Capital Vacations Rewards"),
    (r"rci elite|rci\b", "RCI Elite Rewards"),
    # Cruise-line
    (r"carnival|celebrity|princess|royal caribbean|norwegian cruise|\bncl\b|royal one", "Cruise-line loyalty"),
    # Rail
    (r"amtrak", "Amtrak Guest Rewards"),
    # Brand / Retail / Store
    (r"amazon (store|secured)", "Amazon Store Card (US) — closed-loop"),
    (r"paypal|venmo", "PayPal / Venmo cashback"),
    (r"gm rewards|gm business|\bgm\b", "My GM Rewards"),
    (r"luxury card", "Luxury Card Rewards"),
    (r"upromise", "Upromise Cash Back"),
    (r"bilt", "Bilt Rewards"),
    (r"gemini", "Gemini Crypto Rewards"),
    (r"more rewards", "More Rewards"),
    (r"brim", "Brim Rewards"),
    (r"aspire travel", "Capital One Canada Aspire Reward Miles"),
]

# Evidence-driven classification, replacing the two catch-all NAME regexes deleted on
# 2026-08-27. Those recorded a `basis` that was literally the alternation which matched the
# card's name — no reward text was ever read — and the licensed cc-offers snapshot's own
# `category` field disagreed with them for 9 of the 19 cards whose provenance survived.
#
# This ROUTES a draft; it never VERIFIES one. A third-party category is not D3 evidence, so
# everything it produces lands `status: "draft"` with `earnRules: []`, never issuerConfirmed,
# and promotion still requires reading the issuer's own site.
CASH_BACK_CATEGORIES = {
    "CASH_BACK", "DIGITAL_WALLET_CASH_BACK", "WAREHOUSE_CLUB_CASH_BACK",
    "GAS_RESTAURANT_CASH_BACK", "TRAVEL_CASH_BACK", "EDUCATION_SAVINGS_CASH_BACK",
}

MERCHANT_LOCKED_CATEGORIES = {
    "RETAIL_REWARDS", "RETAIL_REWARDS_AND_FINANCING", "WAREHOUSE_CLUB_REWARDS",
    "WAREHOUSE_CLUB_CREDIT", "CRUISE_REWARDS", "HEALTH_WELLNESS_REWARDS",
}


def classify_from_evidence(row):
    """Classify one raw cc-offers row by its `category`, never by its name.

    Returns (kind, payload) where kind is "proposed", "needsEnumValue" or "refused".
    """
    category = row.get("category")
    if not category:
        return ("refused", {
            "reason": "provenanceWithdrawn",
            "basis": "no retained in-repo provenance; the opencard snapshot was removed by the "
                     "licence audit and this card must be re-sourced from issuer material",
        })

    if category in CASH_BACK_CATEGORIES:
        issuer = (row.get("issuer") or "").lower()
        program_id = "discoverCashback" if "discover" in issuer else "cashback"
        return ("proposed", {
            "programId": program_id,
            "unit": "cad",
            "basis": f"cc-offers category: {category} (routes a draft; does not verify it)",
        })

    if category.endswith("_FINANCING"):
        return ("proposed", {
            "programId": "noRewards",
            "unit": "cad",
            "basis": f"cc-offers category: {category} — a financing product, no rewards programme",
        })

    if category in MERCHANT_LOCKED_CATEGORIES:
        return ("needsEnumValue", {
            "currency": "merchantCredit",
            "basis": f"cc-offers category: {category} — merchant-locked; needs a per-brand "
                     f"programId and a published face value before it can be valued",
        })

    return ("refused", {
        "reason": "unclassifiedCategory",
        "basis": f"cc-offers category: {category} — no routing rule; needs issuer research",
    })

# Dedicated noRewards patterns across issuers (cards with 0% rewards, low APR, balance transfer, credit building, merchant financing)
NO_REWARDS_PATTERNS = (
    r"true line|guaranteed secured|diamond preferred|simplicity|\bslate\b|slate edge|"
    r"greenselect|pnc core|penfed gold|alliant visa.*platinum|business shield|\bshield\b|"
    r"split.*world|reflect|boost secured|bmo platinum(?! rewards)|cutting edge|"
    r"synchrony (car care|luxury|music & sound|outdoors|project|sewing & more|sport)"
)

# Issuer-proprietary rules, applied only when no co-brand matched. Ordered: cashback tokens are
# checked before the issuer's points program, because "Capital One Quicksilver Cash Rewards" is a
# cashback card from an issuer whose flagship currency is miles.
ISSUER_RULES = {
    "Discover": [(r".", "discoverCashback", "usd")],
    "Chase": [
        (r"jpmorgan reserve", "chaseUltimateRewards", "point"),
        (r"freedom|ink business cash", "chaseUltimateRewards", "point"),
        (r"sapphire|\bink\b", "chaseUltimateRewards", "point"),
    ],
    "Citi": [
        (r"at&t points plus", "citiThankYou", "point"),
        (r"custom cash|double cash|dividend|rewards\+|strata|prestige|premier|secured",
         "citiThankYou", "point"),
    ],
    "Capital One": [
        (r"quicksilver|savor|spark cash|platinum|journey|secured|spark 1%", "cashback", "usd"),
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
    "U.S. Bank": [
        (r"cash\+|smartly|state farm cash", "cashback", "usd"),
        (r"altitude", "U.S. Bank Altitude Points", None),
        (r"business leverage", "U.S. Bank Business Rewards Points", None),
        (r"secured|platinum", "noRewards", "none"),
    ],
    "Wells Fargo": [
        (r"active cash", "cashback", "usd"),
        (r"autograph|attune", "Wells Fargo Rewards", None),
    ],
    "FNBO": [
        (r"evergreen", "cashback", "usd"),
        (r"getaway", "FNBO Rewards Points", None),
    ],
    "Navy Federal Credit Union": [
        (r"cashrewards", "cashback", "usd"),
        (r"flagship rewards|go rewards|more rewards", "Navy Federal Rewards", None),
    ],
    "PNC Bank": [
        (r"pnc points", "PNC Points", None),
    ],
    "PenFed Credit Union": [
        (r"pathfinder", "PenFed Points", None),
    ],
    "TD Bank USA": [
        (r"td cash|business solutions|double up", "cashback", "usd"),
        (r"first class", "TD First Class Miles (US)", None),
    ],
    "BMO Bank N.A.": [
        (r"platinum rewards|premium rewards|escape", "BMO Rewards (US)", None),
    ],
    "HSBC": [
        (r"elite|premier", "HSBC Rewards (US)", None),
    ],
    "Goldman Sachs": [
        (r"apple card", "cashback", "usd"),
    ],
    "Comenity": [
        (r"aaa daily advantage", "cashback", "usd"),
        (r"bread rewards", "Bread Rewards", None),
    ],
    "Bread Financial": [
        (r"bread rewards", "Bread Rewards", None),
        (r"kayak", "KAYAK Points", None),
    ],
    "Elan Financial Services": [
        (r"fidelity rewards", "cashback", "usd"),
    ],
    "Petal": [
        (r"petal [12]", "cashback", "usd"),
    ],
    "Synchrony": [
        (r"premier|plus|preferred|home", "cashback", "usd"),
    ],
    "Neo Financial": [
        (r"neo world", "cashback", "cad"),
    ],
}

CASHBACK_FALLBACK = r"cash ?back|cash rewards"


def classify(name: str, issuer: str, market: str, valid_enums: set[str] | None = None,
             evidence_row: dict | None = None):
    s = (name or "").lower()

    if re.search(NO_REWARDS_PATTERNS, s):
        return ("proposed", {"programId": "noRewards", "unit": "none", "basis": f"no-rewards card: {name}"})

    if market == "US" and re.search(r"prime visa|amazon visa", s):
        return ("proposed", {"programId": "cashback", "unit": "usd", "basis": "US Chase Amazon co-brand: 1:1 statement credit and direct deposit"})

    if market == "US" and re.search(r"costco", s):
        return ("proposed", {"programId": "cashback", "unit": "usd", "basis": "US Citi Costco co-brand: 1.0 cash floor / direct deposit"})

    if market == "CA" and re.search(r"costco", s):
        return ("needsEnumValue", {"currency": "costcoCashRewardsCa", "basis": "CA CIBC Costco co-brand: store-locked CAD certificate"})

    if market == "CA" and re.search(r"amazon", s):
        return ("proposed", {"programId": "amazonRewards", "unit": "point", "basis": "CA MBNA Amazon co-brand: 100 pts = $1 Amazon.ca credit"})

    for pat, pid, unit in ENUM_COBRAND:
        if re.search(pat, s):
            return ("proposed", {"programId": pid, "unit": unit, "basis": f"co-brand: {pat}"})

    for pat, currency in MISSING_ENUM_COBRAND:
        if re.search(pat, s):
            return ("needsEnumValue", {"currency": currency, "basis": f"co-brand: {pat}"})

    for pat, pid, unit in ISSUER_RULES.get(issuer, []):
        if re.search(pat, s):
            if valid_enums and pid not in valid_enums:
                return ("needsEnumValue", {"currency": pid, "basis": f"{issuer} family: {pat}"})
            return ("proposed", {"programId": pid, "unit": unit, "basis": f"{issuer} family: {pat}"})

    if re.search(CASHBACK_FALLBACK, s):
        unit = "usd" if market == "US" else "cad"
        return ("proposed", {"programId": "cashback", "unit": unit, "basis": "name says cash back"})

    # Exact source-row matching happens in main(). It replaces only the old residual NAME
    # catch-alls after every established currency and issuer rule has had a chance to match.
    if evidence_row is not None:
        return classify_from_evidence(evidence_row)

    return ("unmapped", {"basis": "no signal in issuer or name"})


def load_cc_offers_by_card_offer() -> dict[str, dict]:
    """Load retained cc-offers evidence, indexed only by its exact card_offer field."""
    manifest = json.loads((PIPELINE / "raw" / "MANIFEST.json").read_text())
    snapshots = [s for s in manifest["snapshots"] if s["sourceId"] == "cc-offers"]
    if len(snapshots) != 1:
        raise RuntimeError(f"Expected one cc-offers snapshot, found {len(snapshots)}")
    snapshot = snapshots[0]
    cache = Path(os.environ.get("PICKME_RAW_CACHE", PIPELINE / ".raw-cache"))
    path = cache / snapshot["snapshotId"] / snapshot["filename"]
    if not path.is_file():
        raise RuntimeError(
            f"cc-offers snapshot is not materialized at {path}. Run "
            f"scripts/fetch-raw-snapshot.sh {snapshot['sha256']} first."
        )
    rows = json.loads(path.read_text())["rows"]
    by_offer = {row["card_offer"]: row for row in rows}
    if len(by_offer) != len(rows):
        raise RuntimeError("cc-offers contains duplicate card_offer values; exact evidence matching is ambiguous")
    return by_offer


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--market", required=True, choices=["US", "CA"])
    args = ap.parse_args()

    queue = json.loads(QUEUE.read_text())["queue"]
    cc_offers_by_card_offer = load_cc_offers_by_card_offer() if args.market == "US" else {}
    aliases = json.loads((PIPELINE / "issuer-aliases.json").read_text())["aliases"].get(args.market, {})
    valid = set(json.loads(SCHEMA.read_text())["$defs"]["programId"]["enum"])

    buckets = {"proposed": {}, "needsEnumValue": {}, "refused": {}, "unmapped": {}}
    seen = set()
    for e in queue:
        if e.get("country") != args.market:
            continue
        cid = e.get("cardId")
        if not cid or cid == "<batch>" or cid in seen:
            continue
        seen.add(cid)
        issuer = aliases.get(e.get("issuer"), e.get("issuer"))
        bucket, payload = classify(
            e.get("officialName"), issuer, args.market, valid,
            cc_offers_by_card_offer.get(e.get("officialName")),
        )
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
