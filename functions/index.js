const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

initializeApp();

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

  const displayName = request.data?.displayName;
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

// Callables land here in later Phase 1b milestones — the game-truth
// inventory: createGame, castVote, proposeElimination, etc. (Milestone
// 4). See implementation_plan.md's "Cloud Functions inventory" section.
