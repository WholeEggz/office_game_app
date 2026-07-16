import 'dart:math';

/// Short, easy-to-say-out-loud words for a restricted case's passphrase —
/// picked so the creator can read 3 of them to a coworker over a desk or a
/// phone call without spelling anything out. Deliberately plain/generic
/// (no proper nouns, nothing that reads as offensive or work-inappropriate)
/// since these end up spoken aloud in an office.
const _passphraseWordList = [
  'apple', 'arrow', 'ash', 'aspen', 'atlas', 'autumn', 'badge', 'bark', 'bay',
  'beacon', 'bear', 'bell', 'birch', 'blaze', 'blue', 'boat', 'bolt', 'bone',
  'branch', 'brass', 'brave', 'breeze', 'brick', 'bridge', 'bright', 'brook',
  'cabin', 'canyon', 'cedar', 'chalk', 'charm', 'chess', 'cliff', 'cloud',
  'clover', 'coal', 'coast', 'comet', 'copper', 'coral', 'crane', 'creek',
  'crown', 'cub', 'dawn', 'delta', 'desert', 'dew', 'dune', 'eagle', 'echo',
  'elm', 'ember', 'falcon', 'feather', 'fern', 'field', 'fin', 'fjord',
  'flame', 'flint', 'fog', 'forest', 'fox', 'frost', 'garnet', 'ghost',
  'glacier', 'glow', 'gold', 'grain', 'grape', 'granite', 'grove', 'gull',
  'harbor', 'hawk', 'hazel', 'heron', 'hill', 'holly', 'honey', 'horizon',
  'iris', 'island', 'ivory', 'ivy', 'jade', 'jasper', 'jay', 'juniper',
  'kelp', 'kite', 'lagoon', 'lake', 'lantern', 'lark', 'laurel', 'leaf',
  'ledge', 'lily', 'lime', 'lion', 'lodge', 'loon', 'lotus', 'lynx',
  'maple', 'marsh', 'meadow', 'mesa', 'mint', 'mist', 'moon', 'moss',
  'moth', 'nest', 'north', 'oak', 'oasis', 'ocean', 'olive', 'onyx',
  'opal', 'orbit', 'orchid', 'osprey', 'otter', 'owl', 'oyster', 'palm',
  'panther', 'peak', 'pearl', 'pebble', 'pepper', 'petal', 'pier', 'pine',
  'plum', 'plume', 'pond', 'poplar', 'quartz', 'quill', 'rain', 'raven',
  'reed', 'reef', 'ridge', 'river', 'robin', 'rock', 'root', 'rose',
  'ruby', 'sage', 'sail', 'sand', 'sapphire', 'shale', 'shell', 'shore',
  'silver', 'sky', 'slate', 'sloth', 'snow', 'sparrow', 'spring', 'spruce',
  'star', 'stone', 'storm', 'stream', 'summit', 'sun', 'swan', 'tide',
  'tiger', 'timber', 'topaz', 'trail', 'tundra', 'valley', 'vine', 'violet',
  'wave', 'wheat', 'willow', 'wind', 'wolf', 'wren',
];

/// Picks 3 distinct words at random — order isn't meaningful (verification
/// is set-based, see `GameRepository.verifyPassphrase`), so no ordering
/// guarantee is needed here either.
List<String> generatePassphraseWords({Random? random}) {
  final rng = random ?? Random();
  final shuffled = [..._passphraseWordList]..shuffle(rng);
  return shuffled.take(3).toList();
}
