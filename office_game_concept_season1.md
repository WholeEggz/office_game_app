# Office Game

*Concept document — Season 1: Mafia-based scenario*

Working draft from a brainstorming session, July 8, 2026. This document collects the design decisions worked out in conversation and flags open questions still to be tested.

## 1. Concept and positioning

A platform for running social scenarios in the background of everyday office life, supported by a mobile app. Season 1 uses the Mafia mechanic as a simple, familiar, and engaging starting point — future seasons can introduce other scenarios on the same engine (roles, phases, voting, secret communication).

Model: aimed directly at employees (D2C), not sold to companies as a B2B tool. Play is unofficial but not hidden from the employer — it runs independently of company structures, without needing HR or IT approval.

Starting point: a small founding group (a handful to a dozen or so people) in one office, with organic growth driven by a recruitment mechanic built into the game itself, rather than marketing activity outside the game.

Important distinction: this is not a corporate-themed game — it's meant to be an escape from work. The narrative layer (setting) should be entirely disconnected from corporate reality.

### Proposed narrative settings (to be chosen)

- Detective noir
- A secret society of alchemists
- A fantasy court of intrigue
- A Vampire: The Masquerade–style atmosphere

## 2. Design pillars

Principles that consistently guided the design decisions made in this conversation, and that should govern any new mechanic going forward:

1. **No one is ever formally removed from the game.** Instead of removing a player, they're demoted into a different role — essential so the game doesn't damage real working relationships.
2. **The digital layer is the baseline; the physical layer is a bonus.** The core loop works fully through the app and already-visible signals (status, calendar); physical clues and gestures are an optional enrichment that kicks in naturally wherever people happen to be close together. One universal core should work regardless of office size or how spread out it is.
3. **No integration with corporate systems.** No connections to the Teams API, badge systems, or location data. All signals are manually self-reported by players in the app — this keeps the game fully independent of IT/HR approval.
4. **Cell structure for the mafia.** Mafia members only know the people in their own recruitment chain (who recruited them, who they recruited), never the full roster. This protects the game from a full information leak when one member is caught.
5. **Only the mafia needs to hide.** Being a villager carries no need to protect a secret — it's the default state, becoming public over time, without the app enforcing this as a rule.

## 3. Starting a game and player population

- Multiple independent games can run simultaneously in a single location (office).
- The mafia roster is drawn at the start of a given game, once the minimum required number of players has been reached.
- A new player can join an already-running game at any time — always as a villager, with the standard starting vote weight.

*This complements the recruitment mechanic (section 8): the villager population is replenished not only through mafia recruitment, but also through a free inflow of new players, which keeps the game alive over the long run. Multiple concurrent games in one location also mean that shared convergence points (section 11) — e.g. QR codes at the entrance — need to distinguish which game a given clue belongs to.*

## 4. Roles and factions

### Mafia

- A hidden group that operates entirely through the app — no physical meetings.
- Cell structure: each member only knows their own recruiter and/or their own recruit.
- Decisions (e.g. how to mark an eliminated villager) are made asynchronously in the app; agreement from the other active members is required.
- The roster is drawn once at the start of the game (see section 3); new players cannot join the mafia directly — they can only enter it through recruitment (section 8).

### Villagers

- Public by default over time — they have no mechanical reason to hide their status.
- Never removed from the game — their in-game strength fades through the vote-weight system (see section 5), but they participate through to the end of the season.

## 5. Vote-weight mechanic (an erosion system instead of elimination)

The core loop replaces classic, binary elimination with a system of gradual weakening.

- Every villager starts with a vote weight of 3.
- A mafia action ("elimination") subtracts 1 point of vote weight from the chosen target, instead of removing them from the game.
- A player at vote weight 0 still fully participates in the game (observing, logging observations), but their vote no longer counts toward voting out suspected mafia members.
- Sharp observations that lead to unmasking a mafia member are rewarded with +1 vote weight — a reward for good deduction, and the foundation for a future ranking/hierarchy system among villagers.

*Open strategic decision: does the mafia concentrate weight subtraction on one person (creates a visible pattern, but neutralizes a specific player faster), or spread it across many people (harder to trace, but weakens any single opponent more slowly)? This needs a deliberate design decision, or testing both variants.*

## 6. Signaling an elimination

The mafia decides in the app how to mark an eliminated villager (e.g. a note left on their monitor) — the method changes each time.

- The marking method is disclosed to all villagers in advance — the method is revealed, not the target.
- This builds day-long vigilance woven naturally into the rhythm of work: everyone is watching their surroundings all day, not just during a designated "night phase."
- Discovering the signal on yourself is the moment you learn you've lost vote weight — narratively stronger than a plain push notification.

## 7. Mafia communication and absence

- The mafia communicates exclusively through the app, asynchronously — no requirement to meet physically.
- An absent mafia member (sick leave, vacation) is marked with an "inactive" checkbox for 24 hours / until end of day.
- An absence doesn't block the others from acting — their participation in that day's decisions isn't required.
- The remaining active mafia members must approve the agreed elimination method in the app before it takes effect.

## 8. Recruitment mechanic

Since villagers are never removed from the game, long seasons need a comeback mechanism for the mafia — otherwise the villagers' advantage would be overwhelming.

- When the ratio of mafia members to villagers drops to roughly 1:5, the mafia gains the ability to recruit new members.
- The natural recruitment target is villagers at vote weight 0 — they have the least to lose, which is also thematically consistent (a marginalized voice is fertile ground for recruitment).
- Every recruitment extends the cell structure with a new recruiter–recruit link.

*The 1:5 threshold is a starting parameter that needs testing and tuning in practice, not a final value.*

## 9. Unmasking a mafia member

When villagers correctly identify and vote out a mafia member, that person "falls" — but doesn't disappear from the game.

- An unmasked mafia member moves into the villager pool — openly, with no further need to hide their status.
- Thanks to the cell structure, they only know 1–2 people from their own recruitment chain, never the full mafia roster.
- They may, but don't have to, reveal what they know about those people at any point later in the game — it's the player's choice, not a forced mechanic.
- They automatically lose access to the mafia's coordination channel in the app the moment their role changes.

## 10. Observation log and meetings

- Villagers can continuously log observations in the app, general or about specific players.
- The log is retained for 3 rounds and then deleted — deliberately ephemeral, to avoid a permanent, searchable record of accusations tied to real coworkers.
- Villagers can freely organize meetings outside the app — over coffee, in person, or even on the company's Teams.
- Votes on suspects can be cast at any point during the day; the outcome is resolved at the end of the working day, at a time the group sets for itself (a sensible default fallback, e.g. 5:00 PM, is recommended for hybrid working hours).

## 11. Scaling: office size and distribution

| Situation | What works | Mechanic adaptation |
|---|---|---|
| Small office (one open space) | Natural proximity — physical clues and gestures work without extra support | Full use of the physical layer as a bonus on top of the digital layer |
| Large multi-floor office building | Shared convergence points: reception, a single café, entry gates | QR codes at convergence points as a crowdsourced "clue economy" instead of one-to-one interactions |
| Mostly remote work / Teams | Already-visible signals: presence status, calendar, meeting attendance | Signals self-reported by players in the app — never through automatic Teams integration |

Overarching principle: one universal game core, fully functional on the digital layer, without maintaining separate game modes for different office types.

## 12. Open questions and parameters to test

| Question | Note |
|---|---|
| Does the mafia concentrate vote-weight subtraction on one person, or spread it across many? | Affects play style and how easily villagers can spot the pattern |
| Is the 1:5 threshold for activating recruitment right? | Needs tuning in practice, can't be settled purely on paper |
| What's the default vote-closing time? | Needs to account for hybrid working hours |
| How should the visibility of mafia communication/convergences be calibrated? | Too easy to detect kills deduction; too hard makes the mafia unbeatable |

## 13. Monetization directions (open, for further work)

The D2C model rules out selling to employers. The following directions came up in conversation as worth exploring further, but none has been chosen yet.

- In-app cosmetics (disguises, secret-identity pseudonyms) — a model proven by Among Us: purely cosmetic, no gameplay advantage, consistent with the escape-from-corporate-life theme.
- Sponsored locations/missions from local businesses (cafés, restaurants near the office) — a model similar to Pokémon Go, sidesteps the need for employer approval since the paying customer is the local business.
- Future seasons/scenarios as paid content packs — analogous to expansions for a board game.

## 14. Recommended next step

The riskiest assumption in the whole concept: whether softened elimination (the vote-weight system) and the forced-convergence mechanics actually work well in practice, not just on paper.

The cheapest way to test this: run a low-tech "season zero" — paper and a group chat, no app built — with the same founding group that sparked the idea. This will validate the core loop and help tune the open parameters (section 12) before any investment in a product.
