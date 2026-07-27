import 'dart:async';
import 'dart:convert';
import 'package:aura_core/aura_core.dart';

/// Fake in-memory [ProvisioningFileSystem] per test deterministici.
final class MemoryProvisioningFileSystem implements ProvisioningFileSystem {
  final Map<String, String> files = {};
  final Set<String> directories = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async => directories.contains(path);

  @override
  Future<String> readAsString(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'readAsString');
    }
    return files[path]!;
  }

  @override
  Future<List<int>> readAsBytes(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'readAsBytes');
    }
    return utf8.encode(files[path]!);
  }

  Future<void> writeAsString(String path, String content) async {
    files[path] = content;
  }

  @override
  Future<void> writeStringRecoverably(
    String path,
    String content, {
    bool preserveExistingBackup = false,
  }) async {
    if (files.containsKey(path)) {
      final oldContent = files[path]!;
      if (!preserveExistingBackup && oldContent.trim().isNotEmpty) {
        files['$path.bak'] = oldContent;
      }
    }
    files[path] = content;
  }

  @override
  Future<void> restoreFromBackup(String targetPath, String backupPath) async {
    if (!files.containsKey(backupPath)) {
      throw const ProvisioningIoException(operation: 'restoreFromBackup');
    }
    files[targetPath] = files[backupPath]!;
  }

  @override
  Future<void> deleteFile(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'deleteFile');
    }
    files.remove(path);
  }

  @override
  Future<bool> deleteFileBestEffort(String path) async {
    if (files.containsKey(path)) {
      files.remove(path);
      return true;
    }
    return false;
  }

  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    if (!files.containsKey(sourcePath)) {
      throw const ProvisioningIoException(operation: 'copyFile');
    }
    files[targetPath] = files[sourcePath]!;
  }

  Future<void> moveFile(String sourcePath, String targetPath) async {
    if (!files.containsKey(sourcePath)) {
      throw const ProvisioningIoException(operation: 'moveFile');
    }
    files[targetPath] = files[sourcePath]!;
    files.remove(sourcePath);
  }

  @override
  Stream<List<int>> openRead(String path) {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'openRead');
    }
    return Stream.value(utf8.encode(files[path]!));
  }

  @override
  Future<int> getFileSize(String path) async {
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'getFileSize');
    }
    return utf8.encode(files[path]!).length;
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final prefix = path.endsWith(r'\') ? path : '$path\\';
    final result = <String>[];
    for (final key in files.keys) {
      if (key.startsWith(prefix)) {
        final sub = key.substring(prefix.length);
        final firstSeg = sub.split(r'\').first;
        if (!result.contains(firstSeg)) result.add(firstSeg);
      }
    }
    for (final dir in directories) {
      if (dir.startsWith(prefix)) {
        final sub = dir.substring(prefix.length);
        final firstSeg = sub.split(r'\').first;
        if (!result.contains(firstSeg)) result.add(firstSeg);
      }
    }
    return result;
  }

  @override
  Future<void> deleteDirectory(String path) async {
    directories.remove(path);
    final prefix = path.endsWith(r'\') ? path : '$path\\';
    files.removeWhere((k, v) => k.startsWith(prefix));
    directories.removeWhere((d) => d.startsWith(prefix));
  }

  @override
  Future<bool> deleteDirectoryBestEffort(String path) async {
    await deleteDirectory(path);
    return true;
  }

  @override
  Future<void> copyDirectory(String sourcePath, String targetPath) async {
    final prefix = sourcePath.endsWith(r'\') ? sourcePath : '$sourcePath\\';
    final targetPrefix =
        targetPath.endsWith(r'\') ? targetPath : '$targetPath\\';
    directories.add(targetPath);

    final toAddFiles = <String, String>{};
    files.forEach((k, v) {
      if (k.startsWith(prefix)) {
        final rel = k.substring(prefix.length);
        toAddFiles['$targetPrefix$rel'] = v;
      }
    });
    files.addAll(toAddFiles);
  }

  @override
  Future<void> moveDirectory(String sourcePath, String targetPath) async {
    await copyDirectory(sourcePath, targetPath);
    await deleteDirectoryBestEffort(sourcePath);
  }

  @override
  Future<void> renameDirectoryWithoutFallback(
      String sourcePath, String targetPath) async {
    await copyDirectory(sourcePath, targetPath);
    await deleteDirectoryBestEffort(sourcePath);
  }

  @override
  Future<void> createDirectory(String path) async {
    directories.add(path);
  }

  int? mockAvailableFreeSpace;

  @override
  Future<int?> getAvailableFreeSpace(String path) async {
    return mockAvailableFreeSpace;
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    if (!files.containsKey(path)) {
      files[path] = utf8.decode(bytes, allowMalformed: true);
    } else {
      final existingBytes = utf8.encode(files[path]!);
      final merged = [...existingBytes, ...bytes];
      files[path] = utf8.decode(merged, allowMalformed: true);
    }
  }

  @override
  Future<void> truncateFile(String path, int length) async {
    if (length == 0) {
      files[path] = '';
      return;
    }
    if (!files.containsKey(path)) {
      throw const ProvisioningIoException(operation: 'truncateFile');
    }
    final currentBytes = utf8.encode(files[path]!);
    if (length >= currentBytes.length) return;
    final truncated = currentBytes.sublist(0, length);
    files[path] = utf8.decode(truncated, allowMalformed: true);
  }
}

/// Fake [ProvisioningClock] per test deterministici.
final class MemoryProvisioningClock implements ProvisioningClock {
  final DateTime _fixedNowUtc;

  const MemoryProvisioningClock(this._fixedNowUtc);

  @override
  DateTime nowUtc() => _fixedNowUtc;
}
