# Office Game — User Manual

*A quiet mystery running in the background of your workday. This manual
explains the current app exactly as it plays today — not the original
pitch, which has moved on in a few places since. For the underlying
design rationale, see `office_game_concept_season1.md`; for the visual
language, see `design_spec.md`.*

## The premise

Somewhere in your office, a case has opened. A handful of people have been
secretly drawn as **the Mafia** — everyone else is a **Witness**. The
Mafia is quietly working to thin out the Witnesses; the Witnesses are
trying to figure out who's Mafia before that happens. Nobody is ever
kicked out of the game — the worst that happens to a Witness is losing
influence, not losing their seat.

There's no "night phase" — everything happens asynchronously through the
app, at whatever pace your real workday allows.

## Joining a case

1. Open the app and choose **Continue as a player**, then enter your name.
2. **Find your case** lists every case currently open at your location.
   Tap **Join** on one to enter it, or **Start a new case** to open your
   own (see [Starting your own case](#starting-your-own-case) below).
3. Once you've joined, that same case always shows **Enter** instead of
   **Join** — tapping it takes you straight back to your dashboard.

A case starts itself automatically the moment enough people have joined
— there's no separate "start" step for a real player to press. The
moment it starts, roles are drawn: a handful of players become Mafia, and
everyone else is a Witness.

## Your two possible roles

**Witness** — the default, public role. You have nothing to hide. You
vote, log observations, and watch for the day's signal like everyone
else.

**Informant** — the hidden, Mafia role. You coordinate secretly with the
other Informants through **the Wire**, and you know you're being hunted.

The moment your role is set (or changes), you get a short reveal: "You
are a Witness" or "You are the Informant." From then on your dashboard
looks a little different depending on which one you are — Informants get
an extra section (the Wire) that Witnesses never see.

## Vote weight — no one is ever removed

Every Witness starts with **3 vote weight**. This is your influence, not
your life:

- When the Mafia successfully marks you, or you cast the round's winning
  vote against a fellow Witness by mistake, you lose 1 weight (down to a
  floor of 0 — it never goes negative).
- At 0 weight you're still fully in the game — you can still vote, it
  just doesn't add anything to the tally anymore.
- Correctly help unmask an Informant, and everyone who voted for them
  gains +1 weight as a reward.
- Your own weight is only ever visible to *you*. Nobody else can see it
  drop — a visible drop would otherwise be a public "confirmed not
  Mafia" stamp, which defeats the point of staying uncertain.

## Casting votes and the daily cutoff

Open **The Roster** to see everyone in the case and cast your vote for
whoever you suspect. Votes aren't secret — **Today's Tally** shows a
running total, ranked by weight, and who voted for whom.

You can vote (or change your vote) at any point during the day. Once the
case's configured daily cutoff time arrives, the round resolves on its
own — nobody has to press anything:

- If the highest-weighted vote landed on an Informant who hasn't been
  caught before, they're **unmasked**: their role flips to Witness in
  front of everyone, and every voter who backed them gets their +1
  reward.
- If it landed on a Witness instead, that Witness loses 1 weight, same
  as a Mafia hit — a vote is never wasted, it just lands somewhere.

**Voting History** (below the roster) keeps a permanent count of who's
voted for whom across the whole case — useful for spotting a pattern,
like two players who always seem to cover for each other. It's a plain
count with no weight numbers, so it can't be used to infer anyone's
eroded weight.

## The Wire — if you're an Informant

Informants coordinate through a shared thread called **the Wire**,
visible only to current, still-hidden Mafia members. It works in the
same propose → agree → act → confirm shape for both of the Mafia's two
tools:

### Marking a Witness

1. Any Informant **proposes an elimination method** against a target
   (e.g. "a note left on their monitor") — the *method*, not the target,
   is immediately shown to every Witness as a forewarning ("The Wire has
   agreed on a signal... watch for it").
2. Every other currently-active Informant has to **accept** before it
   counts as agreed. An absent member (toggled "inactive") isn't required
   to accept, and doesn't block the others.
3. Once agreed, an Informant has a 1-hour window to mark it **Executed**
   — after that, or once the round ends first, the opportunity lapses and
   they have to start over.
4. Once executed, the signal becomes visible to every Witness to check
   for on their own. The real target sees it and can confirm they found
   it — that confirmation ends the round early, right then, without
   waiting for the daily cutoff.

### Recruiting a Witness

Recruitment is the Mafia's comeback mechanic — since Witnesses are never
removed, a case that ran long enough would otherwise leave the Mafia
hopelessly outnumbered.

- Recruitment only becomes available once the Mafia are thin relative to
  the Witnesses still around — the case's own starting ratio is the
  threshold (a case that starts 6 Witnesses to 2 Mafia unlocks
  recruitment once that same ~1:3 ratio is reached again, e.g. after an
  Informant is unmasked).
- It works exactly like marking a Witness — propose a **sign** against a
  target, get every active Informant to agree, then **approach** them
  within the window. The sign becomes visible to every Witness the same
  way a method does.
- The real target can **Accept** (they become an Informant, joining the
  Wire, and the round ends) or **Decline** (they stay a Witness, and the
  slot frees up for another attempt).
- Only one recruitment can be in flight across the whole case at a time.

### Cell structure

An Informant only ever knows their own recruiter and whoever they
personally recruited — never the full Mafia roster. If someone in your
chain gets unmasked, the rest of the Mafia isn't automatically exposed
with them. An unmasked Informant *can* choose to share what they know
about their one or two connections later — it's their call, not something
the app forces.

### If you're going to be away

Toggle yourself **inactive** on the Wire before you step away — the
remaining active Informants can still act without you, and you won't
block their agreement. It resets back to active on its own after 24
hours if you forget to flip it back.

## The Observation Log

Anyone can log a note — general, or specifically **about** another
player — right from their dashboard. Entries show who wrote them and (if
targeted) who they're about, newest at the bottom like any chat. The log
is deliberately short-lived: anything older than 3 rounds is deleted for
good, so it never becomes a permanent, searchable list of accusations
against real coworkers.

## Leaving a case

Tap the sign-out icon and confirm to leave for good — there's no rejoin
in this version. Once you've left:

- You show up in the roster as "*(name)* (left)" and can no longer vote
  or be voted for.
- Your past votes and any observations about you stay in the record —
  leaving doesn't erase history.
- If you were an Informant with a pending, unagreed proposal on the
  table, your leaving counts as automatic agreement from you, the same
  as toggling inactive would.
- A departure can shift the balance of the case on its own — if enough
  Witnesses leave and the Mafia end up at parity with who's left, the
  case can end right there, with no vote or recruitment needed.

## How a case ends

There's no fixed length — a case runs until one side clearly wins:

- **The Witnesses win** the instant no Informant is left standing (every
  one has been unmasked, or has left).
- **The Mafia win** the instant they reach parity (or more) against the
  Witnesses still in the case.

Whichever happens first ends the case immediately — a finale screen
replaces the whole dashboard, naming the winning side and listing
everyone who was ever Mafia over the course of the case. Once a case is
closed, nothing in it is actionable anymore; you can still re-enter to
look at the finale, but voting, coordinating, and logging are all
switched off for good.

## Starting your own case

From **Find your case**, tap **Start a new case** to configure one
before it exists:

- **Case name** — shown in the case list to anyone browsing.
- **Villagers** and **Mafia** — set each directly; **players** is just
  shown as their sum, since that's what the case actually needs to fill
  before it starts. Recruitment's unlock threshold and the Mafia's
  action window are both fixed sensible defaults now, not something you
  configure per case.
- **Daily vote cutoff** — the time of day the round resolves on its own,
  in 24-hour format (defaults to 17:00).

Once the roster fills to the total you've set, the case starts itself —
no one needs to press a "start" button.

---

## A note on today's limitations

This is an early, single-build prototype, not the final multi-device
product:

- Everything lives in memory on one running app instance — closing or
  restarting it resets every case.
- There's a separate **Tester** mode on the entry screen that lets one
  device switch between every player's identity in a case, for trying
  the whole game out solo before real multi-device play exists. It's a
  development stand-in, not part of the real game.
- Duplicate display names are currently allowed within the tester flow.
- Leaving a case is permanent for now — there's no way back in.
