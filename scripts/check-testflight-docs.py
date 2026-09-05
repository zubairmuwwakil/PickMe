#!/usr/bin/env python3
"""Fail when TestFlight instructions contradict current shipping source."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / "App" / "Configuration" / "Versioning.xcconfig"
RUNBOOK = ROOT / "TESTFLIGHT.md"
NOTES = ROOT / "docs" / "compliance" / "testflight-beta-notes.md"


def value(source: str, key: str) -> str:
    match = re.search(rf"^\s*{re.escape(key)}\s*=\s*(\S+)\s*$", source, re.MULTILINE)
    if match is None:
        raise ValueError(f"{key} is missing from {VERSION_FILE.relative_to(ROOT)}")
    return match.group(1)


def main() -> int:
    version_source = VERSION_FILE.read_text()
    marketing = value(version_source, "APP_MARKETING_VERSION")
    build = value(version_source, "APP_BUILD_NUMBER")
    release = f"{marketing} ({build})"
    runbook = RUNBOOK.read_text()
    notes = NOTES.read_text()
    failures: list[str] = []

    required = {
        "TESTFLIGHT.md": [
            f"**Target Version:** `{release}`",
            "Report a problem",
            "/admin/tester-reports",
            "30 days",
            "physical",
        ],
        "docs/compliance/testflight-beta-notes.md": [
            f"**Build:** `{release}`",
            f"Build {release}",
            "Report a problem",
            "30 days",
            "[[DEMO EMAIL]]",
            "[[DEMO PASSWORD]]",
        ],
    }
    for name, needles in required.items():
        source = runbook if name == "TESTFLIGHT.md" else notes
        for needle in needles:
            if needle not in source:
                failures.append(f"{name} must contain {needle!r}")

    combined = runbook + "\n" + notes
    forbidden = [
        r"\b0\.2\s*\(1\)",
        r"\b10-card catalogue\b",
        r"Background Modes?:\s*`?location`?",
        r"altool\s+--upload-app[^\n]*\.app",
    ]
    for pattern in forbidden:
        if re.search(pattern, combined, re.IGNORECASE):
            failures.append(f"TestFlight documentation contains stale claim matching {pattern!r}")

    if failures:
        for failure in failures:
            print(f"check-testflight-docs: {failure}", file=sys.stderr)
        return 1

    print(f"check-testflight-docs: runbook and beta notes match build {release}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
