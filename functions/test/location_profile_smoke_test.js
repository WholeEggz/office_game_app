// Functional smoke test for saveLocationProfile against a live emulator
// suite (auth + firestore + functions must all be running). Complements
// rules_test.js (access control on already-seeded data) by actually
// calling the callable and checking its real upsert/normalization
// behavior, not just what the rules allow.
//
//   node test/location_profile_smoke_test.js

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
const FIRESTORE_BASE = `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

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

async function cleanup(uids) {
  for (const collection of ["locations_countries", "locations_cities", "locations_companies"]) {
    for (const id of ["poland", "warsaw", "acme corp"]) {
      await db.collection(collection).doc(id).delete().catch(() => {});
    }
  }
  for (const uid of uids) {
    await db.collection("users").doc(uid).delete().catch(() => {});
  }
}

async function main() {
  const alice = await mintUserAndIdToken("Alice");
  const bob = await mintUserAndIdToken("Bob");

  console.log("--- saveLocationProfile writes users/{uid} and the lookup docs ---");
  await callCallable("saveLocationProfile", alice.idToken, {
    country: "Poland",
    city: "Warsaw",
    companyOrOffice: "Acme Corp",
  });

  const aliceDoc = await db.collection("users").doc(alice.uid).get();
  assert.equal(aliceDoc.data().country, "Poland");
  assert.equal(aliceDoc.data().city, "Warsaw");
  assert.equal(aliceDoc.data().companyOrOffice, "Acme Corp");
  console.log("PASS: users/{uid} gets the 3 fields");

  const cityDoc = await db.collection("locations_cities").doc("warsaw").get();
  assert.equal(cityDoc.data().display, "Warsaw");
  assert.equal(cityDoc.data().count, 1);
  console.log("PASS: locations_cities/warsaw created with count 1 and first-seen casing");

  console.log("\n--- a second, differently-cased registration increments the same doc ---");
  await callCallable("saveLocationProfile", bob.idToken, {
    country: "poland",
    city: "WARSAW",
    companyOrOffice: "ACME CORP",
  });

  const cityDocAfter = await db.collection("locations_cities").doc("warsaw").get();
  assert.equal(cityDocAfter.data().count, 2);
  // Still "Warsaw" — the first-seen casing isn't overwritten by a later,
  // differently-cased registration converging on the same normalized id.
  assert.equal(cityDocAfter.data().display, "Warsaw");
  console.log("PASS: converges on one doc (count 2), keeping the first-seen display casing");

  const bobDoc = await db.collection("users").doc(bob.uid).get();
  assert.equal(bobDoc.data().city, "WARSAW");
  console.log("PASS: users/{uid} still stores each user's own as-typed casing");

  console.log("\n--- rules: any signed-in user can read the lookup docs, no one can write ---");
  const readRes = await fetch(`${FIRESTORE_BASE}/locations_cities/warsaw`, {
    headers: { Authorization: `Bearer ${bob.idToken}` },
  });
  assert.equal(readRes.status, 200);
  console.log("PASS: a signed-in user can read locations_cities/warsaw");

  const writeRes = await fetch(`${FIRESTORE_BASE}/locations_cities/warsaw`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${bob.idToken}` },
    body: JSON.stringify({ fields: { display: { stringValue: "Tampered" } } }),
  });
  assert.equal(writeRes.status, 403);
  console.log("PASS: a client cannot write locations_cities/warsaw directly");

  await cleanup([alice.uid, bob.uid]);
  console.log("\nAll saveLocationProfile smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
