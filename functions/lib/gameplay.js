// Milestone 4: the game-truth Cloud Functions from implementation_plan.md's
// inventory — vote casting/resolution, elimination/recruitment lifecycle,
// unmasking, leaveGame/setMemberActive/sendMafiaMessage/logObservation.
// Ported function-by-function from LocalGameRepository
// (lib/data/local/local_game_repository.dart) to run server-side, since a
// modified client could otherwise cheat (decrement another player's
// weight, read the mafia roster early, fabricate a role draw).
//
// Deliberately NOT included here, per implementation_plan.md's explicit
// Milestone 4/5 split: the 1-hour execution-window auto-lapse, the 24h
// mafia-inactive auto-reactivation, and the daily-cutoff auto-resolve are
// all `dart:async Timer`s in LocalGameRepository that only fire while that
// process is alive — a real deployment needs Cloud Scheduler / scheduled
// functions instead (Milestone 5). What *is* included here is the
// synchronous, call-time equivalent of each: executeElimination/
// executeRecruitment still reject a call after the window has practically
// closed, and round resolution still lapses anything agreed-but-unexecuted
// when the round ends — proposals just won't proactively flip to `lapsed`
// on their own between calls yet.

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { requireString, requireAuth } = require("./shared");

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
// rounds, lapses anything agreed-but-unexecuted this round, and advances
// to the next round. Shared by resolveVotesForDay,
// acknowledgeEliminationSignal, and respondToRecruitment — all three
// resolve the day the same way, just triggered differently.
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
  });

  const finalPlayers = [...players.values()].map((p) => ({
    ...p,
    ...(playerPatches.get(p.id) || {}),
  }));
  checkGameEndInTx(tx, gameRef, finalPlayers, nextRound);
}

exports.castVote = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const voterId = requireString(data.voterId, "voterId");
  const targetPlayerId = requireString(data.targetPlayerId, "targetPlayerId");
  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const voterRef = gameRef.collection("players").doc(voterId);
    const targetRef = gameRef.collection("players").doc(targetPlayerId);
    const [voterSnap, targetSnap] = await Promise.all([tx.get(voterRef), tx.get(targetRef)]);
    if (!voterSnap.exists) throw new HttpsError("not-found", `${voterId} is not in game ${gameId}`);
    if (voterSnap.data().hasLeft) {
      throw new HttpsError(
        "failed-precondition",
        `${voterId} has left this game and can no longer vote`
      );
    }
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", `${targetPlayerId} is not in game ${gameId}`);
    }
    if (targetSnap.data().hasLeft) {
      throw new HttpsError(
        "failed-precondition",
        `${targetPlayerId} has left this game and can no longer be voted for`
      );
    }

    const round = gameSnap.data().currentRound;
    // Deterministic doc ID so re-voting the same round overwrites instead
    // of needing a query+delete — mirrors LocalGameRepository.castVote's
    // "remove any existing vote by this voter this round, then add".
    tx.set(gameRef.collection("votes").doc(`${voterId}_${round}`), {
      voterId,
      targetPlayerId,
      round,
      weight: voterSnap.data().voteWeight,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {};
});

exports.resolveVotesForDay = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());
    await resolveRoundTransactional(tx, gameRef);
  });

  return {};
});

function emptyThreadEntryFields() {
  return {
    message: null,
    proposedMethod: null,
    proposedTargetId: null,
    acceptedByPlayerIds: [],
    agreedAt: null,
    executedAt: null,
    executedByPlayerId: null,
    lapsed: false,
    confirmedAt: null,
    recruitmentAccepted: null,
  };
}

exports.proposeElimination = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const authorId = requireString(data.authorId, "authorId");
  const method = requireString(data.method, "method");
  const targetPlayerId = requireString(data.targetPlayerId, "targetPlayerId");
  const gameRef = db.collection("games").doc(gameId);
  const entryRef = gameRef.collection("mafiaThread").doc();

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const authorSnap = await tx.get(gameRef.collection("players").doc(authorId));
    assertCurrentMafia(authorSnap.exists ? authorSnap.data() : null, authorId);

    const targetSnap = await tx.get(gameRef.collection("players").doc(targetPlayerId));
    const target = targetSnap.exists ? targetSnap.data() : null;
    if (!target || target.role !== "villager" || target.hasLeft) {
      throw new HttpsError("failed-precondition", "Elimination target must be a current villager");
    }

    const playersSnap = await tx.get(gameRef.collection("players"));
    const players = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    const entry = {
      round: gameSnap.data().currentRound,
      authorId,
      type: "proposal",
      ...emptyThreadEntryFields(),
      proposedMethod: method,
      proposedTargetId: targetPlayerId,
      acceptedByPlayerIds: [authorId],
      createdAt: FieldValue.serverTimestamp(),
    };
    tx.set(entryRef, entry);
    maybeMarkAgreedInTx(tx, gameRef, entryRef, entry, players);
  });

  return { proposalId: entryRef.id };
});

exports.proposeRecruitment = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const recruiterId = requireString(data.recruiterId, "recruiterId");
  const targetPlayerId = requireString(data.targetPlayerId, "targetPlayerId");
  const sign = requireString(data.sign, "sign");
  const gameRef = db.collection("games").doc(gameId);
  const entryRef = gameRef.collection("mafiaThread").doc();

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    const game = gameSnap.data();
    requireGameNotEndedData(game);

    const playersSnap = await tx.get(gameRef.collection("players"));
    const players = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    const livingMafia = players.filter((p) => p.role === "mafia" && !p.hasLeft).length;
    const livingVillagers = players.filter((p) => p.role === "villager" && !p.hasLeft).length;
    const recruitmentUnlocked =
      livingMafia > 0 &&
      livingVillagers > 0 &&
      livingMafia / livingVillagers <= game.recruitmentUnlockThreshold;
    if (!recruitmentUnlocked) {
      throw new HttpsError("failed-precondition", `Recruitment is not yet unlocked in game ${gameId}`);
    }

    const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
    const hasActiveRecruitment = threadSnap.docs.some((d) => {
      const e = d.data();
      return e.type === "recruitment" && !e.lapsed && e.confirmedAt == null;
    });
    if (hasActiveRecruitment) {
      throw new HttpsError("failed-precondition", "Only one recruitment can be in progress at a time");
    }

    const recruiter = players.find((p) => p.id === recruiterId) || null;
    assertCurrentMafia(recruiter, recruiterId);

    const target = players.find((p) => p.id === targetPlayerId) || null;
    if (!target || target.role !== "villager" || target.hasLeft) {
      throw new HttpsError("failed-precondition", "Recruitment target must be a current villager");
    }

    const entry = {
      round: game.currentRound,
      authorId: recruiterId,
      type: "recruitment",
      ...emptyThreadEntryFields(),
      proposedMethod: sign,
      proposedTargetId: targetPlayerId,
      acceptedByPlayerIds: [recruiterId],
      createdAt: FieldValue.serverTimestamp(),
    };
    tx.set(entryRef, entry);
    maybeMarkAgreedInTx(tx, gameRef, entryRef, entry, players);
  });

  return { proposalId: entryRef.id };
});

// Shared by acceptEliminationProposal/acceptRecruitmentProposal — mirrors
// LocalGameRepository, where both are literally the same logic (accept +
// maybeMarkAgreed) with no type check; a proposal ID uniquely identifies
// its own type already.
async function acceptProposalInternal(data) {
  const gameId = requireString(data.gameId, "gameId");
  const proposalId = requireString(data.proposalId, "proposalId");
  const playerId = requireString(data.playerId, "playerId");
  const gameRef = db.collection("games").doc(gameId);
  const entryRef = gameRef.collection("mafiaThread").doc(proposalId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const playerSnap = await tx.get(gameRef.collection("players").doc(playerId));
    assertCurrentMafia(playerSnap.exists ? playerSnap.data() : null, playerId);

    const entrySnap = await tx.get(entryRef);
    if (!entrySnap.exists) throw new HttpsError("not-found", `Unknown proposal ${proposalId}`);
    const entry = entrySnap.data();

    const playersSnap = await tx.get(gameRef.collection("players"));
    const players = playersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    if (entry.agreedAt == null && !(entry.acceptedByPlayerIds || []).includes(playerId)) {
      const updated = [...(entry.acceptedByPlayerIds || []), playerId];
      tx.update(entryRef, { acceptedByPlayerIds: updated });
      entry.acceptedByPlayerIds = updated;
    }
    maybeMarkAgreedInTx(tx, gameRef, entryRef, entry, players);
  });

  return {};
}

exports.acceptEliminationProposal = onCall(async (request) => {
  requireAuth(request);
  return acceptProposalInternal(request.data || {});
});

exports.acceptRecruitmentProposal = onCall(async (request) => {
  requireAuth(request);
  return acceptProposalInternal(request.data || {});
});

exports.executeElimination = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const proposalId = requireString(data.proposalId, "proposalId");
  const playerId = requireString(data.playerId, "playerId");
  const gameRef = db.collection("games").doc(gameId);
  const entryRef = gameRef.collection("mafiaThread").doc(proposalId);

  let windowClosed = false;

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const playerSnap = await tx.get(gameRef.collection("players").doc(playerId));
    assertCurrentMafia(playerSnap.exists ? playerSnap.data() : null, playerId);

    const entrySnap = await tx.get(entryRef);
    if (!entrySnap.exists) throw new HttpsError("not-found", `Unknown proposal ${proposalId}`);
    const entry = entrySnap.data();
    if (entry.agreedAt == null) {
      throw new HttpsError(
        "failed-precondition",
        "This proposal has not been agreed by every active member yet"
      );
    }
    if (entry.executedAt != null) {
      throw new HttpsError("failed-precondition", "This proposal has already been executed");
    }

    const agreedAtMs = entry.agreedAt.toMillis();
    windowClosed =
      entry.lapsed || Date.now() > agreedAtMs + gameSnap.data().executionWindowSeconds * 1000;
    if (windowClosed) {
      tx.update(entryRef, { lapsed: true });
      return;
    }

    const targetRef = gameRef.collection("players").doc(entry.proposedTargetId);
    const targetSnap = await tx.get(targetRef);

    tx.update(entryRef, { executedAt: FieldValue.serverTimestamp() });
    if (targetSnap.exists) {
      const target = targetSnap.data();
      tx.update(targetRef, { voteWeight: Math.max(0, (target.voteWeight || 0) - 1) });
      const moment = newMomentWrite(
        gameRef,
        entry.proposedTargetId,
        "targetedByMafia",
        gameSnap.data().currentRound
      );
      tx.set(moment.ref, moment.data);
    }
    tx.update(gameRef, { eliminationSignalExecuted: true });
  });

  if (windowClosed) {
    throw new HttpsError(
      "failed-precondition",
      "The window to execute this proposal has already closed"
    );
  }
  return {};
});

exports.executeRecruitment = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const proposalId = requireString(data.proposalId, "proposalId");
  const playerId = requireString(data.playerId, "playerId");
  const gameRef = db.collection("games").doc(gameId);
  const entryRef = gameRef.collection("mafiaThread").doc(proposalId);

  let windowClosed = false;

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const playerSnap = await tx.get(gameRef.collection("players").doc(playerId));
    assertCurrentMafia(playerSnap.exists ? playerSnap.data() : null, playerId);

    const entrySnap = await tx.get(entryRef);
    if (!entrySnap.exists) throw new HttpsError("not-found", `Unknown proposal ${proposalId}`);
    const entry = entrySnap.data();
    if (entry.type !== "recruitment") {
      throw new HttpsError("failed-precondition", `${proposalId} is not a recruitment proposal`);
    }
    if (entry.agreedAt == null) {
      throw new HttpsError(
        "failed-precondition",
        "This recruitment has not been agreed by every active member yet"
      );
    }
    if (entry.executedAt != null) {
      throw new HttpsError("failed-precondition", "This recruitment has already been executed");
    }

    const agreedAtMs = entry.agreedAt.toMillis();
    windowClosed =
      entry.lapsed || Date.now() > agreedAtMs + gameSnap.data().executionWindowSeconds * 1000;
    if (windowClosed) {
      tx.update(entryRef, { lapsed: true });
      return;
    }

    // Only now does the target actually see an offer waiting for them.
    tx.update(entryRef, { executedAt: FieldValue.serverTimestamp(), executedByPlayerId: playerId });
    tx.update(gameRef.collection("players").doc(entry.proposedTargetId), {
      pendingRecruiterId: playerId,
    });
    tx.update(gameRef, { recruitmentSignExecuted: true });
  });

  if (windowClosed) {
    throw new HttpsError(
      "failed-precondition",
      "The window to approach this recruit has already closed"
    );
  }
  return {};
});

exports.acknowledgeEliminationSignal = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const playerId = requireString(data.playerId, "playerId");
  const gameRef = db.collection("games").doc(gameId);

  let matched = false;

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const playerSnap = await tx.get(gameRef.collection("players").doc(playerId));
    if (!playerSnap.exists) {
      throw new HttpsError("not-found", `${playerId} is not in game ${gameId}`);
    }

    const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
    const entryDoc = threadSnap.docs.find((d) => {
      const e = d.data();
      return (
        e.type === "proposal" &&
        e.executedAt != null &&
        e.confirmedAt == null &&
        e.proposedTargetId === playerId
      );
    });
    if (!entryDoc) {
      matched = false;
      return;
    }
    matched = true;
    tx.update(entryDoc.ref, { confirmedAt: FieldValue.serverTimestamp() });
    tx.update(gameRef, { eliminationSignalConfirmed: true });
  });

  if (!matched) return { accepted: false };

  // The real target discovering the mark is, narratively, the end of the
  // day — resolve the round the same way the manual "resolve" call would,
  // in a second transaction (this needs the confirm write above to have
  // already committed, since it re-reads round-current state fresh).
  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    requireGameNotEndedData(gameSnap.data());
    await resolveRoundTransactional(tx, gameRef);
  });

  return { accepted: true };
});

exports.respondToRecruitment = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const playerId = requireString(data.playerId, "playerId");
  const accept = data.accept === true;
  const gameRef = db.collection("games").doc(gameId);

  let matched = false;

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const playerRef = gameRef.collection("players").doc(playerId);
    const playerSnap = await tx.get(playerRef);
    if (!playerSnap.exists) {
      throw new HttpsError("not-found", `${playerId} is not in game ${gameId}`);
    }
    const player = playerSnap.data();

    // Mirrors acknowledgeEliminationSignal: everyone sees the same "did
    // this happen to you?" prompt, but it's a silent no-op for anyone who
    // wasn't actually the one approached.
    if (!player.pendingRecruiterId) {
      matched = false;
      return;
    }
    matched = true;
    const recruiterId = player.pendingRecruiterId;
    const recruiterRef = gameRef.collection("players").doc(recruiterId);
    const recruiterSnap = accept ? await tx.get(recruiterRef) : null;

    const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
    const entryDoc = threadSnap.docs.find((d) => {
      const e = d.data();
      return (
        e.type === "recruitment" &&
        e.proposedTargetId === playerId &&
        e.executedAt != null &&
        e.confirmedAt == null
      );
    });

    if (entryDoc) {
      tx.update(entryDoc.ref, { confirmedAt: FieldValue.serverTimestamp(), recruitmentAccepted: accept });
    }

    if (accept) {
      // The recruiter here is whoever actually executed the approach
      // (recorded on the target's pendingRecruiterId), not necessarily
      // whoever originally proposed it.
      tx.update(playerRef, { role: "mafia", recruiterId, pendingRecruiterId: null });
      if (recruiterSnap && recruiterSnap.exists) {
        const recruiter = recruiterSnap.data();
        tx.update(recruiterRef, {
          recruitedPlayerIds: [...(recruiter.recruitedPlayerIds || []), playerId],
        });
      }
      const round = gameSnap.data().currentRound;
      const executedMoment = newMomentWrite(gameRef, recruiterId, "recruitmentExecuted", round);
      tx.set(executedMoment.ref, executedMoment.data);
      const switchedMoment = newMomentWrite(gameRef, playerId, "recruitedSwitchSides", round);
      tx.set(switchedMoment.ref, switchedMoment.data);
    } else {
      tx.update(playerRef, { pendingRecruiterId: null });
    }
    tx.update(gameRef, { recruitmentSignConfirmed: true });
  });

  if (!matched) return { accepted: false };

  // Mirrors acknowledgeEliminationSignal: the real target responding is
  // narratively the end of the day either way (accept or decline).
  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    requireGameNotEndedData(gameSnap.data());
    await resolveRoundTransactional(tx, gameRef);
  });

  return { accepted: true };
});

exports.sendMafiaMessage = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const authorId = requireString(data.authorId, "authorId");
  const text = requireString(data.text, "text");
  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const authorSnap = await tx.get(gameRef.collection("players").doc(authorId));
    assertCurrentMafia(authorSnap.exists ? authorSnap.data() : null, authorId);

    tx.set(gameRef.collection("mafiaThread").doc(), {
      round: gameSnap.data().currentRound,
      authorId,
      type: "message",
      ...emptyThreadEntryFields(),
      message: text,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {};
});

// No _requireGameNotEnded here — mirrors LocalGameRepository.leaveGame,
// which deliberately allows leaving regardless of game state.
exports.leaveGame = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const playerId = requireString(data.playerId, "playerId");
  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    const game = gameSnap.data();

    const playerRef = gameRef.collection("players").doc(playerId);
    const playerSnap = await tx.get(playerRef);
    if (!playerSnap.exists) {
      throw new HttpsError("not-found", `${playerId} is not in game ${gameId}`);
    }

    const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
    const playersSnap = await tx.get(gameRef.collection("players"));
    const players = playersSnap.docs.map((d) =>
      d.id === playerId ? { id: d.id, ...d.data(), hasLeft: true } : { id: d.id, ...d.data() }
    );

    tx.update(playerRef, { hasLeft: true });

    // A departing mafia member can immediately satisfy an unagreed
    // proposal or recruitment that was only waiting on them.
    for (const doc of threadSnap.docs) {
      const entry = doc.data();
      if (
        (entry.type === "proposal" || entry.type === "recruitment") &&
        entry.agreedAt == null &&
        !entry.lapsed
      ) {
        maybeMarkAgreedInTx(tx, gameRef, doc.ref, entry, players);
      }
    }

    // A departure can itself cross a win condition.
    if (game.status === "active") {
      checkGameEndInTx(tx, gameRef, players, game.currentRound);
    }
  });

  return {};
});

// No auto-reactivation scheduling here (Milestone 5's scope) — this only
// sets the flag and re-checks pending agreements, mirroring
// LocalGameRepository.setMemberActive minus its 24h Timer.
exports.setMemberActive = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const playerId = requireString(data.playerId, "playerId");
  const isActive = data.isActive === true;
  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const playerRef = gameRef.collection("players").doc(playerId);
    const playerSnap = await tx.get(playerRef);
    assertCurrentMafia(playerSnap.exists ? playerSnap.data() : null, playerId);

    const threadSnap = await tx.get(gameRef.collection("mafiaThread"));
    const playersSnap = await tx.get(gameRef.collection("players"));
    const players = playersSnap.docs.map((d) =>
      d.id === playerId ? { id: d.id, ...d.data(), isActive } : { id: d.id, ...d.data() }
    );

    tx.update(playerRef, { isActive });

    // Marking someone inactive can immediately satisfy an unagreed
    // proposal or recruitment that was only waiting on them.
    for (const doc of threadSnap.docs) {
      const entry = doc.data();
      if (
        (entry.type === "proposal" || entry.type === "recruitment") &&
        entry.agreedAt == null &&
        !entry.lapsed
      ) {
        maybeMarkAgreedInTx(tx, gameRef, doc.ref, entry, players);
      }
    }
  });

  return {};
});

exports.logObservation = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const authorId = requireString(data.authorId, "authorId");
  const text = requireString(data.text, "text");
  const targetPlayerId = typeof data.targetPlayerId === "string" ? data.targetPlayerId : null;
  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) throw new HttpsError("not-found", `Game ${gameId} not found`);
    requireGameNotEndedData(gameSnap.data());

    const authorSnap = await tx.get(gameRef.collection("players").doc(authorId));
    if (!authorSnap.exists) {
      throw new HttpsError("not-found", `${authorId} is not in game ${gameId}`);
    }

    tx.set(gameRef.collection("observations").doc(), {
      authorId,
      targetPlayerId,
      text,
      round: gameSnap.data().currentRound,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {};
});
