import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class SoundGenerator {
  static final math.Random _random = math.Random();

  // C natural minor scale degrees: C, D, Eb, F, G, Ab, Bb
  static const List<int> _scaleDegrees = [0, 2, 3, 5, 7, 8, 10];

  // 64-step melody theme (represented in scale degrees. -1 is a rest).
  static const List<int> _melodyDegrees = [
    // Chord 0: Cm
    7, -1, 7, 9, 11, -1, 10, 9,
    // Chord 1: Ab
    9, -1, 9, 10, 12, -1, 11, 9,
    // Chord 2: Fm
    10, -1, 10, 12, 14, -1, 13, 12,
    // Chord 3: G
    11, -1, 11, 13, 15, -1, 13, 11,
    // Chord 4: Cm
    7, -1, 7, 9, 11, -1, 13, 14,
    // Chord 5: Eb
    13, -1, 13, 14, 16, -1, 15, 13,
    // Chord 6: Fm
    12, -1, 12, 13, 14, -1, 16, 14,
    // Chord 7: G
    15, -1, 15, 13, 11, -1, 13, 7
  ];

  static List<double> _getChordFreqs(int chordIdx) {
    switch (chordIdx % 8) {
      case 0: return [130.81, 155.56, 196.00]; // Cm
      case 1: return [103.83, 130.81, 155.56]; // Ab
      case 2: return [87.31, 103.83, 130.81];  // Fm
      case 3: return [98.00, 123.47, 146.83];  // G Major (harmonic minor B natural)
      case 4: return [130.81, 155.56, 196.00]; // Cm
      case 5: return [155.56, 196.00, 233.08]; // Eb
      case 6: return [87.31, 103.83, 130.81];  // Fm
      case 7: return [98.00, 123.47, 146.83];  // G Major
      default: return [130.81, 155.56, 196.00];
    }
  }

  static List<dynamic> _getChordInfo(int chordIdx) {
    switch (chordIdx % 8) {
      case 0: return [65.41, false];  // Cm (Root C2)
      case 1: return [51.91, false];  // Ab (Root Ab1)
      case 2: return [43.65, false];  // Fm (Root F1)
      case 3: return [49.00, true];   // G (Root G1)
      case 4: return [65.41, false];  // Cm (Root C2)
      case 5: return [77.78, false];  // Eb (Root Eb2)
      case 6: return [43.65, false];  // Fm (Root F1)
      case 7: return [49.00, true];   // G (Root G1)
      default: return [65.41, false];
    }
  }

  /// Generates all retro arcade SFX and BGM files in the target directory if they do not exist.
  static Future<void> generateAllSounds(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Version management to force regeneration of upgraded procedural files
    final versionFile = File("${dir.path}/audio_version.txt");
    bool forceRegen = true;
    if (versionFile.existsSync()) {
      try {
        final version = versionFile.readAsStringSync().trim();
        if (version == "3") {
          forceRegen = false;
        }
      } catch (_) {}
    }

    final ambientFile = File("${dir.path}/bgm_ambient.wav");
    if (ambientFile.existsSync()) {
      final len = ambientFile.lengthSync();
      // Delete old procedural file or force if version changed
      if (len == 705644 || forceRegen) {
        try { ambientFile.deleteSync(); } catch (_) {}
      }
    }

    final tenseFile = File("${dir.path}/bgm_tense.wav");
    if (tenseFile.existsSync()) {
      final len = tenseFile.lengthSync();
      // Delete old procedural file or force if version changed
      if (len == 352844 || forceRegen) {
        try { tenseFile.deleteSync(); } catch (_) {}
      }
    }

    // 1. bgm_ambient: Polyphonic chiptune ambient track with chord progression (C minor)
    if (!ambientFile.existsSync()) {
      await _generateWavFile(
        ambientFile,
        sampleRate: 22050,
        durationSeconds: 32.0,
        generatePcm: (t) {
          final int chordIdx = (t / 4.0).toInt() % 8;
          final chordInfo = _getChordInfo(chordIdx);
          final double rootFreq = chordInfo[0];
          final bool isGChord = chordInfo[1];
          final chordFreqs = _getChordFreqs(chordIdx);

          // Voice 1: Bassline (Triangle wave, rhythmic pumping)
          final double bassBeat = t % 0.5;
          final double bassEnv = math.exp(-3.5 * bassBeat);
          final double bassPhase = (t * rootFreq) % 1.0;
          final double bassTri = bassPhase < 0.5 ? (4.0 * bassPhase - 1.0) : (3.0 - 4.0 * bassPhase);
          final double bassVal = bassTri * 0.28 * bassEnv;

          // Voice 2: Arpeggiator (Square wave, C64 slow arpeggio style, 4 notes per second)
          final int arpStep = (t * 4.0).toInt() % 4;
          final double arpBeat = (t * 4.0) % 1.0;
          final double localArpT = t % 0.25; // 0.25s per note
          double arpFreq = chordFreqs[arpStep % 3];
          if (arpStep == 3) {
            arpFreq = chordFreqs[1] * 2.0; // octave chord component
          }
          final double arpPhase = (localArpT * arpFreq) % 1.0;
          final double arpSquare = arpPhase < 0.5 ? 0.04 : -0.04;
          final double arpAttack = localArpT < 0.01 ? (localArpT / 0.01) : 1.0; // 10ms attack to prevent clicks
          final double arpEnv = arpAttack * math.exp(-5.0 * arpBeat);
          final double arpVal = arpSquare * arpEnv;

          // Voice 3: Drum simulation (Soft white noise kick, snare, and hi-hats)
          // Kick drum on beats 1 and 3 (every 1.0s)
          final double kickTime = t % 1.0;
          final double kickFreq = 120.0 * math.exp(-25.0 * kickTime);
          final double kickVal = math.sin(2 * math.pi * kickFreq * kickTime) * math.exp(-15.0 * kickTime) * 0.12;

          // Snare on beats 2 and 4 (every 1.0s, offset by 0.5s)
          final double snareTime = (t - 0.5) % 1.0;
          final double snareEnv = math.exp(-22.0 * snareTime);
          final double snareVal = (_random.nextDouble() * 2.0 - 1.0) * 0.035 * snareEnv;

          // Hi-hats on off-beats (every 0.5s, offset by 0.25s)
          final double hatTime = (t - 0.25) % 0.5;
          final double hatEnv = math.exp(-45.0 * hatTime);
          final double hatVal = (_random.nextDouble() * 2.0 - 1.0) * 0.015 * hatEnv;

          final double drumVal = kickVal + snareVal + hatVal;

          // Voice 4: Lead Melody (PWM Square wave + vibrato, 64 steps total, 0.5s per step)
          final int stepIdx = (t / 0.5).toInt() % 64;
          final double stepTime = t % 0.5;
          
          double leadVal = 0.0;
          final int degree = _melodyDegrees[stepIdx];
          if (degree != -1) {
            final int octave = degree ~/ 7;
            final int noteInScale = degree % 7;
            int semitones = _scaleDegrees[noteInScale] + octave * 12;

            if (isGChord && noteInScale == 6) { // Bb becomes B
              semitones += 1;
            }

            const double scaleRoot = 130.81; // C3
            final double leadFreq = scaleRoot * math.pow(2.0, (12 + semitones) / 12.0); // starts at C4

            // Vibrato (6Hz LFO, 1.2% depth)
            final double vibrato = 1.0 + 0.012 * math.sin(2 * math.pi * 6.0 * t);
            final double finalLeadFreq = leadFreq * vibrato;

            // PWM Square Wave (2Hz LFO for pulse width)
            // Use stepTime instead of t for phase calculation to prevent cumulative drift and clicks!
            final double leadPhase = (stepTime * finalLeadFreq) % 1.0;
            final double dutyCycle = 0.5 + 0.3 * math.sin(2 * math.pi * 2.0 * t);
            final double leadOsc = leadPhase < dutyCycle ? 0.08 : -0.08; // quieter lead for less harshness

            // Attack/Decay Envelope (20ms fade-in to prevent digital click)
            final double attack = stepTime < 0.02 ? (stepTime / 0.02) : 1.0;
            final double leadEnv = attack * math.exp(-3.5 * stepTime);
            leadVal = leadOsc * leadEnv;
          }

          return bassVal + arpVal + drumVal + leadVal;
        },
      );
    }

    // 2. bgm_tense: Fast polyphonic 8-bit arpeggiator with chords and white noise drums
    if (!tenseFile.existsSync()) {
      await _generateWavFile(
        tenseFile,
        sampleRate: 22050,
        durationSeconds: 16.0,
        generatePcm: (t) {
          // Chords change every 2.0 seconds in tense mode
          final int chordIdx = (t / 2.0).toInt() % 8;
          final chordInfo = _getChordInfo(chordIdx);
          final double rootFreq = chordInfo[0];
          final bool isGChord = chordInfo[1];
          final chordFreqs = _getChordFreqs(chordIdx);

          // Voice 1: Bassline (Triangle wave, fast pumping with octave jumps)
          final double bassBeat = t % 0.25;
          final double bassEnv = math.exp(-4.5 * bassBeat);
          final int bassStep = (t * 4.0).toInt() % 2;
          final double bassFreq = bassStep == 0 ? rootFreq : rootFreq * 2.0;
          final double bassPhase = (t * bassFreq) % 1.0;
          final double bassTri = bassPhase < 0.5 ? (4.0 * bassPhase - 1.0) : (3.0 - 4.0 * bassPhase);
          final double bassVal = bassTri * 0.22 * bassEnv;

          // Voice 2: Fast Arpeggiator (Square wave, 8 notes per second, 120 BPM)
          final int arpStep = (t * 8.0).toInt() % 8;
          final double arpBeat = (t * 8.0) % 1.0;
          final double localArpT = t % 0.125; // 0.125s per note
          double arpFreq = chordFreqs[arpStep % 3];
          if (arpStep % 4 == 3) {
            arpFreq = chordFreqs[1] * 2.0; // octave jump
          }
          final double arpPhase = (localArpT * arpFreq) % 1.0;
          final double arpSquare = arpPhase < 0.5 ? 0.04 : -0.04;
          final double arpAttack = localArpT < 0.008 ? (localArpT / 0.008) : 1.0; // 8ms attack
          final double arpEnv = arpAttack * math.exp(-7.0 * arpBeat);
          final double arpVal = arpSquare * arpEnv;

          // Voice 3: Drum simulation (Tense, fast hi-hats, punchy kick and snare)
          // Kick drum on beats 1 and 3 (every 0.5s)
          final double kickTime = t % 0.5;
          final double kickFreq = 150.0 * math.exp(-35.0 * kickTime);
          final double kickVal = math.sin(2 * math.pi * kickFreq * kickTime) * math.exp(-20.0 * kickTime) * 0.15;

          // Snare on beats 2 and 4 (every 0.5s, offset by 0.25s)
          final double snareTime = (t - 0.25) % 0.5;
          final double snareEnv = math.exp(-25.0 * snareTime);
          final double snareVal = (_random.nextDouble() * 2.0 - 1.0) * 0.05 * snareEnv;

          // Hi-hats on off-beats (every 0.25s, offset by 0.125s)
          final double hatTime = (t - 0.125) % 0.25;
          final double hatEnv = math.exp(-55.0 * hatTime);
          final double hatVal = (_random.nextDouble() * 2.0 - 1.0) * 0.025 * hatEnv;

          final double drumVal = kickVal + snareVal + hatVal;

          // Voice 4: Lead Melody (PWM Square wave, 64 steps total, 0.25s per step -> playing twice as fast!)
          final int stepIdx = (t / 0.25).toInt() % 64;
          final double stepTime = t % 0.25;

          double leadVal = 0.0;
          final int degree = _melodyDegrees[stepIdx];
          if (degree != -1) {
            final int octave = degree ~/ 7;
            final int noteInScale = degree % 7;
            int semitones = _scaleDegrees[noteInScale] + octave * 12;

            if (isGChord && noteInScale == 6) {
              semitones += 1;
            }

            const double scaleRoot = 130.81; // C3
            final double leadFreq = scaleRoot * math.pow(2.0, (12 + semitones) / 12.0); // starts at C4

            // Vibrato (7Hz LFO, 1.5% depth for tension)
            final double vibrato = 1.0 + 0.015 * math.sin(2 * math.pi * 7.0 * t);
            final double finalLeadFreq = leadFreq * vibrato;

            // PWM Square Wave
            // Use stepTime instead of t for phase calculation to prevent cumulative drift and clicks!
            final double leadPhase = (stepTime * finalLeadFreq) % 1.0;
            final double dutyCycle = 0.5 + 0.3 * math.sin(2 * math.pi * 3.0 * t);
            final double leadOsc = leadPhase < dutyCycle ? 0.07 : -0.07; // quieter lead for less harshness

            // Fast envelope with 15ms fade-in
            final double attack = stepTime < 0.015 ? (stepTime / 0.015) : 1.0;
            final double leadEnv = attack * math.exp(-5.0 * stepTime);
            leadVal = leadOsc * leadEnv;
          }

          return bassVal + arpVal + drumVal + leadVal;
        },
      );
    }

    // Write version file to prevent unnecessary regens
    try {
      versionFile.writeAsStringSync("3");
    } catch (_) {}

    // 3. sfx_click: Retro mechanical keyboard click (decaying pitch glide)
    final clickFile = File("${dir.path}/sfx_click.wav");
    if (!clickFile.existsSync()) {
      await _generateWavFile(
        clickFile,
        sampleRate: 22050,
        durationSeconds: 0.02,
        generatePcm: (t) {
          final double freq = 1500.0 - 700.0 * (t / 0.02);
          final double osc = math.sin(2 * math.pi * freq * t);
          final double env = math.exp(-180.0 * t);
          return osc * 0.3 * env;
        },
      );
    }

    // 4. sfx_alert: Classic arcade dual-tone alarm ("bee-woo")
    final alertFile = File("${dir.path}/sfx_alert.wav");
    if (!alertFile.existsSync()) {
      await _generateWavFile(
        alertFile,
        sampleRate: 22050,
        durationSeconds: 0.4,
        generatePcm: (t) {
          final double lfo = math.sin(2 * math.pi * 5.0 * t); // 5Hz FM LFO
          final double freq = 850.0 + 250.0 * lfo;
          final double osc = math.sin(2 * math.pi * freq * t) >= 0.0 ? 0.3 : -0.3;
          final double env = t < 0.02 ? (t / 0.02) : (t > 0.35 ? (0.4 - t) / 0.05 : 1.0);
          return osc * env;
        },
      );
    }

    // 5. sfx_glitch: Bitcrushed noise buzz
    final glitchFile = File("${dir.path}/sfx_glitch.wav");
    if (!glitchFile.existsSync()) {
      await _generateWavFile(
        glitchFile,
        sampleRate: 22050,
        durationSeconds: 0.15,
        generatePcm: (t) {
          final double env = math.exp(-15.0 * t);
          final double square = math.sin(2 * math.pi * 80.0 * t) >= 0.0 ? 1.0 : -1.0;
          final double rawNoise = math.Random().nextDouble() * 2.0 - 1.0;
          final double bitcrushNoise = (rawNoise * 4.0).round() / 4.0;
          final double mix = 0.5 * square + 0.5 * bitcrushNoise;
          return mix * 0.35 * env;
        },
      );
    }

    // 6. sfx_chime: Ascending chiptune arpeggio (C5 -> E5 -> G5 -> C6 power-up sound)
    final chimeFile = File("${dir.path}/sfx_chime.wav");
    if (!chimeFile.existsSync()) {
      await _generateWavFile(
        chimeFile,
        sampleRate: 22050,
        durationSeconds: 0.45,
        generatePcm: (t) {
          double freq;
          if (t < 0.06) {
            freq = 523.25; // C5
          } else if (t < 0.12) {
            freq = 659.25; // E5
          } else if (t < 0.18) {
            freq = 783.99; // G5
          } else {
            freq = 1046.50; // C6
          }

          final double osc = math.sin(2 * math.pi * freq * t) >= 0.0 ? 0.3 : -0.3;
          final double env = t > 0.18 ? math.exp(-7.0 * (t - 0.18)) : 1.0;
          return osc * env;
        },
      );
    }
  }

  static Future<void> _generateWavFile(
    File file, {
    required int sampleRate,
    required double durationSeconds,
    required double Function(double t) generatePcm,
  }) async {
    final int numSamples = (sampleRate * durationSeconds).toInt();
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int subChunk2Size = numSamples * numChannels * (bitsPerSample ~/ 8);
    final int chunkSize = 36 + subChunk2Size;

    final builder = BytesBuilder();

    // RIFF Header
    builder.add(utf8.encode("RIFF"));
    builder.add(_int32ToBytes(chunkSize));
    builder.add(utf8.encode("WAVE"));

    // fmt Subchunk
    builder.add(utf8.encode("fmt "));
    builder.add(_int32ToBytes(16)); // Subchunk1Size
    builder.add(_int16ToBytes(1));  // AudioFormat (PCM)
    builder.add(_int16ToBytes(numChannels));
    builder.add(_int32ToBytes(sampleRate));
    builder.add(_int32ToBytes(byteRate));
    builder.add(_int16ToBytes(blockAlign));
    builder.add(_int16ToBytes(bitsPerSample));

    // data Subchunk
    builder.add(utf8.encode("data"));
    builder.add(_int32ToBytes(subChunk2Size));

    // Write PCM samples
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double sampleVal = generatePcm(t).clamp(-1.0, 1.0);
      final int sampleInt = (sampleVal * 32767.0).round();
      builder.add(_int16ToBytes(sampleInt));
    }

    await file.writeAsBytes(builder.toBytes());
  }

  static List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  static List<int> _int16ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
    ];
  }
}
