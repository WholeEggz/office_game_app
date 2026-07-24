import '../models/mafia_thread_entry.dart';
import 'hint_context.dart';
import 'hint_definition.dart';

/// "17:00" style formatting for a time-of-day [Duration] since midnight —
/// mirrors `game_screen.dart`'s own `_formatTimeOfDay`, duplicated here
/// rather than shared since this is domain code and that one lives in the
/// UI layer.
String _formatTimeOfDay(Duration timeOfDay) {
  final hours = timeOfDay.inHours % 24;
  final minutes = timeOfDay.inMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

/// True once wall-clock "now" is within [window] of the next real
/// occurrence of time-of-day [cutoffTimeOfDay] — [cutoffTimeOfDay] alone
/// has no date, so this rolls to tomorrow if today's has already passed,
/// mirroring `LocalGameRepository._scheduleDailyCutoff`'s own rollover
/// logic exactly (see `daily_cutoff_test.dart`'s note on why that reads
/// `DateTime.now()` directly instead of `package:clock`).
bool _isWithinWindowBeforeCutoff(Duration cutoffTimeOfDay, Duration window, DateTime now) {
  final todayCutoff = DateTime(now.year, now.month, now.day).add(cutoffTimeOfDay);
  final nextCutoff =
      todayCutoff.isAfter(now) ? todayCutoff : todayCutoff.add(const Duration(days: 1));
  return nextCutoff.difference(now) <= window;
}

/// The live (unlapsed) elimination proposal for the current round, if any
/// — `MafiaThreadEntryType.proposal` is elimination-only (recruitment gets
/// its own `.recruitment` type), and a lapsed one no longer counts as
/// "the thing in progress," so both `propose_elimination_method` and
/// `accept_elimination_method` below are free to re-arm once one lapses.
MafiaThreadEntry? _liveEliminationProposal(HintContext c) {
  for (final entry in c.mafiaThread) {
    if (entry.type == MafiaThreadEntryType.proposal &&
        entry.round == c.game.currentRound &&
        !entry.lapsed) {
      return entry;
    }
  }
  return null;
}

/// Whether [c.self] specifically still needs to accept the current live
/// elimination proposal — false for the proposal's own author (auto-
/// accepted on creation, per `GameRepository.proposeElimination`), and
/// false once every active mafia member (including this one) already has,
/// since `agreedAt` gets set at that point.
bool _hasUnacceptedEliminationProposal(HintContext c) {
  final entry = _liveEliminationProposal(c);
  return entry != null &&
      entry.agreedAt == null &&
      !entry.acceptedByPlayerIds.contains(c.self.id);
}

String _sayHelloMessage(HintContext c) =>
    "Say hello in the Observation Log so others know you're around.";
bool _sayHelloRelevant(HintContext c) => !c.hasEverPosted;
bool _sayHelloCompleted(HintContext c) => c.hasEverPosted;

String _noticeSomethingMessage(HintContext c) =>
    'Did you notice something? Log it in the Observation Log.';
bool _noticeSomethingRelevant(HintContext c) => !c.hasPostedThisRound;
bool _noticeSomethingCompleted(HintContext c) => c.hasPostedThisRound;
String _noticeSomethingDiscriminator(HintContext c) => c.game.currentRound.toString();

String _castFirstVoteMessage(HintContext c) =>
    'When you\'re ready, cast a vote for who you suspect.';
bool _castFirstVoteRelevant(HintContext c) => !c.hasEverVoted;
bool _castFirstVoteCompleted(HintContext c) => c.hasEverVoted;

String _voteBeforeCutoffMessage(HintContext c) =>
    'Cast your vote for today before ${_formatTimeOfDay(c.game.dailyCutoffTime)}.';
// Only within the last hour before cutoff — earlier than that, cast_first_vote
// (for a first-timer) or just quietly waiting is enough; this is a last-call
// nudge, not a standing one. Being time-windowed rather than always-on also
// means it never crowds out whatever else is relevant for most of the day —
// it simply isn't competing for the banner slot until the window opens.
const _voteBeforeCutoffWindow = Duration(hours: 1);
bool _voteBeforeCutoffRelevant(HintContext c) =>
    !c.hasVotedThisRound &&
    _isWithinWindowBeforeCutoff(c.game.dailyCutoffTime, _voteBeforeCutoffWindow, DateTime.now());
bool _voteBeforeCutoffCompleted(HintContext c) => c.hasVotedThisRound;
String _voteBeforeCutoffDiscriminator(HintContext c) => c.game.currentRound.toString();

String _mafiaThreadIntroMessage(HintContext c) =>
    'Coordinate privately with your team on the Wire.';
bool _mafiaThreadIntroRelevant(HintContext c) => !c.hasPostedToMafiaThread;
bool _mafiaThreadIntroCompleted(HintContext c) => c.hasPostedToMafiaThread;

String _proposeEliminationMethodMessage(HintContext c) =>
    'Propose an elimination method on the Wire for today.';
bool _proposeEliminationMethodRelevant(HintContext c) => _liveEliminationProposal(c) == null;
bool _proposeEliminationMethodCompleted(HintContext c) => _liveEliminationProposal(c) != null;
String _proposeEliminationMethodDiscriminator(HintContext c) => c.game.currentRound.toString();

String _acceptEliminationMethodMessage(HintContext c) =>
    'Someone proposed an elimination method on the Wire — accept it to move it forward.';
bool _acceptEliminationMethodRelevant(HintContext c) => _hasUnacceptedEliminationProposal(c);
// Deliberately not `!isRelevant` — "no proposal exists at all" and "self
// already accepted it" both make isRelevant false, but only the latter is
// actually *done*; the former should read notYetRelevant, same reasoning
// as _eliminationMethodAgreedCompleted below.
bool _acceptEliminationMethodCompleted(HintContext c) {
  final entry = _liveEliminationProposal(c);
  return entry != null && entry.acceptedByPlayerIds.contains(c.self.id);
}
String _acceptEliminationMethodDiscriminator(HintContext c) =>
    _liveEliminationProposal(c)?.id ?? 'none';

String _eliminationMethodAgreedMessage(HintContext c) =>
    "The Wire has agreed on today's elimination signal — it's visible to "
    'everyone now, but nothing has happened yet.';
bool _eliminationMethodAgreedRelevant(HintContext c) =>
    c.game.eliminationMethodDescription != null && !c.game.eliminationSignalExecuted;
// Deliberately not `!isRelevant` — "not agreed yet" and "already executed"
// both make isRelevant false, but only the latter is actually *done*; the
// former should read notYetRelevant; a naive negation would read both as
// completed.
bool _eliminationMethodAgreedCompleted(HintContext c) => c.game.eliminationSignalExecuted;
String _eliminationMethodAgreedDiscriminator(HintContext c) =>
    c.game.eliminationMethodDescription ?? '';

String _eliminationAckPendingMessage(HintContext c) =>
    "Check today's elimination signal — confirm it before the window lapses.";
bool _eliminationAckPendingRelevant(HintContext c) =>
    c.game.eliminationSignalExecuted && !c.game.eliminationSignalConfirmed;
bool _eliminationAckPendingCompleted(HintContext c) => c.game.eliminationSignalConfirmed;
// A new signal (new method text) re-arms this even within the same round.
String _eliminationAckPendingDiscriminator(HintContext c) =>
    c.game.eliminationMethodDescription ?? '';

String _recruitmentResponsePendingMessage(HintContext c) =>
    'Someone reached out — check the recruitment sign and respond.';
bool _recruitmentResponsePendingRelevant(HintContext c) =>
    c.game.recruitmentSignExecuted && !c.game.recruitmentSignConfirmed;
bool _recruitmentResponsePendingCompleted(HintContext c) => c.game.recruitmentSignConfirmed;
String _recruitmentResponsePendingDiscriminator(HintContext c) =>
    c.game.recruitmentSignDescription ?? '';

/// The full tutorial hint catalog — see `hint_engine.dart` for how these are
/// evaluated and `hint_progress_screen.dart` for the full-list view. List
/// order here is just catalog/progress-list order; `priority` alone decides
/// banner precedence.
///
/// `TUTORIAL_HINTS.md` at the repo root is a human-readable mirror of this
/// file (a table anyone can skim without reading Dart) — keep it in sync
/// whenever a hint is added, removed, or its logic changes.
///
/// Every hint gets a "Got it" button (see `HintDefinition.dismissKey`).
/// `onboarding` hints below have no `dismissDiscriminator`, so "Got it" is
/// permanent for this game; `recurring` ones set one keyed to whatever
/// makes them relevant again later (the round number, or the current
/// signal's text), so dismissing just clears *this* occurrence rather than
/// silencing a still-useful reminder for good.
///
/// [_eliminationAckPendingRelevant]/[_recruitmentResponsePendingRelevant] key
/// off the same global `Game` flags the existing elimination/recruitment
/// banners use, which don't distinguish "the real target already confirmed
/// via those banners" from "someone else did" — by design, target identity
/// stays ambiguous until told plainly by `acknowledgeEliminationSignal`/
/// `respondToRecruitment` themselves. In practice this window is short: it
/// closes the moment the real target confirms, since that ends the round.
///
/// `propose_elimination_method` -> `accept_elimination_method` ->
/// `elimination_method_agreed` -> `elimination_ack_pending` walk the same
/// propose -> agree -> execute -> confirm lifecycle `MafiaThreadEntry`
/// describes, one hint per stage a mafia member (or, for the last two
/// stages, everyone) might be waiting on. Recruitment's equivalent stages
/// mirror this exactly but only get a hint for the final one
/// (`recruitment_response_pending`) — the propose/accept steps aren't
/// tutorial-covered there, since by the time recruitment unlocks a mafia
/// player has already been through this whole shape once for elimination.
const List<HintDefinition> hintCatalog = [
  HintDefinition(
    id: 'say_hello',
    scope: HintScope.onboarding,
    audience: HintAudience.everyone,
    priority: 90,
    message: _sayHelloMessage,
    isRelevant: _sayHelloRelevant,
    isCompleted: _sayHelloCompleted,
  ),
  HintDefinition(
    id: 'cast_first_vote',
    scope: HintScope.onboarding,
    audience: HintAudience.everyone,
    priority: 80,
    message: _castFirstVoteMessage,
    isRelevant: _castFirstVoteRelevant,
    isCompleted: _castFirstVoteCompleted,
  ),
  HintDefinition(
    id: 'mafia_thread_intro',
    scope: HintScope.onboarding,
    audience: HintAudience.mafia,
    priority: 85,
    message: _mafiaThreadIntroMessage,
    isRelevant: _mafiaThreadIntroRelevant,
    isCompleted: _mafiaThreadIntroCompleted,
  ),
  HintDefinition(
    id: 'accept_elimination_method',
    scope: HintScope.recurring,
    audience: HintAudience.mafia,
    priority: 92,
    dismissDiscriminator: _acceptEliminationMethodDiscriminator,
    message: _acceptEliminationMethodMessage,
    isRelevant: _acceptEliminationMethodRelevant,
    isCompleted: _acceptEliminationMethodCompleted,
  ),
  HintDefinition(
    id: 'propose_elimination_method',
    scope: HintScope.recurring,
    audience: HintAudience.mafia,
    priority: 82,
    dismissDiscriminator: _proposeEliminationMethodDiscriminator,
    message: _proposeEliminationMethodMessage,
    isRelevant: _proposeEliminationMethodRelevant,
    isCompleted: _proposeEliminationMethodCompleted,
  ),
  HintDefinition(
    id: 'elimination_method_agreed',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 55,
    dismissDiscriminator: _eliminationMethodAgreedDiscriminator,
    message: _eliminationMethodAgreedMessage,
    isRelevant: _eliminationMethodAgreedRelevant,
    isCompleted: _eliminationMethodAgreedCompleted,
  ),
  HintDefinition(
    id: 'elimination_ack_pending',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 95,
    dismissDiscriminator: _eliminationAckPendingDiscriminator,
    message: _eliminationAckPendingMessage,
    isRelevant: _eliminationAckPendingRelevant,
    isCompleted: _eliminationAckPendingCompleted,
  ),
  HintDefinition(
    id: 'recruitment_response_pending',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 95,
    dismissDiscriminator: _recruitmentResponsePendingDiscriminator,
    message: _recruitmentResponsePendingMessage,
    isRelevant: _recruitmentResponsePendingRelevant,
    isCompleted: _recruitmentResponsePendingCompleted,
  ),
  HintDefinition(
    id: 'vote_before_cutoff',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 60,
    dismissDiscriminator: _voteBeforeCutoffDiscriminator,
    message: _voteBeforeCutoffMessage,
    isRelevant: _voteBeforeCutoffRelevant,
    isCompleted: _voteBeforeCutoffCompleted,
  ),
  HintDefinition(
    id: 'notice_something',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 50,
    dismissDiscriminator: _noticeSomethingDiscriminator,
    message: _noticeSomethingMessage,
    isRelevant: _noticeSomethingRelevant,
    isCompleted: _noticeSomethingCompleted,
  ),
];
