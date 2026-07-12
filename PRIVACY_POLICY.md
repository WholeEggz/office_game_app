# Privacy Policy — Office Game

*Last updated: July 12, 2026*

Office Game ("the app," "we," "us") is a social deduction game for coworkers, played on your phone. This policy explains what information the app collects, how it's used, and your choices.

## The short version

Office Game runs entirely on information you and the other players in your game type into the app yourselves. We don't collect your location, your contacts, or anything from your employer's systems — the app is deliberately built to work independently of any company IT or HR integration. There are no ads and no analytics trackers in the app today.

## Information we collect

**Account identifier.** When you open the app, it creates an anonymous account for your device using Firebase Authentication. This is a random identifier — it is not tied to a phone number, email address, or any other personal contact information unless you choose to provide one in a future version of the app.

**Display name.** The name you type in when you join or start a case is stored and shown to the other players in that same game. Use a name you're comfortable with your fellow players seeing.

**Gameplay data.** To run the game, we store the information the game itself is built on: which game(s) you've joined, your role and status in each game, votes you cast, in-game observations you log, and similar game-state records. This data is visible to other players in the same game only to the extent the game's own rules reveal it (for example, a mafia member's identity is hidden from villagers until they're caught).

**Device/diagnostic data.** Standard technical data needed to run the app (e.g., crash logs, if a debugging package is enabled in a future version) may be collected. We do not currently run any third-party analytics or advertising SDKs.

## What we don't collect

- Your precise or approximate location
- Your contacts, calendar, or messages
- Any data from your employer's systems (badge access, Teams/Slack, HR platforms) — the game is designed to run entirely independently of these
- Payment information (the app does not currently process payments)

## How we use information

Solely to run the game: matching you to the right game, enforcing the game's rules (who can see what, and when), and letting you and your fellow players see the shared game state. We do not sell your information, and we do not use it for advertising.

## Where information is stored

Game data is stored using Google Firebase (Cloud Firestore and Firebase Authentication), a cloud infrastructure provider. Firebase's own privacy and security practices apply to how they host this data on our behalf: https://firebase.google.com/support/privacy

## Data retention and deletion

Game data persists for as long as a game is active or until we run a cleanup process. To request deletion of your data, contact us at the address below — include the name(s) you've used in the app so we can locate your records.

## Children's privacy

Office Game is intended for adult coworkers and is not directed at children under 13 (or the relevant minimum age in your region). We do not knowingly collect information from children.

## Changes to this policy

If we materially change what we collect or how we use it, we'll update this page and change the "Last updated" date above.

## Contact us

Questions about this policy or your data: **contact@ultralearner.app**

---

*Template notes for whoever's finalizing this (delete before publishing):*
- *If a later version adds phone/email sign-in, real analytics, or push notifications, this document needs a corresponding update — it should always describe what the shipped build actually does, not what's planned.*
- *This is drafted as a reasonable good-faith policy for a small pilot, not reviewed by a lawyer. Given the app handles real coworkers' names and in-game accusations, it's worth a quick pass by counsel before a wide public launch, even if a solo/pilot TestFlight release is fine to ship with this as-is.*
