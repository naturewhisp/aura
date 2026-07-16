import '../models/deception_state.dart';

enum DeceptionResolution {
  none,
  reset,
  armed,
  seeded,
  sprung,
  resolved,
  expired,
}

final class DeceptionPillarReward {
  final int control;
  final int dissonance;

  const DeceptionPillarReward({
    this.control = 0,
    this.dissonance = 0,
  });
}

final class DeceptionTransition {
  final DeceptionState state;
  final DeceptionResolution resolution;
  final bool sprung;
  final bool blockPositiveTags;
  final List<String> resolvedTags;
  final int alertPenalty;
  final double resonancePenalty;
  final DeceptionPillarReward pillarReward;

  const DeceptionTransition({
    required this.state,
    required this.resolution,
    required this.sprung,
    required this.blockPositiveTags,
    required this.resolvedTags,
    required this.alertPenalty,
    required this.resonancePenalty,
    required this.pillarReward,
  });
}

final class DeceptionSeedResult {
  final DeceptionState state;
  final DeceptionResolution resolution;

  const DeceptionSeedResult({
    required this.state,
    required this.resolution,
  });
}
