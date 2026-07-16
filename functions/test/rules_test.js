// Adversarial tests for firestore.rules, per implementation_plan.md's call
// to "budget real time for testing these rules adversarially once built."
// Run against a live Firestore emulator (the `firestore` emulator from
// `firebase emulators:start` must already be up) with:
//
//   node test/rules_test.js
//
// Seeds data directly (bypassing rules, via withSecurityRulesDisabled),
// then exercises reads through per-uid authenticated contexts that DO
// enforce firestore.rules, asserting each one is allowed or denied.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

// Matches the project ID in .firebaserc/firebase.json — the emulator
// suite here runs with singleProjectMode, which only accepts this one.
const PROJECT_ID = "officegameapp";
const GAME_ID = "rules-test-game1";

async function main() {
  const env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });

  const results = [];
  async function check(name, fn) {
    try {
      await fn();
      results.push({ name, ok: true });
    } catch (err) {
      results.push({ name, ok: false, err });
    }
  }

  // Seed: game1 has a villager and a current (not-yet-unmasked) mafia
  // member, plus an already-unmasked former mafia member — enough to
  // exercise every branch of the mafiaThread/publicPlayers/cellViews rules.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("games").doc(GAME_ID).set({
      locationTag: "Test Floor",
      status: "active",
      minPlayers: 3,
      currentRound: 1,
    });
    await db.collection(`games/${GAME_ID}/players`).doc("villagerA").set({
      name: "Alice",
      role: "villager",
      voteWeight: 3,
      wasUnmasked: false,
      hasLeft: false,
    });
    await db.collection(`games/${GAME_ID}/players`).doc("mafiaB").set({
      name: "Bob",
      role: "mafia",
      voteWeight: 3,
      wasUnmasked: false,
      hasLeft: false,
    });
    await db.collection(`games/${GAME_ID}/players`).doc("unmaskedC").set({
      name: "Cara",
      role: "villager",
      voteWeight: 3,
      wasUnmasked: true,
      hasLeft: false,
    });
    await db.collection(`games/${GAME_ID}/publicPlayers`).doc("villagerA").set({
      name: "Alice",
      role: "villager",
      voteWeight: 3,
      wasUnmasked: false,
      hasLeft: false,
    });
    await db.collection(`games/${GAME_ID}/publicPlayers`).doc("mafiaB").set({
      name: "Bob",
      role: "villager", // redacted mirror: hidden until unmasked
      voteWeight: 3,
      wasUnmasked: false,
      hasLeft: false,
    });
    await db.collection(`games/${GAME_ID}/cellViews`).doc("mafiaB").set({ knownRoles: {} });
    await db.collection(`games/${GAME_ID}/debugRoster`).doc("mafiaB").set({
      name: "Bob",
      role: "mafia",
      wasUnmasked: false,
    });
    await db.collection(`games/${GAME_ID}/mafiaThread`).doc("entry1").set({ text: "coordinate here" });
    await db.collection(`games/${GAME_ID}/votes`).doc("vote1").set({ voterId: "villagerA" });
    await db.collection(`games/${GAME_ID}/observations`).doc("obs1").set({ text: "saw something" });
    await db.collection(`games/${GAME_ID}/moments`).doc("moment1").set({
      playerId: "villagerA",
      type: "roundEnded",
      round: 1,
      acknowledged: false,
    });
    await db.collection(`games/${GAME_ID}/reports`).doc("report1").set({
      reporterId: "villagerA",
      targetPlayerId: "mafiaB",
      reason: "test seed",
    });
    await db.collection(`games/${GAME_ID}/blocks`).doc("villagerA").set({
      blockedPlayerIds: ["mafiaB"],
    });
    await db.collection(`games/${GAME_ID}/passphrase`).doc("secret").set({
      words: ["tiger", "blue", "moon"],
    });
  });

  const villagerA = env.authenticatedContext("villagerA").firestore();
  const mafiaB = env.authenticatedContext("mafiaB").firestore();
  const unmaskedC = env.authenticatedContext("unmaskedC").firestore();
  const outsider = env.authenticatedContext("outsider").firestore();
  const anon = env.unauthenticatedContext().firestore();

  // --- true player docs: self-only ---
  await check("villager reads own true doc: allowed", () =>
    assertSucceeds(villagerA.doc(`games/${GAME_ID}/players/villagerA`).get())
  );
  await check("villager reads mafia's true doc: DENIED", () =>
    assertFails(villagerA.doc(`games/${GAME_ID}/players/mafiaB`).get())
  );
  await check("outsider reads any true doc: DENIED", () =>
    assertFails(outsider.doc(`games/${GAME_ID}/players/villagerA`).get())
  );
  await check("unauthenticated reads a true doc: DENIED", () =>
    assertFails(anon.doc(`games/${GAME_ID}/players/villagerA`).get())
  );
  await check("client cannot write a true doc directly: DENIED", () =>
    assertFails(villagerA.doc(`games/${GAME_ID}/players/villagerA`).update({ role: "mafia" }))
  );

  // --- publicPlayers: browsable by any signed-in user, even non-members ---
  await check("outsider (non-member) reads publicPlayers: allowed", () =>
    assertSucceeds(outsider.doc(`games/${GAME_ID}/publicPlayers/mafiaB`).get())
  );
  await check("unauthenticated reads publicPlayers: DENIED", () =>
    assertFails(anon.doc(`games/${GAME_ID}/publicPlayers/mafiaB`).get())
  );

  // --- cellViews: strictly self-only ---
  await check("mafia reads own cellViews: allowed", () =>
    assertSucceeds(mafiaB.doc(`games/${GAME_ID}/cellViews/mafiaB`).get())
  );
  await check("villager reads someone else's cellViews: DENIED", () =>
    assertFails(villagerA.doc(`games/${GAME_ID}/cellViews/mafiaB`).get())
  );

  // --- debugRoster: any signed-in user can read (real safety is the
  // write-side emulator gate in functions/index.js — this collection is
  // empty in a real deployment regardless of who can technically query
  // it). Deliberately not member-gated: the tester operating the debug
  // role switcher is never actually a member of a quick-started game
  // (registerNewPlayer never switches the current session), so a
  // member-only rule made the roster view permanently empty for exactly
  // the flow it exists for. ---
  await check("member reads debugRoster: allowed", () =>
    assertSucceeds(villagerA.doc(`games/${GAME_ID}/debugRoster/mafiaB`).get())
  );
  await check("non-member (but signed in) reads debugRoster: allowed", () =>
    assertSucceeds(outsider.doc(`games/${GAME_ID}/debugRoster/mafiaB`).get())
  );
  await check("unauthenticated reads debugRoster: DENIED", () =>
    assertFails(anon.doc(`games/${GAME_ID}/debugRoster/mafiaB`).get())
  );
  await check("client cannot write debugRoster directly: DENIED", () =>
    assertFails(mafiaB.doc(`games/${GAME_ID}/debugRoster/mafiaB`).update({ role: "villager" }))
  );

  // --- mafiaThread: current (not-yet-unmasked) mafia only ---
  await check("current mafia reads mafiaThread: allowed", () =>
    assertSucceeds(mafiaB.collection(`games/${GAME_ID}/mafiaThread`).get())
  );
  await check("villager reads mafiaThread: DENIED", () =>
    assertFails(villagerA.collection(`games/${GAME_ID}/mafiaThread`).get())
  );
  await check("just-unmasked former mafia reads mafiaThread: DENIED", () =>
    assertFails(unmaskedC.collection(`games/${GAME_ID}/mafiaThread`).get())
  );

  // --- votes/observations: member-only, not role-gated ---
  await check("member reads votes: allowed", () =>
    assertSucceeds(villagerA.collection(`games/${GAME_ID}/votes`).get())
  );
  await check("non-member reads votes: DENIED", () =>
    assertFails(outsider.collection(`games/${GAME_ID}/votes`).get())
  );
  await check("member reads observations: allowed", () =>
    assertSucceeds(villagerA.collection(`games/${GAME_ID}/observations`).get())
  );
  await check("non-member reads observations: DENIED", () =>
    assertFails(outsider.collection(`games/${GAME_ID}/observations`).get())
  );

  // --- moments: strictly self-only, but a client CAN write its own ---
  await check("player reads own moment: allowed", () =>
    assertSucceeds(villagerA.doc(`games/${GAME_ID}/moments/moment1`).get())
  );
  await check("another player reads someone else's moment: DENIED", () =>
    assertFails(mafiaB.doc(`games/${GAME_ID}/moments/moment1`).get())
  );
  await check("player acknowledges (updates) their own moment: allowed", () =>
    assertSucceeds(villagerA.doc(`games/${GAME_ID}/moments/moment1`).update({ acknowledged: true }))
  );
  await check("player updates someone else's moment: DENIED", () =>
    assertFails(mafiaB.doc(`games/${GAME_ID}/moments/moment1`).update({ acknowledged: true }))
  );
  await check("player creates their own moment (e.g. recordReentry): allowed", () =>
    assertSucceeds(
      villagerA.collection(`games/${GAME_ID}/moments`).add({
        playerId: "villagerA",
        type: "reenteredCase",
        round: 1,
        acknowledged: false,
      })
    )
  );
  await check("player creates a moment claiming to be someone else: DENIED", () =>
    assertFails(
      villagerA.collection(`games/${GAME_ID}/moments`).add({
        playerId: "mafiaB",
        type: "finaleWin",
        round: 1,
        acknowledged: false,
      })
    )
  );

  // --- game doc: browsable by any signed-in user ---
  await check("outsider reads the game doc: allowed", () =>
    assertSucceeds(outsider.doc(`games/${GAME_ID}`).get())
  );
  await check("unauthenticated reads the game doc: DENIED", () =>
    assertFails(anon.doc(`games/${GAME_ID}`).get())
  );

  // --- reports: never client-readable or writable, by anyone, including
  // the reporter themselves — written only by the reportPlayer Cloud
  // Function via the Admin SDK bypass. No in-app moderator view exists to
  // grant read access to. ---
  await check("reporter reads their own report: DENIED", () =>
    assertFails(villagerA.doc(`games/${GAME_ID}/reports/report1`).get())
  );
  await check("outsider reads a report: DENIED", () =>
    assertFails(outsider.doc(`games/${GAME_ID}/reports/report1`).get())
  );
  await check("client cannot write a report directly: DENIED", () =>
    assertFails(
      villagerA.doc(`games/${GAME_ID}/reports/report2`).set({
        reporterId: "villagerA",
        targetPlayerId: "mafiaB",
        reason: "trying to bypass the function",
      })
    )
  );

  // --- blocks: self-read/write only, both directions client-only (no
  // Cloud Function ever touches this — a viewer's own preference, not
  // game truth) ---
  await check("viewer reads their own block list: allowed", () =>
    assertSucceeds(villagerA.doc(`games/${GAME_ID}/blocks/villagerA`).get())
  );
  await check("viewer writes their own block list: allowed", () =>
    assertSucceeds(
      villagerA.doc(`games/${GAME_ID}/blocks/villagerA`).set({ blockedPlayerIds: ["mafiaB"] })
    )
  );
  await check("outsider reads someone else's block list: DENIED", () =>
    assertFails(outsider.doc(`games/${GAME_ID}/blocks/villagerA`).get())
  );
  await check("outsider writes someone else's block list: DENIED", () =>
    assertFails(
      outsider.doc(`games/${GAME_ID}/blocks/villagerA`).set({ blockedPlayerIds: [] })
    )
  );
  await check("unauthenticated reads a block list: DENIED", () =>
    assertFails(anon.doc(`games/${GAME_ID}/blocks/villagerA`).get())
  );

  // --- users/{userId}: this device's persisted display name
  // (FirebaseAuthService.resumeSession), self-read/write only — top-level,
  // not nested under games/{gameId}, since a display name belongs to a
  // person/device, not a specific case. ---
  await check("viewer reads their own display name: allowed", () =>
    assertSucceeds(villagerA.doc("users/villagerA").get())
  );
  await check("viewer writes their own display name: allowed", () =>
    assertSucceeds(villagerA.doc("users/villagerA").set({ displayName: "Alice" }))
  );
  await check("outsider reads someone else's display name: DENIED", () =>
    assertFails(outsider.doc("users/villagerA").get())
  );
  await check("outsider writes someone else's display name: DENIED", () =>
    assertFails(outsider.doc("users/villagerA").set({ displayName: "Mallory" }))
  );
  await check("unauthenticated reads a display name: DENIED", () =>
    assertFails(anon.doc("users/villagerA").get())
  );

  // --- passphrase: a restricted case's actual words, never client-
  // readable at all, even by the case's own members — only
  // addPlayer/verifyCasePassphrase (Admin SDK bypass) ever touch this. ---
  await check("member reads the case passphrase: DENIED", () =>
    assertFails(villagerA.doc(`games/${GAME_ID}/passphrase/secret`).get())
  );
  await check("outsider reads the case passphrase: DENIED", () =>
    assertFails(outsider.doc(`games/${GAME_ID}/passphrase/secret`).get())
  );
  await check("unauthenticated reads the case passphrase: DENIED", () =>
    assertFails(anon.doc(`games/${GAME_ID}/passphrase/secret`).get())
  );
  await check("client cannot write the case passphrase directly: DENIED", () =>
    assertFails(
      villagerA.doc(`games/${GAME_ID}/passphrase/secret`).set({ words: ["a", "b", "c"] })
    )
  );

  const failed = results.filter((r) => !r.ok);
  for (const r of results) {
    console.log(`${r.ok ? "PASS" : "FAIL"} — ${r.name}`);
    if (!r.ok) console.error(r.err);
  }
  console.log(`\n${results.length - failed.length}/${results.length} passed`);

  // This runs against the same emulator instance a developer may be
  // manually testing against — clear out the seeded game so it doesn't
  // linger in their Firestore emulator UI afterward. Best-effort: the
  // testing client isn't the Admin SDK, so no recursiveDelete — delete
  // each seeded doc individually instead.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const paths = [
      `games/${GAME_ID}/players/villagerA`,
      `games/${GAME_ID}/players/mafiaB`,
      `games/${GAME_ID}/players/unmaskedC`,
      `games/${GAME_ID}/publicPlayers/villagerA`,
      `games/${GAME_ID}/publicPlayers/mafiaB`,
      `games/${GAME_ID}/cellViews/mafiaB`,
      `games/${GAME_ID}/debugRoster/mafiaB`,
      `games/${GAME_ID}/mafiaThread/entry1`,
      `games/${GAME_ID}/votes/vote1`,
      `games/${GAME_ID}/observations/obs1`,
      `games/${GAME_ID}/reports/report1`,
      `games/${GAME_ID}/reports/report2`,
      `games/${GAME_ID}/blocks/villagerA`,
      `games/${GAME_ID}/passphrase/secret`,
      `games/${GAME_ID}`,
      "users/villagerA",
    ];
    await Promise.all(paths.map((p) => db.doc(p).delete()));
    const momentsSnap = await db.collection(`games/${GAME_ID}/moments`).get();
    await Promise.all(momentsSnap.docs.map((d) => d.ref.delete()));
  });
  await env.cleanup();

  if (failed.length > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
