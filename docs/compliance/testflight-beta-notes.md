# TestFlight beta review notes

**Build:** `2.1 (43)`

**Checked against the shipping source:** 5 September 2026

Replace the demo-account placeholders before submission. The reviewer should be able to use the
core recommendation flow signed out and the report-delivery flow with the demo account.

## Part A — App Review Information → Notes

```text
PickMe (ca.pickme.cardcopilot) calculates which credit card in a user's wallet is expected to
earn the highest reward for a purchase and shows the arithmetic behind that choice. It does not
hold, transfer, or manage funds; initiate payments; connect to bank APIs; or request card numbers,
CVVs, PINs, or online-banking credentials. The user pays manually with their own card.

The core wallet, merchant search, checkout recommendation, and local history work without an
account. Sign-in through Clerk is optional and enables account sync, Wallet Shortcut capture, and
direct tester-report delivery to the In Unity review inbox.

Location is optional and off until the user enables it. While Using permission supports a one-time
nearby-merchant lookup. Always permission supports the separate arrival-alert feature through
Core Location region and significant-change monitoring while the app is closed. PickMe does not
declare the continuous-location background mode and does not run continuous GPS tracking. A user
who declines location can reach the same checkout flow by searching for a merchant by name.

The optional Apple Wallet Shortcut is configured by the user. It can send the Wallet merchant
description, amount, card description, timestamp, and optional current location to the authenticated
In Unity endpoint so the captured purchase can be evaluated. PickMe never receives a card number or
bank credential.

TESTER REPORTS

Account & Settings → Report a problem lets a tester describe expected and actual behaviour, preview
the entire report, and then send it while signed in or privately share a JSON file while signed out.
App version, build, iOS, and catalogue version are automatic. Category counts, a redacted Wallet
delivery diagnostic, and a detailed arrival log are separate opt-ins. The redacted Wallet diagnostic
excludes merchant, amount, card, and coordinates. The detailed arrival log clearly warns that it can
contain precise locations, merchant names, candidate cards, and arrival times. Submitted reports are
kept for 30 days and can be deleted from the app.

REVIEW WALKTHROUGH

1. Launch PickMe and continue without signing in.
2. Add cards from the built-in catalogue, select a default, and finish wallet setup.
3. Choose a merchant or category, enter an amount, and inspect the recommendation explanation.
4. Open Account & Settings → Report a problem. Enter expected and actual behaviour and preview the
   report. Signed out, the app offers a JSON file and states that sharing it does not submit it.
5. Sign in with the demo account below, return to Report a problem, submit a report, and refresh its
   review status.
6. Arrival alerts are optional under Settings. Their background behaviour requires a physical device;
   all manual recommendation features remain available if location is declined.

Demo account email: [[DEMO EMAIL]]
Demo account password: [[DEMO PASSWORD]]

Support: https://inunity.ca/support
Privacy: https://inunity.ca/privacy
```

## Part B — What to Test

### English (Canada)

```text
Build 2.1 (43)

Please test wallet setup, card conditions and valuations, merchant/category checkout advice, reward
math explanations, uncatalogued-card requests, optional Wallet Shortcut capture, and optional arrival
alerts on a physical device.

When something differs from what you expected, open Account & Settings → Report a problem. Preview
the report before sending. Diagnostic counts, a redacted Wallet delivery record, and the detailed
arrival log are optional. Sent reports show their review status and can be deleted in the app.

Please include the approximate time and clear expected-versus-actual behaviour. Never enter card
numbers, passwords, CVVs, PINs, or banking credentials.
```

### Français (Canada) — translation draft

```text
Version 2.1 (43)

Veuillez tester la configuration du portefeuille, les conditions et la valeur des points, les
recommandations par commerce ou catégorie, l'explication des calculs, les demandes de cartes non
répertoriées, la saisie facultative par Raccourci Wallet et les alertes d'arrivée sur un appareil
physique.

Si le résultat diffère de vos attentes, ouvrez Compte et réglages → Signaler un problème. Vérifiez
le rapport avant de l'envoyer. Les compteurs de diagnostic, le diagnostic Wallet expurgé et le
journal détaillé des arrivées sont facultatifs. Les rapports envoyés affichent leur état de révision
et peuvent être supprimés dans l'app.

Indiquez l'heure approximative et décrivez clairement le résultat attendu et le résultat observé.
N'inscrivez jamais de numéro de carte, mot de passe, CVV, NIP ou identifiant bancaire.
```

Have the French text reviewed by a fluent Canadian French speaker before submission.

## Submission checks

- Confirm the build shown in App Store Connect is `2.1 (43)`.
- Replace both demo-account placeholders and test the credentials against production.
- Confirm `https://inunity.ca/privacy` and `https://inunity.ca/support` load while signed out.
- Confirm `/admin/tester-reports` is available only to an authorized reviewer.
- Complete the physical-device arrival and notification checks in `TESTFLIGHT.md`.
- Revisit these notes after any change to accounts, networking, Wallet capture, report attachments,
  location, or retention.
