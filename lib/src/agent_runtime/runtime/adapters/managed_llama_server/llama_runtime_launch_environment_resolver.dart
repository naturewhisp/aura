import 'dart:io' as io;
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// DTO immutabile contenente l'ambiente di lancio isolato process-local per `llama-server`.
@immutable
final class RuntimeLaunchEnvironment {
  final String workingDirectory;
  final Map<String, String> environmentOverrides;

  const RuntimeLaunchEnvironment({
    required this.workingDirectory,
    required this.environmentOverrides,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeLaunchEnvironment &&
          runtimeType == other.runtimeType &&
          workingDirectory == other.workingDirectory &&
          const MapEquality<String, String>().equals(
            environmentOverrides,
            other.environmentOverrides,
          );

  @override
  int get hashCode => Object.hash(
        workingDirectory,
        const MapEquality<String, String>().hash(environmentOverrides),
      );
}

/// Resolver dell'ambiente di lancio process-local per `llama-server`.
abstract interface class LlamaRuntimeLaunchEnvironmentResolver {
  RuntimeLaunchEnvironment resolve({
    required String executablePath,
    required String workingDirectory,
    List<String> vendorDirectories = const [],
    Map<String, String>? baseEnvironment,
    Map<String, String>? environmentOverrides,
  });
}

/// Implementazione predefinita del resolver dell'ambiente di lancio.
final class DefaultLlamaRuntimeLaunchEnvironmentResolver
    implements LlamaRuntimeLaunchEnvironmentResolver {
  const DefaultLlamaRuntimeLaunchEnvironmentResolver();

  @override
  RuntimeLaunchEnvironment resolve({
    required String executablePath,
    required String workingDirectory,
    List<String> vendorDirectories = const [],
    Map<String, String>? baseEnvironment,
    Map<String, String>? environmentOverrides,
  }) {
    // 1. Unione completa dell'ambiente base di sistema con gli overrides specifici
    final env = <String, String>{
      ...(baseEnvironment ?? io.Platform.environment),
      if (environmentOverrides != null) ...environmentOverrides,
    };

    final pathKey = env.keys.firstWhere(
      (k) => k.toUpperCase() == 'PATH',
      orElse: () => 'PATH',
    );

    final rawPath = env[pathKey] ?? '';

    // 2. Separa le voci di PATH esistenti (mantiene .lmstudio se l'eseguibile si trova in LM Studio o se è un percorso vendor CUDA)
    final isLmStudioPath = executablePath.toLowerCase().contains('.lmstudio') ||
        executablePath.toLowerCase().contains('lm-studio');
    final pathSeparator = io.Platform.isWindows ? ';' : ':';
    final existingEntries = rawPath.split(pathSeparator).where((e) {
      final clean = e.toLowerCase().trim();
      if (clean.isEmpty) return false;
      if (!isLmStudioPath &&
          (clean.contains('.lmstudio') || clean.contains('lm-studio'))) {
        final isVendor = clean.contains('vendor') || clean.contains('cuda');
        if (!isVendor) {
          return false;
        }
      }
      return true;
    }).toList();

    // 3. Raccoglie le directory vendor pulite
    final newEntries = <String>[];
    for (final vendor in vendorDirectories) {
      if (vendor.trim().isNotEmpty && !newEntries.contains(vendor.trim())) {
        newEntries.add(vendor.trim());
      }
    }

    void addVendorDirIfExist(String dirPath) {
      if (dirPath.trim().isEmpty) return;
      final cleanDir = dirPath.trim();
      final dirObj = io.Directory(cleanDir);
      if (dirObj.existsSync()) {
        if (!newEntries.contains(cleanDir)) {
          newEntries.add(cleanDir);
        }
        try {
          final subDirs = dirObj.listSync().whereType<io.Directory>();
          for (final sub in subDirs) {
            if (!newEntries.contains(sub.path)) {
              newEntries.add(sub.path);
            }
          }
        } catch (_) {}
      }
    }

    // 4. Discovery automatica di directory vendor CUDA su Windows (se presenti sul sistema)
    if (io.Platform.isWindows) {
      final userProfile = env['USERPROFILE'] ?? env['HOME'] ?? '';
      if (userProfile.isNotEmpty) {
        final lmStudioVendorRoot = io.Directory(
          '$userProfile\\.lmstudio\\extensions\\backends\\vendor',
        );
        if (lmStudioVendorRoot.existsSync()) {
          try {
            final vendorDirs =
                lmStudioVendorRoot.listSync().whereType<io.Directory>();
            for (final dir in vendorDirs) {
              if (dir.path.toLowerCase().contains('cuda')) {
                addVendorDirIfExist(dir.path);
              }
            }
          } catch (_) {}
        }
      }

      final programFiles = env['ProgramFiles'] ?? r'C:\Program Files';
      final cudaToolkitDir =
          io.Directory('$programFiles\\NVIDIA GPU Computing Toolkit\\CUDA');
      if (cudaToolkitDir.existsSync()) {
        try {
          final versions = cudaToolkitDir.listSync().whereType<io.Directory>();
          for (final dir in versions) {
            addVendorDirIfExist('${dir.path}\\bin');
          }
        } catch (_) {}
      }
    }

    // 5. Aggiunge la workingDirectory, la cartella genitore e le relative sottocartelle vendor
    if (workingDirectory.trim().isNotEmpty) {
      final workDir = workingDirectory.trim();
      addVendorDirIfExist(workDir);

      final parentOfWork = io.File(workDir).parent.path;
      if (parentOfWork.isNotEmpty) {
        addVendorDirIfExist(parentOfWork);
        addVendorDirIfExist('$parentOfWork\\vendor');
      }

      final vendorInWork = '$workDir\\vendor';
      addVendorDirIfExist(vendorInWork);
    }

    // 6. Costruisce il nuovo PATH process-local anteponendo le directory vendor
    final sanitizedPath =
        [...newEntries, ...existingEntries].join(pathSeparator);

    final finalEnvironment = Map<String, String>.from(env);
    finalEnvironment[pathKey] = sanitizedPath;

    return RuntimeLaunchEnvironment(
      workingDirectory: workingDirectory.trim().isEmpty
          ? (executablePath.contains('/') || executablePath.contains(r'\')
              ? (executablePath.substring(
                  0,
                  executablePath.lastIndexOf(
                    executablePath.contains(r'\') ? r'\' : '/',
                  ),
                ))
              : '.')
          : workingDirectory.trim(),
      environmentOverrides: Map.unmodifiable(finalEnvironment),
    );
  }
}
