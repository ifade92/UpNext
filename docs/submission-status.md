# UpNext App Store Submission — Status

> Living doc. Update as items complete. Check this first when resuming a session.

**Current state:** First-time submission prep. Sandbox IAP verified end-to-end. Subscription attached to v1.0. ~4 remaining items before submit.

**Last updated:** 2026-04-29

---

## ✅ Done

### Code & manifest (committed in `72154a3`)
- Paywall Terms + Privacy links (App Store guideline 3.1.2)
- `PrivacyInfo.xcprivacy` declaring 6 collected data types
- `Info.plist` `ITSAppUsesNonExemptEncryption = false`
- RevenueCat single App Store API key (Test Store key removed)
- `paywallBypassed = false` in Debug

### App Store Connect
- Two subscriptions created: `upnext_base_monthly` (Ready to Submit), `upnext_multi_monthly` (Missing Metadata, sidelined)
- IAP review screenshot uploaded to `upnext_base_monthly` (1290×2796)
- `upnext_base_monthly` attached to v1.0 via "In-App Purchases and Subscriptions" section on the version page
- App Store Connect API key generated (Team Key, App Manager role) — `.p8` saved locally as `AuthKey_V2LTCYMP45.p8`

### RevenueCat
- Single offering "default" active with `$rc_monthly` package → `upnext_base_monthly`
- `UpNext Pro` entitlement attached to `upnext_base_monthly`
- App Store Connect API integration: P8 key uploaded, "Valid credentials" confirmed
- Sandbox purchase end-to-end verified: customer `$RCA••••6e3c` active, `UpNext Pro` entitlement granted, auto-renewal cycle running

### Web (deployed to upnext-app.com)
- `privacy.html` + `terms.html`: SMS/Twilio claims removed, contact email → `support@upnext-app.com`, dates refreshed

---

## 🔵 Remaining before submit

1. **Demo Firestore account for App Review.** Create `appreview@upnext-app.com` in Firebase Auth. Seed Firestore: `users/{uid}` (role: owner), `shops/{uid}` with `subscriptionStatus: "active"`, `subscriptionTier: "base"`, plus 2-3 sample barbers and services. Capture the credentials for ASC Review Notes.

2. **Capture real App Store screenshots.** Need iPhone 6.9" (1290×2796 or 1320×2868) and iPad 13" (2064×2752). 3-10 per size. Audit `docs/app-store-submission-audit.md` Section 2 has content recommendations. Replace the deleted generic placeholders.
   - **Status 2026-04-29:** Carlos has 7 device screenshots from real Fademasters use, but they're 1206×2622 (iPhone 6.3", below 6.9" requirement). Walk-in customer names scrubbed via Pillow script (saved to `screenshots/edited/`). To-do: retake on iPhone 16 Pro Max simulator at 1290×2796, then re-scrub names if needed.

3. **Fill remaining ASC metadata.** ✅ Mostly done 2026-04-29.
   - App Information: filled (name, subtitle, category, privacy URL, copyright)
   - Version 1.0 text: filled (promo text, description, keywords, support/marketing URLs)
   - App Privacy: filled (6 data types — Name, Email, Phone, User ID, Device ID, Purchase History; all linked, none used for tracking, App Functionality purpose)
   - Age Rating: filled → 4+
   - App Review Information: contact + notes filled. **Sign-In credentials still pending demo account creation.**

4. **Submit.**

---

## ⚠️ Known issues — NOT blocking submission, fix in v1.0.1

- **FCM token not cleared on sign-out.** When user A signs out and user B signs in on the same device, user A's FCM token stays in their Firestore user doc. Result: device receives notifications meant for user A even when signed in as user B. Fix: in `NotificationManager.swift` on sign-out, clear `fcmToken` from previous user's doc before clearing local listener.
- **RevenueCat customer is anonymous (`$RCAnonymousID:...`).** UpNext doesn't call `Purchases.shared.logIn(firebaseUserId)` to associate Apple purchases with Firebase users. Result: revenue analytics in RC can't be tied back to specific shop owners. Fix: call `logIn` after `AuthViewModel` resolves the Firebase user.
- **`pendingSubscriptions` handoff bug** (per CLAUDE.md). Web Stripe payer who hasn't opened iOS yet hits paywall on first iOS launch despite paying. Plan v1.0.1 fix within 2-4 weeks of launch.

---

## Reference docs
- `docs/app-store-submission-audit.md` — full pre-submission audit
- `docs/iap-walkthrough.md` — click-by-click IAP setup
- `docs/revenuecat-asc-setup.md` — strategic RC + ASC setup guide
