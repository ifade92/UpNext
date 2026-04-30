# UpNext — Known Bugs

A running log of identified bugs. Each entry should have a clear symptom, root cause, affected files, suggested fix approach, and priority.

---

## BUG-001: Web→iOS subscription handoff fails on first iOS launch

**Status:** Open — documented, not fixed
**Priority:** High — directly affects paying customers and likely causes refund requests
**Identified:** 2026-04-25

### Symptom
A user signs up on upnext-app.com, pays via Stripe, then opens the iOS app for the first time and hits the paywall despite having paid.

### Root Cause
The Stripe webhook (`functions/src/stripeWebhook.ts`) writes the new subscription to `pendingSubscriptions/{email}` when no matching shop document exists yet. `AuthViewModel.loadShop()` in iOS only fetches `shops/{shopId}` — it does not check `pendingSubscriptions`. Result: the shop doc still says "cancelled" on first launch and iOS never consults the pending collection.

### Affected Files
- `functions/src/stripeWebhook.ts` (writes the pending doc)
- `AuthViewModel.swift` (loadShop method needs fallback)

### Suggested Fix
When `loadShop` finds no matching shop OR finds one with `status="cancelled"`, fall back to checking `pendingSubscriptions/{user.email}`. If found, promote it to a real shop doc with the correct `subscriptionStatus` and `subscriptionTier`, then clear the pending entry.

### Notes
- Webhook code comment in `stripeWebhook.ts` already acknowledges this is the intended handoff
- Discovered during CLAUDE.md audit on 2026-04-25 (commit d6aa33f)

---

## BUG-002: Stale FCM token causes push notifications to follow the previous account on shared device

**Status:** In progress — fix landing in this commit
**Priority:** High — leaks queue activity to whoever last signed in on the device; privacy + noise issue for any shop where staff swap phones or owners re-sign in
**Identified:** 2026-04-29

### Symptom
After signing out of one account and signing into a different account on the same iPhone, the device continues receiving push notifications meant for the OLD account. The new account also receives its own notifications correctly — so the device is effectively subscribed as both users at once.

### Root Cause
On sign-out, the iOS app does not clear the FCM token from the old user's Firestore document. `NotificationManager.teardown()` only nils a local `currentUserId` variable; it never deletes `users/{oldUserId}.fcmToken` and never calls `Messaging.messaging().deleteToken()`. When the new user signs in, `setup(userId:)` writes the SAME device FCM token to `users/{newUserId}.fcmToken` via `setData(merge: true)`, leaving the old user's field untouched and still valid. The backend (`pushNotifications.ts`) queries users by `shopId`, collects every truthy `fcmToken`, and `sendEachForMulticast` pushes to all of them. Existing stale-token cleanup only triggers on `messaging/registration-token-not-registered`, which doesn't fire because the token is genuinely registered.

### Affected Files
- `UpNext/Shared/Services/NotificationManager.swift` (added async `clearTokenForCurrentUser` that deletes Firestore field + calls FCM `deleteToken()`)
- `UpNext/UpNext-Barber/ViewModels/AuthViewModel.swift` (`signOut` is now async; awaits cleanup before `Auth.auth().signOut()`)
- Caller of `signOut` (Settings view) — wraps in Task

### Suggested Fix
On sign-out, before calling `Auth.auth().signOut()`: (1) `users/{currentUserId}.fcmToken` → `FieldValue.delete()`; (2) call `Messaging.messaging().deleteToken()` so OS issues a fresh FCM token on next sign-in. Order matters — Firestore write must complete before Auth sign-out, otherwise rules block the update.

### Notes
- Discovered by Carlos on 2026-04-29 after live account-switch test.
- iOS-only fix; no backend deploy required.
- Regression to retest: same-user sign-out/sign-in still receives pushes (token regenerated cleanly), and BUG-001's web→iOS subscription path is unaffected since `AuthViewModel` is touched.

---

## BUG-003: iOS barber photo upload fails (path mismatch + missing Storage rules + missing Info.plist permission)

**Status:** In progress — fix landing in this commit; storage.rules deploy required to fully activate
**Priority:** High — owners cannot upload barber photos from iOS, blocking onboarding flow
**Identified:** 2026-04-29

### Symptom
On the iOS app, uploading a barber profile photo silently fails or errors out. The same operation works fine on the web dashboard at `public/barber.html`.

### Root Cause
Three stacked issues:
1. **Path mismatch.** iOS wrote to `barbers/{shopId}/{barberId}/profile.jpg`; web wrote to `shops/{shopId}/barbers/{barberId}/photo`. Storage rules (managed only via Firebase Console, not version-controlled) were written around the web path, so iOS uploads were denied at the rules gate.
2. **No Storage rules in repo.** `firebase.json` did not configure Firebase Storage; `storage.rules` did not exist. Rules drift was inevitable and not reviewable in version control.
3. **Missing `NSPhotoLibraryUsageDescription` in `Info.plist`.** Required for App Store review and for any PhotoKit code path requesting full library access.

### Affected Files
- `UpNext/Shared/Services/FirebaseService.swift` — `uploadBarberPhoto` now writes to the unified path `shops/{shopId}/barbers/{barberId}/photo.jpg`
- `storage.rules` (new) — public read on barber photos, authenticated write, 5MB / image-MIME guard, default-deny everything else
- `firebase.json` — added `storage` block referencing `storage.rules`
- `UpNext/Info.plist` — added `NSPhotoLibraryUsageDescription`
- `UpNext/UpNext-Barber/Views/ShopSettingsView.swift` — investigated; no change needed. The defensive `guard let barberId = barber.id` at line 1248 lives inside `EditBarberSheet`, which is only opened for existing barbers (`AddBarberSheet` has no photo control). The "new-barber edge case" hypothesized during investigation does not exist in current code paths.

### Suggested Fix
Already applied in this commit. Remaining manual step: **deploy the storage rules** with `firebase deploy --only storage`. Until that deploys, iOS will continue to fail on the new path because the live rules still reference the old path.

### Notes
- Discovered by Carlos on 2026-04-29.
- Migration impact: existing barber photos at the OLD iOS path (`barbers/...`) become inaccessible after deploy. For Fademasters (only production shop), Carlos plans to re-upload all 15 barber photos manually after deploy — about 10 minutes of work.
