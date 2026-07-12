// Milestone 5: the scheduled equivalents of LocalGameRepository's
// dart:async Timers, which only fire while that process is alive. Cloud
// Scheduler drives these at a fixed interval instead of one precise timer
// per game/player — "up to N minutes late" is an acceptable tradeoff for
// a daily cutoff or a 24h reactivation window, not a correctness issue.
//
// The 3-round observation purge from the same Milestone 5 bullet isn't a
// separate function here: LocalGameRepository does that purge as a step
// inside _resolveRound itself (see roundResolution.js), and
// resolveRoundTransactional already replicates that. Once this sweep
// keeps rounds resolving on schedule, the purge keeps happening as a
// side effect, the same way it does for a manually-resolved round.
//
// exports.scheduledDailyCutoffSweep / exports.scheduledMafiaReactivationSweep
// are the deployable onSchedule functions. runDailyCutoffSweep/
// runMafiaReactivationSweep are the plain, directly-testable functions
// underneath them — index.js re-exports only the two onSchedule wrappers
// by name (not via a blanket Object.assign, unlike gameplay.js) so a
// test script can require this module and call the raw sweep functions
// without going through an actual schedule trigger.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { Timestamp } = require("firebase-admin/firestore");
const { db, maybeMarkAgreedInTx, resolveRoundTransactional } = require("./roundResolution");

async function runDailyCutoffSweep() {
  const now = Timestamp.now();
  const dueSnap = await db
    .collection("games")
    .where("status", "==", "active")
    .where("nextCutoffAt", "<=", now)
    .get();

  for (const doc of dueSnap.docs) {
    const gameRef = doc.ref;
    try {
      await db.runTransaction(async (tx) => {
        const gameSnap = await tx.get(gameRef);
        if (!gameSnap.exists) return;
        const game = gameSnap.data();
        // Re-check inside the transaction — a player resolving manually,
        // or a previous sweep tick, may have already moved the round on
        // since the query above ran.
        if (game.status !== "active") return;
        if (!game.nextCutoffAt || game.nextCutoffAt.toMillis() > Date.now()) return;
        await resolveRoundTransactional(tx, gameRef);
      });
    } catch (err) {
      // One game's failure shouldn't stop the sweep from resolving the
      // rest — logged, not rethrown.
      console.error(`Daily cutoff sweep failed for game ${gameRef.id}:`, err);
    }
  }
}

async function runMafiaReactivationSweep() {
  const now = Timestamp.now();
  const dueSnap = await db.collectionGroup("players").where("inactiveUntil", "<=", now).get();

  for (const playerDoc of dueSnap.docs) {
    const gameRef = playerDoc.ref.parent.parent;
    if (!gameRef) continue;
    try {
      await db.runTransaction(async (tx) => {
        const playerSnap = await tx.get(playerDoc.ref);
        if (!playerSnap.exists) return;
        const player = playerSnap.data();
        // Re-check inside the transaction — a manual reactivation may
        // have already cleared this since the query above ran.
        if (player.isActive || !player.inactiveUntil || player.inactiveUntil.toMillis() > Date.now()) {
          return;
        }

        const gameSnap = await tx.get(gameRef);
        if (!gameSnap.exists || gameSnap.data().status === "ended") return;

        const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
        const playersSnap = await tx.get(gameRef.collection("players"));
        const players = playersSnap.docs.map((d) =>
          d.id === playerDoc.id
            ? { id: d.id, ...d.data(), isActive: true }
            : { id: d.id, ...d.data() }
        );

        tx.update(playerDoc.ref, { isActive: true, inactiveUntil: null });

        // Mirrors LocalGameRepository.setMemberActive's re-check after
        // any active-flag change: reactivating can itself satisfy an
        // unagreed proposal or recruitment that was only waiting on
        // this player.
        for (const entryDoc of threadSnap.docs) {
          const entry = entryDoc.data();
          if (
            (entry.type === "proposal" || entry.type === "recruitment") &&
            entry.agreedAt == null &&
            !entry.lapsed
          ) {
            maybeMarkAgreedInTx(tx, gameRef, entryDoc.ref, entry, players);
          }
        }
      });
    } catch (err) {
      console.error(`Mafia reactivation sweep failed for player ${playerDoc.ref.path}:`, err);
    }
  }
}

exports.scheduledDailyCutoffSweep = onSchedule("every 15 minutes", async () => {
  await runDailyCutoffSweep();
});

exports.scheduledMafiaReactivationSweep = onSchedule("every 30 minutes", async () => {
  await runMafiaReactivationSweep();
});

exports.runDailyCutoffSweep = runDailyCutoffSweep;
exports.runMafiaReactivationSweep = runMafiaReactivationSweep;
