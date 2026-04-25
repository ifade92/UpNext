/**
 * stripeWebhook.ts — Stripe subscription webhook handler for UpNext
 *
 * Handles Stripe webhook events to keep Firestore subscription data in sync.
 *
 * Flow:
 *   1. Customer subscribes via Stripe Payment Link on getupnextapp.com
 *   2. Stripe sends a webhook event to this Cloud Function
 *   3. We update the shop's subscription status/tier in Firestore
 *   4. The iOS app reads Firestore and unlocks features automatically
 *
 * Supported events:
 *   - checkout.session.completed  → New subscription created
 *   - customer.subscription.updated → Plan changed or renewed
 *   - customer.subscription.deleted → Subscription cancelled
 *   - invoice.payment_failed       → Payment failed, grace period
 *
 * Matching logic:
 *   We match Stripe customers to shops by email. When a checkout completes,
 *   we store the stripeCustomerId on the shop doc so future events can
 *   match directly without email lookup.
 *
 * SETUP REQUIRED:
 *   1. Set Stripe secret key:
 *      firebase functions:config:set stripe.secret_key="sk_live_xxx"
 *      firebase functions:config:set stripe.webhook_secret="whsec_xxx"
 *
 *   2. In Stripe Dashboard → Webhooks → Add endpoint:
 *      URL: https://<region>-<project>.cloudfunctions.net/stripeWebhook
 *      Events: checkout.session.completed, customer.subscription.updated,
 *              customer.subscription.deleted, invoice.payment_failed
 */

import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";

// ── Secrets (set via Firebase CLI or Google Cloud Secret Manager) ────────────
const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

// ── Price ID → Tier mapping ─────────────────────────────────────────────────
// Update these with your actual Stripe Price IDs
const PRICE_TO_TIER: Record<string, string> = {
  "price_1TOUbW7SltOVcxC2LgM3Xlw8": "base",   // Base — $49.99/mo
  "price_1TOUba7SltOVcxC2QXhBgJ0x": "multi",   // Multi-Location — $79.99/mo
};

// ── Helper: find a shop by email ────────────────────────────────────────────
async function findShopByEmail(email: string): Promise<admin.firestore.DocumentSnapshot | null> {
  const db = admin.firestore();

  // First, find the user by email in Firebase Auth
  try {
    const userRecord = await admin.auth().getUserByEmail(email);
    // Look for a shop owned by this user
    const shopsSnap = await db
      .collection("shops")
      .where("ownerId", "==", userRecord.uid)
      .limit(1)
      .get();

    if (!shopsSnap.empty) {
      return shopsSnap.docs[0];
    }
  } catch {
    // User not in Firebase Auth yet — they might sign up later
    console.log(`[stripeWebhook] No Firebase Auth user for ${email}`);
  }

  return null;
}

// ── Helper: find a shop by Stripe Customer ID ───────────────────────────────
async function findShopByStripeCustomerId(
  customerId: string
): Promise<admin.firestore.DocumentSnapshot | null> {
  const db = admin.firestore();
  const shopsSnap = await db
    .collection("shops")
    .where("stripeCustomerId", "==", customerId)
    .limit(1)
    .get();

  return shopsSnap.empty ? null : shopsSnap.docs[0];
}

// ── Helper: determine tier from subscription items ──────────────────────────
function getTierFromSubscription(subscription: Stripe.Subscription): string {
  for (const item of subscription.items.data) {
    const tier = PRICE_TO_TIER[item.price.id];
    if (tier) return tier;
  }
  // Default to base if we can't match
  return "base";
}

// ── Helper: store a pending subscription for users who haven't signed up yet ─
async function storePendingSubscription(
  email: string,
  stripeCustomerId: string,
  stripeSubscriptionId: string,
  tier: string
): Promise<void> {
  const db = admin.firestore();
  await db.collection("pendingSubscriptions").doc(email).set({
    email,
    stripeCustomerId,
    stripeSubscriptionId,
    tier,
    status: "active",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`[stripeWebhook] Stored pending subscription for ${email}`);
}

// ── Main webhook handler ────────────────────────────────────────────────────
export const stripeWebhook = onRequest(
  {
    secrets: [stripeSecretKey, stripeWebhookSecret],
    maxInstances: 10,
  },
  async (req, res) => {
    // Lazy init Firebase Admin
    if (!admin.apps.length) {
      admin.initializeApp();
    }

    // Only accept POST requests
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const stripe = new Stripe(stripeSecretKey.value(), {
      apiVersion: "2025-02-24.acacia",
    });

    // ── Verify webhook signature ──────────────────────────────────────────
    let event: Stripe.Event;
    try {
      const sig = req.headers["stripe-signature"] as string;
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig,
        stripeWebhookSecret.value()
      );
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Unknown error";
      console.error(`[stripeWebhook] Signature verification failed: ${message}`);
      res.status(400).send(`Webhook Error: ${message}`);
      return;
    }

    console.log(`[stripeWebhook] Received event: ${event.type}`);

    const db = admin.firestore();

    try {
      switch (event.type) {
        // ── New checkout completed (first-time subscriber) ──────────────
        case "checkout.session.completed": {
          const session = event.data.object as Stripe.Checkout.Session;
          const customerEmail = session.customer_details?.email ?? session.customer_email;
          const customerId = session.customer as string;
          const subscriptionId = session.subscription as string;

          if (!customerEmail) {
            console.error("[stripeWebhook] No email in checkout session");
            break;
          }

          // Fetch the full subscription to determine tier
          const subscription = await stripe.subscriptions.retrieve(subscriptionId);
          const tier = getTierFromSubscription(subscription);

          console.log(
            `[stripeWebhook] Checkout complete: ${customerEmail} → ${tier} tier`
          );

          // Try to find the shop by email
          const shopDoc = await findShopByEmail(customerEmail);

          if (shopDoc) {
            // Shop exists — activate subscription
            await shopDoc.ref.update({
              subscriptionStatus: "active",
              subscriptionTier: tier,
              stripeCustomerId: customerId,
              stripeSubscriptionId: subscriptionId,
              stripeEmail: customerEmail,
            });
            console.log(`[stripeWebhook] Activated shop ${shopDoc.id} → ${tier}`);
          } else {
            // Shop doesn't exist yet — store as pending
            // When the owner signs up in the app, we'll check this collection
            await storePendingSubscription(
              customerEmail,
              customerId,
              subscriptionId,
              tier
            );
          }
          break;
        }

        // ── Subscription updated (plan change, renewal, etc.) ───────────
        case "customer.subscription.updated": {
          const subscription = event.data.object as Stripe.Subscription;
          const customerId = subscription.customer as string;
          const tier = getTierFromSubscription(subscription);

          const shopDoc = await findShopByStripeCustomerId(customerId);

          if (shopDoc) {
            const status = subscription.status === "active" ? "active" : "past_due";
            await shopDoc.ref.update({
              subscriptionStatus: status,
              subscriptionTier: tier,
              stripeSubscriptionId: subscription.id,
            });
            console.log(
              `[stripeWebhook] Updated shop ${shopDoc.id} → ${status}, ${tier}`
            );
          } else {
            console.log(
              `[stripeWebhook] No shop found for Stripe customer ${customerId}`
            );
          }
          break;
        }

        // ── Subscription cancelled ──────────────────────────────────────
        case "customer.subscription.deleted": {
          const subscription = event.data.object as Stripe.Subscription;
          const customerId = subscription.customer as string;

          const shopDoc = await findShopByStripeCustomerId(customerId);

          if (shopDoc) {
            await shopDoc.ref.update({
              subscriptionStatus: "cancelled",
            });
            console.log(`[stripeWebhook] Cancelled shop ${shopDoc.id}`);
          } else {
            console.log(
              `[stripeWebhook] No shop found for cancelled customer ${customerId}`
            );
          }
          break;
        }

        // ── Payment failed ──────────────────────────────────────────────
        case "invoice.payment_failed": {
          const invoice = event.data.object as Stripe.Invoice;
          const customerId = invoice.customer as string;

          const shopDoc = await findShopByStripeCustomerId(customerId);

          if (shopDoc) {
            await shopDoc.ref.update({
              subscriptionStatus: "past_due",
            });
            console.log(`[stripeWebhook] Payment failed for shop ${shopDoc.id}`);
          }
          break;
        }

        default:
          console.log(`[stripeWebhook] Unhandled event type: ${event.type}`);
      }

      res.status(200).json({ received: true });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Unknown error";
      console.error(`[stripeWebhook] Error processing event: ${message}`);
      res.status(500).json({ error: message });
    }
  }
);
