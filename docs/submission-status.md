# UpNext App Store Submission — Status

> Living doc. Update as items complete. Check this first when resuming a session.

**Current state:** First-time submission prep. Sandbox IAP verified end-to-end. ~5 remaining items before submit.

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

1. **Step 5a — verify subscription auto-attaches to v1.0 version.** Modern ASC may auto-include subscriptions from the same Subscription Group when "Ready to Submit". Navigate ASC → My Apps → UpNext - Walk-In Manager → 1.0 Prepare for Submission → scroll for any "In-App Purchases and Subscriptions" section. If none exists, you're done with this step.

2. **Demo Firestore account for App Review.** Create `appreview@upnext-app.com` in Firebase Auth. Seed Firestore: `users/{uid}` (role: owner), `shops/{uid}` with `subscriptionStatus: "active"`, `subscriptionTier: "base"`, plus 2-3 sample barbers and services. Capture the credentials for ASC Review Notes.

3. **Capture real App Store screenshots.** Need iPhone 6.9" (1290×2796 or 1320×2868) and iPad 13" (2064×2752). 3-10 per size. Audit `docs/app-store-submission-audit.md` Section 2 has content recommendations. Replace the deleted generic placeholders.

4. **Fill remaining ASC metadata.** App Information (subtitle, promo text, description, keywords, category), App Privacy questionnaire, Age Rating, Review Notes (with demo credentials). Audit Section 3 has draft copy.

5. **Submit.**

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
