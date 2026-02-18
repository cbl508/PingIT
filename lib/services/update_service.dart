import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String githubOwner = 'cbl508';
  static const String githubRepo = 'PingIT';
  static const String currentVersion = '1.3.0';

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

  /// Download and stage the update with optional progress callback.
  /// Returns true if the updater script was launched successfully.
  Future<bool> downloadAndApply(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}${Platform.pathSeparator}pingit_update');
      if (await updateDir.exists()) await updateDir.delete(recursive: true);
      await updateDir.create(recursive: true);

      // Streaming download with progress tracking
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        final response = await client.send(request).timeout(const Duration(seconds: 120));
        if (response.statusCode != 200) return false;

        final contentLength = response.contentLength ?? 0;
        final bytes = <int>[];
        int received = 0;

        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (contentLength > 0 && onProgress != null) {
            onProgress(received / contentLength);
          }
        }

        final zipFile = File('${updateDir.path}${Platform.pathSeparator}update.zip');
        await zipFile.writeAsBytes(bytes);
      } finally {
        client.close();
      }

      // Extract
      final zipFile = File('${updateDir.path}${Platform.pathSeparator}update.zip');
      final extractDir = Directory('${updateDir.path}${Platform.pathSeparator}extracted');
      await extractDir.create(recursive: true);

      final archiveBytes = await zipFile.readAsBytes();
      Archive archive;
      if (info.downloadUrl.endsWith('.tar.gz') || info.downloadUrl.endsWith('.tgz')) {
        archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(archiveBytes));
      } else {
        archive = ZipDecoder().decodeBytes(archiveBytes);
      }

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
    final currentPid = pid;

    // PowerShell script: waits for PID to exit, copies files, retries
    // elevated if access denied, then restarts the app.
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
# Wait for the running app to exit (up to 60s)
try { Wait-Process -Id $currentPid -Timeout 60 } catch {}
Start-Sleep -Seconds 2

\$src = "$ePath\\*"
\$dst = "$aPath\\"

# Attempt copy — retry up to 5 times for lingering file locks
\$ok = \$false
for (\$i = 0; \$i -lt 5; \$i++) {
    try {
        Copy-Item -Path \$src -Destination \$dst -Recurse -Force -ErrorAction Stop
        \$ok = \$true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}

if (-not \$ok) {
    # Retry with elevation (UAC prompt)
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList @(
        '-Command',
        "Copy-Item -Path '\$src' -Destination '\$dst' -Recurse -Force; Start-Process '$aPath\\pingit.exe'"
    )
    Remove-Item -Path \$MyInvocation.MyCommand.Source -Force
    exit
}

Start-Process "$aPath\\pingit.exe"
Start-Sleep -Seconds 1
Remove-Item -Path \$MyInvocation.MyCommand.Source -Force
''';

    final ps1File = File('$updateDir\\update.ps1');
    await ps1File.writeAsString(script);
    await Process.start(
      'powershell',
      ['-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ps1File.path],
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> _launchUnixUpdater(String updateDir, String extractDir, String appDir) async {
    final currentPid = pid;

    final script = '#!/bin/bash\n'
        '# Wait for the running app to actually exit (up to 60s)\n'
        'for i in \$(seq 1 60); do\n'
        '  kill -0 $currentPid 2>/dev/null || break\n'
        '  sleep 1\n'
        'done\n'
        'sleep 1\n'
        '\n'
        '# Try normal copy, fall back to pkexec for system installs\n'
        'if cp -rf "$extractDir/"* "$appDir/" 2>/dev/null; then\n'
        '  chmod +x "$appDir/pingit"\n'
        'else\n'
        '  pkexec bash -c \'cp -rf "$extractDir/"* "$appDir/" && chmod +x "$appDir/pingit"\'\n'
        'fi\n'
        '\n'
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
