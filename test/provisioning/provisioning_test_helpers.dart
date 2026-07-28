import 'dart:async';
import 'dart:convert';
import 'package:aura_core/aura_core.dart';

/// Fake in-memory [ProvisioningFileSystem] per test deterministici e binary-safe.
final class MemoryProvisioningFileSystem implements ProvisioningFileSystem {
  final Map<String, String> files = {};
  final Map<String, List<int>> byteFiles = {};
  final Set<String> directories = {};

  String _norm(String path) => path.replaceAll('/', r'\');

  @override
  Future<bool> fileExists(String path) async {
    final p = _norm(path);
    return files.containsKey(p) || byteFiles.containsKey(p);
  }

  @override
  Future<bool> directoryExists(String path) async {
    final p = _norm(path);
    if (directories.contains(p)) return true;
    final prefix = p.endsWith(r'\') ? p : '$p\\';
    for (final dir in directories) {
      if (dir.startsWith(prefix)) return true;
    }
    for (final file in {...files.keys, ...byteFiles.keys}) {
      if (file.startsWith(prefix)) return true;
    }
    return false;
  }

  @override
  Future<String> readAsString(String path) async {
    final p = _norm(path);
    if (files.containsKey(p)) return files[p]!;
    if (byteFiles.containsKey(p))
      return utf8.decode(byteFiles[p]!, allowMalformed: true);
    throw const ProvisioningIoException(operation: 'readAsString');
  }

  @override
  Future<List<int>> readAsBytes(String path) async {
    final p = _norm(path);
    if (byteFiles.containsKey(p)) return List<int>.from(byteFiles[p]!);
    if (files.containsKey(p)) return utf8.encode(files[p]!);
    throw const ProvisioningIoException(operation: 'readAsBytes');
  }

  Future<void> writeAsString(String path, String content) async {
    final p = _norm(path);
    files[p] = content;
    byteFiles.remove(p);
  }

  Future<void> writeBytes(String path, List<int> bytes) async {
    final p = _norm(path);
    byteFiles[p] = List<int>.from(bytes);
    files.remove(p);
  }

  @override
  Future<void> writeStringRecoverably(
    String path,
    String content, {
    bool preserveExistingBackup = false,
  }) async {
    final p = _norm(path);
    if (files.containsKey(p) || byteFiles.containsKey(p)) {
      final oldContent = await readAsString(p);
      if (!preserveExistingBackup && oldContent.trim().isNotEmpty) {
        files['$p.bak'] = oldContent;
      }
    }
    files[p] = content;
    byteFiles.remove(p);
  }

  @override
  Future<void> restoreFromBackup(String targetPath, String backupPath) async {
    final tp = _norm(targetPath);
    final bp = _norm(backupPath);
    if (!files.containsKey(bp) && !byteFiles.containsKey(bp)) {
      throw const ProvisioningIoException(operation: 'restoreFromBackup');
    }
    if (byteFiles.containsKey(bp)) {
      byteFiles[tp] = List<int>.from(byteFiles[bp]!);
    } else {
      files[tp] = files[bp]!;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    final p = _norm(path);
    final removedStr = files.remove(p);
    final removedBytes = byteFiles.remove(p);
    if (removedStr == null && removedBytes == null) {
      throw const ProvisioningIoException(operation: 'deleteFile');
    }
  }

  @override
  Future<bool> deleteFileBestEffort(String path) async {
    final p = _norm(path);
    final s = files.remove(p);
    final b = byteFiles.remove(p);
    return s != null || b != null;
  }

  @override
  Future<void> copyFile(String sourcePath, String targetPath) async {
    final sp = _norm(sourcePath);
    final tp = _norm(targetPath);
    if (byteFiles.containsKey(sp)) {
      byteFiles[tp] = List<int>.from(byteFiles[sp]!);
    } else if (files.containsKey(sp)) {
      files[tp] = files[sp]!;
    } else {
      throw const ProvisioningIoException(operation: 'copyFile');
    }
  }

  Future<void> moveFile(String sourcePath, String targetPath) async {
    await copyFile(sourcePath, targetPath);
    await deleteFileBestEffort(sourcePath);
  }

  @override
  Stream<List<int>> openRead(String path) {
    final p = _norm(path);
    if (byteFiles.containsKey(p)) {
      return Stream.value(List<int>.from(byteFiles[p]!));
    }
    if (files.containsKey(p)) {
      return Stream.value(utf8.encode(files[p]!));
    }
    throw const ProvisioningIoException(operation: 'openRead');
  }

  @override
  Future<int> getFileSize(String path) async {
    final p = _norm(path);
    if (byteFiles.containsKey(p)) return byteFiles[p]!.length;
    if (files.containsKey(p)) return utf8.encode(files[p]!).length;
    throw const ProvisioningIoException(operation: 'getFileSize');
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final p = _norm(path);
    final prefix = p.endsWith(r'\') ? p : '$p\\';
    final result = <String>[];
    for (final key in {...files.keys, ...byteFiles.keys}) {
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
    final p = _norm(path);
    directories.remove(p);
    final prefix = p.endsWith(r'\') ? p : '$p\\';
    files.removeWhere((k, v) => k.startsWith(prefix));
    byteFiles.removeWhere((k, v) => k.startsWith(prefix));
    directories.removeWhere((d) => d.startsWith(prefix));
  }

  @override
  Future<bool> deleteDirectoryBestEffort(String path) async {
    await deleteDirectory(path);
    return true;
  }

  @override
  Future<void> copyDirectory(String sourcePath, String targetPath) async {
    final sp = _norm(sourcePath);
    final tp = _norm(targetPath);
    final prefix = sp.endsWith(r'\') ? sp : '$sp\\';
    final targetPrefix = tp.endsWith(r'\') ? tp : '$tp\\';
    directories.add(tp);

    final toAddFiles = <String, String>{};
    files.forEach((k, v) {
      if (k.startsWith(prefix)) {
        final rel = k.substring(prefix.length);
        toAddFiles['$targetPrefix$rel'] = v;
      }
    });
    files.addAll(toAddFiles);

    final toAddByteFiles = <String, List<int>>{};
    byteFiles.forEach((k, v) {
      if (k.startsWith(prefix)) {
        final rel = k.substring(prefix.length);
        toAddByteFiles['$targetPrefix$rel'] = List<int>.from(v);
      }
    });
    byteFiles.addAll(toAddByteFiles);
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
    directories.add(_norm(path));
  }

  int? mockAvailableFreeSpace;

  @override
  Future<int?> getAvailableFreeSpace(String path) async {
    return mockAvailableFreeSpace;
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final p = _norm(path);
    if (byteFiles.containsKey(p)) {
      byteFiles[p]!.addAll(bytes);
    } else if (files.containsKey(p)) {
      final existingBytes = utf8.encode(files[p]!);
      byteFiles[p] = [...existingBytes, ...bytes];
      files.remove(p);
    } else {
      byteFiles[p] = List<int>.from(bytes);
    }
  }

  @override
  Future<void> truncateFile(String path, int length) async {
    final p = _norm(path);
    if (length == 0) {
      files.remove(p);
      byteFiles[p] = [];
      return;
    }
    final currentBytes = await readAsBytes(p);
    if (length >= currentBytes.length) return;
    byteFiles[p] = currentBytes.sublist(0, length);
    files.remove(p);
  }

  @override
  Future<void> renameFile(String sourcePath, String targetPath) async {
    final src = _norm(sourcePath);
    final dst = _norm(targetPath);
    if (byteFiles.containsKey(src)) {
      byteFiles[dst] = byteFiles.remove(src)!;
    } else if (files.containsKey(src)) {
      files[dst] = files.remove(src)!;
    } else {
      throw ProvisioningIoException(operation: 'renameFile_missing[$src]');
    }
  }
}

/// Fake [ProvisioningClock] per test deterministici.
final class MemoryProvisioningClock implements ProvisioningClock {
  final DateTime _fixedNowUtc;

  const MemoryProvisioningClock(this._fixedNowUtc);

  @override
  DateTime nowUtc() => _fixedNowUtc;
}
