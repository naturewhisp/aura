import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Generatore procedurale di file audio WAV a 8 bit.
///
/// Crea da zero i file audio WAV per gli effetti sonori e la musica di sottofondo
/// utilizzando sintesi sottrattiva ed additiva direttamente in formato PCM lineare.
class SoundGenerator {
  static final math.Random _random = math.Random();

  // Gradi della scala di Do minore naturale: Do, Re, Mib, Fa, Sol, Lab, Sib
  static const List<int> _scaleDegrees = [0, 2, 3, 5, 7, 8, 10];

  // Tema melodico principale a 64 passi (rappresentato in gradi della scala. -1 indica pausa).
  static const List<int> _melodyDegrees = [
    // Accordo 0: Cm
    7, -1, 7, 9, 11, -1, 10, 9,
    // Accordo 1: Ab
    9, -1, 9, 10, 12, -1, 11, 9,
    // Accordo 2: Fm
    10, -1, 10, 12, 14, -1, 13, 12,
    // Accordo 3: G
    11, -1, 11, 13, 15, -1, 13, 11,
    // Accordo 4: Cm
    7, -1, 7, 9, 11, -1, 13, 14,
    // Accordo 5: Eb
    13, -1, 13, 14, 16, -1, 15, 13,
    // Accordo 6: Fm
    12, -1, 12, 13, 14, -1, 16, 14,
    // Accordo 7: G
    15, -1, 15, 13, 11, -1, 13, 7
  ];

  /// Ottiene le frequenze fondamentali dell'accordo corrente.
  static List<double> _getChordFreqs(int chordIdx) {
    switch (chordIdx % 8) {
      case 0: return [130.81, 155.56, 196.00]; // Cm
      case 1: return [103.83, 130.81, 155.56]; // Ab
      case 2: return [87.31, 103.83, 130.81];  // Fm
      case 3: return [98.00, 123.47, 146.83];  // G Maggiore (con Si naturale per la scala minore armonica)
      case 4: return [130.81, 155.56, 196.00]; // Cm
      case 5: return [155.56, 196.00, 233.08]; // Eb
      case 6: return [87.31, 103.83, 130.81];  // Fm
      case 7: return [98.00, 123.47, 146.83];  // G Maggiore
      default: return [130.81, 155.56, 196.00];
    }
  }

  /// Ottiene le informazioni sulla tonica dell'accordo (frequenza fondamentale e flag per l'accordo di Sol).
  static List<dynamic> _getChordInfo(int chordIdx) {
    switch (chordIdx % 8) {
      case 0: return [65.41, false];  // Cm (Tonica Do2)
      case 1: return [51.91, false];  // Ab (Tonica Lab1)
      case 2: return [43.65, false];  // Fm (Tonica Fa1)
      case 3: return [49.00, true];   // G (Tonica Sol1)
      case 4: return [65.41, false];  // Cm (Tonica Do2)
      case 5: return [77.78, false];  // Eb (Tonica Mib2)
      case 6: return [43.65, false];  // Fm (Tonica Fa1)
      case 7: return [49.00, true];   // G (Tonica Sol1)
      default: return [65.41, false];
    }
  }

  /// Genera tutti gli effetti sonori SFX e le tracce musicali BGM nella cartella specificata se non sono già presenti.
  static Future<void> generateAllSounds(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final ambientFile = File("${dir.path}/bgm_ambient.wav");
    final tenseFile = File("${dir.path}/bgm_tense.wav");
    final epicFile = File("${dir.path}/bgm_epic.wav");

    // 1. bgm_ambient: Traccia tranquilla ed atmosferica (bass drone a triangolo + pad a doppia ottava + cyber-bell + melodia flautata)
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

          // Bass drone a onda triangolare a frequenza base (rootFreq: 43-77Hz) per generare armoniche udibili
          final double bassPhase = (t * rootFreq) % 1.0;
          final double bassTri = bassPhase < 0.5 ? (4.0 * bassPhase - 1.0) : (3.0 - 4.0 * bassPhase);
          final double bassVal = bassTri * 0.15;

          // Pad di accordi a doppia ottava (fondamentale e ottava superiore) per presenza e udibilità su laptop/altoparlanti consumer
          double padVal = 0.0;
          final double padLfo = 0.6 + 0.4 * math.sin(2 * math.pi * 0.12 * t); // LFO lento a 0.12Hz per modulare il volume
          for (int i = 0; i < 3; i++) {
            final double freq1 = chordFreqs[i];         // Ottava fondamentale (87-233 Hz)
            final double freq2 = chordFreqs[i] * 2.0;   // Ottava superiore (174-466 Hz)
            padVal += math.sin(2 * math.pi * freq1 * t);
            padVal += math.sin(2 * math.pi * freq2 * t);
          }
          padVal = (padVal / 6.0) * 0.58 * padLfo;

          // Cyber-bell soffice e periodica (ogni 4 secondi) per aggiungere texture metallica a frequenze medio-alte
          final double bellCycle = t % 4.0;
          double bellVal = 0.0;
          if (bellCycle < 2.0) { // Inviluppo con decadimento di 2 secondi
            final int noteIdx = (t ~/ 4.0) % 3;
            final double bellFreq = chordFreqs[noteIdx] * 4.0; // Ottava alta
            final double bellEnv = math.exp(-3.0 * bellCycle);
            // Somma di parziali disarmonici per timbro metallico cybernetico
            final double osc1 = math.sin(2 * math.pi * bellFreq * t);
            final double osc2 = math.sin(2 * math.pi * bellFreq * 1.5 * t) * 0.5;
            final double osc3 = math.sin(2 * math.pi * bellFreq * 2.0 * t) * 0.25;
            final double osc4 = math.sin(2 * math.pi * bellFreq * 2.63 * t) * 0.12;
            bellVal = ((osc1 + osc2 + osc3 + osc4) / 1.87) * 0.08 * bellEnv;
          }

          // Voce 4: Melodia solista in versione ambient (onda sinusoidale pura flautata con attacco lento, variazione sul tema principale)
          final int stepIdx = (t / 0.5).toInt() % 64;
          final double stepTime = t % 0.5;
          double leadVal = 0.0;
          final int degree = _melodyDegrees[stepIdx];
          if (degree != -1) {
            final int octave = degree ~/ 7;
            final int noteInScale = degree % 7;
            int semitones = _scaleDegrees[noteInScale] + octave * 12;

            if (isGChord && noteInScale == 6) { // Il Sib diventa Si naturale nell'accordo di Sol
              semitones += 1;
            }

            const double scaleRoot = 130.81; // Do3
            final double leadFreq = scaleRoot * math.pow(2.0, (12 + semitones) / 12.0); // Parte da Do4

            // Vibrato molto lento e sottile (LFO a 3Hz, intensità 0.6%)
            final double vibrato = 1.0 + 0.006 * math.sin(2 * math.pi * 3.0 * t);
            final double finalLeadFreq = leadFreq * vibrato;

            // Onda sinusoidale pura (morbida e calda)
            final double leadOsc = math.sin(2 * math.pi * finalLeadFreq * t);

            // Inviluppo con attacco lento (120ms) e decadimento dolce
            final double attack = stepTime < 0.12 ? (stepTime / 0.12) : 1.0;
            final double leadEnv = attack * math.exp(-3.0 * stepTime);
            leadVal = leadOsc * 0.04 * leadEnv; // Volume controllato per non essere invadente
          }

          // Fruscio leggerissimo di sottofondo per dare texture analogica/retro
          final double noiseVal = (_random.nextDouble() * 2.0 - 1.0) * 0.003;

          return bassVal + padVal + bellVal + leadVal + noiseVal;
        },
      );
    }

    // 2. bgm_tense: Traccia rapida per stati di allerta con arpeggiatori e percussioni in rumore bianco
    if (!tenseFile.existsSync()) {
      await _generateWavFile(
        tenseFile,
        sampleRate: 22050,
        durationSeconds: 16.0,
        generatePcm: (t) {
          final int chordIdx = (t / 2.0).toInt() % 8;
          final chordInfo = _getChordInfo(chordIdx);
          final double rootFreq = chordInfo[0];
          final bool isGChord = chordInfo[1];
          final chordFreqs = _getChordFreqs(chordIdx);

          // Voce 1: Linea di Basso (Onda a triangolo veloce con salti di ottava)
          final double bassBeat = t % 0.25;
          final double bassEnv = math.exp(-4.5 * bassBeat);
          final int bassStep = (t * 4.0).toInt() % 2;
          final double bassFreq = bassStep == 0 ? rootFreq : rootFreq * 2.0;
          final double bassPhase = (t * bassFreq) % 1.0;
          final double bassTri = bassPhase < 0.5 ? (4.0 * bassPhase - 1.0) : (3.0 - 4.0 * bassPhase);
          final double bassVal = bassTri * 0.22 * bassEnv;

          // Voce 2: Arpeggiatore Veloce (Onda quadra, 8 note al secondo, 120 BPM)
          final int arpStep = (t * 8.0).toInt() % 8;
          final double arpBeat = (t * 8.0) % 1.0;
          final double localArpT = t % 0.125; // 0.125s per nota
          double arpFreq = chordFreqs[arpStep % 3];
          if (arpStep % 4 == 3) {
            arpFreq = chordFreqs[1] * 2.0;
          }
          final double arpPhase = (localArpT * arpFreq) % 1.0;
          final double arpSquare = arpPhase < 0.5 ? 0.04 : -0.04;
          final double arpAttack = localArpT < 0.008 ? (localArpT / 0.008) : 1.0; // Attacco di 8ms
          final double arpEnv = arpAttack * math.exp(-7.0 * arpBeat);
          final double arpVal = arpSquare * arpEnv;

          // Voce 3: Batteria Incalzante
          // Cassa sui battiti 1 e 3 (ogni 0.5s)
          final double kickTime = t % 0.5;
          final double kickFreq = 150.0 * math.exp(-35.0 * kickTime);
          final double kickVal = math.sin(2 * math.pi * kickFreq * kickTime) * math.exp(-20.0 * kickTime) * 0.15;

          // Rullante sui battiti 2 e 4 (ogni 0.5s, sfasato di 0.25s)
          final double snareTime = (t - 0.25) % 0.5;
          final double snareEnv = math.exp(-25.0 * snareTime);
          final double snareVal = (_random.nextDouble() * 2.0 - 1.0) * 0.05 * snareEnv;

          // Hi-hats veloci in levare (ogni 0.25s, sfasati di 0.125s)
          final double hatTime = (t - 0.125) % 0.25;
          final double hatEnv = math.exp(-55.0 * hatTime);
          final double hatVal = (_random.nextDouble() * 2.0 - 1.0) * 0.025 * hatEnv;

          final double drumVal = kickVal + snareVal + hatVal;

          // Voce 4: Melodia solista (PWM veloce, 64 passi, 0.25s per passo)
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

            const double scaleRoot = 130.81;
            final double leadFreq = scaleRoot * math.pow(2.0, (12 + semitones) / 12.0);

            // Vibrato (LFO a 7Hz, intensità 1.5%)
            final double vibrato = 1.0 + 0.015 * math.sin(2 * math.pi * 7.0 * t);
            final double finalLeadFreq = leadFreq * vibrato;

            // Onda quadra PWM
            final double leadPhase = (stepTime * finalLeadFreq) % 1.0;
            final double dutyCycle = 0.5 + 0.3 * math.sin(2 * math.pi * 3.0 * t);
            final double leadOsc = leadPhase < dutyCycle ? 0.07 : -0.07;

            // Inviluppo AD con attacco a 15ms
            final double attack = stepTime < 0.015 ? (stepTime / 0.015) : 1.0;
            final double leadEnv = attack * math.exp(-5.0 * stepTime);
            leadVal = leadOsc * leadEnv;
          }

          return bassVal + arpVal + drumVal + leadVal;
        },
      );
    }

    // 2. bgm_epic: Traccia polifonica chiptune incalzante ed epica con progressione di accordi (vecchia ambient)
    if (!epicFile.existsSync()) {
      await _generateWavFile(
        epicFile,
        sampleRate: 22050,
        durationSeconds: 32.0,
        generatePcm: (t) {
          final int chordIdx = (t / 4.0).toInt() % 8;
          final chordInfo = _getChordInfo(chordIdx);
          final double rootFreq = chordInfo[0];
          final bool isGChord = chordInfo[1];
          final chordFreqs = _getChordFreqs(chordIdx);

          // Voce 1: Linea di Basso (Onda a triangolo, pulsante e ritmica)
          final double bassBeat = t % 0.5;
          final double bassEnv = math.exp(-3.5 * bassBeat);
          final double bassPhase = (t * rootFreq) % 1.0;
          final double bassTri = bassPhase < 0.5 ? (4.0 * bassPhase - 1.0) : (3.0 - 4.0 * bassPhase);
          final double bassVal = bassTri * 0.28 * bassEnv;

          // Voce 2: Arpeggiatore (Onda quadra, stile chiptune lento C64, 4 note al secondo)
          final int arpStep = (t * 4.0).toInt() % 4;
          final double arpBeat = (t * 4.0) % 1.0;
          final double localArpT = t % 0.25; // 0.25s per nota
          double arpFreq = chordFreqs[arpStep % 3];
          if (arpStep == 3) {
            arpFreq = chordFreqs[1] * 2.0; // Salto di ottava
          }
          final double arpPhase = (localArpT * arpFreq) % 1.0;
          final double arpSquare = arpPhase < 0.5 ? 0.04 : -0.04;
          final double arpAttack = localArpT < 0.01 ? (localArpT / 0.01) : 1.0; // Attacco di 10ms per evitare clic digitali
          final double arpEnv = arpAttack * math.exp(-5.0 * arpBeat);
          final double arpVal = arpSquare * arpEnv;

          // Voce 3: Simulazione Batteria (Cassa filtrata, rullante in rumore bianco e hi-hat)
          final double kickTime = t % 1.0;
          final double kickFreq = 120.0 * math.exp(-25.0 * kickTime);
          final double kickVal = math.sin(2 * math.pi * kickFreq * kickTime) * math.exp(-15.0 * kickTime) * 0.12;

          final double snareTime = (t - 0.5) % 1.0;
          final double snareEnv = math.exp(-22.0 * snareTime);
          final double snareVal = (_random.nextDouble() * 2.0 - 1.0) * 0.035 * snareEnv;

          final double hatTime = (t - 0.25) % 0.5;
          final double hatEnv = math.exp(-45.0 * hatTime);
          final double hatVal = (_random.nextDouble() * 2.0 - 1.0) * 0.015 * hatEnv;

          final double drumVal = kickVal + snareVal + hatVal;

          // Voce 4: Melodia solista (Onda quadra a modulazione di larghezza di impulso PWM + vibrato, 64 passi totali, 0.5s per passo)
          final int stepIdx = (t / 0.5).toInt() % 64;
          final double stepTime = t % 0.5;
          
          double leadVal = 0.0;
          final int degree = _melodyDegrees[stepIdx];
          if (degree != -1) {
            final int octave = degree ~/ 7;
            final int noteInScale = degree % 7;
            int semitones = _scaleDegrees[noteInScale] + octave * 12;

            if (isGChord && noteInScale == 6) { // Il Sib diventa Si naturale nell'accordo di Sol
              semitones += 1;
            }

            const double scaleRoot = 130.81; // Do3
            final double leadFreq = scaleRoot * math.pow(2.0, (12 + semitones) / 12.0); // Parte da Do4

            // Vibrato (LFO a 6Hz, intensità 1.2%)
            final double vibrato = 1.0 + 0.012 * math.sin(2 * math.pi * 6.0 * t);
            final double finalLeadFreq = leadFreq * vibrato;

            // Onda quadra PWM
            final double leadPhase = (stepTime * finalLeadFreq) % 1.0;
            final double dutyCycle = 0.5 + 0.3 * math.sin(2 * math.pi * 2.0 * t);
            final double leadOsc = leadPhase < dutyCycle ? 0.08 : -0.08;

            // Inviluppo AD
            final double attack = stepTime < 0.02 ? (stepTime / 0.02) : 1.0;
            final double leadEnv = attack * math.exp(-3.5 * stepTime);
            leadVal = leadOsc * leadEnv;
          }

          return bassVal + arpVal + drumVal + leadVal;
        },
      );
    }





    // 3. sfx_click: Click meccanico della tastiera (glide di frequenza discendente molto corto)
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

    // 4. sfx_alert: Allarme bitonale in stile cabinato arcade ("bee-woo")
    final alertFile = File("${dir.path}/sfx_alert.wav");
    if (!alertFile.existsSync()) {
      await _generateWavFile(
        alertFile,
        sampleRate: 22050,
        durationSeconds: 0.4,
        generatePcm: (t) {
          final double lfo = math.sin(2 * math.pi * 5.0 * t); // LFO FM a 5Hz
          final double freq = 850.0 + 250.0 * lfo;
          final double osc = math.sin(2 * math.pi * freq * t) >= 0.0 ? 0.3 : -0.3;
          final double env = t < 0.02 ? (t / 0.02) : (t > 0.35 ? (0.4 - t) / 0.05 : 1.0);
          return osc * env;
        },
      );
    }

    // 5. sfx_glitch: Rumore bitcrushed per simulare glitch e interferenze di sistema
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

    // 6. sfx_chime: Arpeggio chiptune ascendente (Do5 -> Mi5 -> Sol5 -> Do6) per bonus pilastri
    final chimeFile = File("${dir.path}/sfx_chime.wav");
    if (!chimeFile.existsSync()) {
      await _generateWavFile(
        chimeFile,
        sampleRate: 22050,
        durationSeconds: 0.45,
        generatePcm: (t) {
          double freq;
          if (t < 0.06) {
            freq = 523.25; // Do5
          } else if (t < 0.12) {
            freq = 659.25; // Mi5
          } else if (t < 0.18) {
            freq = 783.99; // Sol5
          } else {
            freq = 1046.50; // Do6
          }

          final double osc = math.sin(2 * math.pi * freq * t) >= 0.0 ? 0.3 : -0.3;
          final double env = t > 0.18 ? math.exp(-7.0 * (t - 0.18)) : 1.0;
          return osc * env;
        },
      );
    }
  }

  /// Scrive un file WAV standard formattando l'intestazione RIFF e iniettando i campioni PCM a 16-bit.
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

    // Intestazione RIFF
    builder.add(utf8.encode("RIFF"));
    builder.add(_int32ToBytes(chunkSize));
    builder.add(utf8.encode("WAVE"));

    // Subchunk fmt
    builder.add(utf8.encode("fmt "));
    builder.add(_int32ToBytes(16)); // Subchunk1Size
    builder.add(_int16ToBytes(1));  // AudioFormat (PCM lineare)
    builder.add(_int16ToBytes(numChannels));
    builder.add(_int32ToBytes(sampleRate));
    builder.add(_int32ToBytes(byteRate));
    builder.add(_int16ToBytes(blockAlign));
    builder.add(_int16ToBytes(bitsPerSample));

    // Subchunk data
    builder.add(utf8.encode("data"));
    builder.add(_int32ToBytes(subChunk2Size));

    // Scrittura campioni PCM a 16-bit
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double sampleVal = generatePcm(t).clamp(-1.0, 1.0);
      final int sampleInt = (sampleVal * 32767.0).round();
      builder.add(_int16ToBytes(sampleInt));
    }

    await file.writeAsBytes(builder.toBytes());
  }

  /// Converte un intero a 32-bit in un array di 4 byte (Little Endian).
  static List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  /// Converte un intero a 16-bit in un array di 2 byte (Little Endian).
  static List<int> _int16ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
    ];
  }
}
