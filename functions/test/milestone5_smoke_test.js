// Functional smoke test for Milestone 5's scheduled functions against a
// live emulator suite (auth + firestore + functions + pubsub must all be
// running — the scheduler trigger is pubsub-backed). Not a permanent
// regression suite — a one-shot check that the daily cutoff sweep and
// the mafia-reactivation sweep behave as designed.
//
// Calls the raw sweep functions directly (runDailyCutoffSweep/
// runMafiaReactivationSweep), not through an actual schedule trigger —
// the emulator doesn't simulate the passage of time against a cron
// expression, so this is the intended way to test the logic underneath
// scheduledDailyCutoffSweep/scheduledMafiaReactivationSweep.
//
//   node test/milestone5_smoke_test.js

const assert = require("node:assert/strict");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "officegameapp";

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

initializeApp({ projectId: "officegameapp" });
const db = getFirestore();

const { runDailyCutoffSweep, runMafiaReactivationSweep } = require("../lib/scheduled");

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

async function createGameWithPlayers(creator, others, opts = {}) {
  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "M5 Test Floor",
    minPlayers: 1 + others.length,
    creatorId: creator.uid,
    creatorName: "Creator",
    mafiaCount: opts.mafiaCount || 1,
    ...opts,
  });
  for (const p of others) {
    await callCallable("addPlayer", p.idToken, { gameId, playerId: p.uid, name: p.name });
  }
  return gameId;
}

async function getPlayers(gameId) {
  const snap = await db.collection("games").doc(gameId).collection("players").get();
  const out = {};
  for (const doc of snap.docs) out[doc.id] = doc.data();
  return out;
}

async function cleanup(gameId) {
  const gameRef = db.collection("games").doc(gameId);
  for (const sub of ["players", "publicPlayers", "cellViews", "mafiaThread", "votes", "observations", "moments"]) {
    const snap = await gameRef.collection(sub).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await gameRef.delete();
}

async function testDailyCutoffSweep() {
  console.log("\n--- Daily cutoff sweep ---");
  const creator = await mintUserAndIdToken("CutoffCreator");
  const joiner = await mintUserAndIdToken("CutoffJoiner");
  const gameId = await createGameWithPlayers(creator, [joiner], { mafiaCount: 1 });
  await wait(500);

  const gameRef = db.collection("games").doc(gameId);
  let gameSnap = await gameRef.get();
  assert.equal(gameSnap.data().status, "active");
  assert.ok(gameSnap.data().nextCutoffAt, "nextCutoffAt should be set once the game goes active");
  assert.equal(gameSnap.data().currentRound, 1);

  // Not due yet — a sweep right now should be a no-op.
  await runDailyCutoffSweep();
  gameSnap = await gameRef.get();
  assert.equal(gameSnap.data().currentRound, 1, "sweep should not resolve a game whose cutoff isn't due");

  // Force the cutoff into the past, as if the configured time already
  // passed, and confirm the sweep picks it up.
  await gameRef.update({ nextCutoffAt: Timestamp.fromMillis(Date.now() - 1000) });
  await runDailyCutoffSweep();
  await wait(300);

  gameSnap = await gameRef.get();
  assert.equal(gameSnap.data().currentRound, 2, "sweep should resolve a game whose cutoff is due");
  assert.ok(
    gameSnap.data().nextCutoffAt.toMillis() > Date.now(),
    "resolving should reschedule nextCutoffAt into the future"
  );

  console.log("Daily cutoff sweep OK");
  await cleanup(gameId);
}

async function testMafiaReactivationSweep() {
  console.log("\n--- Mafia reactivation sweep ---");
  const creator = await mintUserAndIdToken("ReactivateCreatorA");
  const joiner = await mintUserAndIdToken("ReactivateJoinerB");
  const other = await mintUserAndIdToken("ReactivateJoinerC");
  const gameId = await createGameWithPlayers(creator, [joiner, other], { mafiaCount: 1 });
  await wait(500);

  const players = await getPlayers(gameId);
  const all = [
    { uid: creator.uid, idToken: creator.idToken },
    { uid: joiner.uid, idToken: joiner.idToken },
    { uid: other.uid, idToken: other.idToken },
  ];
  const mafia = all.find((p) => players[p.uid].role === "mafia");

  await callCallable("setMemberActive", mafia.idToken, {
    gameId,
    playerId: mafia.uid,
    isActive: false,
  });
  await wait(300);

  const gameRef = db.collection("games").doc(gameId);
  let mafiaSnap = await gameRef.collection("players").doc(mafia.uid).get();
  assert.equal(mafiaSnap.data().isActive, false);
  assert.ok(mafiaSnap.data().inactiveUntil, "inactiveUntil should be stamped ~24h out");

  // Not due yet.
  await runMafiaReactivationSweep();
  mafiaSnap = await gameRef.collection("players").doc(mafia.uid).get();
  assert.equal(mafiaSnap.data().isActive, false, "sweep should not reactivate before inactiveUntil");

  // Force the deadline into the past and confirm the sweep reactivates.
  await gameRef
    .collection("players")
    .doc(mafia.uid)
    .update({ inactiveUntil: Timestamp.fromMillis(Date.now() - 1000) });
  await runMafiaReactivationSweep();
  await wait(300);

  mafiaSnap = await gameRef.collection("players").doc(mafia.uid).get();
  assert.equal(mafiaSnap.data().isActive, true, "sweep should reactivate once inactiveUntil has passed");
  assert.equal(mafiaSnap.data().inactiveUntil, null, "inactiveUntil should be cleared on reactivation");

  console.log("Mafia reactivation sweep OK");
  await cleanup(gameId);
}

async function testReactivationUnsticksAPendingProposal() {
  console.log("\n--- Reactivation re-checks a pending proposal ---");
  // 2 mafia: one proposes, the sole OTHER active mafia member needs to
  // accept for the proposal to agree. If that second member is marked
  // inactive first, the proposal only needs the (still-active) proposer —
  // it should auto-agree immediately. This test instead checks the
  // reverse: an inactive member does NOT block agreement, and reactivating
  // them later doesn't retroactively un-agree it (the moment the roster of
  // required members shrank, it may already have agreed).
  const creator = await mintUserAndIdToken("PendingCreatorA");
  const others = await Promise.all(
    ["PendingB", "PendingC", "PendingD"].map((n) => mintUserAndIdToken(n))
  );
  const gameId = await createGameWithPlayers(creator, others, { mafiaCount: 2 });
  await wait(500);

  const players = await getPlayers(gameId);
  const all = [{ uid: creator.uid, idToken: creator.idToken }, ...others];
  const mafiaMembers = all.filter((p) => players[p.uid].role === "mafia");
  assert.equal(mafiaMembers.length, 2);
  const [proposer, otherMafia] = mafiaMembers;
  const target = all.find((p) => players[p.uid].role === "villager");

  // Mark the second mafia member inactive first, so the proposer alone
  // satisfies "every active mafia member" and the proposal auto-agrees.
  await callCallable("setMemberActive", proposer.idToken, {
    gameId,
    playerId: otherMafia.uid,
    isActive: false,
  });
  const { proposalId } = await callCallable("proposeElimination", proposer.idToken, {
    gameId,
    authorId: proposer.uid,
    method: "a note on the monitor",
    targetPlayerId: target.uid,
  });
  await wait(300);

  const gameRef = db.collection("games").doc(gameId);
  let entrySnap = await gameRef.collection("mafiaThread").doc(proposalId).get();
  assert.ok(entrySnap.data().agreedAt != null, "proposal should auto-agree with only one active mafia member");

  // Reactivating the other member later shouldn't change an already-agreed
  // proposal — maybeMarkAgreedInTx is a no-op once agreedAt is set.
  await gameRef
    .collection("players")
    .doc(otherMafia.uid)
    .update({ inactiveUntil: Timestamp.fromMillis(Date.now() - 1000) });
  await runMafiaReactivationSweep();
  await wait(300);

  const reactivatedSnap = await gameRef.collection("players").doc(otherMafia.uid).get();
  assert.equal(reactivatedSnap.data().isActive, true);
  entrySnap = await gameRef.collection("mafiaThread").doc(proposalId).get();
  assert.ok(entrySnap.data().agreedAt != null, "reactivation should not un-agree an already-agreed proposal");

  console.log("Reactivation re-check OK");
  await cleanup(gameId);
}

async function main() {
  await testDailyCutoffSweep();
  await testMafiaReactivationSweep();
  await testReactivationUnsticksAPendingProposal();
  console.log("\nAll Milestone 5 functional smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
