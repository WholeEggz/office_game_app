import '../../domain/models/game.dart';
import '../../domain/models/mafia_thread_entry.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/player.dart';
import '../../domain/models/vote.dart';
import '../../domain/repositories/game_repository.dart';

/// Phase 1b target: Firestore + Cloud Functions, per the data model sketch
/// in `implementation_plan.md` (`games/{gameId}`, `.../players/{playerId}`,
/// `.../mafiaThread`, `.../observations`, `.../votes`). Role assignment,
/// vote-weight subtraction, vote resolution, and the unmasking flip must
/// all run as Cloud Functions there — never client-side — since a modified
/// client could otherwise cheat by decrementing another player's weight or
/// reading the mafia roster early. Every method is unimplemented for now.
///
/// One thing that doesn't carry over as-is from `LocalGameRepository`: the
/// 1-hour execution-window lapse there is a plain `dart:async` `Timer`,
/// which only fires while this process is running. Here it needs to be a
/// scheduled Cloud Function (or a Firestore TTL-style sweep) so a proposal
/// still lapses correctly even if every device is offline when the window
/// closes.
class FirebaseGameRepository implements GameRepository {
  @override
  Future<Game> createGame({
    required String locationTag,
    required int minPlayers,
    required String creatorId,
    required String creatorName,
    int mafiaCount = 1,
    double recruitmentUnlockThreshold = 0.2,
    Duration executionWindow = const Duration(hours: 1),
    Duration dailyCutoffTime = const Duration(hours: 17),
  }) =>
      throw UnimplementedError();

  @override
  Future<Player> addPlayer({
    required String gameId,
    required String playerId,
    required String name,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> leaveGame({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> startGame(String gameId) => throw UnimplementedError();

  @override
  Stream<Game> watchGame(String gameId) => throw UnimplementedError();

  @override
  Stream<List<Game>> watchGames({required String viewerId}) => throw UnimplementedError();

  @override
  Stream<List<Player>> watchVisiblePlayers({
    required String gameId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<MafiaThreadEntry>> watchMafiaThread({
    required String gameId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> proposeElimination({
    required String gameId,
    required String authorId,
    required String method,
    required String targetPlayerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> acceptEliminationProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> executeElimination({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> acknowledgeEliminationSignal({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendMafiaMessage({
    required String gameId,
    required String authorId,
    required String text,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setMemberActive({
    required String gameId,
    required String playerId,
    required bool isActive,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logObservation({
    required String gameId,
    required String authorId,
    required String text,
    String? targetPlayerId,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<Observation>> watchObservations({
    required String gameId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> castVote({
    required String gameId,
    required String voterId,
    required String targetPlayerId,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<Vote>> watchCurrentRoundVotes(String gameId) =>
      throw UnimplementedError();

  @override
  Stream<List<Vote>> watchVoteHistory(String gameId) => throw UnimplementedError();

  @override
  Future<void> resolveVotesForDay(String gameId) => throw UnimplementedError();

  @override
  Future<void> proposeRecruitment({
    required String gameId,
    required String recruiterId,
    required String targetPlayerId,
    required String sign,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> acceptRecruitmentProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> executeRecruitment({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> respondToRecruitment({
    required String gameId,
    required String playerId,
    required bool accept,
  }) =>
      throw UnimplementedError();
}
