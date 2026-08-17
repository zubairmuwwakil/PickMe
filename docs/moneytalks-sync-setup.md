# MoneyTalks sync setup

PickMe checkout works without this configuration. These steps enable only sync, capture feedback, and Wallet Shortcut token creation.

1. In the **new MoneyTalks-dedicated Clerk application** (never the old Looply application), open **Native applications**, enable the Native API, and add an iOS application with App ID Prefix `MC8XJ6GXBM` and bundle ID `ca.pickme.cardcopilot`.
2. Copy its **Publishable key** (`pk_test_…` for development or `pk_live_…` for production). Do not use a secret key in PickMe.
3. In [MoneyTalksConfiguration.swift](../App/CardCopilot/Services/MoneyTalksConfiguration.swift), replace `nil` in `clerkPublishableKey` with the copied key and `nil` in `apiBaseURL` with the deployed MoneyTalks origin, for example `https://moneytalks.example.com/` (include a trailing slash). The origin must serve the three spine routes over HTTPS.
4. In the MoneyTalks deployment, set `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` and `CLERK_SECRET_KEY` from that **same** dedicated app, then set `ALLOWED_EMAILS` to the dogfood owner email. Deploy the server commit and run its Prisma migration before using the iOS client.
5. In PickMe Signing & Capabilities, add **Associated Domains** with `webcredentials:{MoneyTalks Clerk Frontend API URL}`. Copy that Frontend API URL from the dedicated Clerk dashboard; it is not necessarily the MoneyTalks web origin. Regenerate the provisioning profile.
6. Enable the intended owner sign-in methods in Clerk. Run PickMe, open **Sync & Capture**, sign in, create an installation token, and paste it into the per-card Wallet Shortcut described by `MoneyTalks/docs/plans/2026-08-16-wallet-capture-spec.md`.

The installation token is shown once. Paste it directly into the Shortcut; do not commit it or copy it into configuration.
