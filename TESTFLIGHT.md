# PickMe TestFlight runbook

**Target Version:** `2.1 (43)`

**Verified against source:** 5 September 2026

**Bundle identifier:** `ca.pickme.cardcopilot`

The version above is read from `App/Configuration/Versioning.xcconfig`. The documentation check in
`scripts/check-testflight-docs.py` fails CI when this runbook or the beta notes stop matching that
source of truth.

## Release state

| Boundary | Evidence for 2.1 (43) | Status |
|---|---|---|
| Swift report envelope and redaction | Store unit tests | Verified |
| iOS report, status, and delete screens | App target compiled and targeted Xcode tests passed | Verified |
| Authenticated report API and reviewer inbox | MoneyTalks unit and route tests | Verified |
| Neon schema | Production migration applied | Verified |
| Installed TestFlight build | Physical-device TestFlight session | Required before inviting external testers |
| Arrival delivery while the app is closed | Physical arrivals recorded on a TestFlight build | Required before claiming it works in the field |

Passing source tests proves the report pipeline and app compile. It does not prove App Store
processing, installation, notification delivery, or Core Location relaunch behaviour on a physical
device.

## Before archiving

1. Run the repository gate:

   ```bash
   (cd Engine && swift test) && (cd ../android && ./gradlew :core:engine:test)
   python3 scripts/check-testflight-docs.py
   ```

2. Confirm the build metadata and catalogue directly from source:

   ```bash
   cat App/Configuration/Versioning.xcconfig
   jq '{catalogueVersion, cards: (.cards | length)}' contracts/card-catalogue.json
   ```

3. Confirm `https://inunity.ca/support`, `https://inunity.ca/privacy`, and the authenticated
   reviewer inbox at `https://inunity.ca/admin/tester-reports` are reachable.
4. Use an active demo account in App Store Connect. Core recommendations work signed out; sign-in
   is needed to exercise report delivery, report status, and optional account sync.
5. `FIELD_DIAGNOSTICS` is intentionally enabled for this TestFlight build. It exposes an opt-in
   detailed arrival-log attachment that can contain precise locations, merchant names, candidate
   cards, and arrival times. Remove the flag before a public App Store build unless this diagnostic
   surface is still deliberately part of that release.

## Archive and upload

Increment `APP_BUILD_NUMBER` before each uploaded archive. The CardCopilot scheme also increments it
for Archive actions, so check the resulting number before you update App Store Connect notes.

```bash
xcodebuild archive \
  -project App/CardCopilot.xcodeproj \
  -scheme CardCopilot \
  -destination "generic/platform=iOS" \
  -archivePath "build/CardCopilot-2.1-43.xcarchive"
```

Open Xcode **Window → Organizer**, select the archive, then choose **Distribute App → TestFlight &
App Store → Upload**. Let Xcode manage signing for team `MC8XJ6GXBM`. Upload the archive through
Organizer; an `.app` inside the archive is not an App Store upload package.

After processing, copy Part A and Part B from
[`docs/compliance/testflight-beta-notes.md`](docs/compliance/testflight-beta-notes.md) into the
matching App Store Connect fields.

## Internal test pass

Use an internal group first. On a physical iPhone, install the exact build shown above and record
the installed version from PickMe's report preview.

Exercise these stories:

1. Complete wallet setup, including conditions, default card, drawer cards, and valuations.
2. Compare checkout recommendations across grocery, dining, gas, pharmacy, transit, travel, and a
   merchant whose network acceptance excludes one of the cards.
3. Try an uncatalogued card and confirm the issuer-sourced request path appears; no open rule editor
   should appear.
4. Exercise a Wallet Shortcut capture and inspect its delivery stages.
5. Enable arrival alerts, then test real region entry and exit with the app foregrounded,
   backgrounded, and terminated. Record whether iOS accepted the request and whether the alert or
   Lock Screen card was actually visible.
6. Open **Account & Settings → Report a problem**. Enter expected versus actual behaviour, preview
   the complete JSON, and submit it while signed in. Confirm its reference and review status appear
   in the app.
7. Repeat while signed out. Save or share the JSON file privately, import it in the reviewer inbox,
   and confirm the report states that sharing alone does not submit it.
8. In `https://inunity.ca/admin/tester-reports`, triage the report, add review notes, attach an HTTPS
   issue URL when applicable, and record the build containing the resolution. Refresh status in the
   app, then delete the submitted report and confirm it disappears.

The report automatically includes app version, build, iOS version, and catalogue version. Category
counts, a redacted Wallet diagnostic, and the detailed arrival log are separate opt-ins. The Wallet
diagnostic excludes merchant, amount, card, and coordinates. Reports submitted to In Unity expire
after 30 days and can be deleted earlier by the tester or reviewer.

Also monitor TestFlight feedback, screenshots, sessions, crashes, and termination data in App Store
Connect. Link every actionable report to one issue, keep reviewer notes factual, and set **Resolved
in build** only after the fix is present in an uploaded build.

## External test gate

Invite external testers only after the internal physical-device pass has no unresolved data-loss or
crash issue and the tested report can move from submission through review to a visible resolution.
The first external build may require Beta App Review. TestFlight builds expire after 90 days, so do
not use build availability as a permanent record of a finding.

Use a small named external group first. Keep the public-link limit aligned with the number of people
you can support and review promptly.

## Common blockers

| Symptom | Check |
|---|---|
| Sign-in or report submission fails | Confirm the production origin, Clerk configuration, demo account, and `/api/v1/tester-reports` deployment. |
| Report appears sent but is absent in review | Use its reference ID; confirm the reviewer is allowlisted and the production migration is current. |
| Arrival did not appear | Read the local arrival explanation first. iOS accepting a request does not prove it was displayed. |
| Review asks about background location | Explain that PickMe uses region and significant-change monitoring, requests Always only for the optional arrival feature, and does not declare continuous-location background mode. |
| Export compliance prompt appears | Confirm `ITSAppUsesNonExemptEncryption` remains `false` in `App/Info.plist`. |
| Archive already exists | Choose a new archive path containing the new build number. Do not delete an older archive until its upload and symbols are confirmed. |
