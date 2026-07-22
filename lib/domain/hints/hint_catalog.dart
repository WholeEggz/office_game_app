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

String _welcomeHelpMessage(HintContext c) => 'New here? Check Help for how a round works.';
bool _welcomeHelpRelevant(HintContext c) => true;
bool _welcomeHelpCompleted(HintContext c) => c.dismissedHintIds.contains('welcome_help');

String _sayHelloMessage(HintContext c) =>
    "Say hello in the Observation Log so others know you're around.";
bool _sayHelloRelevant(HintContext c) => !c.hasEverPosted;
bool _sayHelloCompleted(HintContext c) => c.hasEverPosted;

String _noticeSomethingMessage(HintContext c) =>
    'Did you notice something? Log it in the Observation Log.';
bool _noticeSomethingRelevant(HintContext c) => !c.hasPostedThisRound;
bool _noticeSomethingCompleted(HintContext c) => c.hasPostedThisRound;

String _castFirstVoteMessage(HintContext c) =>
    'When you\'re ready, cast a vote for who you suspect.';
bool _castFirstVoteRelevant(HintContext c) => !c.hasEverVoted;
bool _castFirstVoteCompleted(HintContext c) => c.hasEverVoted;

String _voteBeforeCutoffMessage(HintContext c) =>
    'Cast your vote for today before ${_formatTimeOfDay(c.game.dailyCutoffTime)}.';
bool _voteBeforeCutoffRelevant(HintContext c) => !c.hasVotedThisRound;
bool _voteBeforeCutoffCompleted(HintContext c) => c.hasVotedThisRound;

String _mafiaThreadIntroMessage(HintContext c) =>
    'Coordinate privately with your team in the Mafia Thread.';
bool _mafiaThreadIntroRelevant(HintContext c) => !c.hasPostedToMafiaThread;
bool _mafiaThreadIntroCompleted(HintContext c) => c.hasPostedToMafiaThread;

String _eliminationAckPendingMessage(HintContext c) =>
    "Check today's signal — confirm it before the window lapses.";
bool _eliminationAckPendingRelevant(HintContext c) =>
    c.game.eliminationSignalExecuted && !c.game.eliminationSignalConfirmed;
bool _eliminationAckPendingCompleted(HintContext c) => c.game.eliminationSignalConfirmed;

String _recruitmentResponsePendingMessage(HintContext c) =>
    'Someone reached out — check the recruitment sign and respond.';
bool _recruitmentResponsePendingRelevant(HintContext c) =>
    c.game.recruitmentSignExecuted && !c.game.recruitmentSignConfirmed;
bool _recruitmentResponsePendingCompleted(HintContext c) => c.game.recruitmentSignConfirmed;

/// The full tutorial hint catalog — see `hint_engine.dart` for how these are
/// evaluated and `hint_progress_screen.dart` for the full-list view. List
/// order here is just catalog/progress-list order; `priority` alone decides
/// banner precedence.
///
/// [_eliminationAckPendingRelevant]/[_recruitmentResponsePendingRelevant] key
/// off the same global `Game` flags the existing elimination/recruitment
/// banners use, which don't distinguish "the real target already confirmed
/// via those banners" from "someone else did" — by design, target identity
/// stays ambiguous until told plainly by `acknowledgeEliminationSignal`/
/// `respondToRecruitment` themselves. In practice this window is short: it
/// closes the moment the real target confirms, since that ends the round.
const List<HintDefinition> hintCatalog = [
  HintDefinition(
    id: 'welcome_help',
    scope: HintScope.onboarding,
    audience: HintAudience.everyone,
    priority: 100,
    dismissible: true,
    message: _welcomeHelpMessage,
    isRelevant: _welcomeHelpRelevant,
    isCompleted: _welcomeHelpCompleted,
  ),
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
    id: 'elimination_ack_pending',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 95,
    message: _eliminationAckPendingMessage,
    isRelevant: _eliminationAckPendingRelevant,
    isCompleted: _eliminationAckPendingCompleted,
  ),
  HintDefinition(
    id: 'recruitment_response_pending',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 95,
    message: _recruitmentResponsePendingMessage,
    isRelevant: _recruitmentResponsePendingRelevant,
    isCompleted: _recruitmentResponsePendingCompleted,
  ),
  HintDefinition(
    id: 'vote_before_cutoff',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 60,
    message: _voteBeforeCutoffMessage,
    isRelevant: _voteBeforeCutoffRelevant,
    isCompleted: _voteBeforeCutoffCompleted,
  ),
  HintDefinition(
    id: 'notice_something',
    scope: HintScope.recurring,
    audience: HintAudience.everyone,
    priority: 50,
    message: _noticeSomethingMessage,
    isRelevant: _noticeSomethingRelevant,
    isCompleted: _noticeSomethingCompleted,
  ),
];
