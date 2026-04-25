/**
 * remoteCleanup.ts — Auto-remove stale remote check-ins
 *
 * Runs every 5 minutes via Cloud Scheduler. Finds queue entries where:
 *   - isRemoteCheckIn === true
 *   - remoteStatus === "on_the_way"  (they never tapped "I'm Here")
 *   - checkInTime is more than 30 minutes ago
 *
 * Those entries get their status set to "removed" — freeing up the spot
 * for customers who are actually at the shop.
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";

// How long remote check-ins have before they're auto-removed (in minutes)
const REMOTE_GRACE_PERIOD_MINUTES = 30;

/**
 * Scheduled function: runs every 5 minutes.
 * Scans ALL shops for stale remote check-ins and removes them.
 */
export const cleanupStaleRemoteCheckIns = onSchedule(
  {
    // Run every 5 minutes — frequent enough to catch expired entries quickly
    schedule: "every 5 minutes",
    timeZone: "America/Chicago",  // Waco, TX timezone
  },
  async () => {
    if (!admin.apps.length) {
      admin.initializeApp();
    }

    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - REMOTE_GRACE_PERIOD_MINUTES * 60 * 1000
    );

    // Get all shops
    const shopsSnap = await db.collection("shops").get();

    let totalRemoved = 0;

    for (const shopDoc of shopsSnap.docs) {
      // Find remote entries still "on_the_way" that checked in before the cutoff
      const staleEntries = await shopDoc.ref
        .collection("queue")
        .where("isRemoteCheckIn", "==", true)
        .where("remoteStatus", "==", "on_the_way")
        .where("checkInTime", "<=", cutoff)
        .get();

      if (staleEntries.empty) continue;

      // Batch remove all stale entries for this shop
      const batch = db.batch();
      staleEntries.forEach((entryDoc) => {
        batch.update(entryDoc.ref, { status: "removed" });
      });

      await batch.commit();
      totalRemoved += staleEntries.size;

      console.log(
        `[remoteCleanup] Removed ${staleEntries.size} stale remote check-in(s) from shop ${shopDoc.id}`
      );
    }

    if (totalRemoved > 0) {
      console.log(`[remoteCleanup] Total removed across all shops: ${totalRemoved}`);
    }
  }
);
