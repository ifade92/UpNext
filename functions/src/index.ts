/**
 * index.ts — UpNext Cloud Functions entry point
 *
 * All Firebase Cloud Functions are exported from here.
 * Each feature area lives in its own file to keep things organized:
 *
 *   - pushNotifications.ts → Staff push alerts via FCM (check-in + remote arrival)
 *   - stripeWebhook.ts     → Stripe subscription sync to Firestore
 *   - remoteCleanup.ts     → Auto-remove stale remote check-ins every 5 min
 *   - notifications.ts     → Customer SMS alerts via Twilio (not yet active)
 *
 * DEPLOY:
 *   cd functions && npm run build && firebase deploy --only functions
 */

import { setGlobalOptions } from "firebase-functions";

// Cap containers so we don't rack up surprise bills on a traffic spike
setGlobalOptions({ maxInstances: 10 });

// ── Push Notifications (FCM) ─────────────────────────────────────────────────
// notifyStaffOnCheckIn:      new queue entry → alert staff
// notifyStaffOnRemoteArrival: remote customer taps "I'm Here" → alert staff
export { notifyStaffOnCheckIn, notifyStaffOnRemoteArrival } from "./pushNotifications";

// ── Remote Check-In Cleanup (Scheduled) ─────────────────────────────────────
// Runs every 5 minutes — removes remote check-ins that never arrived (30 min timeout)
export { cleanupStaleRemoteCheckIns } from "./remoteCleanup";

// ── Stripe Webhook (Subscriptions) ──────────────────────────────────────────
// Handles Stripe subscription events and syncs status to Firestore.
// Set secrets before deploying:
//   firebase functions:secrets:set STRIPE_SECRET_KEY
//   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
export { stripeWebhook } from "./stripeWebhook";

// ── SMS Notifications (Twilio) ───────────────────────────────────────────────
// Sends text messages to customers about their queue position.
// Uncomment after A2P 10DLC registration is complete and Twilio is configured.
// export { onQueueEntryCreated, onQueueEntryStarted, onQueueEntryCompleted } from "./notifications";
