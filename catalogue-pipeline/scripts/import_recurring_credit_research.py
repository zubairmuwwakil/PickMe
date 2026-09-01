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
EDGE_RESEARCH = ROOT / "docs/research/recurring-credit-edge-case-resolution-2026-08-31.json"
CATALOGUE = ROOT / "contracts/card-catalogue.json"
MERCHANT_PACK = ROOT / "contracts/merchant-pack.json"
CATEGORY_TAXONOMY = ROOT / "contracts/purchase-categories.json"

# Explicitly quarantined by the promotion review. These are defensible benefit facts, but their
# current research shape loses cohort, rolling-anchor, shared-limit, seasonal, tax-variable,
# per-transaction-cap, or denomination semantics when converted to CardCredit.
QUARANTINED_CREDITS = {
    ("amex-platinum", "platinum-nexus-credit"),
    ("amex-aeroplan-reserve", "amex-aeroplan-reserve-nexus-credit"),
    ("walmart-rewards-mastercard", "walmart-rewards-annual-walmart-plus-credit"),
    ("walmart-rewards-world-mastercard", "walmart-rewards-world-annual-walmart-plus-credit"),
    ("american-express-the-platinum-card", "amex-plat-us-global-entry-credit"),
    ("american-express-the-platinum-card", "amex-plat-us-tsa-precheck-credit"),
    ("td-aeroplan-visa-infinite", "td-aeroplan-vi-nexus-credit"),
    ("cibc-aventura-visa-infinite", "cibc-aventura-vi-nexus-credit"),
    ("td-aeroplan-visa-infinite-privilege", "td-aeroplan-vip-nexus-credit"),
    ("cibc-aeroplan-visa-infinite-privilege", "cibc-aeroplan-vip-nexus-credit"),
    ("chase-sapphire-preferred-card", "csp-trusted-traveler-credit"),
    ("chase-sapphire-reserve", "csr-trusted-traveler-credit"),
    ("capital-one-venture-rewards-credit-card", "venture-x-trusted-traveler-credit"),
    ("american-express-the-platinum-card", "amex-plat-us-uber-cash-december-bonus"),
    ("american-express-the-platinum-card", "amex-plat-us-walmart-plus-monthly"),
    ("chase-sapphire-reserve", "csr-the-edit-credit"),
    ("chase-sapphire-reserve", "csr-doordash-nonrestaurant-monthly"),
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
NO_CHECKOUT_PREDICATE = {
    "csp-doordash-nonrestaurant-monthly",
    "csr-select-hotels-2026-credit",
    "csr-doordash-restaurant-monthly",
}
RESET_TIMEZONE_UNSUPPORTED = {"csr-stubhub-halfyear"}
ACCOUNT_LEVEL_OVERRIDES = {"csr-lyft-monthly"}
TEMPORARY_CREDIT_ENDS = {
    "csp-doordash-nonrestaurant-monthly": "2027-12-31",
    "csr-select-hotels-2026-credit": "2026-12-31",
    "csr-stubhub-halfyear": "2027-12-31",
    "csr-lyft-monthly": "2027-09-30",
    "csr-peloton-monthly": "2027-12-31",
    "csr-doordash-restaurant-monthly": "2027-12-31",
}
FEE_ASSERTIONS = {
    "american-express-the-platinum-card": (895, "USD"),
    "chase-sapphire-reserve": (795, "USD"),
}

# Exact research text to contract enum. No keyword inference: unrecognized instructions remain
# human-readable instructions without pretending PickMe knows the activation surface.
ENROLLMENT_CHANNELS = {
    "Amex Offers": "issuerPortal",
    "American Express benefit enrollment": "issuerPortal",
    "Select qualifying airline in Amex benefits": "issuerPortal",
    "Add Gold Card to Uber account": "partnerAccount",
    "Add Platinum Card to Uber account": "partnerAccount",
    "Eligible Uber One enrollment/payment setup": "partnerAccount",
    "Link eligible Reserve card to OpenTable profile": "partnerAccount",
    "Activate in Chase.com or Chase Mobile": "issuerPortal",
    "Add eligible card to Lyft app": "partnerAccount",
    "Activate on Chase.com/Chase Mobile and Peloton": "issuerPortal",
    "Activate DashPass": "partnerAccount",
}


def normalized_lookup(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def merchant_resolver() -> dict[str, str]:
    pack = json.loads(MERCHANT_PACK.read_text(encoding="utf-8"))
    candidates: dict[str, set[str]] = {}
    for merchant in pack["merchants"]:
        for value in [merchant["id"], merchant.get("displayName", ""),
                      *merchant.get("matchKeys", [])]:
            if value:
                candidates.setdefault(normalized_lookup(value), set()).add(merchant["id"])
    ambiguous = {key: ids for key, ids in candidates.items() if len(ids) > 1}
    if ambiguous:
        raise RuntimeError(f"Ambiguous canonical merchant aliases: {ambiguous}")
    return {key: next(iter(ids)) for key, ids in candidates.items()}


def canonical_merchants(values: list[str], resolver: dict[str, str]) -> tuple[list[str], list[str]]:
    generic = ("eligible ", "participating ", "selected ", "qualifying ")
    concrete = [value for value in values
                if value and not value.lower().startswith(generic)]
    resolved: list[str] = []
    unresolved: list[str] = []
    for value in concrete:
        merchant_id = resolver.get(normalized_lookup(value))
        if merchant_id:
            resolved.append(merchant_id)
        else:
            unresolved.append(value)
    # Partial merchant lists are more dangerous than no list: they imply excluded partners are
    # ineligible. Only emit the list when every concrete issuer name resolves canonically.
    return (sorted(set(resolved)) if not unresolved else [], sorted(set(unresolved)))


def normalized_schedule(credit_id: str, raw: dict) -> dict:
    basis = raw["basis"]
    if basis == "calendar":
        out = {"basis": basis, "unit": raw["unit"], "interval": raw.get("interval", 1)}
        if raw.get("resetTimeZone") and credit_id not in RESET_TIMEZONE_UNSUPPORTED:
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


def purchase_predicate(card_id: str, credit: dict, resolver: dict[str, str],
                       known_categories: set[str]) -> tuple[dict | None, list[str]]:
    merchants, unresolved = canonical_merchants(credit.get("eligibleMerchants", []), resolver)
    categories = sorted({CATEGORY_MAP.get(value, value)
                         for value in credit.get("eligibleCategories", [])})
    unknown_categories = set(categories) - known_categories
    if unknown_categories:
        raise RuntimeError(f"Unknown purchase categories: {sorted(unknown_categories)}")
    channel = checkout_channel(credit.get("channel"))
    credit_id = STABLE_ID_ALIASES.get((card_id, credit["creditId"]), credit["creditId"])

    if credit_id in NO_CHECKOUT_PREDICATE:
        return None, unresolved
    if not merchants and not channel and not credit.get("mccs") \
            and credit_id not in CATEGORY_ONLY_CHECKOUT \
            and credit_id not in ANY_PURCHASE_CHECKOUT:
        return None, unresolved
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
    return predicate, unresolved


def normalize_credit(card: dict, raw: dict, reviewed_at: str, resolver: dict[str, str],
                     known_categories: set[str], notices: list[str]) -> dict:
    card_id = card["cardId"]
    credit_id = STABLE_ID_ALIASES.get((card_id, raw["creditId"]), raw["creditId"])
    if raw["value"]["currency"] != card["billingCurrency"]:
        raise RuntimeError(f"Currency mismatch for {card_id}/{credit_id}")
    if credit_id in TEMPORARY_CREDIT_ENDS \
            and raw.get("effectiveTo") != TEMPORARY_CREDIT_ENDS[credit_id]:
        raise RuntimeError(f"Missing/incorrect effectiveTo for {card_id}/{credit_id}")
    out = {
        "creditId": credit_id,
        "label": raw["label"],
        "value": {"amount": raw["value"]["amount"], "currency": raw["value"]["currency"]},
        "schedule": normalized_schedule(credit_id, raw["schedule"]),
        "redemptionMethod": raw["redemptionMethod"],
        "allowsPartialUse": raw["partialUseAllowed"],
    }
    predicate, unresolved = purchase_predicate(card_id, raw, resolver, known_categories)
    if predicate is not None:
        out["purchasePredicate"] = predicate
    if unresolved:
        notices.append(f"OMIT {card_id}/{credit_id} unresolved merchants: "
                       + ", ".join(unresolved))
    if raw.get("minimumTransaction"):
        out["minimumTransaction"] = raw["minimumTransaction"]

    required = raw["enrollmentRequired"]
    enrollment = {"required": required}
    if required:
        if channel := ENROLLMENT_CHANNELS.get(raw.get("enrollmentChannel")):
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
    if credit_id in ACCOUNT_LEVEL_OVERRIDES:
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


def transformed() -> tuple[dict, list[str], dict[str, int]]:
    research = json.loads(RESEARCH.read_text(encoding="utf-8"))
    edge = json.loads(EDGE_RESEARCH.read_text(encoding="utf-8"))
    catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    if catalogue["catalogueVersion"] not in {"2.18", "2.19"}:
        raise RuntimeError("Repair importer is pinned to the reviewed 2.18 catalogue snapshot")
    edge_keys = {(claim["cardId"], claim["creditId"])
                 for claim in edge["claims"] if claim["disposition"] != "promote"}
    if not edge_keys.issubset(QUARANTINED_CREDITS):
        raise RuntimeError("Every non-promotable edge resolution must be quarantined explicitly")

    resolver = merchant_resolver()
    taxonomy = json.loads(CATEGORY_TAXONOMY.read_text(encoding="utf-8"))
    known_categories = {item["id"] for item in taxonomy["categories"]}
    known_categories.update(item["id"] for item in taxonomy.get("ruleSideCategories", []))
    cards = {card["cardId"]: card for card in catalogue["cards"]}
    notices: list[str] = []
    actions = {"add": 0, "update": 0, "keep": 0, "remove": 0, "block": 0}

    for reviewed in research["cards"]:
        card_id = reviewed["cardId"]
        if card_id not in cards:
            raise RuntimeError(f"Research references unknown cardId: {card_id}")
        card = cards[card_id]
        card["creditCoverage"] = {
            "status": reviewed["creditCoverageStatus"],
            "lastReviewedAt": reviewed["reviewedAt"],
        }
        existing = {credit["creditId"]: credit for credit in card.get("credits", [])}
        for raw in reviewed["credits"]:
            key = (card_id, raw["creditId"])
            stable_id = STABLE_ID_ALIASES.get(key, raw["creditId"])
            if raw["confidence"] != "high" or raw["value"].get("amount") is None:
                if stable_id in existing and existing[stable_id].get("sourceType") == "issuerConfirmed":
                    del existing[stable_id]
                    actions["remove"] += 1
                notices.append(f"BLOCK {card_id}/{raw['creditId']}: confidence={raw['confidence']}")
                actions["block"] += 1
                continue
            if key in QUARANTINED_CREDITS:
                if stable_id in existing:
                    del existing[stable_id]
                    actions["remove"] += 1
                notices.append(f"BLOCK {card_id}/{raw['creditId']}: promotion review quarantine")
                actions["block"] += 1
                continue
            normalized = normalize_credit(card, raw, research["reviewedAt"], resolver,
                                          known_categories, notices)
            if stable_id not in existing:
                actions["add"] += 1
            elif existing[stable_id] == normalized:
                actions["keep"] += 1
            else:
                actions["update"] += 1
            existing[stable_id] = normalized
        if reviewed["credits"]:
            if existing:
                card["credits"] = list(existing.values())
            else:
                card.pop("credits", None)

    for card_id, (amount, currency) in FEE_ASSERTIONS.items():
        actual = cards[card_id]["fee"]["annual"]
        if actual != {"amount": amount, "currency": currency}:
            raise RuntimeError(f"Fee assertion failed for {card_id}: {actual}")
    catalogue["catalogueVersion"] = "2.19"
    return catalogue, notices, actions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="replace contracts/card-catalogue.json")
    args = parser.parse_args()
    catalogue, notices, actions = transformed()
    # Match the repository's canonical JSON rendering to avoid unrelated Unicode churn.
    rendered = json.dumps(catalogue, indent=2, ensure_ascii=True) + "\n"
    if args.write:
        CATALOGUE.write_text(rendered, encoding="utf-8")
    else:
        current = CATALOGUE.read_text(encoding="utf-8")
        print("CHANGE" if current != rendered else "OK")
    print("promotion report " + " ".join(f"{key}={value}" for key, value in actions.items()))
    print(f"normalized {sum(len(card.get('credits', [])) for card in catalogue['cards'])} total credits")
    for item in notices:
        print(item)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
