# Office Game — Implementation Plan

Based on `office_game_concept_season1.md`. Written for a solo developer (comfortable but not deeply experienced), moving fast, building in Flutter.

## Guiding principle: validate before you build

The concept doc already names the biggest risk: the vote-weight erosion system and forced-convergence mechanics might not actually be fun in practice. Nothing below skips Phase 0 — running the low-tech pilot is the cheapest insurance against building the wrong thing, even on a fast timeline. It can run in parallel with early technical setup, so it doesn't cost you calendar time.

## Phase 0 — Season Zero (low-tech pilot)

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

**To do before next phase** (app-itself gaps, not Firebase/deployment — that's already tracked separately):

- ~~Game lifecycle: define and implement a win/end condition, lock a finished game against further actions, build the finale ceremony.~~ Done.
- ~~Player lifecycle: a way to leave a game, and auto-expiry for the mafia "inactive" toggle instead of a standing manual switch.~~ Done.
- ~~Error handling: every repository action that can throw a `StateError` should show a message, not crash the screen.~~ Done.
- ~~Round/day cutoff: resolve votes automatically at a configured daily time instead of relying only on a manual button.~~ Done.
- **Remove/gate temporary & debug-only elements** — the "Reveal roles (debug)" toggle, the "Resolve today's votes (debug)" button, "Quick start (8 players)", and the tester/role-switcher flow being a first-class option right next to "Continue as a player" on the entry screen all need *some* story (a build flag, a settings toggle, a secret gesture) before this is handed to real coworkers who aren't in on the testing.
- **Minor polish** — the SVG seals/marks under `assets/graphics/` are simple placeholder shapes, fine for a pilot but worth a real illustration pass; numeric form fields (case creation, etc.) silently fall back to defaults on bad input instead of showing a validation error.

**Exit criteria to move on to Phase 1b:** you've played at least one full local round-trip (create → join → start → vote → resolve → recruit → unmask) yourself across a few switched identities, the rules as coded match what Season Zero validated, and nothing in the local implementation feels like it needs a fundamentally different data shape.

## Phase 1b — Firebase backend integration

**Scope: replace the local stubs with a real backend**, multi-device, multi-game-per-location (section 3 of the concept doc already shaped the data model for this — nothing here should require restructuring `Game`/`Player`/etc.).

### Recommended stack

- **Client:** Flutter (your preference, and a solid one — one codebase for iOS + Android, mature ecosystem, good for a solo dev moving fast).
- **Backend: Firebase** (Firestore + Cloud Functions + Firebase Auth + Cloud Messaging). For a solo, moderately-experienced developer trying to move fast, a backend-as-a-service beats standing up your own server — no infra to manage, generous free tier for a pilot-sized user base, and Firestore's realtime listeners give you live game-state updates without building your own websocket layer. Supabase is a reasonable alternative if you'd rather work in SQL, but Firebase + Flutter is the more heavily documented combination, which matters when you're not yet an advanced developer.
- **Auth:** phone number or email + display name only. No corporate SSO, deliberately (design pillar #3).

### Data model sketch

Maps directly onto the domain models already written in Phase 1a:

- `games/{gameId}` — location tag, status (recruiting / active / ended), min-player threshold, narrative skin, created-at.
- `games/{gameId}/players/{playerId}` — role (mafia/villager), vote weight, active/inactive flag, join timestamp.
- `games/{gameId}/mafiaThread/*` — decisions, proposed elimination method, per-member acceptance flags. **Readable only by current mafia members** — enforce with Firestore security rules keyed off the player's role field, not client-side hiding.
- `games/{gameId}/observations/*` — free-text entries, tagged with round number; a scheduled Cloud Function purges entries older than 3 rounds so the ephemerality is a real deletion, not just a UI filter.
- `games/{gameId}/votes/*` — per-round votes, tallied by a Cloud Function at the configured daily cutoff.

### The highest-risk technical piece

This game only works if hidden information stays hidden. A bug that lets a villager's client read the mafia's thread, or that exposes the full roster through a permissive query, doesn't just annoy someone — it breaks the game outright for that entire session. Budget real time for Firestore security rules and test them adversarially (try to read what a given role shouldn't be able to), rather than treating this as an afterthought once the UI works. `LocalGameRepository.watchVisiblePlayers` and `watchMafiaThread` already enforce the equivalent logic in-process — the Firestore rules need to reproduce exactly that behavior, not a looser version of it.

### Server-side (Cloud Functions) vs client-side

Anything that determines game truth — role assignment at game start, vote-weight subtraction, vote resolution, the unmasking flip — should be a Cloud Function, not client logic. A moderately-experienced solo dev will be tempted to do this client-side because it's faster to write; resist it here specifically, since it's the one place where a client-side shortcut directly enables cheating (a modified client could just decrement someone else's weight, or peek at the mafia roster before the reveal).

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
