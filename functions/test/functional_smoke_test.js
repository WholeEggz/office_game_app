// Functional smoke test for createGame/addPlayer/syncPlayerViews against a
// live emulator suite (auth + firestore + functions must all be running).
// Not a permanent regression suite — a one-shot check that the actual role
// draw and publicPlayers/cellViews sync behave as designed, complementing
// rules_test.js (which only checks access control on hand-seeded data).
// Calls the callables as a real authenticated caller (matching the app);
// inspects results via the Admin SDK, which bypasses rules the same way
// the Cloud Functions themselves do — this script needs ground truth, not
// a redacted view.
//
//   node test/functional_smoke_test.js

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
  return { uid: mint.uid, idToken: exchange.idToken };
}

async function callCallable(name, idToken, data) {
  const res = await fetch(`${FUNCTIONS_BASE}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
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

async function main() {
  const creator = await mintUserAndIdToken("Creator");
  const joiner = await mintUserAndIdToken("Joiner");

  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "Smoke Test Floor",
    minPlayers: 2,
    creatorId: creator.uid,
    creatorName: "Creator",
    mafiaCount: 1,
  });
  console.log(`Created game ${gameId}`);
  const gameRef = db.collection("games").doc(gameId);

  let gameSnap = await gameRef.get();
  assert.equal(gameSnap.data().status, "recruiting", "game should still be recruiting with 1/2 players");
  assert.equal(gameSnap.data().creatorCountry, "", "creatorCountry defaults to '' when omitted");
  assert.equal(gameSnap.data().creatorCity, "", "creatorCity defaults to '' when omitted");
  assert.equal(
    gameSnap.data().creatorCompanyOrOffice,
    "",
    "creatorCompanyOrOffice defaults to '' when omitted"
  );

  await callCallable("addPlayer", joiner.idToken, {
    gameId,
    playerId: joiner.uid,
    name: "Joiner",
  });

  // Give the syncPlayerViews trigger a moment to fire.
  await new Promise((r) => setTimeout(r, 1500));

  gameSnap = await gameRef.get();
  assert.equal(gameSnap.data().status, "active", "game should auto-activate once minPlayers is reached");

  const trueDocsSnap = await gameRef.collection("players").get();
  const roles = trueDocsSnap.docs.map((d) => d.data().role);
  assert.equal(roles.filter((r) => r === "mafia").length, 1, "exactly one mafia member should be drawn");
  assert.equal(roles.filter((r) => r === "villager").length, 1, "exactly one villager should remain");

  const publicDocsSnap = await gameRef.collection("publicPlayers").get();
  assert.equal(publicDocsSnap.size, 2, "publicPlayers should mirror both true docs");
  for (const doc of publicDocsSnap.docs) {
    const data = doc.data();
    assert.equal(data.role, "villager", `publicPlayers should hide ${doc.id}'s real role`);
    assert.equal(data.voteWeight, 3, `publicPlayers should show the starting vote weight for ${doc.id}`);
  }

  const cellViewsSnap = await gameRef.collection("cellViews").get();
  assert.equal(cellViewsSnap.size, 2, "cellViews should exist for both players");
  for (const doc of cellViewsSnap.docs) {
    assert.deepEqual(
      doc.data().knownRoles,
      {},
      `cellViews.knownRoles for ${doc.id} should be empty — no recruitment exists yet (Milestone 4)`
    );
  }

  // Name uniqueness + duplicate-join guards.
  await assert.rejects(
    () => callCallable("addPlayer", joiner.idToken, { gameId, playerId: "someone-else", name: "Joiner" }),
    (err) => err.code === "ALREADY_EXISTS",
    "duplicate display name should be rejected"
  );
  await assert.rejects(
    () => callCallable("addPlayer", joiner.idToken, { gameId, playerId: joiner.uid, name: "Joiner Again" }),
    (err) => err.code === "ALREADY_EXISTS",
    "re-adding an already-joined playerId should be rejected"
  );

  await gameRef.collection("players").doc(creator.uid).delete();
  await gameRef.collection("players").doc(joiner.uid).delete();
  await new Promise((r) => setTimeout(r, 500));
  await gameRef.delete();

  console.log("--- createGame(creatorCountry/City/CompanyOrOffice) ---");
  const { gameId: locatedGameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "Smoke Test Floor With Location",
    minPlayers: 4,
    creatorId: creator.uid,
    creatorName: "Creator",
    creatorCountry: "Poland",
    creatorCity: "Warsaw",
    creatorCompanyOrOffice: "Acme Corp",
  });
  const locatedGameSnap = await db.collection("games").doc(locatedGameId).get();
  assert.equal(locatedGameSnap.data().creatorCountry, "Poland");
  assert.equal(locatedGameSnap.data().creatorCity, "Warsaw");
  assert.equal(locatedGameSnap.data().creatorCompanyOrOffice, "Acme Corp");
  console.log("PASS: creatorCountry/City/CompanyOrOffice persist when sent");
  await db.collection("games").doc(locatedGameId).collection("players").doc(creator.uid).delete();
  await db.collection("games").doc(locatedGameId).delete();

  console.log("All functional smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("FAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
