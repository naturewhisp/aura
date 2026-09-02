import 'audio_manager.dart';
import 'audio_scene.dart';

abstract interface class BootAudioService {
  Future<void> initialize({
    required String appDataPath,
    required bool audioEnabled,
    bool? musicEnabled,
    bool? sfxEnabled,
  });

  Future<void> transitionToBoot();

  Future<void> transitionToMenu();
}

final class AudioManagerBootService implements BootAudioService {
  const AudioManagerBootService();

  @override
  Future<void> initialize({
    required String appDataPath,
    required bool audioEnabled,
    bool? musicEnabled,
    bool? sfxEnabled,
  }) {
    return AudioManager().initialize(
      appDataPath,
      audioEnabled: audioEnabled,
      musicEnabled: musicEnabled,
      sfxEnabled: sfxEnabled,
    );
  }

  @override
  Future<void> transitionToBoot() {
    return AudioManager().transitionTo(AudioSceneState.boot);
  }

  @override
  Future<void> transitionToMenu() {
    return AudioManager().transitionTo(AudioSceneState.menu);
  }
}
