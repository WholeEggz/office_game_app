# Office Game — Implementation Plan

Based on `office_game_concept_season1.md`. Written for a solo developer (comfortable but not deeply experienced), moving fast, building in Flutter.

## Guiding principle: validate before you build

The concept doc already names the biggest risk: the vote-weight erosion system and forced-convergence mechanics might not actually be fun in practice. Nothing below skips Phase 0 — running the low-tech pilot is the cheapest insurance against building the wrong thing, even on a fast timeline. It can run in parallel with early technical setup, so it doesn't cost you calendar time.

## Phase 0 — Season Zero (low-tech pilot)

**Status: complete.** Exit criteria below were met; Phase 1a's local prototype and this document's Phase 1b scope both proceed on that basis.

**Goal:** validate the core loop with real people before writing game-logic code.

- Recruit the founding group (the kitchen conversation crowd) — aim for 8–15 players, the minimum needed to make mafia:villager ratios meaningful.
- Run the game manually: a shared spreadsheet for vote weights, a group chat (Slack/Teams/WhatsApp) for mafia coordination and the observation log, paper or sticky notes for the physical elimination signal.
- Track specifically: does the weight-erosion system feel fair at 0? Is the 1:5 recruitment threshold roughly right? Does the elimination-signal mechanic feel fun or intrusive during a real workday? Does the cell-structure recruitment chain hold up with real people forgetting who recruited whom?
- Duration: roughly 2–3 weeks (a few days to recruit and explain rules, one full round-trip of a season to gather signal).
- Can run in parallel with: Flutter project scaffolding, Firebase project setup, App Store / Play Store developer account creation (see Phase 1) — none of that depends on Season Zero's outcome.

**Exit criteria to move on:** most players say they'd play again; at least one full recruitment cycle happened without the game collapsing; no one reported feeling genuinely excluded or uncomfortable.

## Phase 1a — Local, no-backend prototype

**Scope: an interactive, playable version of the rules with zero backend**, so the game logic can be validated and iterated on in code before any server exists. This sits between Phase 0 and the real MVP: Phase 0 tests whether the *rules* are fun with a spreadsheet and a chat app; Phase 1a tests the same rules through an actual app, on one device, switching between player identities to simulate multiple people.

**Delivered:** a working scaffold at `office_game_app/` in this project folder implements this phase already. It's a plain Flutter app (Provider for DI, no external services) with:

- Domain models (`lib/domain/models/`) — `Player`, `Game`, `Observation`, `MafiaThreadEntry`, `Vote` — the same shapes both the local and future Firebase implementations will use.
- Two abstract interfaces (`lib/domain/repositories/`) — `GameRepository` and `AuthService` — that everything else in the app depends on. This is the seam: swap what's behind the interface, and no UI code changes.
- `LocalGameRepository` and `LocalAuthService` (`lib/data/local/`) — a full in-memory implementation of every rule from the concept doc: vote-weight erosion, elimination-method signaling, mafia coordination with active/inactive handling, recruitment, unmasking, and the 3-round observation log.
- A debug-only role switcher (`lib/ui/role_switcher/`) that lets you create a game, add several named players on one device, start the game, and jump into each player's view — the "temporary option to switch between users in different roles on one device" this phase was built around.
- `FirebaseGameRepository` / `FirebaseAuthService` stubs (`lib/data/firebase/`) — same interfaces, every method currently throws `UnimplementedError`. They exist now so the shape of the Phase 1b migration is visible and doesn't require inventing new architecture later.

See `office_game_app/README.md` for setup steps (`flutter create .` to generate platform folders, since those weren't hand-written) and the full Phase 1b migration checklist.

**Why this phase exists as its own step, not folded into Phase 0 or Phase 1b:** it lets you find rules bugs and UX dead-ends (e.g. "what does a weight-0 villager actually see?") by writing and running real code, without yet paying for Firebase setup, security-rule design, or store accounts. It's also the cheapest way to keep "move fast" honest — you're producing working software from day one, just not networked software yet.

**Status:** exit criteria below were met — Phase 1b is now underway (see below). App-itself gaps tracked here, separate from the Firebase/deployment work:

- ~~Game lifecycle: define and implement a win/end condition, lock a finished game against further actions, build the finale ceremony.~~ Done.
- ~~Player lifecycle: a way to leave a game, and auto-expiry for the mafia "inactive" toggle instead of a standing manual switch.~~ Done.
- ~~Error handling: every repository action that can throw a `StateError` should show a message, not crash the screen.~~ Done.
- ~~Round/day cutoff: resolve votes automatically at a configured daily time instead of relying only on a manual button.~~ Done.
- **Remove/gate temporary & debug-only elements — deliberately deferred, not blocking Phase 1b.** The "Reveal roles (debug)" toggle, the "Resolve today's votes (debug)" button, "Quick start (8 players)", and the tester/role-switcher flow all stay as-is through Phase 1b on purpose: they're the tool for exercising the real backend the same way they've exercised the local one (see Phase 1b's "Auth and the debug switcher" section below for how they keep working against Firebase). The gate — a build flag, a settings toggle, a secret gesture — still needs to happen, just later: before any real coworker who isn't in on the testing gets a build.
- ~~Numeric form fields (case creation) silently fall back to defaults on bad input instead of showing a validation error.~~ Done — villagers/mafia/daily-cutoff fields now show a live inline warning on unparseable input, but still fall back the same way they always did rather than blocking submission (a deliberate choice to keep the never-blocks property).
- **Minor polish, remaining** — most SVG seals/marks under `assets/graphics/` are still simple placeholder shapes; `mafia_seal.svg` got a redesign (matching `villager_seal.svg`'s compass-rose framing, with a domino-mask motif and a crack through the seal, replacing a shape that didn't read clearly as anything), the rest are deliberately left as-is for now.

**Exit criteria to move on to Phase 1b:** you've played at least one full local round-trip (create → join → start → vote → resolve → recruit → unmask) yourself across a few switched identities, the rules as coded match what Season Zero validated, and nothing in the local implementation feels like it needs a fundamentally different data shape. Met.

## Phase 1b — Firebase backend integration

**Scope: replace the local stubs with a real backend**, multi-device, multi-game-per-location (section 3 of the concept doc already shaped the data model for this — nothing here should require restructuring `Game`/`Player`/etc.).

### Recommended stack

- **Client:** Flutter (your preference, and a solid one — one codebase for iOS + Android, mature ecosystem, good for a solo dev moving fast).
- **Backend: Firebase** (Firestore + Cloud Functions + Firebase Auth + Cloud Messaging). For a solo, moderately-experienced developer trying to move fast, a backend-as-a-service beats standing up your own server — no infra to manage, generous free tier for a pilot-sized user base, and Firestore's realtime listeners give you live game-state updates without building your own websocket layer. Supabase is a reasonable alternative if you'd rather work in SQL, but Firebase + Flutter is the more heavily documented combination, which matters when you're not yet an advanced developer.
- **Auth:** phone number or email + display name only. No corporate SSO, deliberately (design pillar #3).

### The highest-risk technical piece: redaction can't live in security rules alone

This game only works if hidden information stays hidden — a bug that lets a villager's client read the mafia's thread, or the full roster, doesn't just annoy someone, it breaks the game outright for that session. But the specific risk is sharper than "write careful security rules": **Firestore security rules are a binary allow/deny on a whole document, not a per-viewer field transform.** `LocalGameRepository._publicView` (`lib/data/local/local_game_repository.dart`) returns *different data to different readers of the same player* — role forced to `villager` unless the viewer is that player, an already-unmasked player, or a cell-linked mafia member. There is no security rule that says "let anyone read this document, but each reader sees different field values." Reproducing this needs an actual data-model answer, not just careful rules — that's what the shape below is for.

Realistic options for "different readers, different data" are: (a) route every affected read through a Cloud Function/callable API instead of a native listener, losing realtime streaming, or (b) maintain separate documents per audience, kept in sync server-side. Since `watchVisiblePlayers`/`watchGame`/`watchGames` are `Stream`-returning in `GameRepository` and the UI depends on that for live updates, (b) is the only option that doesn't force rewriting every screen that consumes those streams.

**Data model, per game, per player:**

- `games/{gameId}/players/{playerId}` — the *true* doc: real role, real vote weight, `recruiterId`, `recruitedPlayerIds`, `pendingRecruiterId`. Readable only by `playerId` themself. Writable only by Cloud Functions — the Admin SDK bypasses rules, so client writes to this path are denied outright (this is also where "vote-weight subtraction/role assignment must be server-side" actually gets enforced, not just stated as a principle).
- `games/{gameId}/publicPlayers/{playerId}` — a redacted mirror: name, `isActive`, `wasUnmasked`, `hasLeft`, `joinedAt`, role forced to `villager` unless `wasUnmasked`, vote weight forced to the starting value. Readable by any player who has joined that game. A Firestore `onWrite` trigger on the true doc keeps this in sync — exactly `_publicView`, moved server-side and run once per write instead of once per read.
- `games/{gameId}/cellViews/{viewerId}` — small, mafia-only: the true role/status of exactly that viewer's `recruiterId` and members of `recruitedPlayerIds` (at most a couple of entries). Same trigger maintains it. Reproduces the `knowsCellLink` branch of `LocalGameRepository._visiblePlayers` without exposing it to anyone else.
- `FirebaseGameRepository.watchVisiblePlayers` composes `publicPlayers` + (if the viewer is mafia) `cellViews/{viewerId}` client-side into the same `List<Player>` shape the UI already expects — no UI code changes, matching the seam this whole architecture is built around.
- `games/{gameId}` itself — location tag, status, min-player threshold, narrative skin, created-at, plus the already-public forewarning fields (`eliminationMethodDescription`, `eliminationSignalExecuted`/`Confirmed`, `recruitmentSignDescription`, `recruitmentSignExecuted`/`Confirmed`) — these are already method/sign-only, never-the-target by design (concept doc §6), so the doc itself can be readable by any game member with no redaction needed.
- `games/{gameId}/mafiaThread/*` doesn't need the mirror treatment — it's a genuine binary gate (mafia or not), which a rule *can* express directly by `get()`-ing the requester's own true player doc:
  ```
  allow read: if get(/databases/$(db)/documents/games/$(gameId)/players/$(request.auth.uid)).data.role == 'mafia'
              && get(...).data.wasUnmasked == false;
  ```
- `games/{gameId}/votes/*` and `games/{gameId}/observations/*` aren't secret per the concept doc (voting history is permanent and visible to everyone; observations are ephemeral, not role-gated) — plain "readable by any current game member" rules. Observation purging: a scheduled Cloud Function deletes entries older than 3 rounds, a real deletion not just a UI filter.

Budget real time for testing these rules adversarially once built (villager tries to read another player's true doc/role; non-member tries to read a game's roster; a just-unmasked player confirms they lose `mafiaThread` access; a mafia member confirms they see only their own 1–2 cell links) — this is the one piece of Phase 1b where a shortcut directly breaks the game, not just the UX.

### Cloud Functions inventory

Anything that decides game truth must be a callable Cloud Function, never a direct client write — checked here against the actual `GameRepository` interface (`lib/domain/repositories/game_repository.dart`) rather than left as a general principle:

- `createGame`, `addPlayer` — role draw the instant the roster hits `minPlayers` (mirrors `_autoStartIfReady`/`_activateGame`).
- `castVote`, `resolveVotesForDay` — the latter also runs on a **schedule** (daily cutoff) in addition to being callable, matching `_scheduleDailyCutoff`'s self-rescheduling behavior. Note: in `LocalGameRepository` this is a plain `dart:async` `Timer`, which only fires while the process is alive — a real deployment needs Cloud Scheduler / a scheduled function instead, for a device that goes to sleep.
- `proposeElimination`, `acceptEliminationProposal`, `executeElimination`, `acknowledgeEliminationSignal`.
- `proposeRecruitment`, `acceptRecruitmentProposal`, `executeRecruitment`, `respondToRecruitment`.
- `leaveGame`, `setMemberActive` (plus the 24h auto-reactivation, currently another local `Timer` — same scheduled-function treatment).
- `sendMafiaMessage`, `logObservation` — no anti-cheat concern, but still funneled through functions for consistency and to keep those write paths server-validated (right author, right game, right round).

Left as plain Firestore reads/writes, not Cloud Functions: `fetchUnacknowledgedMoments`, `fetchAllMoments`, `acknowledgeAllMoments`, `recordReentry` — per-player notification bookkeeping, not contested game state; a rule of `playerId == request.auth.uid` is sufficient.

### Auth and the debug switcher

The plan (see Phase 1a above) is to keep the debug role switcher and debug buttons working *against the real backend* through Phase 1b, then gate them before real coworkers get a build — not gate them as a Phase 1b prerequisite. That needs an answer, since `AuthService.knownUsers`/`switchToUser` (`lib/domain/repositories/auth_service.dart`) are debug-switcher concepts with no natural real-Firebase-Auth equivalent — you can't enumerate "every account ever signed in on this device" or silently swap sessions without credentials in real Firebase Auth.

Recommendation: run the **Firebase Local Emulator Suite** (Auth + Firestore + Functions) as the default dev target through all of Phase 1b, the same role `LocalGameRepository` plays today — `flutter run` against emulators, no real project touched, no real phone/email needed, free and instantly resettable. For the debug switcher specifically: a debug-gated callable function (`debugMintTestUser`, denied by rules for any build not pointed at the emulator) creates/looks up a named test user and returns a custom auth token, which `FirebaseAuthService`'s debug path exchanges via `signInWithCustomToken`. `knownUsers` becomes "test users this emulator session has minted"; `switchToUser` becomes "re-exchange that user's stored custom token." `RoleSwitcherScreen` keeps working unchanged against a real (emulated) backend, and the same debug function simply isn't reachable once the app points at the real project for pilot testing with actual coworkers.

### Milestones (in build order)

1. **Firebase project + emulator setup.** Create the Firebase project (console access, billing if needed); add `firebase_core`, `cloud_firestore`, `firebase_auth`, `cloud_functions` to `pubspec.yaml`; `flutterfire configure`; stand up the Local Emulator Suite as the default dev target.
2. **Auth vertical slice**, still on `LocalGameRepository` for game data: real (emulated) `FirebaseAuthService.signInWithDisplayName` plus the debug custom-token minting path. Proves sign-in UX and the emulator loop before the harder redaction problem.
3. **Read-only game data slice**: `createGame`/`addPlayer`/`watchGames`/`watchVisiblePlayers` against Firestore with the true/public-mirror/cell-view split above, still no voting. This is where the redaction architecture gets built and adversarially tested.
4. **Game-truth Cloud Functions**: vote casting/resolution, elimination/recruitment lifecycle, unmasking — the full inventory above, replacing `LocalGameRepository`'s equivalent logic function-by-function, checked conceptually against `test/vote_resolution_test.dart`, `test/mafia_thread_visibility_test.dart`, `test/recruitment_test.dart`, etc.
5. **Scheduled functions**: daily vote cutoff, mafia-inactive auto-reactivation, 3-round observation purge.
6. **Swap the DI seam**: `lib/main.dart`'s `Provider<GameRepository>`/`Provider<AuthService>` point at `Firebase*` instead of `Local*` for a real (non-emulator) pilot build — the one-line change the whole seam was built for.

### Launch logistics (easy to forget, easy to plan for)

- Apple Developer Program ($99/year) and Google Play Console ($25 one-time) — set these up during Phase 0, they're not blocked on anything.
- Apple App Review has real lead time (days, sometimes longer on first submission) — use TestFlight for the pilot cohort so you're not blocked on public review while iterating.
- A privacy policy and basic terms are required by both stores before listing, even for a small pilot — worth a simple one-pager given the app handles real coworkers' names and in-game accusations.

### Estimated timeline

Phase 1a (already scaffolded, remaining work is mostly running/debugging it and playing with the rules): a few days to a week.

Phase 1b: roughly 5–8 weeks if this is close to your main focus; more like 8–12 weeks at evenings-and-weekends pace. The range mostly depends on hours per week, not on the scope changing.

## Phase 2 — Recruitment, unmasking, cell-structure hardening

- Recruitment flow once the mafia:villager ratio crosses the threshold (section 8): recruiter selects a weight-0 villager, target accepts or declines, cell-structure link recorded.
- Unmasking flow (section 9): vote resolution flips a caught mafia member to villager, revokes their `mafiaThread` read access via updated security rules, and surfaces only their own 1–2 known contacts to them — never the full historical mafia roster.
- New-player join flow: join an in-progress game at any time as a fresh villager (section 3).
- Estimated timeline: 3–4 weeks.

## Phase 3 — Growth and scaling

- QR-code convergence points for large, multi-floor buildings (section 11) — only worth building once you're testing beyond a single small office.
- Push notifications tuned for the key beats: signal discovered, vote resolved, recruitment offer received, mafia decision needed.
- Lightweight analytics: round completion rate, day-over-day active players, how far weight typically erodes before a game ends — you'll want this before deciding whether the loop is actually working at a second office.
- Estimated timeline: 3–4 weeks.

## Phase 4 — Monetization pilot

- Start with cosmetics (section 13) — it's the cheapest to build (App Store/Play Store in-app purchase APIs are well-documented, no external partners needed) and it's the direction most consistent with the "escape from corporate life" theme.
- Sponsored local-business missions is a stronger long-term differentiator but requires manual business development (finding cafés willing to pay), not just engineering — treat it as a parallel, non-blocking experiment rather than something on the app's critical path.
- Estimated timeline: 2–3 weeks of engineering for cosmetics; business development for sponsorships runs on its own clock.

## Phase 5 — Platform generalization (later)

Building the reusable "scenario engine" so Season 2 isn't a rebuild — worth doing once Season 1 has real usage data telling you what's actually reusable versus what was Mafia-specific. Not on the critical path now.

## Timeline summary

| Phase | Focus | Estimate |
|---|---|---|
| 0 | Season Zero pilot (low-tech) | 2–3 weeks, parallel to setup |
| 1a | Local no-backend prototype | days to ~1 week (scaffold already delivered) |
| 1b | Firebase backend integration | 5–8 weeks (main-focus pace) |
| 2 | Recruitment, unmasking, join flow | 3–4 weeks |
| 3 | Growth, QR convergence, analytics | 3–4 weeks |
| 4 | Monetization pilot (cosmetics) | 2–3 weeks |
| 5 | Scenario engine for future seasons | later, usage-driven |

First real pilot beyond the founding group: roughly 3–4 months out, assuming substantial time on this and no major surprises in Phase 0. Phase 1a is already scaffolded, which pulls that estimate forward compared to starting from a blank project.

## What would actually kill this

- Season Zero shows the weight-erosion or forced-convergence mechanics aren't fun in practice — fix in Phase 0, before any code depends on them.
- A security-rule mistake leaks hidden-role information — the single technical failure mode that breaks the game outright, not just a bug to patch later.
- No one beyond the founding group wants to play without a company distribution channel — the cold-start risk flagged early in the concept doc. Watch this closely once Phase 1b ships to a second, unaffiliated group.

## This week

- Recruit the Season Zero group and pick a start date.
- Run `flutter create .` inside `office_game_app/` (see its README) to generate platform folders, then `flutter pub get` and `flutter run` to get the Phase 1a prototype on a device or simulator.
- Set up the Firebase project and both store developer accounts — none of this blocks on Season Zero's outcome, and the Firebase project can sit idle until Phase 1b starts.
