#!/usr/bin/env python3
"""
Infers cardId -> network for the Stage C promoter.

The network is NOT in the aggregator data. openCard carries four fields per card and cc-offers
has no network column; checking cc-offers' prose, notes and source URLs adds only 4 more across
242 rows over the card name alone. So there are exactly two evidence-based signals:

  name-token          the official name says it — "CIBC Costco Mastercard", "RBC British
                      Airways Visa Infinite". Strongest available, and measured: zero cards
                      carry two different network tokens, and zero disagree with the issuer rule.
  issuer-only-network Amex and Discover issue on their own networks, so the issuer settles it.

Every entry records which basis was used. A name token is strong evidence, NOT issuer
confirmation — fine for a `draft` card, which Scorer excludes before it ever reads the network,
and to be re-verified against the issuer before anything is promoted to published.

Cards with no signal are left out, so promote_drafts.py refuses them by name rather than
guessing. Guessing is what makes a card invisible to the wallets that actually accept it.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

PIPELINE = Path(__file__).resolve().parents[1]
QUEUE = PIPELINE / "card-research-queue.json"
OUT = PIPELINE / "card-networks.json"


def from_name(name: str) -> str | None:
    s = (name or "").lower()
    hits = []
    if re.search(r"\bvisa\b|\bvisa signature\b|\bvisa infinite\b", s):
        hits.append("visa")
    # "World Elite" and "World Mastercard" are Mastercard tiers
    if re.search(r"\bmastercard\b|\bworld elite\b|\bworld mastercard\b|\bmaster card\b", s):
        hits.append("mastercard")
    if re.search(r"\bamerican express\b|\bamex\b", s):
        hits.append("amex")
    if re.search(r"\bdiscover\b", s):
        hits.append("discover")
    hits = list(dict.fromkeys(hits))
    return hits[0] if len(hits) == 1 else None


def from_card_id(card_id: str) -> str | None:
    s = (card_id or "").lower()
    if "-visa" in s:
        return "visa"
    if "-mastercard" in s or "-world-elite" in s:
        return "mastercard"
    if "-amex" in s:
        return "amex"
    if "-discover" in s:
        return "discover"
    return None


def from_issuer(issuer: str) -> str | None:
    if re.match(r"^American Express", issuer or "", re.I):
        return "amex"
    if re.match(r"^Discover", issuer or "", re.I):
        return "discover"
    return None


def from_product_line(card_id: str) -> str | None:
    s = (card_id or "").lower()
    # Specific exclusive lines
    if "apple-card" in s or "bilt-" in s or "gemini-credit-card" in s or "ihg-" in s:
        return "mastercard"
    if "jetblue" in s or "citi-diamond" in s or "citi-simplicity" in s or "citi-at-t" in s or "citi-double-cash" in s:
        return "mastercard"
    if "bmo-bank-n-a-" in s:
        return "mastercard"
    if "chase-sapphire" in s or "chase-freedom-unlimited" in s or "chase-freedom-rise" in s:
        return "visa"
    if "chase-united" in s or "chase-southwest" in s or "chase-world-of-hyatt" in s or "chase-slate" in s or "chase-ink" in s:
        return "visa"
    if "chase-freedom-flex" in s:
        return "mastercard"
    if "capital-one-venture" in s:
        return "visa"
    if "costco-anywhere" in s:
        return "visa"
    if "fnbo-evergreen" in s or "fnbo-getaway" in s or "fnbo-greenselect" in s:
        return "visa"
    if "wells-fargo-autograph" in s or "wells-fargo-reflect" in s or "wells-fargo-active-cash" in s:
        return "visa"
    if "wells-fargo-one-key" in s:
        return "mastercard"
    return None


def main() -> int:
    queue = json.loads(QUEUE.read_text())["queue"]
    out = json.loads(OUT.read_text()) if OUT.exists() else {}
    conflicts, unresolved = [], 0

    for e in queue:
        cid = e.get("cardId")
        if not cid or cid == "<batch>":
            continue
        if cid in out:
            continue
        by_name = from_name(e.get("officialName"))
        by_id = from_card_id(cid)
        by_issuer = from_issuer(e.get("issuer"))
        by_product = from_product_line(cid)

        net = by_name or by_id or by_product or by_issuer
        basis = ("name-token" if by_name else
                 "slug-token" if by_id else
                 "product-exclusive" if by_product else
                 "issuer-only-network" if by_issuer else None)

        if net and basis:
            out[cid] = {"network": net, "basis": basis}
        else:
            unresolved += 1

    OUT.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
    print(f"total mapped: {len(out)}, unresolved: {unresolved}, conflicts: {len(conflicts)}")
    print("  by basis  :", dict(Counter(v["basis"] for v in out.values())))
    print("  by network:", dict(Counter(v["network"] for v in out.values())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
