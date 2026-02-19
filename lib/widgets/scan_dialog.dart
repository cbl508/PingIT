import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pingit/data/oui_database.dart';

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


/// Reads the local ARP table to find the MAC address for [address].
Future<String?> _getMacAddress(String address) async {
  try {
    ProcessResult result;
    if (Platform.isLinux) {
      result = await Process.run('ip', ['neigh', 'show', address]);
      if (result.exitCode != 0 || (result.stdout as String).trim().isEmpty) {
        result = await Process.run('arp', ['-n', address]);
      }
    } else {
      result = await Process.run('arp', ['-a', address]);
    }
    final output = result.stdout as String;
    final macMatch = RegExp(r'([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}').firstMatch(output);
    if (macMatch != null) {
      return macMatch.group(0)!.replaceAll('-', ':').toUpperCase();
    }
  } catch (_) {}
  return null;
}

/// Pings the host once and extracts the TTL from the response.
Future<int?> _getTTL(String address) async {
  try {
    final List<String> args;
    if (Platform.isWindows) {
      args = ['-n', '1', '-w', '2000', address];
    } else if (Platform.isMacOS) {
      args = ['-c', '1', '-W', '2000', address];
    } else {
      args = ['-c', '1', '-W', '2', address];
    }
    final result = await Process.run('ping', args)
        .timeout(const Duration(seconds: 5));
    final output = result.stdout as String;
    final ttlMatch = RegExp(r'ttl[=:](\d+)', caseSensitive: false).firstMatch(output);
    if (ttlMatch != null) return int.tryParse(ttlMatch.group(1)!);
  } catch (_) {}
  return null;
}

/// Looks up the manufacturer from a MAC address OUI prefix.
String? _lookupVendor(String mac) {
  // Normalize to uppercase hex without separators, then take first 6 chars (OUI)
  final hex = mac.replaceAll(RegExp(r'[:\-.]'), '').toUpperCase();
  if (hex.length < 6) return null;
  return ouiDatabase[hex.substring(0, 6)];
}

/// Infers the likely OS from TTL, open ports, and service banners.
String? _inferOS({int? ttl, required List<int> openPorts, required Map<int, String> banners}) {
  // Banner-based detection (highest confidence)
  for (final banner in banners.values) {
    final lower = banner.toLowerCase();
    if (lower.contains('ubuntu')) return 'Linux (Ubuntu)';
    if (lower.contains('debian')) return 'Linux (Debian)';
    if (lower.contains('centos') || lower.contains('red hat') || lower.contains('rhel')) return 'Linux (RHEL/CentOS)';
    if (lower.contains('fedora')) return 'Linux (Fedora)';
    if (lower.contains('freebsd')) return 'FreeBSD';
    if (lower.contains('openbsd')) return 'OpenBSD';
    if (lower.contains('darwin') || lower.contains('macos')) return 'macOS';
    if (lower.contains('microsoft') || lower.contains('windows') || lower.contains('iis')) return 'Windows';
    if (lower.contains('mikrotik')) return 'MikroTik RouterOS';
    if (lower.contains('openwrt')) return 'OpenWrt';
    if (lower.contains('junos')) return 'Juniper JunOS';
    if (lower.contains('cisco')) return 'Cisco IOS';
  }

  // Port-based hints
  final portSet = openPorts.toSet();
  if (portSet.containsAll([135, 445]) || portSet.contains(3389) || portSet.contains(5985)) {
    return 'Windows';
  }

  // TTL-based guess (lowest confidence)
  if (ttl != null) {
    if (ttl <= 64) return 'Linux/Unix';
    if (ttl <= 128) return 'Windows';
    if (ttl <= 255) return 'Network Device';
  }

  return null;
}

/// Infers the device type from open ports, vendor, and OS.
String _inferDeviceType({required List<int> openPorts, String? vendor, String? os}) {
  final portSet = openPorts.toSet();

  // Vendor-based hints
  if (vendor != null) {
    final v = vendor.toLowerCase();
    if (v.contains('vmware') || v.contains('hyper-v') || v.contains('qemu') || v.contains('virtualbox')) return 'Virtual Machine';
    if (v.contains('raspberry pi')) return 'Single-Board Computer (IoT)';
    if (v.contains('espressif')) return 'IoT Microcontroller';
    if (v.contains('synology') || v.contains('qnap')) return 'NAS';
    if (v.contains('cisco') || v.contains('juniper') || v.contains('aruba') || v.contains('mikrotik')) {
      if (portSet.contains(53) || portSet.contains(67)) return 'Router';
      return 'Network Device';
    }
    if (v.contains('ubiquiti') || v.contains('tp-link') || v.contains('netgear') || v.contains('asus')) {
      return 'Router / Access Point';
    }
    if (v.contains('fortinet')) return 'Firewall';
    if (v.contains('amazon')) return 'Smart Device / IoT';
    if (v.contains('google')) return 'Smart Device / Cloud';
  }

  // Port-based inference
  if (portSet.contains(631) || portSet.contains(9100)) return 'Printer';
  if (portSet.contains(53) && portSet.contains(67)) return 'Router / DHCP Server';
  if (portSet.contains(25) || portSet.contains(587) || portSet.contains(465)) return 'Mail Server';
  if (portSet.containsAll([80, 443]) && (portSet.contains(3306) || portSet.contains(5432) || portSet.contains(27017))) {
    return 'Web + Database Server';
  }
  if (portSet.contains(80) || portSet.contains(443) || portSet.contains(8080)) return 'Web Server';
  if (portSet.containsAll([3389, 445])) return 'Windows Workstation';
  if (portSet.contains(3389)) return 'Windows Server / Workstation';
  if (portSet.contains(1433) || portSet.contains(1521) || portSet.contains(3306) || portSet.contains(5432)) return 'Database Server';
  if (portSet.contains(5900)) return 'Workstation (VNC)';
  if (portSet.contains(9090) || portSet.contains(9200)) return 'Monitoring / Analytics Server';
  if (portSet.contains(6379) || portSet.contains(27017)) return 'Cache / NoSQL Server';
  if (portSet.contains(22) && openPorts.length <= 2) return 'Linux Server';
  if (portSet.contains(53)) return 'DNS Server';

  if (openPorts.isEmpty) return 'Unknown (no open ports detected)';
  return 'Server';
}

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

  String? errorText;
  void startScan(ScanType type, BuildContext dialogContext, void Function(void Function()) setDialogState) async {
    if (controller.text.trim().isEmpty) {
      setDialogState(() => errorText = 'Please enter an address');
      return;
    }
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
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () => startScan(ScanType.quick, dialogContext, setDialogState),
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
                  decoration: InputDecoration(
                    hintText: 'e.g. 192.168.1.1 or google.com',
                    prefixIcon: const Icon(Icons.public),
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) setDialogState(() => errorText = null);
                  },
                  onSubmitted: (_) => startScan(ScanType.quick, dialogContext, setDialogState),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quick Scan: Ports, DNS, MAC, OS & device fingerprinting (no external tools)\nDeep Scan: Full enumeration, OS, MAC, scripts, traceroute (requires nmap)',
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
                onPressed: () => startScan(ScanType.quick, dialogContext, setDialogState),
                child: const Text('Quick Scan'),
              ),
              OutlinedButton(
                onPressed: () => startScan(ScanType.deep, dialogContext, setDialogState),
                child: const Text('Deep Scan'),
              ),
            ],
          ),
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
  final StreamController<String> logStream = StreamController<String>.broadcast();
  final List<String> lines = [
    '[SYSTEM] Initializing Quick Scan...',
    '[TARGET] $address',
    '[SCOPE]  DNS, TTL fingerprint, MAC/vendor, ${_commonPorts.length} port scan, OS & device ID',
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
                      color: lines[i].contains('[OPEN]') || lines[i].contains('[RESULT]') || lines[i].contains('[OS]') || lines[i].contains('[TYPE]')
                          ? const Color(0xFF34D399)
                          : lines[i].contains('[ERROR]') || lines[i].contains('[SYSTEM ERR]')
                              ? Colors.redAccent
                              : lines[i].contains('[SYSTEM]') || lines[i].contains('[PHASE]')
                                  ? const Color(0xFF60A5FA)
                                  : lines[i].contains('[BANNER]') || lines[i].contains('[MAC]') || lines[i].contains('[VENDOR]')
                                      ? const Color(0xFFFBBF24)
                                      : lines[i].contains('[DNS]') || lines[i].contains('[RDNS]') || lines[i].contains('[PING]') || lines[i].contains('[TTL]') || lines[i].contains('[FPRINT]') || lines[i].contains('[PROBE]')
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
                if (showAddButton && isDone)
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
  String? resolvedIp;
  int? ttl;
  String? macAddress;
  String? macVendor;
  final openPorts = <int>[];
  final portBanners = <int, String>{};

  // --- Phase 1: DNS / Reverse DNS Resolution ---
  lines.add('[PHASE] 1/5 — Host Discovery');
  emit('update');
  try {
    final resolved = await InternetAddress.lookup(address);
    if (resolved.isNotEmpty) {
      resolvedIp = resolved.first.address;
      lines.add('[DNS]   $address → $resolvedIp');
      try {
        final reverse = await InternetAddress(resolvedIp).reverse();
        lines.add('[RDNS]  $resolvedIp → ${reverse.host}');
      } catch (_) {
        lines.add('[RDNS]  Reverse lookup not available');
      }
    }
  } catch (_) {
    lines.add('[DNS]   Could not resolve $address');
  }
  emit('update');

  // --- Phase 2: Host Fingerprinting (TTL + Latency) ---
  final target = resolvedIp ?? address;
  lines.add('');
  lines.add('[PHASE] 2/5 — Host Fingerprinting');
  emit('update');

  ttl = await _getTTL(target);
  if (ttl != null) {
    lines.add('[TTL]   $ttl');
    if (ttl <= 64) {
      lines.add('[FPRINT] TTL suggests Linux/macOS/Unix (base 64)');
    } else if (ttl <= 128) {
      lines.add('[FPRINT] TTL suggests Windows (base 128)');
    } else {
      lines.add('[FPRINT] TTL suggests network device (base 255)');
    }
  } else {
    lines.add('[TTL]   ICMP blocked or host unreachable');
  }

  try {
    final sw = Stopwatch()..start();
    final socket = await Socket.connect(target, 80, timeout: const Duration(seconds: 3));
    sw.stop();
    socket.destroy();
    lines.add('[PROBE] Reachable (${sw.elapsedMilliseconds}ms via TCP/80)');
  } catch (_) {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(target, 443, timeout: const Duration(seconds: 3));
      sw.stop();
      socket.destroy();
      lines.add('[PROBE] Reachable (${sw.elapsedMilliseconds}ms via TCP/443)');
    } catch (_) {
      lines.add('[PROBE] Host may be unreachable or blocking common ports');
    }
  }
  emit('update');

  // --- Phase 3: MAC Address Lookup ---
  lines.add('');
  lines.add('[PHASE] 3/5 — MAC Address Lookup');
  emit('update');

  macAddress = await _getMacAddress(target);
  if (macAddress != null) {
    lines.add('[MAC]   $macAddress');
    macVendor = _lookupVendor(macAddress);
    if (macVendor != null) {
      lines.add('[VENDOR] $macVendor');
    } else {
      lines.add('[VENDOR] Unknown manufacturer');
    }
  } else {
    lines.add('[MAC]   Not available (host is on a different subnet)');
  }
  emit('update');

  // --- Phase 4: Port Scan with Banner Grabbing ---
  lines.add('');
  lines.add('[PHASE] 4/5 — Port Scan (${_commonPorts.length} ports)');
  emit('update');

  final ports = _commonPorts.keys.toList()..sort();
  for (int i = 0; i < ports.length; i += 20) {
    final batch = ports.sublist(i, (i + 20).clamp(0, ports.length));
    final futures = batch.map((port) async {
      try {
        final socket = await Socket.connect(target, port, timeout: const Duration(seconds: 1));
        String? banner;
        try {
          socket.write('\r\n');
          final data = await socket.timeout(const Duration(seconds: 2)).first;
          final raw = String.fromCharCodes(data).trim();
          if (raw.isNotEmpty) {
            banner = raw.length > 80 ? raw.substring(0, 80) : raw;
            banner = banner.replaceAll(RegExp(r'[^\x20-\x7E]'), '.');
          }
        } catch (_) {}
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
        if (result.banner != null) {
          lines.add('[BANNER]  └─ ${result.banner}');
        }
        emit('update');
      }
    }

    final scanned = (i + batch.length).clamp(0, ports.length);
    lines.add('[SCAN]  Scanned $scanned/${ports.length} ports...');
    emit('update');
  }

  // --- Phase 5: Analysis & Identification ---
  lines.add('');
  lines.add('[PHASE] 5/5 — Analysis & Identification');
  emit('update');

  final osGuess = _inferOS(ttl: ttl, openPorts: openPorts, banners: portBanners);
  final deviceType = _inferDeviceType(openPorts: openPorts, vendor: macVendor, os: osGuess);

  lines.add('[OS]    ${osGuess ?? 'Could not determine'}');
  lines.add('[TYPE]  $deviceType');
  emit('update');

  // --- Summary ---
  lines.add('');
  lines.add('═══════════════════════════════════════════');
  lines.add('[SYSTEM] SCAN SUMMARY');
  lines.add('═══════════════════════════════════════════');
  if (resolvedIp != null && resolvedIp != address) {
    lines.add('[RESULT] Host: $address ($resolvedIp)');
  } else {
    lines.add('[RESULT] Host: $address');
  }
  if (macAddress != null) {
    lines.add('[RESULT] MAC:  $macAddress${macVendor != null ? ' ($macVendor)' : ''}');
  }
  lines.add('[RESULT] OS:   ${osGuess ?? 'Unknown'}');
  lines.add('[RESULT] Type: $deviceType');
  if (openPorts.isEmpty) {
    lines.add('[RESULT] Ports: No open ports found');
  } else {
    lines.add('[RESULT] Ports: ${openPorts.length} open — ${openPorts.join(", ")}');
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
  final StreamController<String> logStream = StreamController<String>.broadcast();
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
                  if (showAddButton && isDone)
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
  return null;
}
