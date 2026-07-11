// Shared round-resolution logic — extracted out of gameplay.js so both
// the callables there and the Milestone 5 scheduled sweeps in
// scheduled.js can reuse the exact same code path. Plain exports, not
// Cloud Functions themselves (nothing here is wrapped in onCall/
// onSchedule), so this module is safe to require from anywhere without
// the Firebase CLI trying to treat its exports as deployable functions.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");

const db = getFirestore();

function requireGameNotEndedData(gameData) {
  if (gameData.status === "ended") {
    throw new HttpsError("failed-precondition", "This case is closed");
  }
}

function assertCurrentMafia(playerData, playerId) {
  if (!playerData || playerData.role !== "mafia" || playerData.wasUnmasked || playerData.hasLeft) {
    throw new HttpsError("failed-precondition", `${playerId} is not a current mafia member`);
  }
}

// players: array of { id, role, isActive, hasLeft, ... } — a plain-object
// projection of the players collection, not a QuerySnapshot, so callers
// can pass either a fresh read or one patched with an in-flight change
// (e.g. leaveGame's own hasLeft flip) before this runs.
function activeMafiaIds(players) {
  const ids = new Set();
  for (const p of players) {
    if (p.role === "mafia" && p.isActive !== false && !p.hasLeft) ids.add(p.id);
  }
  return ids;
}

function newMomentWrite(gameRef, playerId, type, round) {
  return {
    ref: gameRef.collection("moments").doc(),
    data: {
      playerId,
      type,
      round,
      createdAt: FieldValue.serverTimestamp(),
      acknowledged: false,
    },
  };
}

// Mirrors LocalGameRepository._scheduleDailyCutoff's "next occurrence
// strictly after now" logic — today's cutoff if it hasn't passed yet,
// otherwise tomorrow's. Milestone 4 had no scheduled sweep to drive off
// of this, so it only matters starting here (Milestone 5).
function computeNextCutoffAt(dailyCutoffSeconds, now = new Date()) {
  const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let next = new Date(midnight.getTime() + dailyCutoffSeconds * 1000);
  if (next <= now) {
    next = new Date(next.getTime() + 24 * 60 * 60 * 1000);
  }
  return Timestamp.fromDate(next);
}

// Mirrors LocalGameRepository._maybeMarkAgreed: marks [entryRef] agreed the
// moment every currently-active mafia member has accepted it, and puts the
// method/sign (never the target) in front of every villager as a
// forewarning. No vote weight moves and no offer reaches its target yet —
// that's execution, a separate call.
function maybeMarkAgreedInTx(tx, gameRef, entryRef, entry, players) {
  if (entry.agreedAt != null || entry.executedAt != null || entry.lapsed) return false;
  const required = activeMafiaIds(players);
  const accepted = new Set(entry.acceptedByPlayerIds || []);
  if (required.size === 0) return false;
  for (const id of required) {
    if (!accepted.has(id)) return false;
  }
  tx.update(entryRef, { agreedAt: FieldValue.serverTimestamp() });
  if (entry.type === "proposal") {
    tx.update(gameRef, {
      eliminationMethodDescription: entry.proposedMethod,
      eliminationSignalExecuted: false,
      eliminationSignalConfirmed: false,
    });
  } else {
    tx.update(gameRef, {
      recruitmentSignDescription: entry.proposedMethod,
      recruitmentSignExecuted: false,
      recruitmentSignConfirmed: false,
    });
  }
  return true;
}

// Mirrors LocalGameRepository._checkForGameEnd. Only meaningful to call
// against an `active` game — callers gate on that themselves, since this
// runs mid-transaction after other reads/writes are already in flight.
function checkGameEndInTx(tx, gameRef, players, round) {
  const livingMafia = players.filter((p) => p.role === "mafia" && !p.hasLeft).length;
  const livingVillagers = players.filter((p) => p.role === "villager" && !p.hasLeft).length;
  let winner = null;
  if (livingMafia === 0) winner = "villagers";
  else if (livingMafia >= livingVillagers) winner = "mafia";
  if (!winner) return false;

  tx.update(gameRef, { status: "ended", winner });
  for (const p of players) {
    const everMafia = p.role === "mafia" || p.wasUnmasked;
    const onWinningSide = winner === "mafia" ? everMafia : !everMafia;
    const moment = newMomentWrite(gameRef, p.id, onWinningSide ? "finaleWin" : "finaleLoss", round);
    tx.set(moment.ref, moment.data);
  }
  return true;
}

// Mirrors LocalGameRepository._resolveRound: tallies the current round's
// votes by each voter's *live* weight (not the snapshot on the Vote
// record), applies the unmask+reward or weight-erosion outcome, records
// every player's per-round moment, purges observations older than 3
// rounds, lapses anything agreed-but-unexecuted this round, advances to
// the next round, and reschedules the next daily cutoff — the same as
// LocalGameRepository calling _scheduleDailyCutoff at the end of
// _resolveRound. Shared by resolveVotesForDay,
// acknowledgeEliminationSignal, respondToRecruitment (Milestone 4), and
// the scheduled daily-cutoff sweep (Milestone 5) — all resolve the day
// the same way, just triggered differently.
async function resolveRoundTransactional(tx, gameRef) {
  const gameSnap = await tx.get(gameRef);
  const game = gameSnap.data();
  const currentRound = game.currentRound;

  const playersSnap = await tx.get(gameRef.collection("players"));
  const players = new Map(playersSnap.docs.map((d) => [d.id, { id: d.id, ...d.data() }]));

  const votesSnap = await tx.get(gameRef.collection("votes").where("round", "==", currentRound));
  const roundVotes = votesSnap.docs.map((d) => d.data());

  const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
  const obsSnap = await tx.get(gameRef.collection("observations"));

  const tally = {};
  for (const vote of roundVotes) {
    const liveWeight = (players.get(vote.voterId) || {}).voteWeight || 0;
    tally[vote.targetPlayerId] = (tally[vote.targetPlayerId] || 0) + liveWeight;
  }
  let winnerId = null;
  let bestWeight = 0;
  for (const [targetId, weight] of Object.entries(tally)) {
    if (weight > bestWeight) {
      bestWeight = weight;
      winnerId = targetId;
    }
  }

  const notifiedThisRound = new Set();
  const playerPatches = new Map();
  function patchPlayer(id, patch) {
    playerPatches.set(id, { ...(playerPatches.get(id) || {}), ...patch });
  }
  const momentWrites = [];
  function addMoment(playerId, type, countsAsRoundActivity = true) {
    momentWrites.push({ playerId, type });
    if (countsAsRoundActivity) notifiedThisRound.add(playerId);
  }

  if (winnerId && bestWeight > 0) {
    const target = players.get(winnerId);
    if (target.role === "mafia" && !target.wasUnmasked) {
      // Correctly caught a mafia member: unmask them and reward every
      // voter who picked them.
      const rewardedVoterIds = new Set(
        roundVotes.filter((v) => v.targetPlayerId === winnerId).map((v) => v.voterId)
      );
      patchPlayer(winnerId, { role: "villager", wasUnmasked: true });
      for (const voterId of rewardedVoterIds) {
        const voter = players.get(voterId);
        if (voter) patchPlayer(voterId, { voteWeight: (voter.voteWeight || 0) + 1 });
        addMoment(voterId, "correctVoteReward");
      }
      // Everyone else still finds out an Informant was caught, just
      // without personal credit — the target themselves is covered by
      // the unmask ceremony instead, not a moment.
      for (const id of players.keys()) {
        if (id === winnerId || rewardedVoterIds.has(id)) continue;
        addMoment(id, "mafiaUnmaskedByOthers");
      }
    } else {
      // Voted for a villager instead: the vote still lands, it just
      // erodes their weight the same way a mafia hit would.
      patchPlayer(winnerId, { voteWeight: Math.max(0, (target.voteWeight || 0) - 1) });
      addMoment(winnerId, "targetedByVillagers");
    }
  }

  // Every mafia member who made it through this round without being the
  // one caught. `id === winnerId` excluded explicitly: when the winning
  // target *was* mafia, they're deliberately left out of
  // `notifiedThisRound` above, so without this check they'd still read as
  // mafia/not-unmasked here and wrongly get credited with surviving the
  // very round they were caught in.
  for (const [id, p] of players) {
    if (notifiedThisRound.has(id) || id === winnerId) continue;
    if (p.role === "mafia" && !p.wasUnmasked && !p.hasLeft) {
      addMoment(id, "survivedRoundAsMafia");
    }
  }

  // The generic fallback: everyone still in the game who didn't already
  // get something more specific this round.
  for (const id of players.keys()) {
    if (!notifiedThisRound.has(id)) {
      addMoment(id, "roundEnded");
    }
  }

  const nextRound = currentRound + 1;

  const staleObsRefs = obsSnap.docs
    .filter((d) => nextRound - d.data().round >= 3)
    .map((d) => d.ref);

  // The round ending is the other half of the execution deadline (1 hour,
  // or the round ending — whichever is first): any proposal or
  // recruitment agreed but never executed this round lapses now.
  const lapseRefs = threadSnap.docs
    .filter((d) => {
      const e = d.data();
      return (
        e.round === currentRound &&
        (e.type === "proposal" || e.type === "recruitment") &&
        e.agreedAt != null &&
        e.executedAt == null &&
        !e.lapsed
      );
    })
    .map((d) => d.ref);

  // --- writes (all reads above are complete) ---
  for (const [id, patch] of playerPatches) {
    tx.update(gameRef.collection("players").doc(id), patch);
  }
  for (const m of momentWrites) {
    const moment = newMomentWrite(gameRef, m.playerId, m.type, currentRound);
    tx.set(moment.ref, moment.data);
  }
  for (const ref of staleObsRefs) tx.delete(ref);
  for (const ref of lapseRefs) tx.update(ref, { lapsed: true });

  tx.update(gameRef, {
    currentRound: nextRound,
    // A fresh round starts with no lingering signal from the last one.
    eliminationMethodDescription: null,
    eliminationSignalExecuted: false,
    eliminationSignalConfirmed: false,
    recruitmentSignDescription: null,
    recruitmentSignExecuted: false,
    recruitmentSignConfirmed: false,
    nextCutoffAt: computeNextCutoffAt(game.dailyCutoffSeconds),
  });

  const finalPlayers = [...players.values()].map((p) => ({
    ...p,
    ...(playerPatches.get(p.id) || {}),
  }));
  checkGameEndInTx(tx, gameRef, finalPlayers, nextRound);
}

module.exports = {
  db,
  requireGameNotEndedData,
  assertCurrentMafia,
  activeMafiaIds,
  newMomentWrite,
  computeNextCutoffAt,
  maybeMarkAgreedInTx,
  checkGameEndInTx,
  resolveRoundTransactional,
};
