// Functional smoke test for the reportPlayer Cloud Function against a live
// emulator suite (auth + firestore + functions must all be running).
// Complements rules_test.js (access control on already-seeded data) by
// actually calling the callable and checking its validation + the report
// doc it writes. blockPlayer/unblockPlayer aren't covered here — they're
// plain client-side Firestore writes with no Cloud Function involved, and
// are already covered by rules_test.js (access control) and
// test/moderation_test.dart (LocalGameRepository parity).
//
//   node test/moderation_smoke_test.js

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

async function cleanup(gameId) {
  const gameRef = db.collection("games").doc(gameId);
  for (const sub of ["players", "publicPlayers", "cellViews", "reports", "blocks"]) {
    const snap = await gameRef.collection(sub).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await gameRef.delete();
}

async function main() {
  console.log("--- reportPlayer ---");
  const creator = await mintUserAndIdToken("ReportCreator");
  const joiner = await mintUserAndIdToken("ReportJoiner");
  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "Moderation Test Floor",
    minPlayers: 2,
    creatorId: creator.uid,
    creatorName: creator.name,
  });
  await callCallable("addPlayer", joiner.idToken, {
    gameId,
    playerId: joiner.uid,
    name: joiner.name,
  });

  // Rejects a reporter/target who isn't actually in the game.
  await assert.rejects(
    () =>
      callCallable("reportPlayer", creator.idToken, {
        gameId,
        reporterId: "not-a-real-player",
        targetPlayerId: joiner.uid,
        reason: "test",
      }),
    /not-a-real-player is not in game/
  );
  await assert.rejects(
    () =>
      callCallable("reportPlayer", creator.idToken, {
        gameId,
        reporterId: creator.uid,
        targetPlayerId: "not-a-real-player",
        reason: "test",
      }),
    /not-a-real-player is not in game/
  );
  console.log("PASS: reportPlayer rejects an unknown reporter/target");

  // A valid report succeeds and is actually persisted (checked via the
  // Admin SDK, since firestore.rules denies client reads on this
  // collection entirely).
  const { reportId } = await callCallable("reportPlayer", creator.idToken, {
    gameId,
    reporterId: creator.uid,
    targetPlayerId: joiner.uid,
    reason: "inappropriate display name",
  });
  const reportSnap = await db.collection(`games/${gameId}/reports`).doc(reportId).get();
  assert.ok(reportSnap.exists, "report doc should have been written");
  assert.equal(reportSnap.data().reporterId, creator.uid);
  assert.equal(reportSnap.data().targetPlayerId, joiner.uid);
  assert.equal(reportSnap.data().reason, "inappropriate display name");
  assert.equal(reportSnap.data().observationId, null);
  console.log("PASS: a valid report is persisted with the right fields");

  // A report tied to a specific observation entry.
  const { reportId: reportId2 } = await callCallable("reportPlayer", creator.idToken, {
    gameId,
    reporterId: creator.uid,
    targetPlayerId: joiner.uid,
    reason: "harassment in an observation",
    observationId: "some-observation-id",
  });
  const reportSnap2 = await db.collection(`games/${gameId}/reports`).doc(reportId2).get();
  assert.equal(reportSnap2.data().observationId, "some-observation-id");
  console.log("PASS: a report can reference a specific observation entry");

  await cleanup(gameId);
  console.log("\nAll moderation functional smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
