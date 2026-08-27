# TestFlight Beta Review Notes — text to paste, and why

> ## ⚠ Draft for review before submission
>
> Written by Zubair with Claude; **neither of us is a lawyer.** Part A is addressed to Apple's
> TestFlight Beta App Review team and should be reviewed alongside
> [`app-review-notes.md`](app-review-notes.md) and [`app-privacy-labels.md`](app-privacy-labels.md).
> **[verified]** = quoted from Apple's guidelines or TestFlight documentation ·
> **[inference]** = our reasoning · **[uncertain]** = unresolved.
>
> **Applicability:** TestFlight internal testing does not require Apple beta review (up to 100
> App Store Connect team members). **Beta App Review is required before distributing to external
> tester groups or via public TestFlight links.**
>
> ## 🔴 AMENDED 2026-08-17 — aligned with live architecture and commit bc6c19f
>
> This document reflects the ambient architecture: Clerk authentication, Vercel/Neon backend,
> optional Apple Wallet shortcut capture with retained coordinates, and background region monitoring
> for arrival detection.
>
> **Guideline 2.1(a) demo account posture:** The backend must be live during review (non-negotiable).
> A demo account is strongly advisable to avoid review friction, though self-registration via Clerk
> is open.

**Source:** [Apple Developer — TestFlight Overview](https://developer.apple.com/testflight/) ·
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), checked 2026-08-17.

---

# PART A — Paste into "TestFlight → App Review Information → Notes"

```text
WHAT THIS APP DOES

PickMe (ca.pickme.cardcopilot) calculates which credit card in a user's wallet earns the
highest rewards on an upcoming purchase and displays the arithmetic behind the choice.
The user pays manually with their own physical or digital card. It is a reward-rate
comparison tool over publicly published card reward terms.

NOT A FINANCIAL SERVICES APP (Guidelines 3.2.1(viii), 5.1.1(ix))

The app has no integration with financial networks and no code path that could:
- Hold, transfer, convert, or manage funds or financial accounts
- Connect to bank APIs or financial aggregators (no Plaid, Flinks, or open banking)
- Process, intercept, or initiate payments
- Collect or store credit card numbers, CVVs, PINs, or online banking credentials
  (no field in the app accepts financial credentials)
- Issue or apply for credit cards

Guideline 3.2.1(viii) applies to financial trading, investing, or money management.
PickMe does none of these; it calculates reward values over public terms and functions as
a purchase-time optimization tool.

PRIVACY & SIGNED-OUT FUNCTIONALITY

The core app functions completely on-device without an account:
- Card evaluation, purchase history, saved merchants, and arrival detection run locally
  in an on-device SwiftData store.
- Signing in (via Clerk) is optional.
- If signed in, the user's email address and card bonus-cap usages sync to our backend
  (moneytalks.zubairmuwwakil.com).
- App Privacy labels accurately declare: Contact Info, Identifiers, Purchase History,
  Precise Location, and Other Financial Info — all linked to user, all for App
  Functionality, none used for tracking.

APPLE WALLET TRANSACTION CAPTURE VIA SHORTCUTS

The app includes an optional automation integration with Apple Wallet:
- Users can configure a personal iOS Shortcut triggered by Apple Pay transactions.
- The Shortcut invokes an App Intent / webhook passing the transaction merchant name,
  amount, card used, timestamp, and location coordinates.
- This allows PickMe to verify whether the optimal card was used and record rewards
  earned.
- This integration is completely optional and user-configured; core recommendation and
  manual checkout flows operate independently of it.

LOCATION USAGE & BACKGROUND MODES JUSTIFICATION (Guideline 2.5.4, 5.1.1)

Location is used for two specific user-facing purposes:
1. When In Use (NSLocationWhenInUseUsageDescription): A single one-time fix when the
   user requests nearby merchants, querying MapKit to find the store they are visiting.
2. Always & Background Mode (NSLocationAlwaysAndWhenInUseUsageDescription +
   UIBackgroundModes "location"): The app registers geofenced regions (CLMonitor /
   CLCircularRegion) for a small set of saved merchants. When the user enters a monitored
   area, the app awakens in the background to evaluate whether a notification should be
   posted suggesting the best card before checkout, and computes visit dwell time upon
   exit.

To decide how readily that background wake becomes a notification, the app keeps a local,
on-device record of which recognised merchants the user paid at on at least 3 separate
days in a rolling 90-day window - merchant and date only, never amount, card, or
coordinate, and never uploaded. A merchant clearing that bar is treated as one the user
frequents, which lets a notification there use the user's own alert threshold. The record
is visible and editable in-app ("Learned merchants") and clears with local-history erasure.

- Location tracking is NEVER continuous; no GPS trail or route history is recorded.
- If location permission is denied, the app presents a complete manual merchant search.
  No feature is gated or inaccessible without location.

BACKEND SERVICE & DEMO CREDENTIALS (Guideline 2.1(a))

- The backend service at moneytalks.zubairmuwwakil.com is active and operational.
- While Clerk user registration is open for any tester, pre-configured demo credentials
  are provided below to streamline verification:

Demo Account: [[DEMO EMAIL]] / [[DEMO PASSWORD]]

TESTER / REVIEWER WALKTHROUGH

To test the complete core flow from a fresh install (works anywhere globally):

1. On launch, select 2 or more cards from the built-in Canadian card catalogue (no card
   numbers or private details requested).
2. Tap "Somewhere new" or select a merchant:
   - With location allowed: nearby merchants appear via MapKit.
   - With location denied: enter any merchant name (e.g. "Costco", "Starbucks", "Shell").
3. Select an amount or enter a test purchase amount (e.g., $50).
4. Review the recommendation result: top card recommendation, calculated reward value,
   runner-up card comparison, and specific earn-rule attribution.
5. In Settings / Wallet Setup, examine the card condition toggles and switch thresholds.

CONTACT

[[CONTACT NAME]] — [[CONTACT EMAIL]] — [[CONTACT PHONE]]
Available for questions or clarification during review.
```

---

# PART B — Paste into "TestFlight → What to Test" (Build Release Notes)

### English (en-CA / en-US)
```text
Welcome to the PickMe beta!

PickMe helps you maximize credit card rewards at checkout by calculating the best card in your wallet for every purchase.

What to test in this build:
1. Onboarding & Wallet Setup: Select your cards from the 10-card catalogue, configure card condition rules, and set your default card and switch threshold.
2. Checkout & Recommendations: Try searching for merchants (both via nearby search and manual search) and verify the reward calculation breakdown and runner-up comparisons.
3. Ambient Arrival Notifications: Enable location alerts for your frequent shopping spots and check arrival suggestions.
4. Settings & Data Management: Test the account sync (optional sign-in) and local/cloud account deletion controls under Settings.

Please submit feedback directly through the TestFlight app or take screenshots with notes!
```

### French (fr-CA)
*(Machine-drafted — human legal/linguistic review recommended)*
```text
Bienvenue dans la version bêta de PickMe !

PickMe vous aide à maximiser vos récompenses de cartes de crédit lors de vos achats en calculant la meilleure carte de votre portefeuille pour chaque transaction.

À tester dans cette version :
1. Configuration du portefeuille : Sélectionnez vos cartes parmi le catalogue de 10 cartes, configurez vos conditions et définissez votre carte par défaut ainsi que votre seuil de changement.
2. Recommandations et paiement : Recherchez des commerces (recherche à proximité ou manuelle) et vérifiez le calcul des récompenses et les cartes alternatives.
3. Alertes d'arrivée ambiantes : Activez les alertes de localisation pour vos commerces fréquents et vérifiez les notifications suggérées.
4. Paramètres et gestion des données : Testez la synchronisation (connexion facultative) et les options de suppression de compte locale/en ligne dans les Paramètres.

Envoyez vos commentaires directement via l'application TestFlight ou par capture d'écran !
```

---

# PART C — Why each section is there & pre-submission checklist

## C1. The TestFlight External Review threshold

**[verified]** Internal testers (up to 100 users assigned Admin, App Manager, Developer, Marketer,
or Tester roles in App Store Connect) do not trigger Beta App Review. Builds become available
immediately upon upload and processing.

**[verified]** External tester groups (up to 10,000 testers invited via email or public link)
**require Beta App Review for the first build of a new version**. Subsequent builds for the same
version typically receive expedited review or automated clearance unless significant changes are
flagged.

## C2. Load-bearing review elements

1. **Shortcuts & Wallet Capture:** Explaining the Apple Shortcuts automation upfront prevents
   reviewers from mistaking PickMe for an unapproved FinancialKit consumer or unauthorized payment
   interceptor.
2. **Location background mode justification:** Guideline 2.5.4 strictly evaluates apps declaring
   `UIBackgroundModes = ["location"]`. The notes explicitly explain the `CLMonitor` / region
   monitoring mechanism and confirm continuous GPS is not used.
3. **Merchant-patronage paragraph (added 2026-08-27):** Always location plus a Wallet-transaction
   automation is a combination a beta reviewer is likely to question. The notes now say plainly
   that a local, on-device visit-frequency record (never uploaded) tunes the notification
   threshold, matching the fuller description in
   [`app-privacy-labels.md`](app-privacy-labels.md) §2.3.
4. **Guideline 2.1(a) Backend & Demo Account:** Corrected per commit `bc6c19f`. The backend must
   stay online. The demo credentials prevent unnecessary "need login" rejections.

## C3. Pre-Submission Checklist

- [ ] Confirm the backend at `moneytalks.zubairmuwwakil.com` is healthy (`GET /api/health` or
      equivalent status check).
- [ ] Replace `[[DEMO EMAIL]]` and `[[DEMO PASSWORD]]` with verified test credentials in Clerk.
- [ ] Replace `[[CONTACT NAME]]`, `[[CONTACT EMAIL]]`, and `[[CONTACT PHONE]]`.
- [ ] Verify that the manual merchant search path works cleanly when location is completely denied.
- [ ] Confirm the build version (`MARKETING_VERSION = 0.2`, `CURRENT_PROJECT_VERSION = 1`) matches
      the App Store Connect version record.
- [ ] Verify that external invites are withheld until the Phase-3 dogfood week gate criteria
      (fired/suppressed/coverage) are met.
