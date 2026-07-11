// Functional smoke test for Milestone 6's remaining game-truth pieces —
// startGame and the debugRoster mirror that backs FirebaseGameRepository.
// watchGame's tester-facing roster — against a live emulator suite (auth +
// firestore + functions must all be running). Not a permanent regression
// suite — a one-shot check that these behave as designed.
//
//   node test/milestone6_smoke_test.js

const assert = require("node:assert/strict");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "officegameapp";

const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp({ projectId: "officegameapp" });
const db = getFirestore();

const PROJECT_ID = "officegameapp";
const FUNCTIONS_BASE = `http://127.0.0.1:5001/${PROJECT_ID}/us-central1`;
const AUTH_BASE = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";

async function mintUserAndIdToken(displayName) {
  const mintRes = await fetch(`${FUNCTIONS_BASE}/debugMintTestUser`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ data: { displayName } }),
  });
  const mint = (await mintRes.json()).result;
  const exchangeRes = await fetch(`${AUTH_BASE}/accounts:signInWithCustomToken?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: mint.customToken, returnSecureToken: true }),
  });
  const exchange = await exchangeRes.json();
  return { uid: mint.uid, idToken: exchange.idToken, name: displayName };
}

async function callCallable(name, idToken, data) {
  const res = await fetch(`${FUNCTIONS_BASE}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  const body = await res.json();
  if (body.error) {
    const err = new Error(body.error.message);
    err.code = body.error.status;
    throw err;
  }
  return body.result;
}

async function wait(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

async function cleanup(gameId) {
  const gameRef = db.collection("games").doc(gameId);
  for (const sub of [
    "players",
    "publicPlayers",
    "cellViews",
    "debugRoster",
    "mafiaThread",
    "votes",
    "observations",
    "moments",
  ]) {
    const snap = await gameRef.collection(sub).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await gameRef.delete();
}

async function testStartGame() {
  console.log("\n--- startGame ---");
  const creator = await mintUserAndIdToken("StartCreator");

  // minPlayers 2, only the creator joins — createGame's own
  // maybeActivateGame call leaves it in `recruiting`.
  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "M6 Start Test",
    minPlayers: 2,
    creatorId: creator.uid,
    creatorName: "StartCreator",
    mafiaCount: 1,
  });
  await wait(300);

  let gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().status, "recruiting");

  // Roster still short — startGame should reject with a clear message.
  await assert.rejects(
    () => callCallable("startGame", creator.idToken, { gameId }),
    (err) => err.code === "FAILED_PRECONDITION" && /at least 2 players/.test(err.message),
    "startGame should reject a too-small roster"
  );

  const joiner = await mintUserAndIdToken("StartJoiner");
  await callCallable("addPlayer", joiner.idToken, { gameId, playerId: joiner.uid, name: "StartJoiner" });
  await wait(300);

  gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().status, "active", "addPlayer's own auto-start should have activated it");

  // Already active — startGame should be an idempotent no-op, not an error.
  await callCallable("startGame", creator.idToken, { gameId });

  console.log("startGame OK");
  await cleanup(gameId);
}

async function testDebugRoster() {
  console.log("\n--- debugRoster mirror ---");
  const creator = await mintUserAndIdToken("RosterCreatorA");
  const joiner = await mintUserAndIdToken("RosterJoinerB");

  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "M6 Roster Test",
    minPlayers: 2,
    creatorId: creator.uid,
    creatorName: "RosterCreatorA",
    mafiaCount: 1,
  });
  await callCallable("addPlayer", joiner.idToken, { gameId, playerId: joiner.uid, name: "RosterJoinerB" });
  await wait(500);

  const gameRef = db.collection("games").doc(gameId);
  const debugRosterSnap = await gameRef.collection("debugRoster").get();
  assert.equal(debugRosterSnap.size, 2, "debugRoster should mirror both players (emulator context)");

  const roles = debugRosterSnap.docs.map((d) => d.data().role);
  assert.equal(roles.filter((r) => r === "mafia").length, 1);
  assert.equal(roles.filter((r) => r === "villager").length, 1);

  // publicPlayers still hides the real role — debugRoster is the one
  // place that doesn't, and only because this is the emulator.
  const publicSnap = await gameRef.collection("publicPlayers").get();
  for (const doc of publicSnap.docs) {
    assert.equal(doc.data().role, "villager", "publicPlayers should still redact regardless of debugRoster");
  }

  console.log("debugRoster mirror OK");
  await cleanup(gameId);
}

async function main() {
  await testStartGame();
  await testDebugRoster();
  console.log("\nAll Milestone 6 functional smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
