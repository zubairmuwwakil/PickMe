# App Store Connect Privacy Labels — answers and justifications

> ## ⚠ Draft for review — not submitted
>
> Written by Zubair with Claude; **neither of us is a lawyer.** The privacy "nutrition label" is a
> binding representation to Apple and to users, and a wrong answer is a misrepresentation, not a
> typo. Have Canadian counsel review this alongside
> [`privacy-policy.md`](privacy-policy.md) before submitting.
>
> **[verified]** = quoted from an Apple primary source with URL and date checked ·
> **[inference]** = reasoning from those sources · **[uncertain]** = genuinely unresolved.

**Status:** draft v1, 2026-08-15 · **App:** Canadian Card Copilot for iPhone
**Sources checked 2026-08-15:**
[App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/) ·
[User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/) ·
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

---

## 1. The answer, and why it is shorter than expected

**Declare: "Data Not Collected."** Every data type. The questionnaire ends at the first question.

This is narrower than the framing the project has been carrying — that location is *used but not
linked to identity and not used for tracking*. That framing is correct as a description of the app,
but it answers a question **Apple never asks us**, because Apple's definition of "collect" is about
transmission, not use.

**[verified]** Apple's definition:

> "'Collect' refers to transmitting data off the device in a way that allows you and/or your
> third-party partners to access it for a period longer than what is necessary to service the
> transmitted request in real time."

**[verified]** And the disposition of on-device data:

> "Data that is processed only on device is not 'collected' and does not need to be disclosed in
> your answers. If you derive anything from that data and send it off device, the resulting data
> should be considered separately."

([Apple, App privacy details](https://developer.apple.com/app-store/app-privacy-details/), checked
2026-08-15.)

**[inference]** Canadian Card Copilot transmits nothing off the device to us or to any partner. It
has no backend, no analytics SDK, no advertising SDK, and no account system. The location fix, the
merchant record, the predictions, and the optional purchase amounts are all written to a local
SwiftData store and read back locally. Under the definition above, **none of it is collected**, and
the label must say so.

Answering "Yes, we collect Precise Location" when we do not would be *inaccurate*, not merely
cautious. The label is a factual representation; over-disclosure is a wrong answer in the same way
under-disclosure is.

The rest of this document exists because **the reasoning still has to be written down**: App Review
may ask why an app that prompts for location declares no collection (§4), and every answer below
becomes live the moment any server-side feature ships (§6).

---

## 2. The questionnaire, question by question

### Q1. "Do you or your third-party partners collect any data from this app?"

**Answer: No.**

**Justification.**

| What the app touches | Where it goes | Collected? |
|---|---|---|
| One-time CoreLocation fix | Held in memory to build a MapKit query; the resulting *merchant's* coordinates are written to the local database | **No** — never transmitted to us |
| Card list, card settings, cap-progress estimates, point valuations | Local SwiftData store | **No** |
| Merchant name / Apple Maps id / lat-lon of confirmed merchants | Local SwiftData store (`StoredMerchant`) | **No** |
| Predictions: merchant, category, card, values, valuation, explanation, timestamp | Local SwiftData store (`StoredPrediction`) | **No** |
| Optional purchase amount | Local SwiftData store (`StoredPrediction.amountCad`, nullable) | **No** |
| Corrections, miss class, free-text notes | Local SwiftData store (`StoredObservation`) | **No** |
| MapKit POI / local search request | Sent to **Apple** to service the search in real time; we never receive it | **No** — see §5 |
| Crash and usage data | Nothing installed. No analytics SDK, no crash SDK | **No** |

There are **no third-party partners**. The app has no SDK dependencies beyond Apple frameworks and
one first-party local Swift package (`CardCopilotEngine`), which performs arithmetic and makes no
network calls.

**Because Q1 is "No", App Store Connect asks nothing further.** There is no data-type selection, no
purpose selection, no linked-to-identity question and no tracking question. The remaining sections
record what the answers *would* be.

### Q2–Q5 (not asked). What they would be, for the record

If a future build collected any of this, these are the answers the current feature set implies:

| Data type (Apple's taxonomy) | Would apply to | Purpose | Linked to identity? | Used for tracking? |
|---|---|---|---|---|
| **Precise Location** | the one-time fix; stored merchant coordinates | App Functionality | **No** | **No** |
| **Other Financial Info** | which card products you hold; cap-progress spend estimates | App Functionality | **No** | **No** |
| **Purchase History** | merchant + optional amount + timestamp | App Functionality | **No** | **No** |
| **Other User Content** | free-text correction notes | App Functionality | **No** | **No** |
| **Product Interaction / Usage Data** | n/a — nothing recorded | — | — | — |
| **Crash / Performance Data** | n/a — no crash SDK | — | — | — |
| **Identifiers** (User ID, Device ID) | **none exist** — no account, no advertising identifier, no device identifier read or stored | — | — | — |
| **Payment Info** | **never** — no card numbers, expiry dates, CVV, PINs, or banking credentials are collected or storable anywhere in the app | — | — | — |

Note what is *absent*: with no account, no email, no name, and no device or advertising identifier
anywhere in the app, there is **no identity for anything to be linked to.** That is the structural
reason the "Linked to You" column is No, and it is stronger than a policy commitment — there is no
join key.

**Purpose** would be **App Functionality** in every row. **[verified]** Apple defines it as "Such
as to authenticate the user, enable features, prevent fraud, implement security measures, ensure
server up-time, minimize app crashes, improve scalability and performance, or perform customer
support." Recommending a card *is* the feature.

**[inference]** *Product Personalization* — "Customizing what the user sees, such as a list of
recommended products, posts, or suggestions" — is a plausible second reading, since the app does
produce a recommendation. We read it as App Functionality because the recommendation **is** the
product rather than a personalization layer over it, and because Apple's personalization examples
are content-feed shaped. **[uncertain]** — if counsel or App Review prefers Product
Personalization, adding it costs nothing and is the safer of the two. It is moot while Q1 is "No".

---

## 3. "Not linked to you" — the reasoning, if it is ever needed

**[verified]** Apple: "You'll need to identify whether each data type is linked to the user's
identity (via their account, device, or other details) by you and/or your third-party partners.
Data collected from an app is often linked to the user's identity, unless specific privacy
protections are put in place before collection to de-identify or anonymize it."

**[inference]** The app clears this without needing de-identification measures, because linkage is
impossible by construction:

1. **No account.** No sign-up, sign-in, email, phone number, or name. Guideline 5.1.1(v) — "If your
   app doesn't include significant account-based features, let people use it without a login" — is
   satisfied by having no login at all.
2. **No identifier.** The app does not read the IDFA or IDFV, does not generate a persistent
   installation ID, and does not transmit a device identifier, because it transmits nothing.
3. **No transmission.** Linkage would have to happen somewhere. There is no server on which to
   perform it and no partner to perform it with.

The local `UUID` primary keys on `StoredPrediction` / `StoredObservation` / `StoredMerchant` are
SwiftData row identifiers. They never leave the device, are not derived from device hardware, and
are meaningless outside the one database file.

---

## 4. "Not used for tracking" — and the answer to the obvious reviewer question

**[verified]** Apple's definition: "Tracking refers to the act of linking user or device data
collected from your app with user or device data collected from other companies' apps, websites, or
offline properties for targeted advertising or advertising measurement purposes. Tracking also
refers to sharing user or device data with data brokers."

**[verified]** And the first item on Apple's own list of what is **not** tracking:

> "When user or device data from your app is linked to third-party data solely on the user's device
> and is not sent off the device in a way that can identify the user or device."

([Apple, User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/),
checked 2026-08-15.)

**[inference]** This is the app's exact shape. It joins a location fix to a merchant record to a
card catalogue **entirely on device**, and sends nothing off it. There is no advertising of any
kind, first- or third-party, and no data broker relationship.

**Therefore: no `NSUserTrackingUsageDescription` key, and no AppTrackingTransparency prompt.**
**[verified]** ATT permission is required "in order to track them or access their device's
advertising identifier" — the app does neither. Adding an ATT prompt an app does not need is itself
a defect; it trains users to grant permissions reflexively.

### If App Review asks: "your app requests location but declares no data collection"

This is the most likely follow-up, and it has a clean answer. Suggested reply:

> Canadian Card Copilot requests location to run a one-time nearby-merchant search through MapKit
> so the user can confirm which store they are in. The location fix is used on device to build that
> query and is never transmitted to us — we operate no server, and the app contains no analytics,
> crash-reporting, or advertising SDK of any kind.
>
> Per Apple's App Privacy guidance, "Data that is processed only on device is not 'collected' and
> does not need to be disclosed in your answers." On that definition the app collects nothing, so
> "Data Not Collected" is the accurate declaration. Requesting a permission and collecting data are
> different things, and this app does the first without the second.
>
> The app is fully usable if location is declined: a manual merchant search reaches every feature.

---

## 5. The one genuinely arguable case: MapKit

**[uncertain] — flagged rather than resolved.**

`MKLocalPointsOfInterestRequest` and `MKLocalSearch` send a search term and a map region to Apple's
servers. Region is derived from the user's location. So *something* does leave the device.

**The case for "not collected"** — and why we are going with it:

- Apple's definition turns on data being transmitted "in a way that allows **you and/or your
  third-party partners** to access it." **We** never access it. The publisher receives nothing,
  logs nothing, and has no agreement with Apple giving it access to Maps queries.
- The definition further excludes data held no "longer than what is necessary to service the
  transmitted request in real time." A POI search is the paradigm case of a real-time serviced
  request.
- Apple is the platform vendor answering an OS-framework call, not a third-party partner of ours in
  the sense the label contemplates. **[inference]**

**Why it is still flagged.** The reasoning above is ours, not a quotation. We did not find an Apple
statement that says in terms "MapKit searches do not require disclosure by the developer." A
conservative counsel may prefer disclosing **Coarse Location → App Functionality → Not Linked →
Not Tracking**. That would be an over-disclosure, and it would put a "Location" chip on the App
Store product page that we would then have to explain.

**Recommendation:** declare Data Not Collected; keep this section as the written record of why; and
**disclose the MapKit transmission plainly in the privacy policy regardless** — which
[`privacy-policy.md`](privacy-policy.md) §6 does.

That split is deliberate and worth stating: **the label and the policy answer different questions.**
The label asks a narrow, defined question about what the *developer* collects. The policy answers
the broader question a user actually has — "does anything about me leave my phone?" — where the
honest answer is "yes, one search query, and it goes to Apple, not to us." Answering the narrow
question narrowly and the broad question broadly is not inconsistency; collapsing them would be.

---

## 6. What would change these answers

Any of the following flips Q1 to **Yes** and makes §2's table live. Treat this as a checklist to
re-run before any release that adds a network call:

| Change | New declaration |
|---|---|
| Any analytics or crash SDK (Firebase, Sentry, Amplitude, TelemetryDeck, …) | Usage Data / Diagnostics, and re-examine tracking |
| Any backend of our own, even "anonymous" telemetry | whatever is sent; "anonymous" is not automatically Not Linked |
| Crowdsourced merchant observations (design doc §10, Phase 2) | **Precise Location + Purchase History, off device.** The largest single change on the roadmap — it inverts the privacy posture the product is currently built on |
| Remote versioned catalogue updates (design doc §10) | **Likely still "No"** — downloading a catalogue sends no user data upward. **[inference]**, confirm at the time |
| Accounts or sync | Contact Info, Identifiers, and Linked-to-You throughout |
| Any advertising, affiliate tracking, or referral attribution | Third-Party Advertising, and ATT almost certainly required |
| Statement CSV import (design doc v1.5 candidate) | **Still "No"** if parsing is local, which is the design. Worth re-confirming — the data involved is far more sensitive than anything the app holds today |

**[verified]** Guideline 5.1.2(ii): "Data collected for one purpose may not be repurposed without
further consent unless otherwise explicitly permitted by law." The crowdsourcing feature cannot
reuse merchant confirmations gathered under today's local-only promise. It needs fresh, separate
consent — and users who decline must keep the app they installed.

---

## 7. What to click in App Store Connect

1. **App Store Connect → your app → App Privacy → Get Started.**
2. Q: *"Do you or your third-party partners collect any data from this app?"* → **No.**
3. Confirm the "Data Not Collected" declaration. The product page will show
   **"Data Not Collected — The developer does not collect any data from this app."**
4. **Privacy Policy URL** — required regardless of the answer above.
   **[verified]** Guideline 5.1.1(i): "All apps must include a link to their privacy policy in the
   App Store Connect metadata field and within the app in an easily accessible manner." Both halves.
   See [`submission-readiness.md`](submission-readiness.md) §A4 (hosting) and §B3 (in-app link).
5. **Do not** add `NSUserTrackingUsageDescription` to `Info.plist` (§4).
6. **Do** write a specific `NSLocationWhenInUseUsageDescription`.
   **[verified]** Guideline 5.1.1(ii): "Ensure your purpose strings clearly and completely describe
   your use of the data."
   Draft: *"Card Copilot takes a single location reading to list the shops near you, so you can
   confirm where you are without typing. Your location is never sent anywhere — you can also search
   for a merchant by name instead."*
   Do **not** request `NSLocationAlwaysAndWhenInUseUsageDescription`. **[verified]** Guideline
   5.1.1(iii): "Apps should only request access to data relevant to the core functionality."
7. **Re-run this document** before every release that touches networking (§6).
