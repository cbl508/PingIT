import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String githubOwner = 'cbl508';
  static const String githubRepo = 'PingIT';
  static const String currentVersion = '1.3.3';

  /// Check GitHub Releases API for a newer version.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'PingIT-Updater',
        },
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

  /// Download and extract the update to a staging directory.
  /// Does NOT launch the updater — call [launchUpdaterAndExit] when ready.
  Future<StagedUpdate?> downloadAndStage(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}${Platform.pathSeparator}pingit_update');
      if (await updateDir.exists()) await updateDir.delete(recursive: true);
      await updateDir.create(recursive: true);

      final zipFile = File('${updateDir.path}${Platform.pathSeparator}update.zip');
      final sink = zipFile.openWrite();

      // Streaming download with progress tracking
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        request.headers['User-Agent'] = 'PingIT-Updater';
        
        final response = await client.send(request).timeout(const Duration(seconds: 120));
        if (response.statusCode != 200) {
          await sink.close();
          return null;
        }

        final contentLength = response.contentLength ?? 0;
        int received = 0;

        await response.stream.forEach((chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0 && onProgress != null) {
            onProgress(received / contentLength);
          }
        });

        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        rethrow;
      } finally {
        client.close();
      }

      // Extract
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

      final appDir = File(Platform.resolvedExecutable).parent.path;
      return StagedUpdate(updateDir.path, extractDir.path, appDir);
    } catch (e) {
      debugPrint('Update staging failed: $e');
      return null;
    }
  }

  /// Launch the platform updater script and exit the app.
  /// The script waits for this process to exit, copies files, and restarts.
  Future<void> launchUpdaterAndExit(StagedUpdate staged) async {
    if (Platform.isWindows) {
      await _launchWindowsUpdater(staged);
    } else {
      await _launchUnixUpdater(staged);
    }
    // Brief delay so the UpdatingScreen is visible before the app exits.
    await Future.delayed(const Duration(seconds: 2));
    exit(0);
  }

  Future<void> _launchWindowsUpdater(StagedUpdate staged) async {
    final ePath = staged.extractDir.replaceAll('/', '\\');
    final aPath = staged.appDir.replaceAll('/', '\\');
    final currentPid = pid;

    // PowerShell script: waits for PID to exit, copies files, retries
    // elevated if access denied, then restarts the app.
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
try { Wait-Process -Id $currentPid -Timeout 60 } catch {}
Start-Sleep -Seconds 2

[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
\$notify = New-Object System.Windows.Forms.NotifyIcon
\$notify.Icon = [System.Drawing.SystemIcons]::Information
\$notify.Visible = \$true
\$notify.ShowBalloonTip(10000, 'PingIT', 'Installing update — restarting shortly...', 'Info')

\$src = "$ePath\\*"
\$dst = "$aPath\\"

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
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList @(
        '-NoProfile', '-Command',
        "Copy-Item -Path '\$src' -Destination '\$dst' -Recurse -Force; Start-Process '$aPath\\pingit.exe'"
    )
    Remove-Item -Path \$MyInvocation.MyCommand.Source -Force
    exit
}

\$notify.Visible = \$false
\$notify.Dispose()
Start-Process "$aPath\\pingit.exe"
Start-Sleep -Seconds 1
Remove-Item -Path \$MyInvocation.MyCommand.Source -Force
''';

    final ps1File = File('${staged.updateDir}\\update.ps1');
    await ps1File.writeAsString(script);

    // Use a VBS wrapper to launch PowerShell completely hidden (no console flash)
    final vbsScript =
        'CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""${ps1File.path}""", 0, False\r\n';
    final vbsFile = File('${staged.updateDir}\\launch_update.vbs');
    await vbsFile.writeAsString(vbsScript);
    await Process.start('wscript', [vbsFile.path], mode: ProcessStartMode.detached);
  }

  Future<void> _launchUnixUpdater(StagedUpdate staged) async {
    final currentPid = pid;
    final extractDir = staged.extractDir;
    final appDir = staged.appDir;

    final script = '#!/bin/bash\n'
        'for i in \$(seq 1 60); do\n'
        '  kill -0 $currentPid 2>/dev/null || break\n'
        '  sleep 1\n'
        'done\n'
        'sleep 1\n'
        'notify-send -a PingIT "PingIT" "Installing update — restarting shortly..." 2>/dev/null\n'
        '\n'
        'if cp -rf "$extractDir/"* "$appDir/" 2>/dev/null; then\n'
        '  chmod +x "$appDir/pingit"\n'
        'else\n'
        '  pkexec bash -c \'cp -rf "$extractDir/"* "$appDir/" && chmod +x "$appDir/pingit"\'\n'
        'fi\n'
        '\n'
        '"$appDir/pingit" &\n'
        'rm -- "\$0"\n';

    final shFile = File('${staged.updateDir}/update.sh');
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

class StagedUpdate {
  final String updateDir;
  final String extractDir;
  final String appDir;

  StagedUpdate(this.updateDir, this.extractDir, this.appDir);
}
