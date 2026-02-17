import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pingit/main.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/email_service.dart';
import 'package:pingit/services/storage_service.dart';
import 'package:pingit/services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.devices,
    required this.groups,
    required this.onImported,
    required this.onEmailSettingsChanged,
  });

  final List<Device> devices;
  final List<DeviceGroup> groups;
  final Function(List<Device>) onImported;
  final Function(EmailSettings) onEmailSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storageService = StorageService();
  late TextEditingController _smtpController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _recipientController;
  bool _emailEnabled = false;
  Timer? _settingsSaveDebounce;

  // Update state
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;
  bool _isApplyingUpdate = false;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    _smtpController = TextEditingController();
    _userController = TextEditingController();
    _passController = TextEditingController();
    _recipientController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _storageService.loadEmailSettings();
    if (!mounted) return;
    setState(() {
      _smtpController.text = settings.smtpServer;
      _userController.text = settings.username;
      _passController.text = settings.password;
      _recipientController.text = settings.recipientEmail;
      _emailEnabled = settings.isEnabled;
    });
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    _smtpController.dispose();
    _userController.dispose();
    _passController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 300), () {
      final settings = EmailSettings(
        smtpServer: _smtpController.text,
        username: _userController.text,
        password: _passController.text,
        recipientEmail: _recipientController.text,
        isEnabled: _emailEnabled,
      );
      widget.onEmailSettingsChanged(settings);
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final update = await UpdateService().checkForUpdate();
    if (!mounted) return;
    setState(() {
      _updateInfo = update;
      _isCheckingUpdate = false;
      _updateChecked = true;
    });
  }

  Future<void> _applyUpdate() async {
    if (_updateInfo == null) return;
    setState(() => _isApplyingUpdate = true);
    final success = await UpdateService().downloadAndApply(_updateInfo!);
    if (!mounted) return;
    if (success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Update Ready', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Text(
            'The update has been downloaded and staged. The application will now restart to apply the update.',
            style: GoogleFonts.inter(),
          ),
          actions: [
            FilledButton(
              onPressed: () => exit(0),
              child: const Text('Restart Now'),
            ),
          ],
        ),
      );
    } else {
      setState(() => _isApplyingUpdate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update failed. Please try again later.')),
      );
    }
  }

  Future<void> _exportToCSV() async {
    List<List<dynamic>> rows = [
      ["Device", "Type", "Address", "Timestamp", "Status", "Latency", "Loss"],
    ];
    for (var d in widget.devices) {
      for (var h in d.history) {
        rows.add([
          d.name,
          d.type.name,
          d.address,
          h.timestamp.toIso8601String(),
          h.status.name,
          h.latencyMs ?? "",
          h.packetLoss ?? "",
        ]);
      }
    }
    final csvData = const ListToCsvConverter().convert(rows);
    final suggestedName =
        'pingit_audit_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';

    String? outputPath;
    if (!kIsWeb) {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV Audit',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
    }

    if (outputPath == null || outputPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export cancelled.')));
      return;
    }

    try {
      await File(outputPath).writeAsString(csvData);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV exported to $outputPath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e')));
    }
  }

  Future<void> _importCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final csvText = await _readSelectedCsv(result);
      if (csvText == null || csvText.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read CSV file.')),
        );
        return;
      }

      final fields = const CsvToListConverter().convert(csvText);

      final existingAddresses = widget.devices
          .map((d) => d.address.trim().toLowerCase())
          .toSet();
      final importedAddresses = <String>{};
      List<Device> newDevices = [];
      int skipped = 0;
      for (int i = 1; i < fields.length; i++) {
        try {
          final row = fields[i];
          if (row.length < 2) {
            skipped++;
            continue;
          }

          final name = row[0].toString().trim();
          final address = row[1].toString().trim();
          final normalizedAddress = address.toLowerCase();
          final isInvalid = name.isEmpty || address.isEmpty;
          final isDuplicate =
              existingAddresses.contains(normalizedAddress) ||
              importedAddresses.contains(normalizedAddress);

          if (isInvalid || isDuplicate) {
            skipped++;
            continue;
          }

          importedAddresses.add(normalizedAddress);
          newDevices.add(
            Device(name: name, address: address, type: DeviceType.server),
          );
        } catch (e) {
          skipped++;
        }
      }

      if (newDevices.isNotEmpty) {
        widget.onImported(newDevices);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${newDevices.length} nodes. Skipped $skipped rows.',
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No nodes imported. Skipped $skipped rows.')),
        );
      }
    }
  }

  Future<String?> _readSelectedCsv(FilePickerResult result) async {
    if (kIsWeb) {
      final bytes = result.files.single.bytes;
      if (bytes == null) return null;
      return utf8.decode(bytes);
    }

    final path = result.files.single.path;
    if (path == null || path.isEmpty) return null;
    return File(path).readAsString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'System Configuration',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSectionHeader('APPLICATION'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Version'),
                      subtitle: Text('v${UpdateService.currentVersion}'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _isCheckingUpdate
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_outlined),
                      title: Text(_updateInfo != null
                          ? 'Update Available: v${_updateInfo!.version}'
                          : _updateChecked
                              ? 'You\'re up to date'
                              : 'Check for Updates'),
                      subtitle: _updateInfo != null
                          ? Text(_updateInfo!.releaseNotes, maxLines: 3, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: _updateInfo != null
                          ? FilledButton(
                              onPressed: _isApplyingUpdate ? null : _applyUpdate,
                              child: _isApplyingUpdate
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Install'),
                            )
                          : null,
                      onTap: _isCheckingUpdate ? null : _checkForUpdate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('ENVIRONMENT'),
              Card(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(
                              'System',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(
                              'Light',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        selected: {themeNotifier.value},
                        onSelectionChanged: (selection) {
                          setState(() => themeNotifier.value = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('OUTBOUND ALERTS (SMTP)'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Enable Email Alerts'),
                        subtitle: const Text(
                          'Send alerts when devices go offline',
                        ),
                        value: _emailEnabled,
                        onChanged: (val) {
                          setState(() => _emailEnabled = val);
                          _saveSettings();
                        },
                      ),
                      const Divider(),
                      TextField(
                        controller: _smtpController,
                        decoration: const InputDecoration(
                          labelText: 'SMTP Server',
                          hintText: 'smtp.gmail.com',
                        ),
                        onChanged: (_) => _saveSettings(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _userController,
                        decoration: const InputDecoration(
                          labelText: 'Username (Email)',
                        ),
                        onChanged: (_) => _saveSettings(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passController,
                        decoration: const InputDecoration(
                          labelText: 'Password / App Key',
                        ),
                        obscureText: true,
                        onChanged: (_) => _saveSettings(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _recipientController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient Email',
                        ),
                        onChanged: (_) => _saveSettings(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Note: For Gmail, use an "App Password" rather than your primary password.',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('UTILITIES'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.analytics_outlined),
                      title: const Text('Generate CSV Audit'),
                      subtitle: const Text('Export all historical telemetry'),
                      onTap: _exportToCSV,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('Bulk Import Infrastructure'),
                      subtitle: const Text(
                        'Import multiple nodes from CSV (Name, Address)',
                      ),
                      onTap: _importCSV,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
