import 'dart:convert';

import 'package:aura_core/aura_offline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/audio_manager.dart';
import 'voice_service.dart';

/// Crea la voce di PANOPTICON per l'app desktop.
///
/// I file del motore si cercano in `speech/` accanto all'eseguibile (o in
/// `AURA_SPEECH_DIR`). Se mancano, la voce risulta «non disponibile» e il gioco
/// prosegue in silenzio. Restituisce null solo se il profilo non è leggibile.
Future<VoiceService?> createDesktopVoiceService({
  required bool Function() isAllowed,
  AssetBundle? bundle,
  VoiceAssetLocation? location,
}) async {
  final VoiceProfile profile;
  try {
    final raw = await (bundle ?? rootBundle)
        .loadString('assets/config/panopticon_voice.json');
    profile = VoiceProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    debugPrint('[VOICE] Profilo voce non leggibile: voce disattivata.');
    return null;
  }
  final where = location ?? VoiceAssetLocation.resolve();
  final available = where.isComplete(profile);
  if (!available) {
    debugPrint('[VOICE] File della voce assenti: voce non disponibile.');
  }
  return VoiceService(
    engine: available
        ? KokoroOnnxSpeechEngine(files: where.filesFor(profile))
        : SilentSpeechEngine(),
    playback: AudioplayersVoiceBackend(),
    profile: profile,
    isAllowed: isAllowed,
    setDucked: AudioManager().setVoiceDucked,
    assetsAvailable: available,
  );
}
