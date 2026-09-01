#!/usr/bin/env python3
import importlib.util
import json
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("import_recurring_credit_research.py")
SPEC = importlib.util.spec_from_file_location("recurring_credit_importer", SCRIPT)
IMPORTER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(IMPORTER)


class RecurringCreditImporterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalogue, cls.notices, cls.actions = IMPORTER.transformed()
        cls.cards = {card["cardId"]: card for card in cls.catalogue["cards"]}
        cls.us_pack = json.loads(IMPORTER.US_REMAINING_RESEARCH.read_text(encoding="utf-8"))

    def test_us_pack_matches_canonical_card_ids(self):
        ids = [card["cardId"] for card in self.us_pack["cards"]]
        self.assertEqual(74, len(ids))
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), set(ids) & self.cards.keys())

    def test_every_us_high_confidence_claim_has_explicit_disposition(self):
        high = {
            (card["cardId"], credit["creditId"])
            for card in self.us_pack["cards"]
            for credit in card["credits"]
            if credit["confidence"] == "high"
        }
        quarantined = high & IMPORTER.QUARANTINED_CREDITS
        self.assertEqual(19, len(high))
        self.assertEqual(13, len(IMPORTER.US_REMAINING_PROMOTABLE_CREDITS))
        self.assertEqual(6, len(quarantined))
        self.assertEqual(high, IMPORTER.US_REMAINING_PROMOTABLE_CREDITS | quarantined)

    def test_us_promotions_are_draft_only_and_quarantines_are_absent(self):
        canonical = {
            (card["cardId"], credit["creditId"]): (card, credit)
            for card in self.catalogue["cards"]
            for credit in card.get("credits", [])
        }
        for key in IMPORTER.US_REMAINING_PROMOTABLE_CREDITS:
            card, credit = canonical[key]
            self.assertEqual("draft", card.get("status"))
            self.assertEqual("issuerConfirmed", credit["sourceType"])
            self.assertTrue(credit["sources"])
            self.assertFalse(any(isinstance(term, list) for term in credit.get("usageTerms", [])))
        for key in IMPORTER.QUARANTINED_CREDITS:
            if key[0] in {card["cardId"] for card in self.us_pack["cards"]}:
                self.assertNotIn(key, canonical)

    def test_import_is_idempotent_at_release_version(self):
        self.assertEqual("2.20", self.catalogue["catalogueVersion"])
        self.assertEqual(0, self.actions["add"])
        self.assertEqual(0, self.actions["update"])
        self.assertEqual(43, self.actions["keep"])
        self.assertEqual(0, self.actions["remove"])
        self.assertEqual(56, self.actions["block"])


if __name__ == "__main__":
    unittest.main()
