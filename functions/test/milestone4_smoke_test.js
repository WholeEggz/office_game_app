// Functional smoke test for Milestone 4's game-truth Cloud Functions
// against a live emulator suite (auth + firestore + functions must all be
// running). Not a permanent regression suite — a one-shot check that
// voting, elimination, recruitment, unmasking, and leaveGame behave as
// designed, complementing rules_test.js (access control) and
// functional_smoke_test.js (Milestone 3's createGame/addPlayer).
//
// Calls callables as real authenticated users (matching the app);
// arranges deterministic scenarios and inspects ground truth via the
// Admin SDK, which bypasses rules the same way the Cloud Functions
// themselves do.
//
//   node test/milestone4_smoke_test.js

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

async function createGameWithPlayers(creator, others, opts = {}) {
  const { gameId } = await callCallable("createGame", creator.idToken, {
    locationTag: "M4 Test Floor",
    minPlayers: 1 + others.length,
    creatorId: creator.uid,
    creatorName: "Creator",
    mafiaCount: opts.mafiaCount || 1,
    recruitmentUnlockThreshold: opts.recruitmentUnlockThreshold ?? 0.2,
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

async function testEliminationLifecycle() {
  console.log("\n--- Elimination lifecycle ---");
  const creator = await mintUserAndIdToken("ElimCreator");
  const joiner = await mintUserAndIdToken("ElimJoiner");
  const gameId = await createGameWithPlayers(creator, [joiner], { mafiaCount: 1 });
  await wait(500);

  const players = await getPlayers(gameId);
  const mafiaId = Object.keys(players).find((id) => players[id].role === "mafia");
  const villagerId = Object.keys(players).find((id) => players[id].role === "villager");
  const mafiaTok = mafiaId === creator.uid ? creator.idToken : joiner.idToken;
  const villagerTok = villagerId === creator.uid ? creator.idToken : joiner.idToken;
  assert.ok(mafiaId && villagerId, "expected exactly one mafia and one villager");

  const { proposalId } = await callCallable("proposeElimination", mafiaTok, {
    gameId,
    authorId: mafiaId,
    method: "a note on the monitor",
    targetPlayerId: villagerId,
  });

  await wait(300);
  let threadSnap = await db.collection("games").doc(gameId).collection("mafiaThread").doc(proposalId).get();
  assert.ok(threadSnap.data().agreedAt != null, "sole mafia's proposal should auto-agree");

  await callCallable("executeElimination", mafiaTok, { gameId, proposalId, playerId: mafiaId });
  await wait(300);

  let villagerSnap = await db.collection("games").doc(gameId).collection("players").doc(villagerId).get();
  assert.equal(villagerSnap.data().voteWeight, 2, "execute should drop the target's weight 3 -> 2");

  let gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().eliminationSignalExecuted, true);
  assert.equal(gameSnap.data().currentRound, 1, "round should not advance until acknowledged");

  const { accepted } = await callCallable("acknowledgeEliminationSignal", villagerTok, {
    gameId,
    playerId: villagerId,
  });
  assert.equal(accepted, true, "the real target's acknowledgement should match");
  await wait(500);

  gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().currentRound, 2, "acknowledging should resolve the round");
  assert.equal(gameSnap.data().eliminationSignalExecuted, false, "signal flags reset for the new round");

  const momentsSnap = await db
    .collection("games")
    .doc(gameId)
    .collection("moments")
    .where("playerId", "==", villagerId)
    .get();
  const types = momentsSnap.docs.map((d) => d.data().type);
  assert.ok(types.includes("targetedByMafia"), "target should get a targetedByMafia moment");

  console.log("Elimination lifecycle OK");
  await cleanup(gameId);
}

async function testVotingCatchesMafia() {
  console.log("\n--- Voting catches mafia (unmask + reward + game end) ---");
  const creator = await mintUserAndIdToken("VoteCreatorA");
  const p2 = await mintUserAndIdToken("VoteJoinerB");
  const p3 = await mintUserAndIdToken("VoteJoinerC");
  const gameId = await createGameWithPlayers(creator, [p2, p3], { mafiaCount: 1 });
  await wait(500);

  const players = await getPlayers(gameId);
  const all = [
    { uid: creator.uid, idToken: creator.idToken },
    { uid: p2.uid, idToken: p2.idToken },
    { uid: p3.uid, idToken: p3.idToken },
  ];
  const mafia = all.find((p) => players[p.uid].role === "mafia");
  const villagers = all.filter((p) => players[p.uid].role !== "mafia");
  assert.equal(villagers.length, 2, "expected exactly 2 villagers with mafiaCount 1 of 3");

  for (const voter of villagers) {
    await callCallable("castVote", voter.idToken, {
      gameId,
      voterId: voter.uid,
      targetPlayerId: mafia.uid,
    });
  }

  await callCallable("resolveVotesForDay", villagers[0].idToken, { gameId });
  await wait(500);

  const after = await getPlayers(gameId);
  assert.equal(after[mafia.uid].role, "villager", "caught mafia should flip to villager");
  assert.equal(after[mafia.uid].wasUnmasked, true);
  for (const voter of villagers) {
    assert.equal(after[voter.uid].voteWeight, 4, `correct voter ${voter.uid} should be rewarded 3 -> 4`);
  }

  const gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().status, "ended", "no living mafia left — villagers should win immediately");
  assert.equal(gameSnap.data().winner, "villagers");

  const momentsSnap = await db.collection("games").doc(gameId).collection("moments").get();
  const rewardMoments = momentsSnap.docs.filter((d) => d.data().type === "correctVoteReward");
  assert.equal(rewardMoments.length, 2, "both correct voters should get a correctVoteReward moment");
  const finaleMoments = momentsSnap.docs.filter((d) => d.data().type === "finaleWin" || d.data().type === "finaleLoss");
  assert.equal(finaleMoments.length, 3, "every player should get a finale moment once the game ends");

  console.log("Voting-catches-mafia OK");
  await cleanup(gameId);
}

async function testVotingHitsVillager() {
  console.log("\n--- Voting hits a villager (weight erosion) ---");
  const creator = await mintUserAndIdToken("ErodeCreator");
  const p2 = await mintUserAndIdToken("ErodeJoinerB");
  const p3 = await mintUserAndIdToken("ErodeJoinerC");
  const gameId = await createGameWithPlayers(creator, [p2, p3], { mafiaCount: 1 });
  await wait(500);

  const players = await getPlayers(gameId);
  const all = [
    { uid: creator.uid, idToken: creator.idToken },
    { uid: p2.uid, idToken: p2.idToken },
    { uid: p3.uid, idToken: p3.idToken },
  ];
  const villagers = all.filter((p) => players[p.uid].role === "villager");
  const target = villagers[0];
  const voter = villagers[1] || all.find((p) => players[p.uid].role === "mafia");

  await callCallable("castVote", voter.idToken, { gameId, voterId: voter.uid, targetPlayerId: target.uid });
  await callCallable("resolveVotesForDay", voter.idToken, { gameId });
  await wait(500);

  const after = await getPlayers(gameId);
  assert.equal(after[target.uid].voteWeight, 2, "villager hit by a vote should erode 3 -> 2");
  assert.equal(after[target.uid].role, "villager", "should stay a villager, not get unmasked");

  console.log("Voting-hits-villager OK");
  await cleanup(gameId);
}

async function testRecruitmentLifecycle() {
  console.log("\n--- Recruitment lifecycle (+ cellViews fan-out) ---");
  const creator = await mintUserAndIdToken("RecruitCreator");
  const others = await Promise.all(
    ["RecruitB", "RecruitC", "RecruitD", "RecruitE", "RecruitF"].map((n) => mintUserAndIdToken(n))
  );
  // 1 mafia : 5 villagers = 0.2 ratio, at the default recruitmentUnlockThreshold.
  const gameId = await createGameWithPlayers(creator, others, { mafiaCount: 1 });
  await wait(500);

  const players = await getPlayers(gameId);
  const all = [{ uid: creator.uid, idToken: creator.idToken }, ...others];
  const mafia = all.find((p) => players[p.uid].role === "mafia");
  const target = all.find((p) => players[p.uid].role === "villager");

  const { proposalId } = await callCallable("proposeRecruitment", mafia.idToken, {
    gameId,
    recruiterId: mafia.uid,
    targetPlayerId: target.uid,
    sign: "a specific pen on their desk",
  });
  await wait(300);

  await callCallable("executeRecruitment", mafia.idToken, { gameId, proposalId, playerId: mafia.uid });
  await wait(300);

  let targetSnap = await db.collection("games").doc(gameId).collection("players").doc(target.uid).get();
  assert.equal(targetSnap.data().pendingRecruiterId, mafia.uid);

  const { accepted } = await callCallable("respondToRecruitment", target.idToken, {
    gameId,
    playerId: target.uid,
    accept: true,
  });
  assert.equal(accepted, true);
  await wait(500);

  const after = await getPlayers(gameId);
  assert.equal(after[target.uid].role, "mafia", "accepting should flip the target to mafia");
  assert.equal(after[target.uid].recruiterId, mafia.uid);
  assert.ok(after[mafia.uid].recruitedPlayerIds.includes(target.uid));

  const gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().currentRound, 2, "responding should resolve the round");

  // cellViews: both sides of the new link should see each other's real role.
  const mafiaCellView = await db.collection("games").doc(gameId).collection("cellViews").doc(mafia.uid).get();
  assert.equal(mafiaCellView.data().knownRoles[target.uid], "mafia");
  const targetCellView = await db.collection("games").doc(gameId).collection("cellViews").doc(target.uid).get();
  assert.equal(targetCellView.data().knownRoles[mafia.uid], "mafia");

  // Now catch the ORIGINAL recruiter by a villager vote — this is the
  // fan-out case: the recruit's cellViews must pick up the recruiter's
  // new (unmasked) role even though the write only touches the recruiter's
  // own doc.
  const villagerVoters = all.filter((p) => p.uid !== mafia.uid && p.uid !== target.uid).slice(0, 2);
  for (const voter of villagerVoters) {
    await callCallable("castVote", voter.idToken, {
      gameId,
      voterId: voter.uid,
      targetPlayerId: mafia.uid,
    });
  }
  await callCallable("resolveVotesForDay", villagerVoters[0].idToken, { gameId });
  await wait(500);

  const targetCellViewAfterUnmask = await db
    .collection("games")
    .doc(gameId)
    .collection("cellViews")
    .doc(target.uid)
    .get();
  assert.equal(
    targetCellViewAfterUnmask.data().knownRoles[mafia.uid],
    "villager",
    "recruit's cellViews should fan-out-update once their recruiter is unmasked"
  );

  console.log("Recruitment lifecycle + cellViews fan-out OK");
  await cleanup(gameId);
}

async function testLeaveGame() {
  console.log("\n--- leaveGame triggers game-end check ---");
  const creator = await mintUserAndIdToken("LeaveCreatorA");
  const p2 = await mintUserAndIdToken("LeaveJoinerB");
  const gameId = await createGameWithPlayers(creator, [p2], { mafiaCount: 1 });
  await wait(500);

  const players = await getPlayers(gameId);
  const all = [{ uid: creator.uid, idToken: creator.idToken }, { uid: p2.uid, idToken: p2.idToken }];
  const mafia = all.find((p) => players[p.uid].role === "mafia");

  await callCallable("leaveGame", mafia.idToken, { gameId, playerId: mafia.uid });
  await wait(500);

  const gameSnap = await db.collection("games").doc(gameId).get();
  assert.equal(gameSnap.data().status, "ended", "the only mafia leaving should end the game");
  assert.equal(gameSnap.data().winner, "villagers");

  console.log("leaveGame game-end check OK");
  await cleanup(gameId);
}

async function main() {
  await testEliminationLifecycle();
  await testVotingCatchesMafia();
  await testVotingHitsVillager();
  await testRecruitmentLifecycle();
  await testLeaveGame();
  console.log("\nAll Milestone 4 functional smoke checks passed.");
}

main()
  .catch((err) => {
    console.error("\nFAILED:", err);
    process.exitCode = 1;
  })
  .finally(() => process.exit());
