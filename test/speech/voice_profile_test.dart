import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

ActorCue _cue({required int alert, int dissonance = 0}) => ActorCue(
      semanticCategory: SemanticCategory.authorityFraming,
      appliedDeltaAlert: 0,
      appliedDeltaImperative: 0,
      appliedDeltaControl: 0,
      appliedDeltaDissonance: 0,
      creativityIndex: 0,
      injectionRisk: 0,
      resonance: 1.0,
      alertLevel: alert,
      imperativePillar: 0,
      controlPillar: 0,
      dissonancePillar: dissonance,
      recalculationTriggered: false,
      safetyOverrideApplied: false,
      dramaticInstruction: '',
      actingDirectives: const [],
      narrativeContext: const NarrativeMemory(
        playerClaims: [],
        aiConcessions: [],
        activeMetaphors: [],
        forbiddenRepetitions: [],
      ),
    );

Map<String, dynamic> _asset() => jsonDecode(
        File('app/assets/config/panopticon_voice.json').readAsStringSync())
    as Map<String, dynamic>;

void main() {
  group('VoiceProfile', () {
    test('carica il profilo di PANOPTICON distribuito con l\'app', () {
      final p = VoiceProfile.fromJson(_asset());
      expect(p.identityId, 'panopticon');
      expect(p.voiceFile, 'im_nicola.bin');
      expect(p.effects.echoDelaysMs, [45, 90]);
      expect(p.alertRules.single.minAlert, 70);
    });

    test('rifiuta chiavi sconosciute, valori fuori intervallo e percorsi', () {
      Map<String, dynamic> base() =>
          {'identity_id': 'x', 'voice_file': 'v.bin'};
      expect(VoiceProfile.fromJson(base()).baseSpeed, 1);
      expect(() => VoiceProfile.fromJson({...base(), 'tono': 1}),
          throwsA(isA<VoiceProfileException>()));
      expect(() => VoiceProfile.fromJson({...base(), 'base_speed': 3}),
          throwsA(isA<VoiceProfileException>()));
      expect(() => VoiceProfile.fromJson({...base(), 'voice_file': '../v.bin'}),
          throwsA(isA<VoiceProfileException>()));
      expect(
          () => VoiceProfile.fromJson({...base(), 'voice_file': r'C:\v.bin'}),
          throwsA(isA<VoiceProfileException>()));
      expect(() => VoiceProfile.fromJson({...base(), 'sentence_pause_ms': 1.5}),
          throwsA(isA<VoiceProfileException>()));
      expect(
        () => VoiceProfile.fromJson({
          ...base(),
          'effects': {
            'echo_delays_ms': [45],
            'echo_decays': []
          },
        }),
        throwsA(isA<VoiceProfileException>()),
      );
      expect(
        () => VoiceProfile.fromJson({
          ...base(),
          'alert_rules': [
            {'min_alert': 70, 'dissonance': 1},
          ],
        }),
        throwsA(isA<VoiceProfileException>()),
      );
    });
  });

  group('VoiceDirector', () {
    final profile = VoiceProfile.fromJson(_asset());

    test('applica la regola di allerta più alta raggiunta', () {
      final calm = VoiceDirector.direct(profile, _cue(alert: 30));
      final alarm = VoiceDirector.direct(profile, _cue(alert: 85));
      expect(calm.request.speed, 1.0);
      expect(calm.pause, const Duration(milliseconds: 300));
      expect(alarm.request.speed, closeTo(1.06, 1e-9));
      expect(alarm.pause, const Duration(milliseconds: 180));
      expect(VoiceDirector.direct(profile, null).request.speed, 1.0);
    });

    test('non dipende dai pilastri nascosti', () {
      final a = VoiceDirector.direct(profile, _cue(alert: 40));
      final b = VoiceDirector.direct(profile, _cue(alert: 40, dissonance: 95));
      expect(b.request.speed, a.request.speed);
      expect(b.pause, a.pause);
    });
  });

  group('VoiceEffectChain', () {
    SpeechAudio sine(double hz, {double amp = 0.5, int n = 24000}) =>
        SpeechAudio(
          samples: Float32List.fromList([
            for (var i = 0; i < n; i++)
              amp * math.sin(2 * math.pi * hz * i / 24000)
          ]),
          sampleRate: 24000,
        );
    double rms(SpeechAudio a, [int from = 4800]) {
      var s = 0.0;
      for (var i = from; i < a.samples.length; i++) {
        s += a.samples[i] * a.samples[i];
      }
      return math.sqrt(s / (a.samples.length - from));
    }

    test('nessun effetto lascia l\'audio invariato', () {
      final a = sine(440);
      expect(VoiceEffectChain.apply(a, VoiceEffectSettings.none).samples,
          a.samples);
      expect(
          VoiceEffectChain.apply(SpeechAudio.silent(), VoiceEffectSettings.none)
              .isEmpty,
          isTrue);
    });

    test('i filtri attenuano fuori banda e lasciano passare il centro', () {
      const bp = VoiceEffectSettings(highpassHz: 140, lowpassHz: 6500);
      expect(rms(VoiceEffectChain.apply(sine(1000), bp)),
          closeTo(rms(sine(1000)), 0.02));
      expect(rms(VoiceEffectChain.apply(sine(30), bp)),
          lessThan(rms(sine(30)) * 0.1));
      expect(rms(VoiceEffectChain.apply(sine(11000), bp)),
          lessThan(rms(sine(11000)) * 0.3));
    });

    test('il compressore riduce i segnali sopra soglia', () {
      const c =
          VoiceEffectSettings(compressorThresholdDb: -20, compressorRatio: 3);
      expect(rms(VoiceEffectChain.apply(sine(440, amp: 0.8), c)),
          lessThan(0.8 / math.sqrt2 * 0.6));
      expect(rms(VoiceEffectChain.apply(sine(440, amp: 0.01), c)),
          closeTo(0.01 / math.sqrt2, 0.001));
    });

    test('l\'eco allunga l\'audio e il guadagno è limitato', () {
      const e = VoiceEffectSettings(
          echoDelaysMs: [45, 90], echoDecays: [0.18, 0.1], outputGain: 4);
      final out = VoiceEffectChain.apply(sine(440, amp: 0.9, n: 2400), e);
      expect(out.samples.length, 2400 + 2160);
      expect(out.samples.every((s) => s.abs() <= 1.0), isTrue);
    });
  });
}
