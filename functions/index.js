const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

initializeApp();

const db = getFirestore();

// Every villager's starting vote weight (concept doc §5) — mirrors
// LocalGameRepository's `_startingVoteWeight`. Also the value forced onto
// every other player's entry in publicPlayers, for the same reason
// LocalGameRepository._publicView does it: a real, changing number would
// leak "this player has been confirmed not mafia" the moment it first
// drops, since only a non-mafia target ever loses weight (a mafia target
// gets unmasked instead).
const STARTING_VOTE_WEIGHT = 3;

function requireString(value, field) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function requirePositiveInt(value, field) {
  if (!Number.isInteger(value) || value < 1) {
    throw new HttpsError("invalid-argument", `${field} must be a positive integer.`);
  }
  return value;
}

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return request.auth;
}

function newPlayerDoc(name) {
  return {
    name,
    role: "villager",
    voteWeight: STARTING_VOTE_WEIGHT,
    isActive: true,
    recruiterId: null,
    recruitedPlayerIds: [],
    wasUnmasked: false,
    pendingRecruiterId: null,
    hasLeft: false,
    joinedAt: FieldValue.serverTimestamp(),
  };
}

// Fisher-Yates — used for the mafia draw, same as
// LocalGameRepository._activateGame's `..shuffle(Random())`.
function shuffle(items) {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [items[i], items[j]] = [items[j], items[i]];
  }
  return items;
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
  batch.update(gameRef, { status: "active" });
  await batch.commit();
}

// createGame/addPlayer — checked against GameRepository's actual interface
// (lib/domain/repositories/game_repository.dart), per implementation_plan.md's
// Cloud Functions inventory. Anything that decides game truth (role draw,
// name-uniqueness) must be server-side, never a direct client write — these
// are the two Milestone 3 needs; the rest of the inventory lands in
// Milestone 4.

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
//     derived from their own recruiterId/recruitedPlayerIds. Nothing in
//     Milestone 3 ever sets those fields (recruitment lands in Milestone
//     4), so this is always `{}` for now — the mechanism is built and
//     tested ahead of the feature that populates it.
//
// Known gap, deferred to Milestone 4: this only re-derives the *written*
// player's own cellViews. When recruitment/unmasking start mutating
// role/wasUnmasked, every viewer who has that player as a cell link also
// needs their cellViews refreshed — this trigger doesn't yet fan out to
// them. Not reachable in Milestone 3 since recruiterId/recruitedPlayerIds
// are never set, but must be revisited before Milestone 4 ships.
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
  await cellViewRef.set({ knownRoles });
});

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

// Callables land here in Milestone 4 — vote casting/resolution,
// elimination/recruitment lifecycle, unmasking. See
// implementation_plan.md's "Cloud Functions inventory" section.
