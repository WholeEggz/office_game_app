import '../../domain/models/player.dart';

/// Detective-noir flavor labels layered on top of the mechanic-accurate
/// `PlayerRole` enum (villager/mafia) used everywhere else in the code.
/// Villagers are public by default, so they're "Witnesses"; the mafia work
/// in secret, so they're "Informants" — matching the role-reveal example
/// in design_spec.md §3 ("You are the informant").
String noirRoleLabel(PlayerRole role) =>
    role == PlayerRole.mafia ? 'Informant' : 'Witness';

String noirRoleHeadline(PlayerRole role) => role == PlayerRole.mafia
    ? 'You are the Informant'
    : 'You are a Witness';

String noirRoleSubtitle(PlayerRole role) => role == PlayerRole.mafia
    ? 'You work an angle no one else can see. Trust only the two contacts in your own chain.'
    : 'You have nothing to hide. Everything you notice is a lead worth logging.';
