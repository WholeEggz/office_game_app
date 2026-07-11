# office_game_app

Phase 1a of the Office Game (see `../office_game_concept_season1.md`,
`../design_spec.md`, `../implementation_plan.md`): a fully playable,
zero-backend prototype of the Season 1 Mafia rules, styled per the design
spec, with a debug screen for switching between player identities on one
device.

## Setup

Platform folders are already generated (`flutter create .` has been run).

```
flutter pub get
flutter run
```

Pick any connected device or simulator — this is a plain Flutter app with no
external services, so no Firebase project or API keys are needed yet.

## What's here

- `lib/domain/models/` — `Player`, `Game`, `Observation`, `MafiaThreadEntry`,
  `Vote`: the shapes both the local and future Firebase implementations share.
- `lib/domain/repositories/` — `GameRepository` and `AuthService`, the seam
  everything else depends on.
- `lib/data/local/` — `LocalGameRepository` and `LocalAuthService`: a full
  in-memory implementation of every rule in the concept doc (vote-weight
  erosion, elimination signaling, mafia coordination with active/inactive
  handling, recruitment, unmasking, the 3-round observation log). State
  resets when the app restarts.
- `lib/data/firebase/` — `FirebaseGameRepository` / `FirebaseAuthService`
  stubs; every method throws `UnimplementedError` for now.
- `lib/design/` — the visual design system from `design_spec.md` (colors,
  typography, spacing/radii/motion tokens, the assembled `ThemeData`).
- `lib/ui/role_switcher/` — debug-only entry point: create a game, add
  players, start it, and jump into any player's own view.
- `lib/ui/game/` — `GameScreen`, a single player's view: role reveal
  ceremony, vote-weight pill, elimination-signal banner, mafia thread (mafia
  only), observation log, roster + voting, and the unmask ceremony.

## Playing a round on one device

1. `flutter run`, fill in a location tag / minimum players / your name,
   tap **Open the case**.
2. Use **Add & join** to add enough players to reach the minimum.
3. Tap **Start the game** — this draws the mafia roster.
4. Tap **Enter** next to a player to open their `GameScreen`. Use the
   back button to return to the roster and enter as someone else.
5. As mafia: propose an elimination method + target, have the other
   active mafia accept it, then check villagers for the revealed signal.
6. As anyone: log observations, cast votes, then tap **Resolve today's
   votes (debug)** — this stands in for the day's cutoff a real deployment
   would trigger automatically.

There's no dedicated `/`, single source of "whose turn is it" — this is a
one-device stand-in for the real multi-device game, not the real thing.

## Phase 1b migration checklist (Firebase)

Full detail (why each piece is shaped this way, especially the redaction
architecture) lives in `../implementation_plan.md`'s Phase 1b section —
this is the condensed build-order checklist.

The debug role switcher and debug buttons (`RoleSwitcherScreen`, "Reveal
roles," "Resolve today's votes," "Quick start") **stay as-is through this
whole phase on purpose** — they're the tool for exercising the real
backend, gated only once real coworkers start getting builds.

- [ ] **Milestone 1 — project + emulator.** Create the Firebase project;
      add `firebase_core`, `cloud_firestore`, `firebase_auth`,
      `cloud_functions` to `pubspec.yaml`; `flutterfire configure`; stand up
      the Firebase Local Emulator Suite (Auth + Firestore + Functions) as
      the default dev target, the same role `LocalGameRepository` plays now.
- [ ] **Milestone 2 — auth vertical slice**, still on `LocalGameRepository`
      for game data: real (emulated) `FirebaseAuthService.signInWithDisplayName`,
      plus a debug-gated `debugMintTestUser` Cloud Function +
      `signInWithCustomToken` so the role switcher's `knownUsers`/`switchToUser`
      keep working against emulated Firebase Auth instead of the current
      fake in-memory identities.
- [ ] **Milestone 3 — read-only game data.** `createGame`/`addPlayer`/
      `watchGames`/`watchVisiblePlayers` against Firestore using the
      true-doc/public-mirror/cell-view split (`games/{gameId}/players/*` →
      private; `.../publicPlayers/*` → redacted mirror kept in sync by an
      `onWrite` trigger; `.../cellViews/{viewerId}` → mafia-only cell-link
      reveal) — this is where the redaction logic actually gets built and
      needs adversarial testing (see implementation_plan.md), not a plain
      "keyed off the role field" rule.
- [ ] **Milestone 4 — game-truth Cloud Functions**: vote casting/resolution,
      elimination/recruitment lifecycle, unmasking. Never client-side — a
      modified client could otherwise decrement another player's weight or
      read the mafia roster early. Full function list in
      `implementation_plan.md`.
- [ ] **Milestone 5 — scheduled functions**: daily vote cutoff
      (`resolveVotesForDay`, replacing the local `Timer`), mafia-inactive
      24h auto-reactivation, and observation purging (older than 3 rounds —
      a real deletion, not just a UI filter).
- [ ] **Milestone 6 — swap the DI seam.** `Provider<GameRepository>` /
      `Provider<AuthService>` in `lib/main.dart`, from `Local*` to
      `Firebase*`, for a real (non-emulator) pilot build — no UI code
      should need to change.
