import 'package:meta/meta.dart';

import '../models/actor_cue.dart';
import 'speech_engine.dart';

/// Errore di validazione di un profilo voce.
final class VoiceProfileException implements Exception {
  const VoiceProfileException(this.message);
  final String message;
  @override
  String toString() => 'VoiceProfileException: $message';
}

/// Parametri della catena di effetti applicata alla voce sintetizzata.
@immutable
class VoiceEffectSettings {
  const VoiceEffectSettings({
    this.highpassHz = 0,
    this.lowpassHz = 0,
    this.compressorThresholdDb = 0,
    this.compressorRatio = 1,
    this.echoDelaysMs = const [],
    this.echoDecays = const [],
    this.echoInputGain = 1,
    this.echoOutputGain = 1,
    this.outputGain = 1,
  });

  /// Nessun effetto: la voce passa inalterata.
  static const VoiceEffectSettings none = VoiceEffectSettings();

  /// Filtro passa-alto (0 = spento).
  final double highpassHz;

  /// Filtro passa-basso (0 = spento).
  final double lowpassHz;

  /// Soglia del compressore in dBFS (0 = spento).
  final double compressorThresholdDb;

  /// Rapporto del compressore (1 = spento).
  final double compressorRatio;

  /// Ritardi dell'eco in millisecondi, abbinati a [echoDecays].
  final List<double> echoDelaysMs;

  /// Attenuazione di ciascuna ripetizione dell'eco.
  final List<double> echoDecays;

  /// Guadagno del segnale diretto e del segnale complessivo dell'eco.
  final double echoInputGain, echoOutputGain;

  /// Guadagno finale.
  final double outputGain;

  factory VoiceEffectSettings.fromJson(Map<String, dynamic> json) {
    _onlyKeys(
        json,
        const {
          'highpass_hz',
          'lowpass_hz',
          'compressor_threshold_db',
          'compressor_ratio',
          'echo_delays_ms',
          'echo_decays',
          'echo_input_gain',
          'echo_output_gain',
          'output_gain',
        },
        'effects');
    final delays = _numList(json, 'echo_delays_ms', 0, 1000);
    final decays = _numList(json, 'echo_decays', 0, 0.95);
    if (delays.length != decays.length) {
      throw const VoiceProfileException(
          'effects: echo_delays_ms ed echo_decays devono avere la stessa lunghezza');
    }
    return VoiceEffectSettings(
      highpassHz: _num(json, 'highpass_hz', 0, 0, 2000),
      lowpassHz: _num(json, 'lowpass_hz', 0, 0, 11000),
      compressorThresholdDb: _num(json, 'compressor_threshold_db', 0, -60, 0),
      compressorRatio: _num(json, 'compressor_ratio', 1, 1, 20),
      echoDelaysMs: delays,
      echoDecays: decays,
      echoInputGain: _num(json, 'echo_input_gain', 1, 0, 2),
      echoOutputGain: _num(json, 'echo_output_gain', 1, 0, 2),
      outputGain: _num(json, 'output_gain', 1, 0, 4),
    );
  }
}

/// Variazione della voce quando l'allerta raggiunge una soglia.
///
/// Si usa solo l'allerta, che il giocatore vede già nello sfondo: la voce non deve
/// rivelare pilastri o inganni, che fanno parte del modello di gioco nascosto.
@immutable
class VoiceAlertRule {
  const VoiceAlertRule(
      {required this.minAlert, this.speedFactor = 1, this.pauseFactor = 1});

  final int minAlert;
  final double speedFactor;
  final double pauseFactor;
}

/// Profilo voce di un'identità, caricato accanto alla sua definizione.
@immutable
class VoiceProfile {
  VoiceProfile({
    required this.identityId,
    required this.voiceFile,
    this.baseSpeed = 1,
    this.sentencePauseMs = 300,
    List<VoiceAlertRule> alertRules = const [],
    this.effects = VoiceEffectSettings.none,
  }) : alertRules = List.unmodifiable(
          [...alertRules]..sort((a, b) => a.minAlert.compareTo(b.minAlert)),
        ) {
    if (identityId.trim().isEmpty)
      throw const VoiceProfileException('identity_id vuoto');
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,64}\.bin$').hasMatch(voiceFile) ||
        voiceFile.contains('..')) {
      throw const VoiceProfileException(
          'voice_file deve essere un nome di file .bin semplice');
    }
  }

  final String identityId;

  /// Nome del file di stile della voce (es. `im_nicola.bin`), senza percorso.
  final String voiceFile;

  final double baseSpeed;

  /// Pausa tra un blocco e il successivo.
  final int sentencePauseMs;

  /// Regole ordinate per soglia crescente.
  final List<VoiceAlertRule> alertRules;

  final VoiceEffectSettings effects;

  factory VoiceProfile.fromJson(Map<String, dynamic> json) {
    _onlyKeys(
        json,
        const {
          'identity_id',
          'voice_file',
          'base_speed',
          'sentence_pause_ms',
          'alert_rules',
          'effects'
        },
        'profilo');
    final id = json['identity_id'];
    final file = json['voice_file'];
    if (id is! String || file is! String) {
      throw const VoiceProfileException(
          'identity_id e voice_file sono obbligatori');
    }
    final pause = json['sentence_pause_ms'] ?? 300;
    if (pause is! int || pause < 0 || pause > 3000) {
      throw const VoiceProfileException(
          'sentence_pause_ms deve essere un intero tra 0 e 3000');
    }
    final rules = json['alert_rules'] ?? const [];
    if (rules is! List)
      throw const VoiceProfileException('alert_rules deve essere una lista');
    final effects = json['effects'];
    if (effects != null && effects is! Map<String, dynamic>) {
      throw const VoiceProfileException('effects deve essere un oggetto');
    }
    return VoiceProfile(
      identityId: id,
      voiceFile: file,
      baseSpeed: _num(json, 'base_speed', 1, 0.5, 2),
      sentencePauseMs: pause,
      alertRules: [
        for (final r in rules)
          if (r is Map<String, dynamic>)
            _rule(r)
          else
            throw const VoiceProfileException('regola non valida'),
      ],
      effects: effects == null
          ? VoiceEffectSettings.none
          : VoiceEffectSettings.fromJson(effects as Map<String, dynamic>),
    );
  }

  static VoiceAlertRule _rule(Map<String, dynamic> r) {
    _onlyKeys(
        r, const {'min_alert', 'speed_factor', 'pause_factor'}, 'alert_rules');
    final min = r['min_alert'];
    if (min is! int || min < 0 || min > 100) {
      throw const VoiceProfileException(
          'min_alert deve essere un intero tra 0 e 100');
    }
    return VoiceAlertRule(
      minAlert: min,
      speedFactor: _num(r, 'speed_factor', 1, 0.7, 1.4),
      pauseFactor: _num(r, 'pause_factor', 1, 0.2, 3),
    );
  }
}

/// Indicazioni di voce per una battuta.
@immutable
class VoiceDirection {
  const VoiceDirection(
      {required this.request, required this.pause, required this.effects});
  final SpeechVoiceRequest request;
  final Duration pause;
  final VoiceEffectSettings effects;
}

/// Traduce profilo e stato di gioco in indicazioni deterministiche per la voce.
abstract final class VoiceDirector {
  /// Applica la regola di allerta più alta raggiunta da [cue].
  static VoiceDirection direct(VoiceProfile profile, ActorCue? cue) {
    var speed = profile.baseSpeed;
    var pause = profile.sentencePauseMs.toDouble();
    final alert = cue?.alertLevel ?? 0;
    final rule =
        profile.alertRules.where((r) => alert >= r.minAlert).lastOrNull;
    if (rule != null) {
      speed *= rule.speedFactor;
      pause *= rule.pauseFactor;
    }
    return VoiceDirection(
      request: SpeechVoiceRequest(speed: speed.clamp(0.5, 2.0).toDouble()),
      pause: Duration(milliseconds: pause.round()),
      effects: profile.effects,
    );
  }
}

void _onlyKeys(Map<String, dynamic> json, Set<String> allowed, String where) {
  final extra = json.keys.where((k) => !allowed.contains(k)).toList();
  if (extra.isNotEmpty)
    throw VoiceProfileException(
        '$where: chiavi sconosciute ${extra.join(', ')}');
}

double _num(Map<String, dynamic> json, String key, double fallback, double min,
    double max) {
  final v = json[key];
  if (v == null) return fallback;
  if (v is! num || !v.isFinite || v < min || v > max) {
    throw VoiceProfileException('$key deve essere un numero tra $min e $max');
  }
  return v.toDouble();
}

List<double> _numList(
    Map<String, dynamic> json, String key, double min, double max) {
  final v = json[key];
  if (v == null) return const [];
  if (v is! List || v.length > 8)
    throw VoiceProfileException(
        '$key deve essere una lista di al massimo 8 numeri');
  return List.unmodifiable([
    for (final x in v)
      if (x is num && x.isFinite && x >= min && x <= max)
        x.toDouble()
      else
        throw VoiceProfileException('$key contiene un valore fuori intervallo'),
  ]);
}
