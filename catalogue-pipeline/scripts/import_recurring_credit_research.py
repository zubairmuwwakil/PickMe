#!/usr/bin/env python3
"""Normalize the issuer recurring-credit research pack into the canonical catalogue.

This is intentionally conservative. It promotes high-confidence fixed-value records only,
refuses cohort schedules the contract cannot express, never invents MCCs/time zones, and emits a
purchasePredicate only when the research gives a machine-matchable merchant/channel or one of the
two explicitly audited broad purchase rules below.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / "docs/research/issuer-recurring-credit-research-2026-08-31.json"
CATALOGUE = ROOT / "contracts/card-catalogue.json"

BLOCKED_COHORTS = {
    ("amex-platinum", "platinum-nexus-credit"),
    ("amex-aeroplan-reserve", "amex-aeroplan-reserve-nexus-credit"),
}
STABLE_ID_ALIASES = {
    ("american-express-gold-card", "amex-gold-dining-monthly"): "amex-gold-dining-credit",
    ("american-express-the-platinum-card", "amex-plat-us-airline-fee-credit"):
        "amex-plat-airline-fee-credit",
}
CATEGORY_MAP = {
    "airlineIncidentalFee": "travel",
    "airlineTicketUpgradeFees": "travel",
    "airportLoungeAccessFees": "travel",
    "airportParking": "travel",
    "baggageFees": "travel",
    "membership": "memberships",
    "rideshare": "transit",
    "seatSelection": "travel",
    "trustedTravelerApplicationFee": "travel",
    "trustedTravelerMembership": "travel",
    "vacationPackage": "travel",
    "wellness": "fitness",
}
CATEGORY_ONLY_CHECKOUT = {"csr-travel-credit"}
ANY_PURCHASE_CHECKOUT = {"bmo-eclipse-lifestyle-credit"}
FEE_CORRECTIONS = {
    "american-express-the-platinum-card": (895, "USD"),
    "chase-sapphire-reserve": (795, "USD"),
}


def slug(value: str) -> str:
    value = value.lower().replace("+", " plus ").replace("&", " and ")
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", value)).strip("-")


def concrete_merchants(values: list[str]) -> list[str]:
    generic = ("eligible ", "participating ", "selected ", "qualifying ")
    return sorted({slug(value) for value in values
                   if value and not value.lower().startswith(generic)})


def normalized_schedule(raw: dict) -> dict:
    basis = raw["basis"]
    if basis == "calendar":
        out = {"basis": basis, "unit": raw["unit"], "interval": raw.get("interval", 1)}
        if raw.get("resetTimeZone"):
            out["resetTimeZone"] = raw["resetTimeZone"]
        return out
    if basis == "rolling":
        return {"basis": basis, "intervalMonths": raw["intervalMonths"]}
    if basis == "accountAnniversary":
        if raw.get("intervalMonths"):
            months = raw["intervalMonths"]
        elif raw.get("unit") == "year":
            months = 12 * raw.get("interval", 1)
        else:
            raise ValueError(f"Unresolvable anniversary schedule: {raw}")
        return {"basis": basis, "intervalMonths": months}
    raise ValueError(f"Unknown credit schedule basis: {basis}")


def enrollment_channel(instructions: str | None) -> str | None:
    if not instructions:
        return None
    lowered = instructions.lower()
    if any(name in lowered for name in ("uber", "lyft", "opentable", "peloton")):
        return "partnerAccount"
    if any(name in lowered for name in ("american express", "amex", "chase")):
        return "issuerPortal"
    return None


def checkout_channel(raw: str | None) -> str | None:
    lowered = (raw or "").lower()
    if "american express travel" in lowered:
        return "amexTravel"
    if "chase travel" in lowered:
        return "chaseTravel"
    if "capital one travel" in lowered:
        return "capitalOneTravel"
    if "expedia for td" in lowered:
        return "expediaForTD"
    return None


def purchase_predicate(card_id: str, credit: dict) -> dict | None:
    merchants = concrete_merchants(credit.get("eligibleMerchants", []))
    categories = sorted({CATEGORY_MAP.get(value, value)
                         for value in credit.get("eligibleCategories", [])})
    channel = checkout_channel(credit.get("channel"))
    credit_id = STABLE_ID_ALIASES.get((card_id, credit["creditId"]), credit["creditId"])

    if not merchants and not channel and credit_id not in CATEGORY_ONLY_CHECKOUT \
            and credit_id not in ANY_PURCHASE_CHECKOUT:
        return None
    predicate: dict = {}
    if categories and (merchants or channel or credit_id in CATEGORY_ONLY_CHECKOUT):
        predicate["categories"] = categories
    if merchants:
        predicate["merchantInclude"] = merchants
    if credit.get("mccs"):
        predicate["mccInclude"] = credit["mccs"]
    if credit.get("country"):
        predicate["country"] = credit["country"]
    if channel:
        predicate["channels"] = [channel]
    return predicate


def normalize_credit(card_id: str, raw: dict, reviewed_at: str) -> dict:
    credit_id = STABLE_ID_ALIASES.get((card_id, raw["creditId"]), raw["creditId"])
    out = {
        "creditId": credit_id,
        "label": raw["label"],
        "value": {"amount": raw["value"]["amount"], "currency": raw["value"]["currency"]},
        "schedule": normalized_schedule(raw["schedule"]),
        "redemptionMethod": raw["redemptionMethod"],
        "allowsPartialUse": raw["partialUseAllowed"],
    }
    predicate = purchase_predicate(card_id, raw)
    if predicate is not None:
        out["purchasePredicate"] = predicate
    if raw.get("minimumTransaction"):
        out["minimumTransaction"] = raw["minimumTransaction"]

    required = raw["enrollmentRequired"]
    enrollment = {"required": required}
    if required:
        if channel := enrollment_channel(raw.get("enrollmentChannel")):
            enrollment["channel"] = channel
        if raw.get("enrollmentUrl"):
            enrollment["url"] = raw["enrollmentUrl"]
        if raw.get("enrollmentChannel"):
            enrollment["instructions"] = raw["enrollmentChannel"]
    out["enrollment"] = enrollment

    roles = raw.get("primaryAdditionalCardEligibility") or {}
    role_values = []
    if roles.get("primary"):
        role_values.append("primary")
    if roles.get("additional"):
        role_values.append("additional")
    terms = " ".join(filter(None, [raw.get("directPurchaseRestrictions"), raw.get("evidence")]))
    eligibility: dict = {}
    if role_values:
        eligibility["cardholderRoles"] = role_values
    if re.search(r"per account|account-level|share(?:d)? the account", terms, re.I):
        eligibility["accountLevelLimit"] = True
    if re.search(r"good standing", terms, re.I):
        eligibility["accountStandingRequired"] = True
    deadline = re.search(r"within (\d+) days", terms, re.I)
    if re.search(r"proof must be submitted|claim submission", terms, re.I):
        eligibility["claimRequired"] = True
    if deadline:
        eligibility["claimDeadlineDays"] = int(deadline.group(1))
    if eligibility:
        out["eligibility"] = eligibility
    if raw.get("directPurchaseRestrictions"):
        out["usageTerms"] = [raw["directPurchaseRestrictions"]]
    if raw.get("effectiveFrom"):
        out["effectiveFrom"] = raw["effectiveFrom"]
    if raw.get("effectiveTo"):
        out["effectiveTo"] = raw["effectiveTo"]
    out["sourceType"] = "issuerConfirmed"
    out["lastVerifiedAt"] = reviewed_at
    out["sources"] = sorted({source["url"] for source in raw["sources"]})
    if raw.get("evidence"):
        out["_note"] = raw["evidence"]
    return out


def transformed() -> tuple[dict, list[str]]:
    research = json.loads(RESEARCH.read_text(encoding="utf-8"))
    catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    if catalogue["catalogueVersion"] not in {"2.17", "2.18"}:
        raise RuntimeError("Importer is pinned to the reviewed 2.17 catalogue snapshot")
    cards = {card["cardId"]: card for card in catalogue["cards"]}
    skipped: list[str] = []

    for reviewed in research["cards"]:
        card_id = reviewed["cardId"]
        if card_id not in cards:
            raise RuntimeError(f"Research references unknown cardId: {card_id}")
        card = cards[card_id]
        card["creditCoverage"] = {
            "status": reviewed["creditCoverageStatus"],
            "lastReviewedAt": reviewed["reviewedAt"],
        }
        promoted = []
        for raw in reviewed["credits"]:
            key = (card_id, raw["creditId"])
            if raw["confidence"] != "high" or raw["value"].get("amount") is None:
                skipped.append(f"{card_id}/{raw['creditId']}: confidence={raw['confidence']}")
                continue
            if key in BLOCKED_COHORTS:
                skipped.append(f"{card_id}/{raw['creditId']}: cohort schedule not representable")
                continue
            promoted.append(normalize_credit(card_id, raw, research["reviewedAt"]))
        if reviewed["credits"] and promoted:
            card["credits"] = promoted

    for card_id, (amount, currency) in FEE_CORRECTIONS.items():
        cards[card_id]["fee"]["annual"] = {"amount": amount, "currency": currency}
    catalogue["catalogueVersion"] = "2.18"
    return catalogue, skipped


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="replace contracts/card-catalogue.json")
    args = parser.parse_args()
    catalogue, skipped = transformed()
    # Match the repository's canonical JSON rendering to avoid unrelated Unicode churn.
    rendered = json.dumps(catalogue, indent=2, ensure_ascii=True) + "\n"
    if args.write:
        CATALOGUE.write_text(rendered, encoding="utf-8")
    else:
        current = CATALOGUE.read_text(encoding="utf-8")
        print("CHANGE" if current != rendered else "OK")
    print(f"normalized {sum(len(card.get('credits', [])) for card in catalogue['cards'])} total credits")
    for item in skipped:
        print(f"SKIP {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
