const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

const { STARTING_VOTE_WEIGHT, requireString, requirePositiveInt, requireAuth, shuffle } =
  require("./lib/shared");

// Must run before requiring ./lib/roundResolution — that module calls
// getFirestore() at its own top level, which throws "no app" if the
// default app isn't initialized yet.
initializeApp();

const { computeNextCutoffAt } = require("./lib/roundResolution");

const db = getFirestore();

function newPlayerDoc(name) {
  return {
    name,
    role: "villager",
    voteWeight: STARTING_VOTE_WEIGHT,
    isActive: true,
    inactiveUntil: null,
    recruiterId: null,
    recruitedPlayerIds: [],
    wasUnmasked: false,
    pendingRecruiterId: null,
    hasLeft: false,
    joinedAt: FieldValue.serverTimestamp(),
  };
}

// Draws roles the moment the roster reaches minPlayers — mirrors
// LocalGameRepository._autoStartIfReady/_activateGame exactly, including
// clamping mafiaCount to [1, roster size] regardless of what the game
// document asks for. A no-op if the game isn't still `recruiting` or
// hasn't reached that size yet.
async function maybeActivateGame(gameRef) {
  const gameSnap = await gameRef.get();
  const game = gameSnap.data();
  if (!game || game.status !== "recruiting") return;

  const playersSnap = await gameRef.collection("players").get();
  if (playersSnap.size < game.minPlayers) return;

  const ids = shuffle(playersSnap.docs.map((doc) => doc.id));
  const mafiaCount = Math.min(Math.max(game.mafiaCount || 1, 1), ids.length);
  const mafiaIds = new Set(ids.slice(0, mafiaCount));

  const batch = db.batch();
  for (const doc of playersSnap.docs) {
    if (mafiaIds.has(doc.id)) {
      batch.update(doc.ref, { role: "mafia" });
    }
  }
  // Starts the daily-cutoff clock (Milestone 5's scheduled sweep) the
  // same moment LocalGameRepository._activateGame calls
  // _scheduleDailyCutoff — right when the game actually goes active.
  batch.update(gameRef, { status: "active", nextCutoffAt: computeNextCutoffAt(game.dailyCutoffSeconds) });
  await batch.commit();
}

// createGame/addPlayer — checked against GameRepository's actual interface
// (lib/domain/repositories/game_repository.dart), per implementation_plan.md's
// Cloud Functions inventory.

exports.createGame = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const locationTag = requireString(data.locationTag, "locationTag");
  const minPlayers = requirePositiveInt(data.minPlayers, "minPlayers");
  const creatorId = requireString(data.creatorId, "creatorId");
  const creatorName = requireString(data.creatorName, "creatorName");
  const mafiaCount = Number.isInteger(data.mafiaCount) ? data.mafiaCount : 1;
  const recruitmentUnlockThreshold =
    typeof data.recruitmentUnlockThreshold === "number" ? data.recruitmentUnlockThreshold : 0.2;
  const executionWindowSeconds = Number.isInteger(data.executionWindowSeconds)
    ? data.executionWindowSeconds
    : 3600;
  const dailyCutoffSeconds = Number.isInteger(data.dailyCutoffSeconds)
    ? data.dailyCutoffSeconds
    : 17 * 3600;
  const rulesDescription = typeof data.rulesDescription === "string" ? data.rulesDescription : "";

  const gameRef = db.collection("games").doc();
  const playerRef = gameRef.collection("players").doc(creatorId);

  await db.runTransaction(async (tx) => {
    tx.set(gameRef, {
      locationTag,
      status: "recruiting",
      minPlayers,
      currentRound: 1,
      rulesDescription,
      mafiaCount,
      recruitmentUnlockThreshold,
      executionWindowSeconds,
      dailyCutoffSeconds,
      eliminationMethodDescription: null,
      eliminationSignalExecuted: false,
      eliminationSignalConfirmed: false,
      recruitmentSignDescription: null,
      recruitmentSignExecuted: false,
      recruitmentSignConfirmed: false,
      winner: null,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(playerRef, newPlayerDoc(creatorName));
  });

  // Covers the edge case where minPlayers is already met the moment the
  // creator joins (e.g. minPlayers: 1) — same rule as addPlayer.
  await maybeActivateGame(gameRef);

  return { gameId: gameRef.id };
});

exports.addPlayer = onCall(async (request) => {
  requireAuth(request);
  const data = request.data || {};
  const gameId = requireString(data.gameId, "gameId");
  const playerId = requireString(data.playerId, "playerId");
  const name = requireString(data.name, "name");

  const gameRef = db.collection("games").doc(gameId);
  const playerRef = gameRef.collection("players").doc(playerId);

  await db.runTransaction(async (tx) => {
    const gameSnap = await tx.get(gameRef);
    if (!gameSnap.exists) {
      throw new HttpsError("not-found", `Game ${gameId} not found`);
    }
    if (gameSnap.data().status === "ended") {
      throw new HttpsError("failed-precondition", "This case has already ended.");
    }

    const existing = await tx.get(playerRef);
    if (existing.exists) {
      throw new HttpsError("already-exists", `${playerId} has already joined this game`);
    }

    // Two coworkers really can share a first name in real life, but within
    // a single roster that's confusing (who's "Bob" in the observation
    // log?) — same case/whitespace-insensitive uniqueness check as
    // LocalGameRepository.addPlayer.
    const playersSnap = await tx.get(gameRef.collection("players"));
    const normalized = name.trim().toLowerCase();
    const nameTaken = playersSnap.docs.some(
      (doc) => (doc.data().name || "").trim().toLowerCase() === normalized
    );
    if (nameTaken) {
      throw new HttpsError("already-exists", `"${name}" is already in this game`);
    }

    tx.set(playerRef, newPlayerDoc(name));
  });

  // Real players never see a manual "start the game" button — without
  // this, a game joined entirely through the real player flow would sit
  // in `recruiting` forever.
  await maybeActivateGame(gameRef);

  return { playerId };
});

// Reproduces LocalGameRepository._publicView/_visiblePlayers server-side,
// run once per write instead of once per read (implementation_plan.md's
// redaction architecture). Maintains two documents per true player-doc
// write:
//   - publicPlayers/{playerId}: the redacted mirror everyone sees.
//   - cellViews/{playerId}: this player's own cell-link role reveals,
//     derived from their own recruiterId/recruitedPlayerIds — plus a
//     fan-out to anyone who has *this* player as their own cell link
//     (their recruiter, or anyone they recruited), since a role change
//     here can make their cellViews stale too (e.g. a recruiter getting
//     unmasked later needs their recruit's cellViews refreshed, not just
//     their own).
exports.syncPlayerViews = onDocumentWritten("games/{gameId}/players/{playerId}", async (event) => {
  const { gameId, playerId } = event.params;
  const gameRef = db.collection("games").doc(gameId);
  const publicRef = gameRef.collection("publicPlayers").doc(playerId);
  const cellViewRef = gameRef.collection("cellViews").doc(playerId);

  const after = event.data && event.data.after;
  if (!after || !after.exists) {
    await Promise.all([
      publicRef.delete().catch(() => {}),
      cellViewRef.delete().catch(() => {}),
    ]);
    return;
  }

  const player = after.data();
  const revealRole = player.wasUnmasked || player.role !== "mafia";

  await publicRef.set({
    name: player.name,
    role: revealRole ? player.role : "villager",
    voteWeight: STARTING_VOTE_WEIGHT,
    isActive: player.isActive,
    wasUnmasked: player.wasUnmasked,
    hasLeft: player.hasLeft,
    joinedAt: player.joinedAt,
  });

  await recomputeCellView(gameRef, playerId, player);

  // Fan out to anyone whose OWN cellViews depends on this player's role:
  // their recruiter, or anyone they recruited. Without this, a recruit's
  // cellViews would go stale the moment their recruiter is later caught
  // and unmasked by a vote — the recruiter's own write only refreshes the
  // recruiter's cellViews, not everyone who has the recruiter as a link.
  const dependentSnaps = await Promise.all([
    gameRef.collection("players").where("recruiterId", "==", playerId).get(),
    gameRef.collection("players").where("recruitedPlayerIds", "array-contains", playerId).get(),
  ]);
  const dependentIds = new Set();
  for (const snap of dependentSnaps) {
    for (const doc of snap.docs) {
      if (doc.id !== playerId) dependentIds.add(doc.id);
    }
  }
  await Promise.all(
    [...dependentIds].map(async (dependentId) => {
      const dependentSnap = await gameRef.collection("players").doc(dependentId).get();
      if (dependentSnap.exists) {
        await recomputeCellView(gameRef, dependentId, dependentSnap.data());
      }
    })
  );
});

// Recomputes cellViews/{playerId} from [player]'s own recruiterId/
// recruitedPlayerIds — factored out so both the written player and any
// dependent (their recruiter, or anyone they recruited) can be refreshed
// with the same logic.
async function recomputeCellView(gameRef, playerId, player) {
  const linkIds = [];
  if (player.recruiterId) linkIds.push(player.recruiterId);
  for (const id of player.recruitedPlayerIds || []) linkIds.push(id);

  const knownRoles = {};
  if (linkIds.length > 0) {
    const snaps = await Promise.all(
      linkIds.map((id) => gameRef.collection("players").doc(id).get())
    );
    for (const snap of snaps) {
      if (snap.exists) knownRoles[snap.id] = snap.data().role;
    }
  }
  await gameRef.collection("cellViews").doc(playerId).set({ knownRoles });
}

// Debug-only identity minting for the role switcher (Phase 1a's "temporary
// option to switch between users in different roles on one device"). Real
// Firebase Auth only supports one signed-in user per app instance, so the
// switcher's multi-identity simulation is reproduced by minting a fresh
// test user + custom token here; FirebaseAuthService exchanges the token
// client-side via signInWithCustomToken. See implementation_plan.md's
// "Auth and the debug switcher" section.
//
// FUNCTIONS_EMULATOR is set by the Cloud Functions runtime itself when
// running under `firebase emulators:start` — this function refuses to run
// anywhere else, so it's a no-op even if it were ever accidentally
// deployed to production.
exports.debugMintTestUser = onCall(async (request) => {
  if (process.env.FUNCTIONS_EMULATOR !== "true") {
    throw new HttpsError(
      "permission-denied",
      "debugMintTestUser only runs against the Firebase Local Emulator Suite."
    );
  }

  const displayName = request.data && request.data.displayName;
  if (typeof displayName !== "string" || displayName.trim() === "") {
    throw new HttpsError("invalid-argument", "displayName is required.");
  }

  const auth = getAuth();
  // Always a fresh identity, even for a repeated displayName — mirrors
  // LocalAuthService.registerNewPlayer, which never collapses two
  // simulated players sharing a name into one identity.
  const user = await auth.createUser({ displayName: displayName.trim() });
  const customToken = await auth.createCustomToken(user.uid);
  return { uid: user.uid, displayName: displayName.trim(), customToken };
});

// Milestone 4: vote casting/resolution, elimination/recruitment
// lifecycle, unmasking, leaveGame/setMemberActive/sendMafiaMessage/
// logObservation. See implementation_plan.md's "Cloud Functions
// inventory" section.
Object.assign(exports, require("./lib/gameplay"));

// Milestone 5: scheduled functions — daily vote cutoff, mafia-inactive
// auto-reactivation. Named explicitly rather than Object.assign'd like
// gameplay.js above: functions/lib/scheduled.js also exports the plain,
// directly-testable sweep functions underneath these two, which aren't
// themselves deployable Cloud Functions and shouldn't end up in this
// module's exports.
const scheduled = require("./lib/scheduled");
exports.scheduledDailyCutoffSweep = scheduled.scheduledDailyCutoffSweep;
exports.scheduledMafiaReactivationSweep = scheduled.scheduledMafiaReactivationSweep;
