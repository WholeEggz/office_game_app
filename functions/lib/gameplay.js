// Milestone 4: the game-truth Cloud Functions from implementation_plan.md's
// inventory — vote casting/resolution, elimination/recruitment lifecycle,
// unmasking, leaveGame/setMemberActive/sendMafiaMessage/logObservation.
// Ported function-by-function from LocalGameRepository
// (lib/data/local/local_game_repository.dart) to run server-side, since a
// modified client could otherwise cheat (decrement another player's
// weight, read the mafia roster early, fabricate a role draw).
//
// The 1-hour execution-window auto-lapse, the 24h mafia-inactive
// auto-reactivation, and the daily-cutoff auto-resolve are all
// `dart:async Timer`s in LocalGameRepository that only fire while that
// process is alive — a real deployment needs Cloud Scheduler / scheduled
// functions instead. This file has the call-time equivalent of each
// (executeElimination/executeRecruitment reject a call after the window
// has practically closed; round resolution lapses anything
// agreed-but-unexecuted when the round ends); setMemberActive below
// stamps `inactiveUntil` so a *scheduled* sweep can proactively flip
// someone back to active between calls — see functions/lib/scheduled.js
// (Milestone 5) for that sweep and the matching one for the daily cutoff.

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { requireString, requireAuth } = require("./shared");
const {
  db,
  requireGameNotEndedData,
  assertCurrentMafia,
  newMomentWrite,
  maybeMarkAgreedInTx,
  checkGameEndInTx,
  resolveRoundTransactional,
} = require("./roundResolution");

// Concept doc §7: a mafia member marked inactive (sick leave, vacation) is
// absent "for 24 hours / until end of day" — mirrors LocalGameRepository's
// `_inactivityAutoResetWindow`.
const INACTIVITY_AUTO_RESET_WINDOW_MS = 24 * 60 * 60 * 1000;

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

    // Marking someone inactive stamps a 24h deadline the scheduled
    // reactivation sweep (functions/lib/scheduled.js) watches for;
    // reactivating (manually or via that sweep) clears it.
    const inactiveUntil = isActive
      ? null
      : Timestamp.fromMillis(Date.now() + INACTIVITY_AUTO_RESET_WINDOW_MS);
    tx.update(playerRef, { isActive, inactiveUntil });

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
