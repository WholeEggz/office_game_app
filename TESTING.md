# Office Game — Manual UI Test Cases (Phase 1a)

How to run the app while testing:

```
cd office_game_app
flutter run -d chrome   # or: flutter run  (pick a simulator/device)
```

The app now opens on a mode-picker (§0): **Player** is the real flow (one
identity per device, register → find your case → join it); **Tester** is
the debug role switcher used for every other section below — from the
mode-picker, tap "Continue as tester" to reach it, add players, then tap
**Enter** next to a name to jump into that player's own `GameScreen`. Use
the back button to return to the roster and enter as someone else.
Recommended: create a game with **minimum players = 4** so you don't have
to add 8+ names to reach the mafia-count / recruitment tests.

---

## 0. Entry screen & the real player flow

| # | Steps | Expected |
|---|---|---|
| 0.1 | Launch app | Lands on "How do you want to play?" with two cards: "Player" (register, find your case, join it) and "Tester" (one device, switch identities) |
| 0.2 | Tap "Continue as tester" | Opens the debug role switcher (§1) |
| 0.3 | Go back, tap "Continue as a player" instead | "Who are you?" form: a name field, "Continue" button |
| 0.4 | Leave name blank, tap "Continue" | Nothing happens (no-op on empty name) |
| 0.5 | Enter a name, tap "Continue" | "Find your case" list appears: "Signed in as <name>", any existing cases (name, status, player count, Join/Enter button), "No cases open yet." if none exist, and a "Start a new case" button at the bottom |
| 0.6 | Tap "Start a new case" | Opens the case creation screen (§0b) |
| 0.7 | After creating a case (§0b) or having someone else create one, go back to "Find your case" | The new case now appears in the list with a "Join" button (you haven't joined it yet) |
| 0.8 | Tap "Join" on a case you're not in | You're added to its roster, then land straight in your own `GameScreen` (role-reveal ceremony plays) |
| 0.9 | Go back to "Find your case" for a case you already joined | Its button now reads "Enter" instead of "Join" — tapping it re-enters your existing `GameScreen` without calling join again |
| 0.10 | With two cases open, check that each only lists players who joined *that* case | No cross-contamination between cases in the list's player counts |
| 0.11 | Create a case with villagers = 3, mafia = 1 (§0b, for 4 total players), then join it as 3 more distinct players (through "Find your case" → "Join", not the tester flow) until the roster reaches 4 | The instant the 4th player joins, the game flips to `active` on its own — no "Start the game" button exists anywhere in this flow, and none of the 4 needed to do anything beyond joining. Re-enter as each player: at least one is mafia, not all 4 villagers (regression test — this used to silently never start, since only the tester flow's manual button triggered role assignment) |

---

## 0b. Case creation screen (settings before the case exists)

Reached from "Start a new case" (§0.6). All fields have fixed starting
defaults (not suggestions derived from anything else you type), so leaving
everything untouched reproduces the exact behavior from before this screen
existed. The "Defaults match what the concept doc recommends..." blurb
that used to sit under the "Case settings" header is gone — the screen
just shows the fields now.

The old "Minimum players to start" and "Players per mafia member" text
fields are gone — the players/villagers/mafia roster summary itself is now
the input: "villagers" and "mafia" are directly editable, "players" is
shown as the read-only sum of the two (this is a change from an earlier
version of this screen, where "players" was the editable field and
"villagers" was the derived one — villagers+mafia now feels like the more
natural way to build a roster).

The old "Villagers per mafia member to unlock recruitment" and "Hours to
act on an agreed signal before it lapses" fields are gone too — there's no
UI for them anymore. Recruitment's unlock threshold is now always computed
from the case's own starting players/mafia split (whatever ratio you start
at is the ratio recruitment unlocks at), and the execution window is
always a fixed 1 hour. (Might expose these as editable, changeable-mid-game
settings later — not yet.)

| # | Steps | Expected |
|---|---|---|
| 0b.1 | Open the screen | Fields: "Case name" (prefilled "The Office"), then a roster summary row reading "8 players" (read-only) / "6 villagers" (editable) / "2 mafia" (editable), a caption below it, a boxed "DAILY VOTE CUTOFF" field (prefilled "17:00") styled to match the roster row (monospace value, same card background/border), a caption below it, "Open the case" button |
| 0b.2 | Edit "villagers" to 10, without touching "mafia" | "players" updates live to 12; "mafia" stays at 2 — nothing here suggests a new mafia value based on the villager count anymore |
| 0b.3 | Edit "mafia" to 3, without touching "villagers" | "players" updates live to 9 (6 + 3); "villagers" stays at 6 |
| 0b.4 | Set "mafia" to 0 or leave it blank | "mafia" floors at 1 for the purposes of "players" (mirrors the repo's own game-start floor), so "players" reads villagers + 1, not villagers |
| 0b.5 | Set villagers to 2, leave mafia at its default 2, create + join enough players | The moment the roster fills, the finale screen appears immediately — 2 mafia against 2 villagers is already parity (§12), so the case never actually becomes playable at this exact split. Good to know before picking a small villager count and leaving mafia untouched |
| 0b.6 | Set "mafia" to 1, villagers to 3, then create + join 3 more players | Exactly 1 mafia among the 4, matching §0.11's auto-start regression test |
| 0b.7 | Create a case with villagers = 8, mafia = 2 (10 players total), start it, then check "The Wire" as mafia for a "Propose recruitment" option | Available immediately from round 1 — the threshold is computed as *exactly* this case's own starting ratio (2/8 = 0.25), so the starting ratio always already satisfies "at or below the threshold." Unlike the tester flow's fixed 0.2 default (§6), a case created here never starts out recruitment-locked |
| 0b.8 | Set "Daily vote cutoff" to a time a minute or two from now (24h format, e.g. "14:32") | See §13 for what this actually does once the case is running |
| 0b.9 | Type something unparseable into "Daily vote cutoff" (e.g. "banana") and create the case | Falls back to the 17:00 default rather than crashing or blocking case creation |
| 0b.10 | Leave every field at its default (6 villagers, 2 mafia, 17:00 cutoff) and create a case | 8 players total; 2 mafia among them; recruitment unlock threshold computed as 2/6 ≈ 0.33 (this case's own starting split); 1-hour execution window; 17:00 daily cutoff |

---

## 1. Setup & roster (tester flow)

| # | Steps | Expected |
|---|---|---|
| 1.1 | From the mode-picker, tap "Continue as tester" | Lands on "Open a new case" form: location tag (prefilled "Third Floor"), minimum players (prefilled "8"), your name, "Open the case" button |
| 1.2 | Leave name blank, tap "Open the case" | Nothing happens (button is a no-op on empty name — no crash, no game created) |
| 1.3 | Enter a name, tap "Open the case" | Roster screen appears: game info card (location, `recruiting`, round 1, "1/8 players"), an "Add & join" row, "Need N more players" button (disabled-looking), a debug roster list showing yourself as `villager` |
| 1.4 | Use "Add & join" to add 3 more distinct names | Each appears in the debug roster below, count in the info card increments, all shown as `villager` |
| 1.5 | Try adding a name that's already in this roster (exact match, or same name with different case/spacing, e.g. " bob " vs "Bob") | Rejected with a SnackBar ("... is already in this game") — one roster can't have two players with the same name, even though the same name is free to reuse across *different* games |
| 1.6 | With players < minPlayers | "Start the game" button shows "Need N more players" and does nothing when tapped |
| 1.7 | Reach minPlayers, tap "Start the game" | Game flips to `active`; roster shows some players re-labeled `mafia` (roughly 1 in 4, minimum 1); round stays 1 |

---

## 2. Role reveal ceremony

| # | Steps | Expected |
|---|---|---|
| 2.1 | From roster, tap "Enter" next to a **villager** | Full-screen ceremony: role badge (brass circle, eye icon) scales in with a slight overshoot, then "You are a Witness" headline fades/slides up, subtitle text, "Open the case file" button |
| 2.2 | Tap "Enter" next to a **mafia** player instead | Same ceremony but crimson circle with a mask icon, headline "You are the Informant" |
| 2.3 | Tap "Open the case file" | Ceremony dismisses, main dashboard appears (name, role label, vote-weight pill top-right, roster card, observation log) |
| 2.4 | Go back to roster, re-enter the **same** player | Ceremony plays again (Phase 1a intentionally replays it every entry — this is a debug convenience, not a bug) |
| 2.5 | Enable "reduce motion" (OS-level accessibility setting, or emulate via browser devtools `prefers-reduced-motion: reduce`) and re-enter a player | Ceremony content appears instantly with no scale/fade animation |

---

## 3. Elimination signal (propose → agree → execute → confirm → round ends)

Full agreement no longer applies the elimination immediately — it starts a
1-hour execution window (also capped by the round ending, whichever comes
first) and immediately reveals the *method* (not the target) to every
villager as a forewarning. A mafia member has to explicitly mark it
executed within that window, or the agreed elimination lapses and is lost.
Once the real target confirms receiving it, the round ends automatically.

| # | Steps | Expected |
|---|---|---|
| 3.1 | Enter as a mafia player | Dashboard shows a crimson-bordered "The Wire" card: active/inactive switch, empty thread ("No coordination yet this round."), a message box, "Propose elimination method" button |
| 3.2 | Tap "Propose elimination method" | Dialog opens: dropdown of current villagers, free-text method field, Propose/Cancel |
| 3.3 | Pick a target, type a method (e.g. "a note left on their monitor"), tap Propose | Dialog closes; "The Wire" now shows "Proposed: ... → <target>", "1 accepted", an "Accept" button (since only you as author have accepted so far); no banner yet for villagers |
| 3.4 | If there's more than one mafia member: go back, enter as the **other** mafia member, open "The Wire", tap "Accept" on the pending proposal | Once every *active* mafia member has accepted, the entry flips to "Agreed: ..." with a live "Execute within 59:5x" countdown and an "Executed" button |
| 3.5 | Enter as **any villager** right after agreement (before execution) | A crimson banner already appears: "THE WIRE HAS AGREED ON A SIGNAL", the method text, and "Watch for it — it hasn't happened yet." No tap-to-reveal veil, no confirm button yet — nothing has actually happened |
| 3.6 | Tap "Executed" (as any current mafia member) | Entry flips to "Applied: ... → <target>", shows "Awaiting confirmation"; the target's vote weight drops now (not at 3.4) |
| 3.7 | Re-enter as a villager | The banner now reads "TODAY'S SIGNAL", covered by a "Tap to check today's signal" veil |
| 3.8 | Tap the banner | Left-to-right wipe animation reveals the method text, then an "I found it" button appears underneath |
| 3.9 | Tap "I found it" as a **non-targeted** villager | Text changes to "— you weren't the target"; nothing else happens — round doesn't end, no confirmation recorded |
| 3.10 | Enter as the **targeted villager** specifically, reveal the banner, tap "I found it" | Briefly shows "— confirmed received", then the round ends: back on the roster/dashboard the round number has advanced and the signal banner is gone (a fresh round has no lingering signal) |
| 3.11 | Check "The Wire" (any mafia view) after 3.10 | That entry still permanently shows "Confirmed received" — the entry itself keeps the record even though the round-level banner cleared |
| 3.12 | Propose + reach full agreement, then (as any player) tap "Resolve today's votes (debug)" **before** executing | Entry flips to "Lapsed: ..." with a muted border; no weight change — the round ending closed the window. Mafia have to propose a fresh method/target from scratch; the old one can't be executed anymore |

---

## 4. Mafia absence (active/inactive)

| # | Steps | Expected |
|---|---|---|
| 4.1 | With 2+ mafia, enter as one, toggle "Active" switch off | Switch flips; that member is now inactive |
| 4.2 | Propose an elimination as the *other*, still-active mafia member | Entry goes straight to "Agreed: ..." with a countdown — the inactive member isn't required to accept |
| 4.3 | Toggle the same member back to "Active" mid-round, then propose a *new* elimination before anyone accepts | This time the entry should stay "Proposed" (not "Agreed") until every currently-active member (including the one just re-activated) accepts |
| 4.4 | Toggle "Active" off and leave it | Not practically waitable manually (auto-reactivates after 24 real hours per the concept doc's "24 hours / until end of day"), but covered by an automated test (`test/player_lifecycle_test.dart`, using virtual time) — confirms the switch doesn't just stay off forever until someone remembers to flip it |

---

## 5. Voting & unmasking

| # | Steps | Expected |
|---|---|---|
| 5.0 | Enter as any player, find the "Reveal roles (debug)" switch (above "The Roster") | Off by default. Roster shows no role labels |
| 5.0b | Toggle it on | Every roster row (including your own) now shows its real role underneath the name — mafia in crimson, villager in muted text. This bypasses the repository's redaction *locally in this screen only*, for solo playtesting; a real deployment would drop this control (same category as "Resolve today's votes (debug)") |
| 5.0c | Toggle it off again | Role labels disappear immediately; nothing else about the roster (tally, voting) changes |
| 5.1 | Enter as any player, open "The Roster" card | A "TODAY'S TALLY" summary at the top ("No votes cast yet this round." when empty), then every other player listed with name + "Vote" button — no weight pill next to them (only your own row, up top, shows a real number; see §5.9b for why) |
| 5.2 | Tap "Vote" on a mafia member (you'll need to know who's mafia from the debug roster) | Button label changes to "Voted"; that row now has a brass-tinted background, a check-circle icon, and brass/bold name text; the tally above now shows "<name> — N votes" with "from you" underneath |
| 5.3 | Switch to a couple of other villagers and vote for the same mafia member | Each shows the brass "voted" row styling on their own screen; the tally (visible to everyone, since votes aren't secret) accumulates total weight and lists every voter's name, e.g. "from Alice, Bob, you" |
| 5.3b | Have someone vote for a *different* candidate too | Tally now lists both candidates, ranked strongest-first by total vote weight (not just headcount) |
| 5.4 | Enter as any player, tap "Resolve today's votes (debug)" | Round advances (e.g. round 1 → 2) |
| 5.5 | Check the mafia member who received the most vote-weight | If they were mafia: role flips to villager, debug roster shows "unmasked mafia" |
| 5.6 | Re-enter that just-unmasked player | "UNMASKED" stamp ceremony plays (scale + slight rotation snap), dismiss by tapping; role badge is now brass/eye instead of crimson/mask |
| 5.7 | Check the villagers who voted for the unmasked target | Their vote weight should be +1 from before |
| 5.8 | Enter as the unmasked player, open "The Roster" | They no longer see "The Wire" mafia section — access revoked immediately |
| 5.9 | Vote for a **villager** (not mafia) across enough weight to "win" the round, then resolve | The vote isn't wasted: that villager's own vote weight drops by 1 (floored at 0) — the same erosion a mafia elimination causes. No unmask, and (unlike 5.7) the voters themselves get no reward for this one |
| 5.9b | Re-enter as any *other* player (not the eroded villager, not the debug view) and check "The Roster" | The eroded villager still shows no weight pill at all — their real (lower) weight is never shown to anyone but themselves. Only the debug role-switcher's raw game view and the eroded player's own top-of-screen pill reflect the drop. This is deliberate: a visible drop would otherwise be a public "confirmed not mafia" stamp the moment it first moved |
| 5.10 | Repeat 5.9 against the same villager across a few more rounds until their weight hits 0 | Weight stops at 0, never goes negative (check via debug roster or the eroded player's own screen) |
| 5.11 | Have only **one** low-weight villager vote (nobody else votes that round), then resolve | Resolution still happens — there's no minimum vote count/quorum, just whoever has the single highest total weight this round (plurality, not majority) |

---

## 5b. Voting history

Unlike the observation log (deliberately ephemeral, purged after 3 rounds),
every vote ever cast is kept for the whole game — the concept is that
tracking who votes for whom, and how often, over time is exactly what
helps spot mafia patterns (e.g. two players always covering for each
other).

| # | Steps | Expected |
|---|---|---|
| 5b.1 | Cast a few votes in round 1 (see §5), then open "Voting History" (below "The Roster") | Grouped by voter, e.g. "Alice" → "→ Bob: 1 time" — a plain count, deliberately no weight number (summing a voter's own weight over time would leak their erosion the same way a roster pill would, so it's left out; see §5.9b) |
| 5b.2 | Resolve the round (§5.4), then check "The Roster"'s "TODAY'S TALLY" | Empty again ("No votes cast yet this round.") — that summary is current-round only |
| 5b.3 | Check "Voting History" again after resolving | Round 1's votes are still listed — history is not cleared by round resolution |
| 5b.4 | Cast new votes in round 2 | They're added to "Voting History" alongside round 1's — same voter can accumulate multiple lines if they've voted for different targets across rounds, each with its own count |
| 5b.5 | As the same voter, change your vote target mid-round (§ vote-changing) before resolving | Still only counts as **one** history entry for that round (voting doesn't create duplicate entries per change, only per resolved/cast round) |

---

## 6. Recruitment (propose+sign → agree → approach → everyone responds)

Recruitment now mirrors elimination (§3) step for step, including the
public forewarning and a banner every villager sees — not just the mafia
thread. Any current villager is a valid target now (not just weight-0),
and only one recruitment can be in flight at a time.

Recruitment unlocks once mafia are *thin* relative to villagers — ratio
drops to roughly 1:5 or lower (section 8) — not while mafia are already
well-stocked. An 8-player Quick Start draws 2 mafia / 6 villagers
(2/6 ≈ 0.33), which is still locked. To test this with 2 mafia still
remaining afterward (so you can exercise the "other member accepts" step
below), use a bigger custom game instead: "Open a new case" with minimum
players 12 → 3 mafia / 9 villagers get drawn (3/9 ≈ 0.33, locked), then
correctly vote out **one** of those 3 mafia (§5) — down to 2 mafia / 10
villagers = exactly 0.2, right at the "roughly 1:5" threshold.

| # | Steps | Expected |
|---|---|---|
| 6.1 | Create a 12-player game, add players, start it | 3 mafia drawn; enter as one — "The Wire" shows no "Recruitment unlocked" section yet (3/9 ≈ 0.33) |
| 6.1b | Vote out one of the 3 mafia members correctly (§5), then re-enter as one of the 2 remaining mafia | Now 2 mafia / 10 villagers = 0.2 — "The Wire" shows "Recruitment unlocked" and a "Propose recruitment" button |
| 6.2 | Tap "Propose recruitment" | Dialog opens: dropdown of **all current villagers** (a full-weight one included), a free-text "sign" field (e.g. "a specific pen left on their desk"), Cancel/Propose |
| 6.3 | Pick a target, type a sign, tap Propose | "The Wire" shows "Recruiting: <sign> → <target>", "1 accepted", an Accept button — nothing visible to villagers yet |
| 6.4 | Enter as the other mafia member, tap Accept | Entry flips to "Agreed: <sign> → <target>" with a live "Approach within 59:5x" countdown and an "Approached" button |
| 6.5 | Enter as **any villager** right after agreement (before approaching) | A brass banner already appears: "THE WIRE IS RECRUITING", the sign text, "Watch for it — it hasn't happened yet." No reveal veil, no response buttons yet |
| 6.6 | Tap "Approached" (as any current mafia member) | Entry flips to "Approached: <sign> → <target>", "Awaiting response"; the target's `pendingRecruiterId` is set |
| 6.7 | Re-enter as a villager | Banner now reads "A SIGN TO WATCH FOR", covered by a "Tap to check for the sign" veil |
| 6.8 | Tap the banner | Wipe animation reveals the sign, then Decline/Accept buttons appear underneath |
| 6.9 | Tap either button as a **non-targeted** villager | Text changes to "— not you"; nothing else happens — no round end, no state change |
| 6.10 | Enter as the **targeted villager** specifically, reveal the banner, tap "Decline" | Shows "— you declined"; player stays a villager; round ends (round number advances); "The Wire" now reads "Declined: <sign> → <target>"; "Propose recruitment" is enabled again (slot freed) |
| 6.11 | Propose again (any target), agree, approach, then enter as that real target and tap "Accept" | Shows "— you're in", round ends; player flips to mafia (debug roster confirms); re-entering them shows the mafia role reveal/dashboard with "The Wire" |
| 6.12 | Check "The Wire": who is recorded as the recruit's recruiter | Whoever tapped "Approached" (the one who actually delivered it), not necessarily whoever originally proposed it |
| 6.13 | While one recruitment is agreed/mid-flight, try "Propose recruitment" again | Button is disabled, reads "Recruitment already in progress" |
| 6.14 | Propose + agree, then tap "Resolve today's votes (debug)" **before** approaching | Entry flips to "Lapsed", muted border; target never sees an offer; banner clears; slot frees up |
| 6.15 | Enter as the **recruiter** | No direct UI surfaces the new recruit's full history today (matches the cell-structure rule — verify the debug roster's `recruiterId` isn't exposed anywhere in the real player view) |

---

## 7. Observation log

| # | Steps | Expected |
|---|---|---|
| 7.1 | Enter as any player, open "Observation Log" card | Dropdown defaulting to "General observation", a text field, a submit icon button |
| 7.2 | Type a general note, submit | Appears at the top of the log (most recent first) |
| 7.3 | Pick "About <name>" from the dropdown, type a note, submit | Appears prefixed with that player's name |
| 7.4 | Resolve 3+ rounds (repeat §5.4) without adding new observations | Once the log's round is more than 3 rounds behind the current round, the old entries disappear — confirms the retention window, not just a filtered display |

---

## 8. Visibility / redaction (the security-sensitive part)

| # | Steps | Expected |
|---|---|---|
| 8.1 | Compare the debug roster (RoleSwitcherScreen) against any real villager's "The Roster" card | The villager's view never shows another player's true mafia role — only villager, unless that player has been unmasked |
| 8.2 | Enter as a mafia member with a known recruiter/recruit | Roster should reveal the *true* role only for that one connected player, not the full mafia list |
| 8.3 | Enter as any player and check "The Wire" | Only current, non-unmasked mafia members can see it at all — try entering as a plain villager and confirm the section doesn't render |

---

## 9. Responsive / visual

| # | Steps | Expected |
|---|---|---|
| 9.1 | Resize to mobile width (~375px) | Cards, forms, and lists reflow without clipping or horizontal scroll |
| 9.2 | Resize to desktop width (~1280px) | Same screens remain readable — content doesn't awkwardly stretch full-width (acceptable if it does for this phase, just confirm nothing breaks) |
| 9.3 | Increase system/browser text scale | List rows and cards grow rather than clipping text (no fixed-height containers around text) |

---

## 10. Leaving a case

| # | Steps | Expected |
|---|---|---|
| 10.1 | Enter as any player, tap the sign-out icon in the app bar | Confirmation dialog: "Leave this case?" with Cancel/Leave |
| 10.2 | Tap Cancel | Dialog closes, nothing changes |
| 10.3 | Tap Leave | Screen replaces the whole dashboard with "You left this case" — no roster, voting, or mafia section reachable anymore |
| 10.4 | As a different, still-active player, check "The Roster" | The departed player's row now reads "<name> (left)", muted, with no "Vote" button next to it — you can't vote for them |
| 10.5 | As that same still-active player, check "TODAY'S TALLY" / voting history if the departed player voted earlier in the game | Their past votes are still listed by name — leaving doesn't erase history |
| 10.6 | With 2 mafia members and a pending, unagreed elimination proposal, have the non-proposing mafia member leave instead of accepting | The proposal immediately flips to "Agreed" — a departure satisfies pending agreement the same way marking someone inactive does |
| 10.7 | Try to have a departed player's identity attempt to vote (e.g. via the tester flow's debug roster, entering as them again) | Voting throws/rejects rather than silently succeeding — a left player can't vote or be voted for |
| 10.8 | With 2 mafia and 6 villagers (locked — 2/6 is above the default 1:5 threshold), have one mafia member leave | Recruitment unlocks for the remaining mafia member — the *living* ratio (1 mafia / 6 villagers = 1:6) is what counts, not the raw roster, which still shows 2 mafia rows |

---

## 11. Error handling (repository rejections show a message, not a crash)

Every action that calls into the repository (propose/accept/execute elimination or recruitment, send mafia message, cast a vote, toggle active, log an observation, resolve the day, leave the case) is expected to show a SnackBar instead of crashing the screen if the repository rejects it. Concretely:

| # | Steps | Expected |
|---|---|---|
| 11.1 | Have mafia agree + execute an elimination, then (in the tester flow) tap "Executed" on the same entry again | SnackBar ("This proposal has already been executed") rather than a red error screen |
| 11.2 | Let an agreed elimination's 1-hour execution window lapse (fixed now, no shorter option in the case creation screen — worth timing this one rather than waiting live), then try to execute it | SnackBar explaining the window closed, no crash |
| 11.3 | As a mafia member proposing an elimination against a target who (unknown to this section's redacted view) is already secretly mafia or already has a pending recruitment offer | Generic SnackBar ("That lead went cold — try someone else.") — deliberately vague so it doesn't leak *why*, unlike 11.1/11.2 where the real reason is safe to show |

---

## 12. Ending a case (win conditions, locking, the finale ceremony)

There's no fixed season length. Villagers win the instant no living mafia
member remains (all unmasked, or all left); mafia win the instant they
reach parity or a majority against living villagers ("living" excludes
anyone who's left — see §10). Whichever crosses first ends the case, for
good.

Recommended setup for testing this without a huge roster: create a case
with villagers = 3 and mafia = 1 (§0b), for 4 total players — one
successful unmask ends it immediately.

| # | Steps | Expected |
|---|---|---|
| 12.1 | With a 1-mafia game, have everyone vote out that mafia member, then resolve | The moment they'd normally just flip to "unmasked villager," the whole dashboard is instead replaced by a finale screen: a headline ("The Villagers Win" in brass, with a magnifying-glass icon), "Case closed at round N", and a "THE MAFIA" list naming every player who was ever mafia (crimson mask icons) |
| 12.2 | Re-enter any player (mafia or villager) after the case ended | Same finale screen appears again — it's driven by `Game.status`, not a one-time ceremony, so it's stable to revisit |
| 12.3 | As any player, try to vote, propose an elimination/recruitment, send a mafia message, or log an observation via the tester's debug tools against this now-ended game | Every one throws/rejects ("This case is closed") — nothing is actionable anymore, not just hidden in the UI |
| 12.4 | From "Find your case" (§0), check this ended case in the list | Status reads "ended"; a **member** sees an "Enter" button (to view the finale); a **non-member** sees a disabled "Closed" button instead of "Join" |
| 12.5 | Set up a game where mafia can reach parity via recruitment (e.g. villagers 3, mafia 1 from §0b, for 4 total players — recruitment is unlocked from round 1 by default now, no extra setup needed) and have the sole mafia member successfully recruit one villager | The instant the recruit accepts, the finale screen appears instead of the round just continuing — headline "The Mafia Wins" in crimson, same mafia-roster list (now including the newly recruited member) |
| 12.6 | In a game partway through §12.5's setup, have enough villagers leave (§10) to tip mafia into parity with those remaining | Leaving itself can trigger the finale — you don't need a vote or recruitment event, just the departure crossing the threshold |

---

## 13. Daily vote cutoff (automatic resolution)

The "Resolve today's votes (debug)" button is still there and still works
— this doesn't replace it, it just means nobody *has* to press it. Every
game now also resolves its current round on its own once the configured
daily cutoff time arrives, no button required.

| # | Steps | Expected |
|---|---|---|
| 13.1 | Open "The Roster" area near the bottom of the dashboard | A line reading "Today's votes resolve on their own around HH:mm — no one has to press anything," just above the debug button, reflecting this case's configured cutoff |
| 13.2 | Create a case (§0b) with "Daily vote cutoff" set to 1–2 minutes from now, join enough players to start, then just leave the app open and wait | Once that clock time arrives, the round resolves by itself — round number advances, any pending unmask/erosion effects apply, exactly as if someone had tapped the debug button |
| 13.3 | Tap "Resolve today's votes (debug)" yourself well before the configured cutoff | Round advances immediately, same as always. The *original* cutoff instant doesn't also separately fire later for the same round — the next round gets its own freshly-scheduled cutoff |
| 13.4 | Let a case play until it ends (§12), noting the configured cutoff time | No further auto-resolution happens after the case closes — the finale screen stays put, nothing crashes if you leave the app open past the old cutoff |
| 13.5 | Create two cases with different cutoff times running at once | Each resolves on its own schedule independently — one case's cutoff firing doesn't affect the other |

---

## Known Phase-1a limitations (not bugs)

- State is in-memory only — refreshing the page resets everything.
- No real multi-device play; the role switcher is a deliberate stand-in.
- The daily cutoff (§13) is a plain in-process `Timer` — it only fires while
  this app instance keeps running, and resets like everything else in
  Phase 1a if the app restarts. A real deployment would trigger it via a
  Cloud Function instead, independent of any one device staying open.
  "Resolve today's votes (debug)" still remains as a manual override.
- Duplicate display names are allowed (each "Add & join" is a new identity).
- Leaving a case is permanent — there's no rejoin flow in this version.
- No fixed season length — a case with a very lopsided starting ratio (or
  one nobody ever plays out) can end almost immediately or run indefinitely.
