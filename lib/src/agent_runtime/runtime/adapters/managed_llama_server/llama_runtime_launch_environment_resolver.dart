import 'dart:io' show Platform;
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
      ...(baseEnvironment ?? Platform.environment),
      if (environmentOverrides != null) ...environmentOverrides,
    };

    final pathKey = env.keys.firstWhere(
      (k) => k.toUpperCase() == 'PATH',
      orElse: () => 'PATH',
    );

    final rawPath = env[pathKey] ?? '';

    // 2. Separa le voci di PATH esistenti ed elimina riferimenti legacy a LM Studio
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final existingEntries = rawPath.split(pathSeparator).where((e) {
      final clean = e.toLowerCase().trim();
      return clean.isNotEmpty &&
          !clean.contains('.lmstudio') &&
          !clean.contains('lm-studio');
    }).toList();

    // 3. Raccoglie le directory vendor pulite
    final newEntries = <String>[];
    for (final vendor in vendorDirectories) {
      if (vendor.trim().isNotEmpty && !newEntries.contains(vendor.trim())) {
        newEntries.add(vendor.trim());
      }
    }

    // 4. Aggiunge anche la workingDirectory se contiene librerie o DLL nativi
    if (workingDirectory.trim().isNotEmpty &&
        !newEntries.contains(workingDirectory.trim())) {
      newEntries.add(workingDirectory.trim());
    }

    // 5. Costruisce il nuovo PATH process-local anteponendo le directory vendor
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
