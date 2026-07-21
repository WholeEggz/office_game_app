import '../models/game.dart';
import '../models/game_moment.dart';
import '../models/mafia_thread_entry.dart';
import '../models/observation.dart';
import '../models/player.dart';
import '../models/vote.dart';

/// Everything the app needs to run a game lives behind this interface.
/// `LocalGameRepository` implements it entirely in memory for Phase 1a;
/// `FirebaseGameRepository` implements the same contract with Firestore +
/// Cloud Functions for Phase 1b. No UI code should depend on which one is
/// behind the seam.
abstract class GameRepository {
  /// Creates a new game in the `recruiting` state and adds [creatorName] as
  /// its first villager. [mafiaCount], [recruitmentUnlockThreshold],
  /// [executionWindow], and [dailyCutoffTime] default to the values in
  /// [Game]'s own constructor — a case creation screen can expose them as
  /// tunable settings, but no caller is required to think about them.
  /// [rulesDescription] is the creator's own free-text description of this
  /// case's variant of the rules (see [Game.rulesDescription]) — optional,
  /// blank by default.
  ///
  /// [isRestricted] gates the case behind a 3-word passphrase (see
  /// [Game.isRestricted], [verifyPassphrase], [addPlayer]) — [passphraseWords]
  /// must then be exactly 3 non-blank words; the caller (the case-creation
  /// screen) is responsible for generating and showing them to the
  /// creator, since they're the one who has to relay them out of band.
  /// Stored case/whitespace-insensitively and never returned by anything
  /// a prospective player can read.
  /// [creatorCountry]/[creatorCity]/[creatorCompanyOrOffice] denormalize
  /// the creator's own saved location (see [Game.creatorCountry]) so
  /// "Find your case" can sort by it without a per-row profile lookup —
  /// optional and blank by default, same treatment as [rulesDescription]:
  /// a caller that doesn't care about this feature (most tests) can
  /// simply omit them.
  Future<Game> createGame({
    required String locationTag,
    required int minPlayers,
    required String creatorId,
    required String creatorName,
    int mafiaCount = 1,
    double recruitmentUnlockThreshold = 0.2,
    Duration executionWindow = const Duration(hours: 1),
    Duration dailyCutoffTime = const Duration(hours: 17),
    String rulesDescription = '',
    bool isRestricted = false,
    List<String>? passphraseWords,
    String creatorCountry = '',
    String creatorCity = '',
    String creatorCompanyOrOffice = '',
  });

  /// Adds a new player to the game, always as a villager at the standard
  /// starting vote weight — works before or after the game has started
  /// (section 3). Throws a [StateError] if [name] (case/whitespace
  /// insensitive) is already taken by another player in this same game —
  /// two people can share a first name in real life, but not within one
  /// roster, where it'd be ambiguous who's who in votes and observations.
  ///
  /// [passphraseWords] is required, and checked against the case's actual
  /// passphrase (case/whitespace-insensitively, order not significant), if
  /// and only if [Game.isRestricted] — throws a [StateError] on a mismatch
  /// (or a missing/incomplete [passphraseWords] for a restricted case).
  /// This is the real enforcement point, not just [verifyPassphrase]'s
  /// pre-join UI gate: a client skipping straight to [addPlayer] without
  /// ever calling [verifyPassphrase] still can't get in without the actual
  /// words.
  Future<Player> addPlayer({
    required String gameId,
    required String playerId,
    required String name,
    List<String>? passphraseWords,
  });

  /// Checks [words] against [gameId]'s actual passphrase
  /// (case/whitespace-insensitively, order not significant) without
  /// joining or changing anything — the pre-join UI gate that unlocks a
  /// restricted case's details screen for a prospective player who hasn't
  /// joined yet. Always `true` for a case where [Game.isRestricted] is
  /// false, since there's nothing to check. [addPlayer] re-validates
  /// independently — this alone never grants membership.
  Future<bool> verifyPassphrase({
    required String gameId,
    required List<String> words,
  });

  /// The actual passphrase words for a restricted case — only ever
  /// returns non-null for the case's own creator ([Game.creatorId]);
  /// null for anyone else, or for an unrestricted case. Lets the admin
  /// look the pass back up (e.g. to repeat it to a new coworker) after
  /// the one-time reveal at creation.
  Future<List<String>?> fetchGamePassphrase({
    required String gameId,
    required String playerId,
  });

  /// Voluntarily removes [playerId] from active play — they stop
  /// counting toward votes, elimination/recruitment targets, and (if
  /// mafia) coordination or proposal-agreement gating, but stay in
  /// [Game.players] so their name keeps resolving in vote/observation
  /// history instead of collapsing to "someone". Irreversible in Phase
  /// 1a — there's no rejoin flow. Throws a [StateError] if [playerId]
  /// isn't in this game.
  Future<void> leaveGame({
    required String gameId,
    required String playerId,
  });

  /// Draws the mafia roster (always at least one mafia member, and never
  /// more than the roster size, regardless of what [Game.mafiaCount] asks
  /// for) and flips the game to `active`. In practice [createGame] and [addPlayer] already
  /// trigger this automatically the instant the roster reaches
  /// [Game.minPlayers] — no real player flow needs to call it. It's
  /// idempotent (a no-op if the game has already started) rather than an
  /// error, since callers like the debug role switcher's manual "Start the
  /// game" button race against that automatic trigger, not against a real
  /// mistake. Throws a [StateError] only if called before the threshold is
  /// met.
  Future<void> startGame(String gameId);

  /// Full, unredacted game state — used by the debug role switcher only.
  /// Anything rendering a real player's view should use
  /// [watchVisiblePlayers] instead.
  Stream<Game> watchGame(String gameId);

  /// Every game created so far, each redacted for [viewerId] exactly like
  /// [watchVisiblePlayers] redacts a single game — so browsing this list
  /// before joining never reveals anyone's mafia membership. Powers a real
  /// player's "find the game you were invited to" screen, as opposed to the
  /// debug role switcher's unredacted [watchGame].
  Stream<List<Game>> watchGames({required String viewerId});

  /// Player list redacted for [viewerId]: every role reads as villager
  /// except the viewer's own record, an already-unmasked former mafia
  /// member (public by definition — section 9), or a player [viewerId] knows
  /// through their own recruiter/recruit cell link (section 4). Vote weight
  /// is redacted the same way and for the same reason as role: every
  /// player other than the viewer always reads as the untouched starting
  /// weight, because a real, changing number would silently reveal "this
  /// player has been confirmed not mafia" the moment it first drops (only
  /// mafia targets get unmasked instead of weight-eroded) — the concept doc
  /// (section 5/6) means for that loss to be discovered by the target
  /// alone, not read off a roster by everyone.
  Stream<List<Player>> watchVisiblePlayers({
    required String gameId,
    required String viewerId,
  });

  /// The mafia's async coordination channel (section 7). Emits an empty
  /// list for any viewer who isn't a *current* mafia member — an unmasked
  /// member loses access the moment they flip (section 9).
  Stream<List<MafiaThreadEntry>> watchMafiaThread({
    required String gameId,
    required String viewerId,
  });

  /// Proposes an elimination method + target. Auto-accepted by [authorId].
  Future<void> proposeElimination({
    required String gameId,
    required String authorId,
    required String method,
    required String targetPlayerId,
  });

  /// Accepts a pending elimination proposal. Once every currently-active
  /// mafia member has accepted, the proposal is *agreed*: the method
  /// (never the target) immediately becomes visible to every villager as
  /// a forewarning (section 6 — real day-long vigilance means knowing
  /// what to watch for before it happens), and a countdown starts (1
  /// hour, or less if the round ends first) during which any current
  /// mafia member can call [executeElimination]. Agreement alone does not
  /// move any vote weight yet.
  Future<void> acceptEliminationProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  });

  /// Confirms an agreed proposal was actually carried out. Only now does
  /// the target lose 1 vote weight and `Game.eliminationSignalExecuted`
  /// flip true for every villager. Throws a [StateError] if the proposal
  /// isn't agreed yet, was already executed, or its execution window has
  /// already lapsed.
  Future<void> executeElimination({
    required String gameId,
    required String proposalId,
    required String playerId,
  });

  /// A player's acknowledgement that they received the signal. Returns
  /// `true` if [playerId] was the actual target — in which case
  /// `Game.eliminationSignalConfirmed` becomes true for every villager and
  /// the round ends immediately (the same effect as [resolveVotesForDay]),
  /// since the target discovering the mark is, narratively, the end of the
  /// day. Returns `false` with no side effects if [playerId] wasn't the
  /// target — the caller is told plainly they weren't, per how this
  /// specific confirmation flow was designed (unlike role visibility
  /// elsewhere, this one is not required to stay ambiguous).
  Future<bool> acknowledgeEliminationSignal({
    required String gameId,
    required String playerId,
  });

  /// A free-text coordination note, distinct from a formal proposal.
  Future<void> sendMafiaMessage({
    required String gameId,
    required String authorId,
    required String text,
  });

  /// Marks a mafia member inactive (sick leave, vacation) for the rest of
  /// the day — absence never blocks the others from acting (section 7).
  Future<void> setMemberActive({
    required String gameId,
    required String playerId,
    required bool isActive,
  });

  /// Logs an observation, general or about a specific player (section 10).
  Future<void> logObservation({
    required String gameId,
    required String authorId,
    required String text,
    String? targetPlayerId,
  });

  /// The observation log, already limited to the last 3 rounds — older
  /// entries are deleted by the repository, not just filtered on read.
  Stream<List<Observation>> watchObservations({
    required String gameId,
    required String viewerId,
  });

  /// Casts (or replaces) [voterId]'s vote for the current round. A
  /// weight-0 player can still vote — it simply won't count (section 5).
  /// Throws a [StateError] if either [voterId] or [targetPlayerId] has
  /// left the game ([Player.hasLeft]).
  Future<void> castVote({
    required String gameId,
    required String voterId,
    required String targetPlayerId,
  });

  /// Votes cast so far in the current round — votes aren't secret, so this
  /// isn't redacted per-viewer.
  Stream<List<Vote>> watchCurrentRoundVotes(String gameId);

  /// Every vote ever cast in this game, across all rounds — unlike the
  /// observation log, voting history is never purged, since tracking who
  /// votes for whom (and how often) over time is exactly what's useful for
  /// spotting mafia patterns. Not redacted per-viewer, same as
  /// [watchCurrentRoundVotes].
  Stream<List<Vote>> watchVoteHistory(String gameId);

  /// Tallies the current round's votes (highest total weight wins — a
  /// plurality, no minimum threshold) at the day's cutoff (section 10).
  /// The vote is never a no-op, only the effect differs by who it lands
  /// on: if the winning target is a current mafia member, they're
  /// unmasked (flipped to villager, mafia-thread access revoked) and
  /// every voter who picked them gains +1 vote weight (section 5); if the
  /// winning target is a villager, the vote lands the same way a mafia
  /// elimination would — they lose 1 vote weight, floored at 0. Then
  /// advances the round and purges observations older than 3 rounds.
  ///
  /// This is also what fires on its own at [Game.dailyCutoffTime] every
  /// day — calling this manually (a debug convenience, not something a
  /// real player flow needs) just makes it happen sooner, and either way
  /// the next day's cutoff gets freshly scheduled from whenever the round
  /// actually resolved.
  Future<void> resolveVotesForDay(String gameId);

  /// Proposes recruiting a target — any current villager, not just a
  /// weight-0 one (the intent is more real-world mafia/villager
  /// interaction, not a narrowly optimal target) — plus a [sign], the
  /// recruitment equivalent of an elimination [proposeElimination] method
  /// (e.g. "a specific pen left on their desk"). Only valid once
  /// [Game.recruitmentUnlocked], while [recruiterId] is a current mafia
  /// member, and while no other recruitment is already in flight for this
  /// game — recruitment has a single slot, mirroring how elimination has a
  /// single active signal. Goes through the exact same agree → execute →
  /// confirm lifecycle as an elimination proposal: [acceptRecruitmentProposal]
  /// arms the countdown and — mirroring section 6 — puts [sign] (never the
  /// target) in front of every villager as a forewarning; only
  /// [executeRecruitment] actually puts the offer in front of the target.
  Future<void> proposeRecruitment({
    required String gameId,
    required String recruiterId,
    required String targetPlayerId,
    required String sign,
  });

  /// Accepts a pending recruitment proposal. Once every currently-active
  /// mafia member has accepted, it's agreed and the execution countdown
  /// starts — mirrors [acceptEliminationProposal] exactly, just for the
  /// recruitment slot.
  Future<void> acceptRecruitmentProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  });

  /// Confirms an agreed recruitment was actually approached in the real
  /// world. Only now does the target actually see the offer waiting for
  /// them, and `Game.recruitmentSignExecuted` flips true for every
  /// villager (mirrors [executeElimination] exactly). [playerId] becomes
  /// the target's recruiter (cell structure, design pillar #4), since
  /// they're the one who had the real conversation. Throws a [StateError]
  /// under the same conditions as [executeElimination] (not agreed yet,
  /// already executed, or the window already lapsed).
  Future<void> executeRecruitment({
    required String gameId,
    required String proposalId,
    required String playerId,
  });

  /// A player's answer to the recruitment sign — never forced (section 8).
  /// Mirrors [acknowledgeEliminationSignal]: any villager can call this
  /// (the UI shows the same "did this happen to you?" prompt to everyone,
  /// exactly like the elimination signal banner), but it only actually
  /// applies [accept] if [playerId] is the real target — in which case
  /// `Game.recruitmentSignConfirmed` becomes true for every villager, the
  /// slot frees up, and the round ends immediately, same as
  /// [acknowledgeEliminationSignal]. Returns `false` with no side effects
  /// if [playerId] wasn't the target.
  Future<bool> respondToRecruitment({
    required String gameId,
    required String playerId,
    required bool accept,
  });

  /// Every [GameMoment] recorded for [playerId] in this game that hasn't
  /// been acknowledged yet (see [acknowledgeAllMoments]), oldest first —
  /// however many rounds' worth accumulated since they last checked in.
  /// A UI showing these should still collapse consecutive
  /// [GameMomentType.roundEnded] entries with nothing else to say down to
  /// just the most recent one; every other type is specific enough to
  /// show in full.
  Future<List<GameMoment>> fetchUnacknowledgedMoments({
    required String gameId,
    required String playerId,
  });

  /// Marks every currently-unacknowledged moment for [playerId] in this
  /// game as seen — call after presenting whatever [fetchUnacknowledgedMoments]
  /// just returned, so the same moments don't resurface next time.
  Future<void> acknowledgeAllMoments({
    required String gameId,
    required String playerId,
  });

  /// Every [GameMoment] ever recorded for [playerId] in this game,
  /// acknowledged or not, oldest first — unlike
  /// [fetchUnacknowledgedMoments], acknowledging never removes anything
  /// from this. Powers the cross-case track record screen, which needs a
  /// player's full history rather than just what they haven't seen yet.
  Future<List<GameMoment>> fetchAllMoments({
    required String gameId,
    required String playerId,
  });

  /// Records a [GameMomentType.reenteredCase] moment — call when a player
  /// opens a case they've already joined (as opposed to [addPlayer] or
  /// [createGame], which record [GameMomentType.joinedCase] for a first
  /// visit). Scoped to the real player flow ("Enter" on an already-joined
  /// case); the debug role switcher's own "Enter" doesn't call this, since
  /// it already intentionally replays other ceremonies on every visit.
  Future<void> recordReentry({
    required String gameId,
    required String playerId,
  });

  /// Reports [targetPlayerId] for [reason] — either a general report
  /// ([observationId] null) or a report of a specific observation entry
  /// they authored. Recorded for later moderator review; on its own this
  /// has no visible effect for anyone in the game — pair with
  /// [blockPlayer] if the reporter also wants [targetPlayerId]'s
  /// observations hidden from their own view right away.
  Future<void> reportPlayer({
    required String gameId,
    required String reporterId,
    required String targetPlayerId,
    required String reason,
    String? observationId,
  });

  /// Hides [blockedPlayerId]'s observation-log entries from [viewerId]'s
  /// own view of this game, from now on — a per-viewer preference, not a
  /// game-truth change, so it never affects voting, roles, or anyone
  /// else's view. Independent of [reportPlayer]: blocking doesn't require
  /// having reported anyone, and reporting doesn't block automatically.
  Future<void> blockPlayer({
    required String gameId,
    required String viewerId,
    required String blockedPlayerId,
  });

  /// Reverses [blockPlayer].
  Future<void> unblockPlayer({
    required String gameId,
    required String viewerId,
    required String blockedPlayerId,
  });

  /// [viewerId]'s current block list for this game.
  Stream<Set<String>> watchBlockedPlayerIds({
    required String gameId,
    required String viewerId,
  });
}
