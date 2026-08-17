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

> ## 🔴 REWRITTEN 2026-08-17 — the answer has flipped
>
> **Draft v1 (2026-08-15) declared "Data Not Collected". That is now false and must not be
> submitted.** It described an app with no accounts, no server, and no outbound traffic except
> MapKit. Since then three things shipped:
>
> 1. **Clerk authentication** — real accounts, real email addresses, a real session token.
> 2. **A backend** at `moneytalks.zubairmuwwakil.com` the app reads cap usage and capture
>    feedback from.
> 3. **Apple Wallet transaction capture** — a Shortcut that POSTs merchant, amount, card, time
>    **and precise coordinates** to that backend, where the coordinates are *retained*.
>
> v1's own §6 listed exactly these as the changes that would flip Q1 to "Yes". They did.
>
> The reasoning in §4 (tracking) and §6 (MapKit) survives largely intact and is retained. §1, §2,
> §3 and §8 are rewritten.

**Status:** draft v2, 2026-08-17 · **App:** PickMe for iPhone (bundle `ca.pickme.cardcopilot`)
**Sources checked 2026-08-15, re-checked 2026-08-17:**
[App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/) ·
[User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/) ·
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

---

## 1. The answer

**Q1: "Do you or your third-party partners collect any data from this app?" → YES.**

**[verified]** Apple's definition of "collect":

> "'Collect' refers to transmitting data off the device in a way that allows you and/or your
> third-party partners to access it for a period longer than what is necessary to service the
> transmitted request in real time."

**[verified]** And of on-device data:

> "Data that is processed only on device is not 'collected' and does not need to be disclosed in
> your answers. If you derive anything from that data and send it off device, the resulting data
> should be considered separately."

([Apple, App privacy details](https://developer.apple.com/app-store/app-privacy-details/), checked
2026-08-17.)

PickMe now does both things at once, and the label has to describe the union:

- **The checkout engine is still entirely local.** Recommendations, the prediction log, purchases,
  statement observations, saved merchants, and the discovery cache never leave the device.
- **The account and capture path transmits and retains.** A signed-in owner's email, user id, cap
  usage, captured wallet transactions, and the **coordinates of where those transactions
  happened** are held on a server the publisher controls.

### 1.1 The awkward part: it depends on the user

Most of what follows is only true for an owner who signs in and assembles the Wallet Shortcut. An
owner who never does is in exactly the position v1 described — nothing reaches the publisher at all.

**Apple's questionnaire has no way to say that.** The label describes the app, not a user's
configuration. **[inference]** So every data type the app is *capable* of collecting must be
declared, and the fact that collection is optional belongs in the privacy policy and in the app's
own onboarding, not in the label. Under-declaring because a feature is opt-in would be a
misrepresentation; over-declaring an optional feature is accurate but incomplete, which the policy
then completes.

**[uncertain] — flag for counsel.** Whether the *Shortcut* leg counts as "data collected from this
app." The Shortcut is assembled by the user inside Apple's Shortcuts app, authenticated with a
token PickMe issues, posting to PickMe's server. The data unquestionably reaches the publisher; the
question is only whether Apple treats a user-assembled Shortcut as part of the app's collection
surface. **We answer yes.** The publisher receives and stores the data, which is the substance the
label is about, and a narrower reading would let any developer launder collection through
Shortcuts.

---

## 2. Data types to declare

Every row below is **App Functionality** for purpose, **Linked to You**, and **Not Used for
Tracking**. §3 and §4 justify the last two columns.

| Data type (Apple's taxonomy) | What it is here | Reaches the server via |
|---|---|---|
| **Contact Info → Email Address** | The address used to sign in | Clerk |
| **Identifiers → User ID** | Clerk user id; wallet-installation id | Clerk, capture |
| **Purchase History** | Captured Wallet transactions: merchant, amount, currency, card, timestamp | Wallet Shortcut |
| **Location → Precise Location** | Coordinates and accuracy captured at transaction time, **retained** on the event | Wallet Shortcut |
| **Other Financial Info** | Cap usage per card; which card products are held | Sync |

### 2.1 Precise Location deserves its own paragraph

This is the most sensitive declaration on the list and the one most likely to draw a reviewer
question. The Wallet capture Shortcut takes a location fix at transaction time and sends it with
the transaction. The server does **not** truncate it after resolving the merchant — the
[wallet capture spec](../../../MoneyTalks/docs/plans/2026-08-16-wallet-capture-spec.md) records
that as a deliberate owner decision on 2026-08-17: *"the complete record is the product."*

So the server holds a linkable history of where a person shopped, when, on which card, for how
much. That is precise location linked to identity, retained indefinitely, and the label must say
so. It is defensible as App Functionality — location disambiguates an ambiguous merchant string —
but it is not incidental and must not be described as if it were.

**[inference]** Retention is a policy choice, not a technical necessity. The spec notes every
location column is nullable and redaction is a single UPDATE. If counsel is uncomfortable, the
mitigation is cheap and the label would soften accordingly.

### 2.2 What is still NOT collected

| Not declared | Why |
|---|---|
| **Crash / Performance Data** | No crash SDK. Nothing installed. |
| **Product Interaction / Usage Data** | No analytics SDK, first- or third-party. |
| **Advertising Data, Device ID** | No ad networks. The IDFA is never read; ATT is not requested. |
| **Payment Info** | **Never.** No card numbers, expiry dates, CVV, PINs, or banking credentials exist anywhere in the app or on the server. No payment rail, no bank connection. |
| **Contacts, Photos, Health, Browsing, Messages, Audio** | Not touched. |
| **Sensitive Info** | Not collected. |

The local prediction log, purchases, observations, saved merchant coordinates, and the discovery
cache are **not declared**, because they are processed only on device and Apple's definition
excludes them. The privacy policy still describes them in full — see §7 on why the two documents
answer different questions.

---

## 3. "Linked to You" — Yes, and why that is the honest answer

**[verified]** Apple: "You'll need to identify whether each data type is linked to the user's
identity (via their account, device, or other details) by you and/or your third-party partners."

v1 answered No, and gave a structural reason: there was no account, so there was no join key. **The
Clerk account is that join key.** Wallet events carry a `userId`; cap usage is per account; the
email identifies the person. Every declared row is linked.

**[inference]** No de-identification measure is claimed, because none is applied. Claiming
anonymisation we do not perform would be worse than declaring the linkage.

---

## 4. "Used for Tracking" — still No

**[verified]** Apple's definition: "Tracking refers to the act of linking user or device data
collected from your app with user or device data collected from other companies' apps, websites, or
offline properties for targeted advertising or advertising measurement purposes. Tracking also
refers to sharing user or device data with data brokers."
([Apple, User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/),
checked 2026-08-17.)

**[inference]** None of that happens. There is no advertising of any kind, no advertising
identifier is read, no data broker relationship exists, and no data is combined with any other
company's data. The server is the publisher's own and receives data from the publisher's own app
and Shortcut.

**Therefore: still no `NSUserTrackingUsageDescription`, and no ATT prompt.** **[verified]** ATT
permission is required "in order to track them or access their device's advertising identifier" —
the app does neither. Adding a prompt an app does not need trains users to grant permissions
reflexively.

Note this answer is now doing real work. In v1 it followed trivially from collecting nothing. It
now rests on the substantive claim that the publisher does not share or cross-link — a claim that
must be re-checked before any partnership, affiliate link, or referral scheme.

---

## 5. Location permissions — what changed, and what App Review will ask

The app requests **Always** authorization and declares the `location` background mode, because
arrival detection uses region monitoring that must fire while the app is not running.

`Info.plist` currently declares both:
- `NSLocationWhenInUseUsageDescription` — the one-time fix for finding a nearby merchant
- `NSLocationAlwaysAndWhenInUseUsageDescription` — arrival detection at saved and discovered areas

**This directly contradicts v1 §7 item 6**, which instructed *"Do not request
`NSLocationAlwaysAndWhenInUseUsageDescription`"* on guideline 5.1.1(iii) grounds ("only request
access to data relevant to the core functionality"). That instruction was written before ambient
arrival was a feature. Now that arrival detection *is* core functionality, Always is defensible —
but the justification has to be made rather than assumed.

### If App Review asks why an app like this needs Always

Suggested reply:

> PickMe tells you which credit card to use before you pay. Its arrival feature monitors a small
> number of geofenced shopping areas so it can suggest a card as you walk in — which requires
> region monitoring while the app is not running, and therefore "Always" authorization. The app
> never starts continuous location updates: it uses significant-location-change monitoring and
> region entry/exit only.
>
> The feature is entirely optional, off until the user enables it on a dedicated explainer screen,
> and the app is fully usable without it. Declining location leaves every feature reachable through
> manual merchant search.

**[inference]** Expect a follow-up about the background mode. The honest answer is that region
monitoring and significant-change monitoring both require it, and neither streams GPS.

---

## 6. MapKit — the analysis from v1, still standing, with one change

`MKLocalPointsOfInterestRequest` and `MKLocalSearch` send a search term and a map region to Apple.
**We** never receive it. v1 concluded this is not developer collection, because Apple's definition
turns on data being transmitted "in a way that allows **you and/or your third-party partners** to
access it," and Apple here is the OS vendor answering a framework call. That reasoning is unchanged
and still ours rather than a quotation — **[uncertain]** as it was.

**What changed:** these queries now also fire from **merchant discovery**, which runs on
significant location changes rather than only when the owner asks. Apple therefore receives a
sparse, passive signal of the owner's movement rather than only deliberate searches.

It does not change the label answer — the publisher still receives nothing — but it does change
what the privacy policy must disclose, and [`privacy-policy.md`](privacy-policy.md) §6 now says so
plainly. The query rate is deliberately held low: a speed gate skips driving, and a spatial cache
with negative caching means a place already looked at is never re-queried inside the retention
window.

---

## 7. Label and policy answer different questions

Worth restating, because the gap is wider in v2 than it was in v1.

The **label** asks a narrow, defined question: what does the *developer* collect? Local-only data
is excluded by Apple's own definition, so the prediction log, the purchases, the saved merchant
coordinates and the discovery cache do not appear on it.

The **policy** answers the question a user actually has: *what does this app know about me, and
what leaves my phone?* There, all of it belongs — including the local records, because "it stays on
your device" is a promise a user is entitled to see written down and is meaningless if the document
never admits the data exists.

Answering the narrow question narrowly and the broad question broadly is not inconsistency.
Collapsing them would be.

---

## 8. What would change these answers again

Re-run before any release that touches networking, accounts, or location:

| Change | New declaration |
|---|---|
| Any analytics or crash SDK | Usage Data / Diagnostics, and re-examine tracking |
| Advertising, affiliate tracking, or referral attribution | Third-Party Advertising; ATT almost certainly required; §4 would need rewriting |
| Sharing captured data with any other company | **Tracking becomes Yes.** The single most consequential change available |
| Truncating or dropping retained coordinates | Precise Location may soften to Coarse, or drop entirely |
| Crowdsourced merchant observations | Already covered by the Precise Location + Purchase History rows, but re-examine consent |
| Statement CSV import | Still local if parsing is local — confirm at the time |
| Removing the account and server | Back to v1's answer, but only if capture goes too |

**[verified]** Guideline 5.1.2(ii): "Data collected for one purpose may not be repurposed without
further consent unless otherwise explicitly permitted by law." Captured transaction data gathered
to power card advice cannot later feed anything else without fresh, separate consent.

---

## 9. What to click in App Store Connect

1. **App Store Connect → your app → App Privacy → Get Started.**
2. Q1 → **Yes.**
3. Select the five data types in §2. For each: purpose **App Functionality**, **Linked to the
   user: Yes**, **Used for tracking: No**.
4. **Privacy Policy URL** — required. **[verified]** Guideline 5.1.1(i): "All apps must include a
   link to their privacy policy in the App Store Connect metadata field **and within the app in an
   easily accessible manner**." Both halves.
5. **Do not** add `NSUserTrackingUsageDescription` (§4).
6. **Do** keep both location purpose strings specific and accurate (§5).
7. **Account deletion must be reachable in-app.** **[verified]** Guideline 5.1.1(v). Already built
   — Settings → Delete Account, with the local keep-or-erase choice.
8. **Re-run this document** before every release that touches networking, accounts, or location.
