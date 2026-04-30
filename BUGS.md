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
