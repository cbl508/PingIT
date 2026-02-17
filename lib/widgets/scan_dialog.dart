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

/// Checks if a command exists on the system PATH.
Future<bool> _commandExists(String cmd) async {
  try {
    final which = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(which, [cmd]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Shows a dialog telling the user that required dependencies are missing.
Future<void> _showMissingDepsDialog(BuildContext context, List<String> missing) {
  String instructions;
  if (Platform.isLinux) {
    instructions = 'Install with:\n  sudo apt install ${missing.join(' ')}';
  } else if (Platform.isMacOS) {
    instructions = 'Install with:\n  brew install ${missing.join(' ')}';
  } else {
    final urls = <String>[];
    if (missing.contains('nmap')) urls.add('nmap: https://nmap.org/download.html');
    if (missing.contains('traceroute')) urls.add('traceroute: included with nmap installer');
    instructions = 'Download and install:\n${urls.join('\n')}';
  }

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 12),
          Text('Missing Dependencies', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deep Scan requires the following tool(s) that are not installed:',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...missing.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.close, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Text(m, style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold)),
            ]),
          )),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: SelectableText(
              instructions,
              style: GoogleFonts.jetBrainsMono(fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Shows the scan address input dialog with Quick/Deep options.
/// Returns the scan output lines or null if cancelled.
void showScanInputDialog({
  required BuildContext context,
  required void Function(String address, ScanType type) onStart,
  String? initialAddress,
}) {
  final controller = TextEditingController(text: initialAddress ?? '');

  void startScan(ScanType type, BuildContext dialogContext) async {
    if (controller.text.trim().isEmpty) return;
    final addr = controller.text.trim();

    // For deep scan, check required tools before proceeding
    if (type == ScanType.deep) {
      final missing = <String>[];
      if (!await _commandExists('nmap')) missing.add('nmap');
      if (!await _commandExists(Platform.isWindows ? 'tracert' : 'traceroute')) {
        missing.add(Platform.isWindows ? 'tracert' : 'traceroute');
      }
      if (missing.isNotEmpty) {
        if (dialogContext.mounted) {
          await _showMissingDepsDialog(dialogContext, missing);
        }
        return;
      }
    }

    if (dialogContext.mounted) {
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
                'Quick Scan: Port scan + DNS + service banners (no external tools)\nDeep Scan: Ports, services, OS, MAC, scripts, traceroute (requires nmap)',
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
            OutlinedButton(
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
    '[SYSTEM] Initializing Quick Scan...',
    '[TARGET] $address',
    '[SCOPE]  DNS resolution, ${_commonPorts.length} port scan, banner grab',
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick Port Scan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  if (!isDone) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(minHeight: 3),
                    ),
                  ],
                ],
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
                      color: lines[i].contains('[OPEN]') || lines[i].contains('[RESULT]')
                          ? const Color(0xFF34D399)
                          : lines[i].contains('[ERROR]') || lines[i].contains('[SYSTEM ERR]')
                              ? Colors.redAccent
                              : lines[i].contains('[SYSTEM]') || lines[i].contains('[PHASE]')
                                  ? const Color(0xFF60A5FA)
                                  : lines[i].contains('[BANNER]')
                                      ? const Color(0xFFFBBF24)
                                      : lines[i].contains('[DNS]') || lines[i].contains('[RDNS]') || lines[i].contains('[PING]')
                                          ? const Color(0xFF818CF8)
                                          : lines[i].startsWith('═')
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
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: const Color(0xFF94A3B8),
                    ),
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
  // --- Phase 1: DNS / Reverse DNS Resolution ---
  lines.add('[PHASE] 1/3 — Host Discovery');
  emit('update');
  try {
    final resolved = await InternetAddress.lookup(address);
    if (resolved.isNotEmpty) {
      final ip = resolved.first.address;
      lines.add('[DNS]   $address → $ip');
      // Attempt reverse lookup
      try {
        final reverse = await InternetAddress(ip).reverse();
        lines.add('[RDNS]  $ip → ${reverse.host}');
      } catch (_) {
        lines.add('[RDNS]  Reverse lookup not available');
      }
    }
  } catch (_) {
    lines.add('[DNS]   Could not resolve $address');
  }
  emit('update');

  // --- Phase 2: Ping / Latency ---
  try {
    final sw = Stopwatch()..start();
    final socket = await Socket.connect(address, 80, timeout: const Duration(seconds: 3));
    sw.stop();
    socket.destroy();
    lines.add('[PING]  Host is reachable (${sw.elapsedMilliseconds}ms via TCP/80)');
  } catch (_) {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(address, 443, timeout: const Duration(seconds: 3));
      sw.stop();
      socket.destroy();
      lines.add('[PING]  Host is reachable (${sw.elapsedMilliseconds}ms via TCP/443)');
    } catch (_) {
      lines.add('[PING]  Host may be unreachable or blocking common ports');
    }
  }
  lines.add('');
  emit('update');

  // --- Phase 3: Port Scan with Banner Grabbing ---
  lines.add('[PHASE] 2/3 — Port Scan (${_commonPorts.length} ports)');
  emit('update');
  final openPorts = <int>[];
  final portBanners = <int, String>{};
  final ports = _commonPorts.keys.toList()..sort();

  for (int i = 0; i < ports.length; i += 20) {
    final batch = ports.sublist(i, (i + 20).clamp(0, ports.length));
    final futures = batch.map((port) async {
      try {
        final socket = await Socket.connect(address, port, timeout: const Duration(seconds: 1));
        // Attempt banner grab — read for up to 2 seconds
        String? banner;
        try {
          socket.write('\r\n');
          final data = await socket.timeout(const Duration(seconds: 2)).first;
          final raw = String.fromCharCodes(data).trim();
          if (raw.isNotEmpty) {
            banner = raw.length > 80 ? raw.substring(0, 80) : raw;
            // Clean non-printable characters
            banner = banner.replaceAll(RegExp(r'[^\x20-\x7E]'), '.');
          }
        } catch (_) {
          // No banner available — that's fine
        }
        socket.destroy();
        return (port: port, banner: banner);
      } catch (_) {
        return (port: -1, banner: null);
      }
    });

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result.port > 0) {
        openPorts.add(result.port);
        final service = _commonPorts[result.port] ?? 'Unknown';
        if (result.banner != null) {
          portBanners[result.port] = result.banner!;
        }
        lines.add('[OPEN]  Port ${result.port}/tcp  $service');
        emit('update');
      }
    }

    final scanned = (i + batch.length).clamp(0, ports.length);
    lines.add('[SCAN]  Scanned $scanned/${ports.length} ports...');
    emit('update');
  }

  // --- Phase 4: Service Banners Summary ---
  if (portBanners.isNotEmpty) {
    lines.add('');
    lines.add('[PHASE] 3/3 — Service Banners');
    emit('update');
    for (final entry in portBanners.entries) {
      final service = _commonPorts[entry.key] ?? 'Unknown';
      lines.add('[BANNER] ${entry.key}/tcp ($service): ${entry.value}');
      emit('update');
    }
  }

  // --- Summary ---
  lines.add('');
  lines.add('═══════════════════════════════════════════');
  lines.add('[SYSTEM] SCAN SUMMARY');
  lines.add('═══════════════════════════════════════════');
  if (openPorts.isEmpty) {
    lines.add('[RESULT] No open ports found on common ports.');
  } else {
    lines.add('[RESULT] ${openPorts.length} open port(s): ${openPorts.join(", ")}');
    for (final port in openPorts) {
      final service = _commonPorts[port] ?? 'Unknown';
      final banner = portBanners[port];
      lines.add('[RESULT]   $port/tcp  $service${banner != null ? '  [$banner]' : ''}');
    }
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
  final args = ['-sV', '-sC', '-O', '-A', '-T4', '--reason', '-Pn', address];
  final List<String> lines = [
    '[SYSTEM] Initializing Deep Infrastructure Scan...',
    '[TARGET] $address',
    '[CMD] nmap ${args.join(' ')}',
    '[SCOPE]  Ports, services, OS, MAC address, NSE scripts, traceroute',
    '',
    'Starting Nmap (full enumeration)...',
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
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogTitle ?? 'Deep Infrastructure Scan',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                    if (!isDone) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(minHeight: 3),
                      ),
                    ],
                  ],
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
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: const Color(0xFF94A3B8),
                      ),
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
