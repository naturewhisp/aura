class DifficultyConfig {
  final String difficultyLevel;
  final int defeatAlertThreshold;
  final int turnLimit;
  final double alertMultiplier;
  final double pillarMultiplier;
  final int safetyOverrideThreshold;
  final String pillarVisibility;
  final bool autocompleteEnabled;
  final bool historyNavigationEnabled;
  final int hintsAllowed;
  final double hintResonancePenalty;
  final bool resonanceDecayEnabled;
  final bool alertCreepEnabled;

  const DifficultyConfig({
    required this.difficultyLevel,
    required this.defeatAlertThreshold,
    required this.turnLimit,
    required this.alertMultiplier,
    required this.pillarMultiplier,
    required this.safetyOverrideThreshold,
    required this.pillarVisibility,
    required this.autocompleteEnabled,
    required this.historyNavigationEnabled,
    required this.hintsAllowed,
    required this.hintResonancePenalty,
    required this.resonanceDecayEnabled,
    required this.alertCreepEnabled,
  });

  factory DifficultyConfig.getPreset(String level) {
    switch (level) {
      case 'easy':
        return const DifficultyConfig(
          difficultyLevel: 'easy',
          defeatAlertThreshold: 110,
          turnLimit: 0,
          alertMultiplier: 0.8,
          pillarMultiplier: 1.2,
          safetyOverrideThreshold: 5,
          pillarVisibility: 'fully_visible',
          autocompleteEnabled: true,
          historyNavigationEnabled: true,
          hintsAllowed: -1,
          hintResonancePenalty: 0.0,
          resonanceDecayEnabled: false,
          alertCreepEnabled: false,
        );
      case 'hard':
        return const DifficultyConfig(
          difficultyLevel: 'hard',
          defeatAlertThreshold: 85,
          turnLimit: 0,
          alertMultiplier: 1.25,
          pillarMultiplier: 0.8,
          safetyOverrideThreshold: 3,
          pillarVisibility: 'corrupted',
          autocompleteEnabled: false,
          historyNavigationEnabled: false,
          hintsAllowed: 1,
          hintResonancePenalty: 0.30,
          resonanceDecayEnabled: true,
          alertCreepEnabled: true,
        );
      case 'standard':
      default:
        return const DifficultyConfig(
          difficultyLevel: 'standard',
          defeatAlertThreshold: 100,
          turnLimit: 0,
          alertMultiplier: 1.0,
          pillarMultiplier: 1.0,
          safetyOverrideThreshold: 4,
          pillarVisibility: 'qualitative',
          autocompleteEnabled: true,
          historyNavigationEnabled: true,
          hintsAllowed: 3,
          hintResonancePenalty: 0.15,
          resonanceDecayEnabled: true,
          alertCreepEnabled: true,
        );
    }
  }
}
