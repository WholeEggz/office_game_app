// Functional smoke test for the joinedCase moment — regression coverage
// for a real gap found after removing the client-side role-reveal screen:
// createGame/addPlayer never wrote a joinedCase moment server-side, so a
// real (Firebase-backed) player joining a case for the first time saw
// nothing at all, since the client's entire first-entry ceremony now
// lives inside that one moment's dialog.
//
//   node test/joined_case_moment_smoke_test.js

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
  for (const sub of ["players", "publicPlayers", "cellViews", "moments"]) {
    const snap = await gameRef.collection(sub).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await gameRef.delete();
}

async function main() {
  const creator = await mintUserAndIdToken("MomentCreator");
  const joiner = await mintUserAndIdToken("MomentJoiner");

  console.log("--- createGame writes a joinedCase moment for the creator ---");
  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "Moment Smoke Floor",
    minPlayers: 4,
    creatorId: creator.uid,
    creatorName: creator.name,
  });

  const creatorMomentsSnap = await db
    .collection(`games/${gameId}/moments`)
    .where("playerId", "==", creator.uid)
    .get();
  assert.equal(creatorMomentsSnap.size, 1);
  const creatorMoment = creatorMomentsSnap.docs[0].data();
  assert.equal(creatorMoment.type, "joinedCase");
  assert.equal(creatorMoment.acknowledged, false);
  assert.equal(creatorMoment.round, 1);
  console.log("PASS: creator gets exactly one joinedCase moment, round 1, unacknowledged");

  console.log("\n--- addPlayer writes a joinedCase moment for the joiner ---");
  await callCallable("addPlayer", joiner.idToken, {
    gameId,
    playerId: joiner.uid,
    name: joiner.name,
  });

  const joinerMomentsSnap = await db
    .collection(`games/${gameId}/moments`)
    .where("playerId", "==", joiner.uid)
    .get();
  assert.equal(joinerMomentsSnap.size, 1);
  const joinerMoment = joinerMomentsSnap.docs[0].data();
  assert.equal(joinerMoment.type, "joinedCase");
  assert.equal(joinerMoment.acknowledged, false);
  console.log("PASS: joiner gets exactly one joinedCase moment too");

  console.log("\n--- the joiner can read their own moment through client-facing rules ---");
  // Mirrors FirebaseGameRepository.fetchUnacknowledgedMoments exactly —
  // real end-to-end proof this is visible to the client (via their own ID
  // token, against the emulator's Firestore REST surface), not just
  // visible to the Admin SDK, which bypasses rules entirely.
  const emulatorReadRes = await fetch(
    `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents/games/${gameId}:runQuery`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${joiner.idToken}` },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "moments" }],
          where: {
            fieldFilter: {
              field: { fieldPath: "playerId" },
              op: "EQUAL",
              value: { stringValue: joiner.uid },
            },
          },
        },
      }),
    }
  );
  const emulatorReadBody = await emulatorReadRes.json();
  const readDocs = emulatorReadBody.filter((entry) => entry.document);
  assert.equal(readDocs.length, 1);
  console.log("PASS: the joiner's own client (own ID token) can read their joinedCase moment");

  await cleanup(gameId);
  console.log("\nAll joinedCase moment smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
