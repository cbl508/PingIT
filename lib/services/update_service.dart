import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String githubOwner = 'cbl508';
  static const String githubRepo = 'PingIT';
  static const String currentVersion = '1.0.0';

  /// Check GitHub Releases API for a newer version.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final latestTag = (json['tag_name'] as String).replaceFirst('v', '');

      if (_isNewer(latestTag, currentVersion)) {
        final assets = json['assets'] as List;
        final platformKey = Platform.isWindows
            ? 'windows'
            : Platform.isLinux
                ? 'linux'
                : Platform.isMacOS
                    ? 'macos'
                    : '';

        final matching = assets.cast<Map<String, dynamic>>().where(
          (a) => (a['name'] as String).toLowerCase().contains(platformKey),
        );

        if (matching.isNotEmpty) {
          return UpdateInfo(
            version: latestTag,
            downloadUrl: matching.first['browser_download_url'] as String,
            releaseNotes: (json['body'] as String?) ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return null;
  }

  /// Download and stage the update. Returns true if the updater script was
  /// launched successfully. The caller should then exit the app so the
  /// script can replace the running binary.
  Future<bool> downloadAndApply(UpdateInfo info) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}${Platform.pathSeparator}pingit_update');
      if (await updateDir.exists()) await updateDir.delete(recursive: true);
      await updateDir.create(recursive: true);

      // Download the release archive
      final response = await http.get(Uri.parse(info.downloadUrl));
      if (response.statusCode != 200) return false;

      final zipFile = File('${updateDir.path}${Platform.pathSeparator}update.zip');
      await zipFile.writeAsBytes(response.bodyBytes);

      // Extract
      final extractDir = Directory('${updateDir.path}${Platform.pathSeparator}extracted');
      await extractDir.create(recursive: true);

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filePath = '${extractDir.path}${Platform.pathSeparator}${file.name}';
        if (file.isFile) {
          final outFile = File(filePath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      // Write and launch a platform-specific updater script that runs after
      // this process exits.
      final appDir = File(Platform.resolvedExecutable).parent.path;

      if (Platform.isWindows) {
        await _launchWindowsUpdater(updateDir.path, extractDir.path, appDir);
      } else {
        await _launchUnixUpdater(updateDir.path, extractDir.path, appDir);
      }

      return true;
    } catch (e) {
      debugPrint('Update failed: $e');
      return false;
    }
  }

  Future<void> _launchWindowsUpdater(String updateDir, String extractDir, String appDir) async {
    final ePath = extractDir.replaceAll('/', '\\');
    final aPath = appDir.replaceAll('/', '\\');

    final script = '@echo off\r\n'
        'timeout /t 3 /nobreak >nul\r\n'
        'xcopy /s /y /q "$ePath\\*" "$aPath\\"\r\n'
        'start "" "$aPath\\pingit.exe"\r\n'
        'del "%~f0"\r\n';

    final batFile = File('$updateDir\\update.bat');
    await batFile.writeAsString(script);
    await Process.start('cmd', ['/c', batFile.path], mode: ProcessStartMode.detached);
  }

  Future<void> _launchUnixUpdater(String updateDir, String extractDir, String appDir) async {
    final script = '#!/bin/bash\n'
        'sleep 3\n'
        'cp -rf "$extractDir/"* "$appDir/"\n'
        'chmod +x "$appDir/pingit"\n'
        '"$appDir/pingit" &\n'
        'rm -- "\$0"\n';

    final shFile = File('$updateDir/update.sh');
    await shFile.writeAsString(script);
    await Process.run('chmod', ['+x', shFile.path]);
    await Process.start('bash', [shFile.path], mode: ProcessStartMode.detached);
  }

  bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3 && i < l.length && i < c.length; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}
