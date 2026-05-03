/**
 * createBillingPortalSession.ts — Stripe Customer Portal session opener
 *
 * Lets a web-subscribed shop owner open Stripe's hosted Customer Portal to:
 *   - Cancel their subscription
 *   - Update their payment method
 *   - View invoices
 *
 * Called from public/barber.html via the Firebase Functions client SDK
 * (httpsCallable).
 *
 * SECURITY MODEL — read this before changing anything:
 *   - This is an HTTPS-callable function (`onCall`), so the auth context is
 *     populated from the caller's Firebase ID token automatically.
 *   - We NEVER trust the client request body. The client sends an empty
 *     payload. We look up `shopId` and `stripeCustomerId` ourselves from
 *     Firestore using the authenticated UID.
 *   - We require `users/{uid}.role === "owner"` so a barber on the same
 *     shop can't open the owner's billing portal.
 *
 * Configuration prerequisite:
 *   The Stripe Dashboard → Settings → Customer Portal must be configured
 *   (cancellation enabled, business info populated). Until that's done,
 *   `billingPortal.sessions.create` will fail at runtime.
 *
 * SETUP:
 *   Reuses STRIPE_SECRET_KEY secret already set for stripeWebhook:
 *     firebase functions:secrets:set STRIPE_SECRET_KEY  (already done)
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";

// Reuses the same secret that stripeWebhook.ts uses
const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");

// Where Stripe sends the user when they finish in the portal.
// Sends them back to the web dashboard.
const RETURN_URL = "https://upnext-app.com/barber.html";

export const createBillingPortalSession = onCall(
  {
    secrets: [stripeSecretKey],
    maxInstances: 10,
    // Default region us-central1 — matches stripeWebhook
  },
  async (request) => {
    // Lazy init Firebase Admin (matches stripeWebhook.ts pattern)
    if (!admin.apps.length) {
      admin.initializeApp();
    }

    // ── Auth gate ─────────────────────────────────────────────────────────
    // onCall populates request.auth from the caller's Firebase ID token.
    // No token → not signed in → reject.
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to manage your subscription."
      );
    }

    const db = admin.firestore();

    // ── Confirm the caller is the shop owner ─────────────────────────────
    // We look up the user's role + shopId server-side. The client cannot
    // pass these values in — preventing a barber from poking at the owner's
    // billing portal by hand-crafting a request.
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }

    const userData = userSnap.data() ?? {};
    if (userData.role !== "owner") {
      throw new HttpsError(
        "permission-denied",
        "Only shop owners can manage the subscription."
      );
    }

    const shopId = userData.shopId as string | undefined;
    if (!shopId) {
      throw new HttpsError(
        "failed-precondition",
        "No shop linked to this account."
      );
    }

    // ── Fetch the Stripe customer ID from the shop doc ───────────────────
    const shopSnap = await db.collection("shops").doc(shopId).get();
    if (!shopSnap.exists) {
      throw new HttpsError("not-found", "Shop document not found.");
    }

    const stripeCustomerId = shopSnap.get("stripeCustomerId") as
      | string
      | undefined;

    if (!stripeCustomerId) {
      // Could happen if the user is an App Store subscriber on iOS — they
      // have no Stripe customer record. The web UI should not reach this
      // function in that case, but we guard anyway.
      throw new HttpsError(
        "failed-precondition",
        "No Stripe customer on file for this shop."
      );
    }

    // ── Create a one-time portal session ─────────────────────────────────
    const stripe = new Stripe(stripeSecretKey.value(), {
      apiVersion: "2025-02-24.acacia",
    });

    try {
      const session = await stripe.billingPortal.sessions.create({
        customer: stripeCustomerId,
        return_url: RETURN_URL,
      });

      return { url: session.url };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Unknown error";
      console.error(
        `[createBillingPortalSession] Stripe error for shop ${shopId}: ${message}`
      );
      throw new HttpsError(
        "internal",
        "Could not open the billing portal. Please try again or email support@upnext-app.com."
      );
    }
  }
);
