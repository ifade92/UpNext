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
