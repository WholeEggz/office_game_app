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

Implement `FirebaseGameRepository` / `FirebaseAuthService` against the data
model in `../implementation_plan.md` (`games/{gameId}`,
`.../players/{playerId}`, `.../mafiaThread`, `.../observations`,
`.../votes`):

- [ ] Firebase project + Firestore + Cloud Functions + Auth + Cloud Messaging.
- [ ] Auth: phone number or email + display name only (no corporate SSO).
- [ ] Cloud Functions for anything that determines game truth: role
      assignment at start, vote-weight subtraction, vote resolution, the
      unmasking flip. Never client-side — a modified client could otherwise
      decrement another player's weight or read the mafia roster early.
- [ ] Firestore security rules that reproduce `LocalGameRepository`'s
      `watchVisiblePlayers` / `watchMafiaThread` redaction exactly, tested
      adversarially (try to read what a given role shouldn't be able to).
- [ ] Scheduled Cloud Function to purge observations older than 3 rounds —
      a real deletion, not just a UI filter.
- [ ] Swap the `Provider<GameRepository>` / `Provider<AuthService>` in
      `lib/main.dart` from the `Local*` implementations to the `Firebase*`
      ones — no UI code should need to change.
