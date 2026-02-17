import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

enum ScanType { quick, deep }

/// Common TCP ports for the built-in quick scanner.
const Map<int, String> _commonPorts = {
  21: 'FTP', 22: 'SSH', 23: 'Telnet', 25: 'SMTP', 53: 'DNS',
  80: 'HTTP', 110: 'POP3', 111: 'RPC', 135: 'MSRPC', 139: 'NetBIOS',
  143: 'IMAP', 443: 'HTTPS', 445: 'SMB', 465: 'SMTPS', 587: 'Submission',
  993: 'IMAPS', 995: 'POP3S', 1433: 'MSSQL', 1521: 'Oracle', 1723: 'PPTP',
  3306: 'MySQL', 3389: 'RDP', 5432: 'PostgreSQL', 5900: 'VNC',
  5985: 'WinRM', 6379: 'Redis', 8080: 'HTTP-Alt', 8443: 'HTTPS-Alt',
  8888: 'HTTP-Alt2', 9090: 'Prometheus', 9200: 'Elasticsearch',
  27017: 'MongoDB',
};

/// Shows the scan address input dialog with Quick/Deep options.
/// Returns the scan output lines or null if cancelled.
void showScanInputDialog({
  required BuildContext context,
  required void Function(String address, ScanType type) onStart,
  String? initialAddress,
}) {
  final controller = TextEditingController(text: initialAddress ?? '');

  void startScan(ScanType type, BuildContext dialogContext) {
    if (controller.text.trim().isNotEmpty) {
      final addr = controller.text.trim();
      Navigator.pop(dialogContext);
      onStart(addr, type);
    }
  }

  showDialog(
    context: context,
    builder: (dialogContext) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => startScan(ScanType.quick, dialogContext),
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: Text('Network Scan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter a hostname or IP address to scan.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.jetBrainsMono(),
                decoration: const InputDecoration(
                  hintText: 'e.g. 192.168.1.1 or google.com',
                  prefixIcon: Icon(Icons.public),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => startScan(ScanType.quick, dialogContext),
              ),
              const SizedBox(height: 12),
              Text(
                'Quick Scan: Built-in TCP port scan (no external tools needed)\nDeep Scan: Full nmap service/OS detection (requires nmap)',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => startScan(ScanType.quick, dialogContext),
              child: const Text('Quick Scan'),
            ),
            FilledButton(
              onPressed: () => startScan(ScanType.deep, dialogContext),
              child: const Text('Deep Scan'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Runs a scan and shows live terminal-style output dialog.
/// Returns the scan output lines when done.
Future<List<String>?> runScanDialog({
  required BuildContext context,
  required String address,
  required ScanType scanType,
  String? dialogTitle,
  bool showAddButton = false,
}) async {
  if (scanType == ScanType.quick) {
    return _runBuiltInScan(context: context, address: address, showAddButton: showAddButton);
  } else {
    return _runNmapScan(context: context, address: address, dialogTitle: dialogTitle, showAddButton: showAddButton);
  }
}

/// Built-in TCP port scanner — no external tools needed.
Future<List<String>?> _runBuiltInScan({
  required BuildContext context,
  required String address,
  bool showAddButton = false,
}) async {
  final StreamController<String> logStream = StreamController<String>();
  final List<String> lines = [
    '[SYSTEM] Initializing Quick TCP Port Scan...',
    '[TARGET] $address',
    '[PORTS] Scanning ${_commonPorts.length} common ports...',
    '',
  ];
  final scrollController = ScrollController();
  bool isClosed = false;
  bool isDone = false;

  void emit(String message) {
    if (!isClosed) logStream.add(message);
  }

  Future<void> closeStream() async {
    if (!isClosed) {
      isClosed = true;
      await logStream.close();
    }
  }

  // Run scan asynchronously
  _performTcpScan(address, lines, emit).then((_) {
    isDone = true;
    emit('DONE');
    closeStream();
  });

  bool? addNode;

  await showDialog(
    context: context,
    builder: (dialogContext) => StreamBuilder<String>(
      stream: logStream.stream,
      builder: (ctx, snapshot) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: 200.ms,
              curve: Curves.easeOut,
            );
          }
        });

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (isDone) Navigator.pop(dialogContext);
            },
            const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(dialogContext),
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              title: Text('Quick Port Scan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF0F172A),
              content: Container(
                width: 700,
                height: 500,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                padding: const EdgeInsets.all(16),
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: lines.length,
                  itemBuilder: (context, i) => Text(
                    lines[i],
                    style: GoogleFonts.jetBrainsMono(
                      color: lines[i].contains('[OPEN]')
                          ? const Color(0xFF34D399)
                          : lines[i].contains('[ERROR]') || lines[i].contains('[SYSTEM ERR]')
                              ? Colors.redAccent
                              : lines[i].contains('[SYSTEM]')
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('DISMISS'),
                ),
                if (showAddButton && snapshot.data == 'DONE')
                  FilledButton.icon(
                    onPressed: () {
                      addNode = true;
                      Navigator.pop(dialogContext);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('ADD AS NODE'),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  scrollController.dispose();
  await closeStream();
  if (addNode == true) return lines;
  return null;
}

Future<void> _performTcpScan(String address, List<String> lines, void Function(String) emit) async {
  final openPorts = <int>[];
  final ports = _commonPorts.keys.toList()..sort();

  // Scan in batches of 20 concurrent connections
  for (int i = 0; i < ports.length; i += 20) {
    final batch = ports.sublist(i, (i + 20).clamp(0, ports.length));
    final futures = batch.map((port) async {
      try {
        final socket = await Socket.connect(address, port, timeout: const Duration(seconds: 1));
        socket.destroy();
        return port;
      } catch (_) {
        return -1;
      }
    });

    final results = await Future.wait(futures);
    for (final port in results) {
      if (port > 0) {
        openPorts.add(port);
        final service = _commonPorts[port] ?? 'Unknown';
        lines.add('[OPEN]  Port $port/tcp  $service');
        emit('update');
      }
    }

    // Progress update
    final scanned = (i + batch.length).clamp(0, ports.length);
    lines.add('[SCAN]  Scanned $scanned/${ports.length} ports...');
    emit('update');
  }

  lines.add('');
  if (openPorts.isEmpty) {
    lines.add('[SYSTEM] No open ports found on common ports.');
  } else {
    lines.add('[SYSTEM] Found ${openPorts.length} open port(s): ${openPorts.join(", ")}');
  }
  lines.add('[SYSTEM] Quick scan completed.');
}

/// Deep scan using nmap with comprehensive switches.
Future<List<String>?> _runNmapScan({
  required BuildContext context,
  required String address,
  String? dialogTitle,
  bool showAddButton = false,
}) async {
  final StreamController<String> logStream = StreamController<String>();
  final args = ['-sV', '-sC', '-O', '-A', '-T4', address];
  final List<String> lines = [
    '[SYSTEM] Initializing Deep Infrastructure Scan...',
    '[TARGET] $address',
    '[CMD] nmap ${args.join(' ')}',
    '',
    'Starting Nmap (service/version/OS/script detection)...',
  ];
  final scrollController = ScrollController();

  Process? process;
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;
  bool isClosed = false;
  bool isDone = false;

  void emit(String message) {
    if (!isClosed) logStream.add(message);
  }

  Future<void> closeStream() async {
    if (!isClosed) {
      isClosed = true;
      await logStream.close();
    }
  }

  void killProcess() {
    process?.kill();
    process = null;
  }

  try {
    process = await Process.start('nmap', args, runInShell: Platform.isWindows);
    stdoutSub = process!.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isNotEmpty) {
        lines.add(line.trim());
        emit(line);
      }
    }, onError: (e) {
      lines.add('[SYSTEM ERR] Decoding error: $e');
      emit('ERROR');
    });
    stderrSub = process!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isNotEmpty) {
        lines.add('[SYSTEM ERR] $line');
        emit(line);
      }
    }, onError: (e) {
      lines.add('[SYSTEM ERR] Decoding error: $e');
      emit('ERROR');
    });
    process!.exitCode.then((code) async {
      lines.add('');
      if (code == 0) {
        lines.add('[SYSTEM] Deep scan completed successfully.');
      } else {
        lines.add('[SYSTEM] Scan exited with code $code.');
        lines.add('Note: OS detection (-O) usually requires root/sudo privileges.');
      }
      isDone = true;
      emit('DONE');
      await closeStream();
    });
  } catch (e) {
    final installHint = Platform.isLinux
        ? 'Install with: sudo apt install nmap'
        : Platform.isMacOS
            ? 'Install with: brew install nmap'
            : 'Download from https://nmap.org/download.html';
    lines.add('[ERROR] "nmap" utility not found on this system.');
    lines.add('[HINT] $installHint');
    isDone = true;
    emit('ERROR');
    await closeStream();
  }

  bool? addNode;

  if (context.mounted) {
    await showDialog(
      context: context,
      builder: (dialogContext) => StreamBuilder<String>(
        stream: logStream.stream,
        builder: (ctx, snapshot) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              scrollController.animateTo(
                scrollController.position.maxScrollExtent,
                duration: 200.ms,
                curve: Curves.easeOut,
              );
            }
          });

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (isDone) Navigator.pop(dialogContext);
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                killProcess();
                Navigator.pop(dialogContext);
              },
            },
            child: Focus(
              autofocus: true,
              child: AlertDialog(
                title: Text(
                  dialogTitle ?? 'Deep Infrastructure Scan',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
                backgroundColor: const Color(0xFF0F172A),
                content: Container(
                  width: 700,
                  height: 500,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: lines.length,
                    itemBuilder: (context, i) => Text(
                      lines[i],
                      style: GoogleFonts.jetBrainsMono(
                        color: lines[i].contains('[SYSTEM ERR]')
                            ? Colors.redAccent
                            : lines[i].contains('[ERROR]')
                                ? Colors.redAccent
                                : lines[i].contains('[HINT]')
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF34D399),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      killProcess();
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('DISMISS'),
                  ),
                  if (showAddButton && snapshot.data == 'DONE')
                    FilledButton.icon(
                      onPressed: () {
                        addNode = true;
                        Navigator.pop(dialogContext);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('ADD AS NODE'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  killProcess();
  await stdoutSub?.cancel();
  await stderrSub?.cancel();
  await closeStream();
  scrollController.dispose();

  if (addNode == true) return lines;
  return lines;
}
