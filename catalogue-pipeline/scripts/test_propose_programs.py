import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from propose_programs import classify_from_evidence


def test_cash_back_category_routes_to_cashback():
    row = {"card_offer": "AARP Essential Rewards Mastercard", "issuer": "Barclays",
           "category": "CASH_BACK"}
    kind, payload = classify_from_evidence(row)
    assert kind == "proposed"
    assert payload["programId"] == "cashback"
    assert "CASH_BACK" in payload["basis"]


def test_discover_issuer_routes_to_discover_cashback():
    row = {"card_offer": "NHL Discover it Credit Card", "issuer": "Discover",
           "category": "CASH_BACK"}
    kind, payload = classify_from_evidence(row)
    assert payload["programId"] == "discoverCashback"


def test_digital_wallet_cash_back_is_still_cash_back():
    row = {"card_offer": "PayPal Cashback Mastercard", "issuer": "Synchrony",
           "category": "DIGITAL_WALLET_CASH_BACK"}
    kind, payload = classify_from_evidence(row)
    assert payload["programId"] == "cashback"


def test_financing_category_routes_to_no_rewards():
    row = {"card_offer": "CareCredit Credit Card", "issuer": "Synchrony",
           "category": "HEALTH_WELLNESS_FINANCING"}
    kind, payload = classify_from_evidence(row)
    assert kind == "proposed"
    assert payload["programId"] == "noRewards"


def test_retail_rewards_needs_a_merchant_credit_decision():
    row = {"card_offer": "Gap Encore Mastercard", "issuer": "Barclays",
           "category": "RETAIL_REWARDS"}
    kind, payload = classify_from_evidence(row)
    assert kind == "needsEnumValue"
    assert payload["currency"] == "merchantCredit"


def test_no_category_is_refused_not_guessed():
    row = {"card_offer": "Kohl's Charge Card", "issuer": "Capital One", "category": None}
    kind, payload = classify_from_evidence(row)
    assert kind == "refused"
    assert payload["reason"] == "provenanceWithdrawn"
