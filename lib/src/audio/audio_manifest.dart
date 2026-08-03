import 'package:meta/meta.dart';

/// Tipologia di traccia audio.
enum AudioTrackKind {
  bgm,
  sfx,
}

/// Ruolo funzionale della traccia all'interno dell'esperienza di gioco.
enum AudioTrackRole {
  mainMenu,
  ambient,
  tense,
  epic,
  click,
  alert,
  glitch,
  chime,
}

/// Codici di fallimento e diagnosi tipizzati per l'infrastruttura audio.
enum AudioAssetFailureCode {
  manifestMissing,
  manifestMalformed,
  unsupportedSchemaVersion,
  trackMissing,
  sizeMismatch,
  checksumMismatch,
  invalidRiffHeader,
  unsupportedEncoding,
  formatMismatch,
  durationMismatch,
  bundledRepairFailed,
  proceduralFallbackUsed,
}

/// Eccezione di dominio per errori relativi al manifest o alle tracce audio.
@immutable
final class AudioManifestException implements Exception {
  final AudioAssetFailureCode code;
  final String message;
  final String? trackId;

  const AudioManifestException({
    required this.code,
    required this.message,
    this.trackId,
  });

  @override
  String toString() =>
      'AudioManifestException[$code]: $message${trackId != null ? ' (track: $trackId)' : ''}';
}

/// Descrizione immutabile di una singola traccia audio all'interno del manifest.
@immutable
final class AudioTrackDescriptor {
  final String id;
  final AudioTrackKind kind;
  final AudioTrackRole role;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final String codec;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int durationMs;
  final bool loop;
  final bool required;

  AudioTrackDescriptor({
    required this.id,
    required this.kind,
    required this.role,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.durationMs,
    required this.loop,
    required this.required,
  }) {
    if (id.trim().isEmpty) {
      throw const AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'L\'ID della traccia non può essere vuoto.',
      );
    }
    if (filename.trim().isEmpty ||
        filename.contains('/') ||
        filename.contains(r'\') ||
        filename.contains('..')) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Filename non valido o sospetto path traversal: "$filename".',
        trackId: id,
      );
    }
    if (sizeBytes <= 0) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.sizeMismatch,
        message: 'La dimensione sizeBytes deve essere maggiore di zero.',
        trackId: id,
      );
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.checksumMismatch,
        message:
            'Formato hash SHA-256 non valido (richieste 64 cifre esadecimali).',
        trackId: id,
      );
    }
    if (sampleRate <= 0 || channels <= 0 || bitsPerSample <= 0) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.formatMismatch,
        message:
            'Parametri audio (sampleRate, channels, bitsPerSample) non validi.',
        trackId: id,
      );
    }
  }

  factory AudioTrackDescriptor.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "id" della traccia deve essere una stringa.',
      );
    }

    final rawKind = json['kind'];
    final kind = switch (rawKind) {
      'bgm' => AudioTrackKind.bgm,
      'sfx' => AudioTrackKind.sfx,
      _ => throw AudioManifestException(
          code: AudioAssetFailureCode.manifestMalformed,
          message: 'Tipologia traccia "kind" non valida: $rawKind',
          trackId: id,
        ),
    };

    final rawRole = json['role'];
    final role = switch (rawRole) {
      'mainMenu' => AudioTrackRole.mainMenu,
      'ambient' => AudioTrackRole.ambient,
      'tense' => AudioTrackRole.tense,
      'epic' => AudioTrackRole.epic,
      'click' => AudioTrackRole.click,
      'alert' => AudioTrackRole.alert,
      'glitch' => AudioTrackRole.glitch,
      'chime' => AudioTrackRole.chime,
      _ => throw AudioManifestException(
          code: AudioAssetFailureCode.manifestMalformed,
          message: 'Ruolo traccia "role" non valido: $rawRole',
          trackId: id,
        ),
    };

    final filename = json['filename'];
    if (filename is! String) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "filename" deve essere una stringa.',
        trackId: id,
      );
    }

    final sizeBytes = json['sizeBytes'];
    if (sizeBytes is! int) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "sizeBytes" deve essere un intero esatto.',
        trackId: id,
      );
    }

    final sha256 = json['sha256'];
    if (sha256 is! String) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "sha256" deve essere una stringa.',
        trackId: id,
      );
    }

    final codec = json['codec'];
    if (codec is! String) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "codec" deve essere una stringa.',
        trackId: id,
      );
    }

    final sampleRate = json['sampleRate'];
    if (sampleRate is! int) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "sampleRate" deve essere un intero.',
        trackId: id,
      );
    }

    final channels = json['channels'];
    if (channels is! int) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "channels" deve essere un intero.',
        trackId: id,
      );
    }

    final bitsPerSample = json['bitsPerSample'];
    if (bitsPerSample is! int) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "bitsPerSample" deve essere un intero.',
        trackId: id,
      );
    }

    final durationMs = json['durationMs'];
    if (durationMs is! int) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "durationMs" deve essere un intero.',
        trackId: id,
      );
    }

    final loop = json['loop'];
    if (loop is! bool) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "loop" deve essere un booleano.',
        trackId: id,
      );
    }

    final required = json['required'];
    if (required is! bool) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "required" deve essere un booleano.',
        trackId: id,
      );
    }

    return AudioTrackDescriptor(
      id: id,
      kind: kind,
      role: role,
      filename: filename,
      sizeBytes: sizeBytes,
      sha256: sha256,
      codec: codec,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      durationMs: durationMs,
      loop: loop,
      required: required,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'role': role.name,
        'filename': filename,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'codec': codec,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitsPerSample': bitsPerSample,
        'durationMs': durationMs,
        'loop': loop,
        'required': required,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrackDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          role == other.role &&
          filename == other.filename &&
          sizeBytes == other.sizeBytes &&
          sha256 == other.sha256 &&
          codec == other.codec &&
          sampleRate == other.sampleRate &&
          channels == other.channels &&
          bitsPerSample == other.bitsPerSample &&
          durationMs == other.durationMs &&
          loop == other.loop &&
          required == other.required;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        role,
        filename,
        sizeBytes,
        sha256,
        codec,
        sampleRate,
        channels,
        bitsPerSample,
        durationMs,
        loop,
        required,
      );
}

/// Contenitore immutabile per il manifest delle risorse audio.
@immutable
final class AudioManifest {
  final int schemaVersion;
  final String audioSetId;
  final List<AudioTrackDescriptor> tracks;

  AudioManifest({
    required this.schemaVersion,
    required this.audioSetId,
    required this.tracks,
  }) {
    if (schemaVersion != 1) {
      throw AudioManifestException(
        code: AudioAssetFailureCode.unsupportedSchemaVersion,
        message:
            'Versione di schema non supportata: $schemaVersion (attesa: 1).',
      );
    }
    if (audioSetId.trim().isEmpty) {
      throw const AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'L\'audioSetId non può essere vuoto.',
      );
    }
    final seenIds = <String>{};
    final seenFilenames = <String>{};
    for (final track in tracks) {
      if (!seenIds.add(track.id)) {
        throw AudioManifestException(
          code: AudioAssetFailureCode.manifestMalformed,
          message: 'ID traccia duplicato nel manifest: "${track.id}".',
          trackId: track.id,
        );
      }
      if (!seenFilenames.add(track.filename)) {
        throw AudioManifestException(
          code: AudioAssetFailureCode.manifestMalformed,
          message:
              'Filename traccia duplicato nel manifest: "${track.filename}".',
          trackId: track.id,
        );
      }
    }
  }

  factory AudioManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "schemaVersion" deve essere un intero.',
      );
    }

    final audioSetId = json['audioSetId'];
    if (audioSetId is! String) {
      throw const AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "audioSetId" deve essere una stringa.',
      );
    }

    final rawTracks = json['tracks'];
    if (rawTracks is! List) {
      throw const AudioManifestException(
        code: AudioAssetFailureCode.manifestMalformed,
        message: 'Il campo "tracks" deve essere una lista.',
      );
    }

    final tracks = rawTracks
        .map((t) => AudioTrackDescriptor.fromJson(t as Map<String, dynamic>))
        .toList();

    return AudioManifest(
      schemaVersion: schemaVersion,
      audioSetId: audioSetId,
      tracks: List.unmodifiable(tracks),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'audioSetId': audioSetId,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  /// Cerca una traccia nel manifest tramite il suo ID univoco.
  AudioTrackDescriptor? findTrackById(String id) {
    for (final t in tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Cerca una traccia nel manifest tramite il suo ruolo funzionale.
  AudioTrackDescriptor? findTrackByRole(AudioTrackRole role) {
    for (final t in tracks) {
      if (t.role == role) return t;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioManifest &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          audioSetId == other.audioSetId &&
          _listEquals(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        audioSetId,
        Object.hashAll(tracks),
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
