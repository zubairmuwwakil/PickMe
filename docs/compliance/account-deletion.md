# Deletion, as built

**Status:** describes shipped code, not intent. Verified against PickMe `2569f4c` and MoneyTalks
`07dc568`, both on `main` as of 2026-08-17.

This exists because `privacy-policy.md` §7 and §8 describe deletion controls that were written
before accounts, sync, or the Wallet Shortcut existed. That document must be corrected against this
one before it is published — see [§5](#5-corrections-owed-to-privacy-policymd). Until then, treat
this file as the source of truth for what deletion actually does.

---

## 1. Two stores, two owners

The single most common misreading of this system is that "PickMe holds no data." That is true of
**our servers** and false of **the device**.

### PickMe on the iPhone — held locally, never uploaded

`CardCopilotApp.swift:24` declares a SwiftData container with no in-memory configuration, i.e. an
on-disk store that survives relaunch:

| Model | Contents |
|---|---|
| `StoredMerchant` | name, POI identifier, **latitude, longitude**, confirmed category, confirmation count, last seen |
| `StoredPrediction` | merchant, predicted category, winning card, **amount spent**, valuation in force, headline, timestamp |
| `StoredObservation` | card actually used, observed category, reward units posted, miss class, **free-text note** |

Plus two `UserDefaults` keys (`ambientDiagnostics.v1`, `ambientMutedMerchantIDs.v1`) and, when
ambient alerts are enabled, CoreLocation geofences around up to 20 of those coordinates.

Taken together this is a running record of **where the owner shopped, when, how much they spent,
and which card they used** — including precise coordinates at rest.

**None of it is ever transmitted.** `MoneyTalksSync.swift` never references any of the three
models. The app's complete outbound payload surface is `{"label": …}` when creating a Wallet
Shortcut token, `{"scope": "account"}` when deleting an account, and the Clerk bearer token. Cap
sync is a *pull*.

For Apple's App Privacy labels this local store is legitimately **not collected** — Apple treats
data processed only on device and never sent off device as uncollected. That is a labelling
conclusion, not a licence to say the app holds nothing.

**This is a statement about the local store only, not the app-wide label answer.** The app as a
whole declares collection, because the account and the Wallet capture path do transmit — see
[`app-privacy-labels.md`](app-privacy-labels.md) §2. Reading this paragraph as "the app declares
Data Not Collected" would be reading it backwards.

### MoneyTalks on the server — the account

Everything keyed to a `User` row in Postgres, including transactions captured by the Wallet
Shortcut (`/api/v1/wallet-events`), cap usage ledgers and accruals, owner state, wallet
installations, and the purchase/return/subscription spine.

Transaction data reaches the server **from the Shortcut, not from the app.**

---

## 2. The three controls

| Control | Where | Needs an account? | Removes |
|---|---|---|---|
| Erase this iPhone's history | PickMe → gear → This iPhone | **No** | The whole local store above: predictions, observations, merchants, mute list, counters, and live geofences |
| Delete my data | Web → Settings → Privacy & Data | Yes | Every server row owned by the user; the account and sign-in remain, so they can start over |
| Delete account | PickMe → gear → Danger zone, **and** Web → Settings → Privacy & Data | Yes | The `User` row (everything cascades off it) and the Clerk user. Offers the local erase above as a separate choice |

The local control is deliberately **not** gated on being signed in. Checkout never required an
account, so a user who has never signed in still has a local history — and must not have to create
an account, or delete one, in order to erase it.

---

## 3. Ordering and failure semantics

Account deletion is database-first, Clerk-second, and that order is load-bearing:

1. `prisma.user.delete()` — every `user` relation in `schema.prisma` declares `onDelete: Cascade`,
   with no exceptions, so this removes all server-side data with no table list to fall behind the
   schema.
2. `clerkClient().users.deleteUser()` — a `404` is treated as success, so a retry is idempotent.

If step 2 fails, the data is already gone and the sign-in still works, so the user can retry. The
reverse order would strand undeleted personal data behind a login that no longer functions. The
API says so explicitly, returning `{ dataDeleted: true }` on that path.

**No residual record is kept.** The `DataDeletionJob` row created to track the operation is itself
a child of `User`, so it cascades away with the account. A deleted account leaves no trace, not
even the record of its own deletion. A *failed* deletion does leave a `FAILED` job row, because in
that case the user still exists.

On the device, every step after the server confirms is local cleanup that cannot fail the
operation. If the server call fails, **nothing local is touched** and the UI says so.

---

## 4. What deletion does *not* reach

- **The local history, unless chosen.** Account deletion defaults to *keeping* it. It never left
  the phone, so the account has no claim on it, and an accidental deletion should cost the account
  rather than the owner's own record of what the app advised.
- **iPhone backups.** iCloud or computer backups may contain the app's store; those are governed by
  the owner's iOS settings, not by us.
- **Apple.** Maps/POI lookups are answered by Apple under Apple's privacy policy. We receive no
  copy, so there is nothing for us to delete.

### App Review path (Guideline 5.1.1(v))

Sign in → tap the **gear** on the main screen → **Danger zone → Delete Account** → step 1 states
the consequences and takes the keep-or-erase decision for local history → step 2 confirms
destructively. Signed out, the row is absent because there is no account to delete; **Erase This
iPhone's History** remains available.

---

## 5. Corrections owed to `privacy-policy.md`

These are statements in the current draft that shipped code contradicts. **The policy must not be
published until they are fixed** — the draft says as much about itself at §B1.

> **Resolved in the published page (2026-08-17).** All seven are corrected in
> `MoneyTalks/src/app/privacy/content.ts`, published at
> https://moneytalks.zubairmuwwakil.com/privacy (MoneyTalks `910fc9f`). Item 4 is scoped to the web
> hub rather than built for iOS; item 5 is dropped rather than built. `policy-claims.test.ts` pins
> each retraction so it cannot be reintroduced silently.
>
> **The corrections are not back-ported into `privacy-policy.md`** — it is retained as the long-form
> working document with its wrong sections intact, so this list stays legible against them. This
> file remains the source of truth for what deletion does.
>
> Two things the published page discloses that this file does not cover, both server-side: the
> Wallet Shortcut posts optional precise coordinates that are **retained** un-truncated per the
> owner decision in `MoneyTalks/docs/plans/2026-08-16-wallet-capture-spec.md` §Privacy/retention,
> and the Gmail integration holds the `gmail.readonly` scope — whole-mailbox read access, which the
> scan-mode setting narrows in processing but not in authorization.

1. **§6 — "That is the app's only outbound network activity of any kind."** False once signed in.
   The app talks to MoneyTalks (Clerk auth, cap/feedback pull, installation tokens, deletion) and
   the Wallet Shortcut posts transactions to it.
2. **§7 — "We do not set an expiry, because we hold nothing and cannot delete anything on your
   behalf."** False for account holders. We hold server data and we can, and do, delete it.
3. **§8 — "If you write to us with a request for your data, we will have nothing to send you."**
   False for account holders.
4. **§8 — "Access / get a copy: Settings → Export."** The iOS app has **no export control**. The
   web hub does (`/api/data/export`). Either build the iOS export or scope the claim to the web.
5. **§7/§8 — "delete individual records."** Not built. There is no per-record delete in the app;
   there is now a whole-store erase. Either build it or drop the claim.
6. **§B1 — "Sections 7 and 8 describe controls that do not exist in the code yet."** Partly
   resolved: delete-all and account deletion now exist. Export and per-record delete do not.
7. **Naming.** The draft still says "Canadian Card Copilot" throughout; the product is PickMe as of
   `d4338e2`.

Item 1 is the serious one. The others overstate a feature; item 1 misdescribes the data flow.
