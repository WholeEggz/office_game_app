// Functional smoke test for restricted cases against a live emulator
// suite (auth + firestore + functions must all be running). Complements
// rules_test.js (access control on already-seeded data) by actually
// calling createGame/addPlayer/verifyCasePassphrase and checking their
// real validation, not just what the rules allow.
//
//   node test/restricted_case_smoke_test.js

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
  for (const sub of ["players", "publicPlayers", "cellViews", "passphrase"]) {
    const snap = await gameRef.collection(sub).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await gameRef.delete();
}

async function main() {
  console.log("--- createGame(isRestricted) ---");
  const creator = await mintUserAndIdToken("RestrictedCreator");
  const joiner = await mintUserAndIdToken("RestrictedJoiner");

  await assert.rejects(
    () =>
      callCallable("createGame", creator.idToken, {
        locationTag: "Too Few Words Floor",
        minPlayers: 2,
        creatorId: creator.uid,
        creatorName: creator.name,
        isRestricted: true,
        passphraseWords: ["tiger", "blue"],
      }),
    /exactly 3 distinct passphrase words/
  );
  console.log("PASS: createGame rejects fewer than 3 passphrase words");

  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "Restricted Smoke Floor",
    minPlayers: 2,
    creatorId: creator.uid,
    creatorName: creator.name,
    isRestricted: true,
    passphraseWords: ["Tiger", " blue ", "MOON"],
  });

  // The actual words are never client-readable by anyone but the case's
  // own creator — checked via the Admin SDK, since firestore.rules is
  // what gates client reads on this collection.
  const passphraseSnap = await db.collection(`games/${gameId}/passphrase`).doc("secret").get();
  assert.deepEqual(passphraseSnap.data().words.sort(), ["blue", "moon", "tiger"]);
  console.log("PASS: the passphrase is stored normalized");

  const gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().creatorId, creator.uid);
  console.log("PASS: the game doc records its creatorId");

  console.log("\n--- passphrase read access (firestore.rules) ---");
  const readPassphraseAs = async (idToken) =>
    fetch(
      `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents/games/${gameId}/passphrase/secret`,
      { headers: { Authorization: `Bearer ${idToken}` } }
    );
  const creatorRead = await readPassphraseAs(creator.idToken);
  assert.equal(creatorRead.status, 200);
  console.log("PASS: the creator (admin) can read their own case's passphrase");

  const joinerRead = await readPassphraseAs(joiner.idToken);
  assert.equal(joinerRead.status, 403);
  console.log("PASS: a non-creator is still denied");

  console.log("\n--- verifyCasePassphrase ---");
  const wrongCheck = await callCallable("verifyCasePassphrase", joiner.idToken, {
    gameId,
    words: ["wrong", "words", "here"],
  });
  assert.equal(wrongCheck.matches, false);
  const rightCheck = await callCallable("verifyCasePassphrase", joiner.idToken, {
    // Order and case shouldn't matter.
    gameId,
    words: ["MOON", "Tiger", "blue"],
  });
  assert.equal(rightCheck.matches, true);
  console.log("PASS: verifyCasePassphrase matches case/whitespace/order-insensitively");

  const stillJustCreator = await db.collection(`games/${gameId}/players`).get();
  assert.equal(stillJustCreator.size, 1);
  console.log("PASS: verifyCasePassphrase never joins anyone");

  console.log("\n--- addPlayer(passphraseWords) ---");
  await assert.rejects(
    () =>
      callCallable("addPlayer", joiner.idToken, {
        gameId,
        playerId: joiner.uid,
        name: joiner.name,
      }),
    /Incorrect passphrase/
  );
  await assert.rejects(
    () =>
      callCallable("addPlayer", joiner.idToken, {
        gameId,
        playerId: joiner.uid,
        name: joiner.name,
        passphraseWords: ["wrong", "words", "here"],
      }),
    /Incorrect passphrase/
  );
  console.log("PASS: addPlayer rejects a missing or wrong passphrase");

  await callCallable("addPlayer", joiner.idToken, {
    gameId,
    playerId: joiner.uid,
    name: joiner.name,
    passphraseWords: ["blue", "MOON", "Tiger"],
  });
  const playersSnap = await db.collection(`games/${gameId}/players`).get();
  assert.equal(playersSnap.size, 2);
  console.log("PASS: addPlayer accepts the correct passphrase, case/order-insensitively");

  await cleanup(gameId);
  console.log("\nAll restricted-case functional smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
