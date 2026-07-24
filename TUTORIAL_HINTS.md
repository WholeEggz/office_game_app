# Tutorial hints

*The source of truth for what's actually implemented is
`lib/domain/hints/hint_catalog.dart` — this table is a human-readable
mirror of it for anyone who wants the shape of the whole hint system at a
glance, without reading Dart. Keep the two in sync whenever either
changes.*

The tutorial system (`lib/domain/hints/`, `lib/ui/game/tutorial_hint_banner.dart`,
`lib/ui/game/hint_progress_screen.dart`) is a small rule engine, not a
scripted sequence: each hint is a pure `relevant`/`completed` predicate
over live game state, evaluated fresh every time. The top-of-screen
banner shows the single highest-`priority` hint that's currently relevant
and not completed; the full progress screen (the checklist icon in the
game's app bar) shows every hint's status side by side, onboarding and
recurring alike — see "The progress list vs. the banner" below for what
that means for a recurring hint's status over time. It also includes the
pre-game hints (registration, "Find your case", case creation — see
"Static onboarding hints" below) ahead of the in-game ones, so the list
covers the whole journey, not just what happened after joining this case.

Every hint gets a "Got it" button (bottom-right of the banner) — tapping
it dismisses that hint. A hint whose message points at a specific other
screen (only `welcome_help`, a *static* pre-game hint — see "Static
onboarding hints" below) gets a second button ("Open Help") alongside it;
every hint in the in-game catalog below just has "Got it", since they're
all about something on the current screen already.

`onboarding` hints complete once and never resurface for that case (but
are scoped per case, not per player for life — see "Known limitations"
below). `recurring` hints re-derive their status every time, since they
key off state that resets each round (e.g. "have I voted *this* round") —
"Got it" on one of these only silences *that occurrence*, not the
reminder forever (see "Dismissal" below).

## The banner's fade + stagger

`TutorialHintBanner` doesn't just snap from one hint to the next. When
the shown hint is dismissed or naturally completes, it fades out, then a
~900ms gap passes with nothing shown, then whatever's next fades in. This
is deliberate — replacing one nudge with another the instant it's
dismissed reads as the app nagging the player; the pause gives them a
beat of breathing room. See `_TutorialHintBannerState._onContext` for the
actual state machine.

## Dismissal

Every hint's "Got it" writes to the same `GameRepository.dismissHint`/
`watchDismissedHintIds` per-game ledger (mirrors `blocks`, see
`firestore.rules`). What differs is the *key* used
(`HintDefinition.dismissKey`):

- **`onboarding` hints** (no `dismissDiscriminator`): keyed by `id` alone
  — dismissal is permanent for this game.
- **`recurring` hints** (have a `dismissDiscriminator`): keyed by `id` +
  whatever that function returns for the current context (the round
  number, or the current signal's text). Once that discriminator changes
  — a new round starts, a new signal goes out — the key changes too, so
  the hint is free to reappear. "Got it" on `vote_before_cutoff` this
  round doesn't silence it next round.

| id | scope | audience | priority | dismiss discriminator | message | relevant when | completed when |
|---|---|---|---|---|---|---|---|
| `elimination_ack_pending` | recurring | everyone | 95 | current elimination signal's method text | "Check today's elimination signal — confirm it before the window lapses." | the elimination signal has executed and isn't confirmed yet | the elimination signal is confirmed |
| `recruitment_response_pending` | recurring | everyone | 95 | current signal's sign text | "Someone reached out — check the recruitment sign and respond." | the recruitment sign has executed and isn't confirmed yet | the recruitment sign is confirmed |
| `accept_elimination_method` | recurring | current Mafia only | 92 | the live proposal's own id | "Someone proposed an elimination method on the Wire — accept it to move it forward." | there's a live (unlapsed) elimination proposal this round self hasn't accepted (never relevant for the proposer, who's auto-accepted) | self has accepted the live proposal — never true before one exists at all (see "Elimination method lifecycle hints" below for why this isn't just `!isRelevant`) |
| `say_hello` | onboarding | everyone | 90 | — (permanent) | "Say hello in the Observation Log so others know you're around." | player has never logged an observation | player has logged at least one observation (any round) |
| `mafia_thread_intro` | onboarding | current Mafia only | 85 | — (permanent) | "Coordinate privately with your team on the Wire." | player is current Mafia and has never posted to the Wire | player has posted to the Wire at least once |
| `propose_elimination_method` | recurring | current Mafia only | 82 | current round number | "Propose an elimination method on the Wire for today." | no live (unlapsed) elimination proposal exists yet this round | a live elimination proposal exists this round (proposed, whether or not agreed yet) |
| `cast_first_vote` | onboarding | everyone | 80 | — (permanent) | "When you're ready, cast a vote for who you suspect." | player has never cast a vote | player has cast at least one vote (any round) |
| `vote_before_cutoff` | recurring | everyone | 60 | current round number | "Cast your vote for today before {dailyCutoffTime}." | player hasn't voted this round *and* it's within 1 hour of `dailyCutoffTime` | player has voted this round |
| `elimination_method_agreed` | recurring | everyone | 55 | current elimination method's text | "The Wire has agreed on today's elimination signal — it's visible to everyone now, but nothing has happened yet." | the elimination method is agreed (visible) but not yet executed | the elimination signal has executed (see "Elimination method lifecycle hints" — not just `!isRelevant`) |
| `notice_something` | recurring | everyone | 50 | current round number | "Did you notice something? Log it in the Observation Log." | player hasn't logged an observation this round | player has logged an observation this round |

(Table above is sorted by `priority`, highest first — the same order the
banner picks between simultaneously-active hints.)

## Elimination method lifecycle hints

`propose_elimination_method` -> `accept_elimination_method` ->
`elimination_method_agreed` -> `elimination_ack_pending` walk the same
propose -> agree -> execute -> confirm shape `MafiaThreadEntry`'s doc
comment describes, one hint per stage a mafia member (or, for the last
two stages, everyone) might be waiting on. Recruitment mirrors this
lifecycle exactly underneath, but only gets a tutorial hint for its final
stage (`recruitment_response_pending`) — by the time recruitment unlocks,
a mafia player has already been through this whole shape once already for
elimination.

Two of these (`accept_elimination_method`, `elimination_method_agreed`)
deliberately do *not* define `isCompleted` as `!isRelevant`, unlike most
hints in this catalog. Both have a real third state — "nothing has
happened yet, there's nothing to do or confirm" — that isn't the same as
"done": for `accept_elimination_method`, that's "no proposal exists at
all" (should read Not started, not Completed); for
`elimination_method_agreed`, that's "not agreed yet" (same). A naive
negation would misread that state as Completed the instant nothing was
relevant, rather than showing Not started until the thing being confirmed
actually happens. See `_hasUnacceptedEliminationProposal`/
`_eliminationMethodAgreedCompleted`'s doc comments in `hint_catalog.dart`.

`vote_before_cutoff` also picked up a second condition on top of "haven't
voted this round": it's only relevant within the last hour before
`dailyCutoffTime` (`_isWithinWindowBeforeCutoff`, reading real wall-clock
time the same way `LocalGameRepository._scheduleDailyCutoff` already
does). Earlier in the round, either `cast_first_vote` (a first-timer) or
just not being nagged yet is the right state — this is a last-call
reminder, not a standing one. Being time-windowed also means it never
crowds out something else that's relevant for most of the day: it simply
isn't competing for the banner slot outside its window, rather than
sitting there at a fixed priority the whole time.

## The progress list vs. the banner

`HintProgressScreen` lists every hint that applies to the player —
onboarding and recurring alike (see the filter in `HintProgressScreen.build`:
`allHintStatuses(...).where((e) => e.$1.appliesTo(hintContext))`). The
difference between the two scopes shows up in how a hint's status
*behaves* there over time, not in whether it's listed at all: an
onboarding hint's status only ever moves one way (Not started -> Pending
-> Completed, and stays Completed); a recurring hint's can cycle back to
Pending next round even after reading Completed this round — that's
expected, not a bug, since the round itself is the same discriminator
used to reset "Got it" dismissals (see "Dismissal" above).

`HintProgressScreen` resolves `self` via `GameRepository.watchVisiblePlayers`
(the same viewer-redacted roster `game_screen.dart` uses), *not*
`Game.playerById` off `watchGame`'s own `Game.players` field — that field
is only ever populated via the emulator-only `debugRoster` collection
(see `firebase_game_repository.dart`), so it's always empty against a
real Firebase backend. Reading `self` from there used to make this whole
screen render as an empty `SizedBox.shrink()` for every real player,
invisible when testing against `LocalGameRepository` (whose `Game.players`
*is* the real roster) — hence "some users see an empty list."

## Debug: resetting hint statuses for testing

`HintProgressScreen` shows a "Reset all hint statuses (debug)" button
above the list, gated by `kDebugMode` (same convention as `game_screen
.dart`'s "Reveal roles (debug)"/"Resolve today's votes (debug)" — never
shown in a release build). It clears both dismissal ledgers at once:
`GameRepository.clearDismissedHints` (this game's "Got it" ledger) and
`AuthService.clearDismissedHints` (the pre-game, player-level one), then
re-fetches the static half so the list reflects it immediately — the
in-game half refreshes on its own since it's already backed by a live
stream.

This only undoes "Got it" dismissals — it can't and doesn't touch hints
whose completion is derived from real game state (having actually voted,
posted an observation, etc.). To fully replay those too, start a fresh
case or a fresh identity instead; there's no safe way to rewind real game
history from a debug button.

## Known limitations

- **`elimination_ack_pending`/`recruitment_response_pending` can't tell
  "I personally checked and wasn't the target" from "someone else
  confirmed it."** There's no per-player acknowledgement flag in the
  domain model — only the global `Game.eliminationSignalConfirmed`/
  `recruitmentSignConfirmed` flags the real banners already use. In
  practice the window is short: it closes the moment the real target
  confirms, since that ends the round.
- **`say_hello`'s "ever posted" check only sees the last 3 rounds** of
  observations, since the repository purges anything older — a player
  who posted once long ago and has been quiet since can see this nudge
  again. Treated as an acceptable side effect (it's still a reasonable
  nudge to re-engage), not a bug.
- **Onboarding hints are scoped per case, not per player for life.**
  Every onboarding hint's dismissal/completion state resets for each new
  case a player joins, mirroring how observations/votes/the mafia thread
  are already per-case data. There's no cross-case player-preferences
  store to make it lifetime-scoped instead — flag if that's ever worth
  adding. (The *static*, pre-game hints below are the exception — they
  use a genuinely player-level store instead, since they have no game to
  scope to.)

## Static onboarding hints (pre-game screens)

The registration, case-list ("Find your case"), and case-creation screens
have no `Game`/`Player` to hang a `HintDefinition` off of — they render
before a game exists or before the player has joined one. These use a
separate, simpler mechanism: `StaticHintBanner`
(`lib/ui/common/static_hint_banner.dart`) — same sage-green look and
"Got it" + fade-out behavior as the in-game banner, but backed by a plain
`StaticHintInfo` (id + message, optionally `actionLabel`/`actionTarget` —
same idea as `HintDefinition`'s, reusing the same `HintActionTarget` enum
— for a hint whose message points at another screen) from
`staticHintCatalog` (`lib/domain/hints/static_hint_catalog.dart`), *not*
`hintCatalog`. No relevant/completed predicates or stagger sequencing —
each is either dismissed or not; a screen with more than one just stacks
them in catalog order (the case-list screen does this today: `welcome_help`
above `case_list_location_sort`). `StaticHintBanner` takes just an `id`
and looks its message/action up there — the one place that pairing is
written down, so the banner and `HintProgressScreen`'s merged list can
never disagree about the wording.

Dismissal here goes through `AuthService.dismissHint`/
`fetchDismissedHints` instead of `GameRepository` — a *player*-level
ledger (piggybacked on the same `users/{uid}` Firestore doc `displayName`
already lives on), since these screens exist before any `gameId` does.
Once dismissed, a given `id` never shows again for that identity (on any
device, in any case), and reads as "Completed" in `HintProgressScreen`.
This is also why `welcome_help` lives here rather than in `hintCatalog`:
it used to be an in-game hint dismissed via the game-scoped
`GameRepository.dismissHint`, which needs a real `gameId` — fine inside
an actual case, but there wasn't one on the "Find your case" screen where
this hint actually needs to show first, so dismissing it there always
threw and surfaced the "Couldn't dismiss that — try again" SnackBar.
Moving it to the player-level static mechanism fixed both problems at
once.

| id | screen | file | action | message |
|---|---|---|---|---|
| `welcome_help` | Find your case | `lib/ui/entry/player_entry_screen.dart` (`_buildGameList`) | "Open Help" -> Help screen | "New here? Open Help to see how a round works, and keep an eye out for hints like this one as you move through the app." |
| `registration_location` | Registration | `lib/ui/entry/player_entry_screen.dart` (`_buildRegisterForm`) | — | "The location you enter here becomes a case's location if you start one later, so keep it accurate." |
| `case_list_location_sort` | Find your case | `lib/ui/entry/player_entry_screen.dart` (`_buildGameList`) | — | "Cases near your office float to the top of this list — join one below, or start your own if you don't see it yet." |
| `case_creation_restricted_location` | Case creation | `lib/ui/entry/case_creation_screen.dart` | — | "Mark this case Restricted if you want to control who can join with a passphrase. Its location comes from your own profile — the one you set when you registered." |

To add another one of these: add a `StaticHintInfo(id: '...', message:
'...')` entry to `staticHintCatalog` (plus `actionLabel`/`actionTarget` if
it should point at another screen), then drop a
`const StaticHintBanner(id: '...')` at the relevant spot in the screen's
build method — pick a globally-unique `id` (it's a flat, player-wide
namespace, not scoped per screen), and place it before any other static
banner on the same screen if it should show first. It'll automatically
show up in `HintProgressScreen` too, ahead of the in-game entries. No test
in `hint_engine_test.dart` needed (there's no relevant/completed logic to
verify) — see `test/static_hint_catalog_test.dart` for the kind of thing
worth covering instead (catalog shape, action wiring).

`StaticHintBanner` needs an `AuthService` above it in the widget tree
just to render (it checks dismissed state on `initState`, before the
fade-in even starts) — any widget test that pumps a screen using one
needs `Provider<AuthService>.value(...)` in the tree even if the test
never touches auth directly, or it throws `ProviderNotFoundException`.
That async check also means the banner's true height isn't known until
one frame after the initial pump — a widget test that calls
`ensureVisible`/taps something further down the same scrollable page
needs an extra `await tester.pump();` right after `pumpWidget` before
doing so, or the layout can shift out from under an early `ensureVisible`
call. Both gotchas are already handled via the `_pumpCaseCreation` helper
in `case_creation_screen_test.dart` and inline comments in
`player_entry_registration_test.dart`, `case_list_sort_filter_test.dart`,
`case_details_screen_test.dart`, `game_location_sort_test.dart`,
`restricted_case_test.dart`, and `game_screen_moments_test.dart`.

## Adding or changing an in-game hint

(For a pre-game one, see "Static onboarding hints" above instead —
different catalog, no predicates.)

1. Add/edit the `HintDefinition` entry in `hint_catalog.dart` (message,
   `isRelevant`, `isCompleted`, `priority`, `audience`, `scope`,
   `dismissDiscriminator` for a `recurring` hint, `actionLabel`/
   `actionTarget` if it should point at another screen — no in-game hint
   uses this today, but `StaticHintInfo`'s `welcome_help` entry above
   shows the pattern).
2. If it needs a new `actionTarget`, add the enum value to
   `HintActionTarget` (`hint_definition.dart`) and a matching case in
   `_performAction` (`tutorial_hint_banner.dart`) — that's the only place
   allowed to know about `Navigator`/screens, keeping `hint_catalog.dart`
   a pure domain file.
3. Add a matching case to `_iconFor` in `hint_progress_screen.dart` (a
   placeholder Phosphor icon is fine until real artwork exists).
4. Update the table above.
5. Add/update a case in `test/hint_engine_test.dart` covering the new
   relevant/completed/dismiss logic.
