import 'audio_manager.dart';
import 'audio_scene.dart';

abstract interface class BootAudioService {
  Future<void> initialize({
    required String appDataPath,
    required bool audioEnabled,
  });

  Future<void> transitionToMenu();
}

final class AudioManagerBootService implements BootAudioService {
  const AudioManagerBootService();

  @override
  Future<void> initialize({
    required String appDataPath,
    required bool audioEnabled,
  }) {
    return AudioManager().initialize(
      appDataPath,
      audioEnabled: audioEnabled,
    );
  }

  @override
  Future<void> transitionToMenu() {
    return AudioManager().transitionTo(AudioSceneState.menu);
  }
}
