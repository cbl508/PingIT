import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pingit/main.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/email_service.dart';
import 'package:pingit/services/report_service.dart';
import 'package:pingit/services/storage_service.dart';
import 'package:pingit/services/update_service.dart';
import 'package:pingit/services/webhook_service.dart';
import 'package:pingit/screens/updating_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.devices,
    required this.groups,
    required this.onImported,
    required this.onEmailSettingsChanged,
    required this.onWebhookSettingsChanged,
    required this.onQuietHoursChanged,
  });

  final List<Device> devices;
  final List<DeviceGroup> groups;
  final Function(List<Device>) onImported;
  final Function(EmailSettings) onEmailSettingsChanged;
  final Function(WebhookSettings) onWebhookSettingsChanged;
  final Function(QuietHoursSettings) onQuietHoursChanged;

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

  // Webhook state
  late TextEditingController _webhookUrlController;
  late TextEditingController _telegramTokenController;
  late TextEditingController _telegramChatIdController;
  WebhookType _webhookType = WebhookType.generic;
  bool _webhookEnabled = false;

  // Quiet hours state
  bool _quietEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);
  Set<int> _quietDays = {1, 2, 3, 4, 5, 6, 7};

  // Update state
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;
  bool _isApplyingUpdate = false;
  bool _updateChecked = false;
  double _updateProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _smtpController = TextEditingController();
    _userController = TextEditingController();
    _passController = TextEditingController();
    _recipientController = TextEditingController();
    _webhookUrlController = TextEditingController();
    _telegramTokenController = TextEditingController();
    _telegramChatIdController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _storageService.loadEmailSettings();
    final webhook = await _storageService.loadWebhookSettings();
    final quiet = await _storageService.loadQuietHours();
    if (!mounted) return;
    setState(() {
      _smtpController.text = settings.smtpServer;
      _userController.text = settings.username;
      _passController.text = settings.password;
      _recipientController.text = settings.recipientEmail;
      _emailEnabled = settings.isEnabled;

      _webhookUrlController.text = webhook.url;
      _webhookType = webhook.type;
      _webhookEnabled = webhook.enabled;
      _telegramTokenController.text = webhook.botToken ?? '';
      _telegramChatIdController.text = webhook.chatId ?? '';

      _quietEnabled = quiet.enabled;
      _quietStart = TimeOfDay(hour: quiet.startHour, minute: quiet.startMinute);
      _quietEnd = TimeOfDay(hour: quiet.endHour, minute: quiet.endMinute);
      _quietDays = quiet.daysOfWeek.toSet();
    });
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    _smtpController.dispose();
    _userController.dispose();
    _passController.dispose();
    _recipientController.dispose();
    _webhookUrlController.dispose();
    _telegramTokenController.dispose();
    _telegramChatIdController.dispose();
    super.dispose();
  }

  void _saveEmailSettings() {
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

  void _saveWebhookSettings() {
    final url = _webhookUrlController.text.trim();
    if (_webhookType != WebhookType.telegram && url.isNotEmpty) {
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid webhook URL. Please enter a valid URL starting with https://.')),
        );
        return;
      }
    }
    final settings = WebhookSettings(
      url: url,
      type: _webhookType,
      enabled: _webhookEnabled,
      botToken: _telegramTokenController.text.trim(),
      chatId: _telegramChatIdController.text.trim(),
    );
    widget.onWebhookSettingsChanged(settings);
  }

  void _saveQuietHours() {
    final settings = QuietHoursSettings(
      enabled: _quietEnabled,
      startHour: _quietStart.hour,
      startMinute: _quietStart.minute,
      endHour: _quietEnd.hour,
      endMinute: _quietEnd.minute,
      daysOfWeek: _quietDays.toList()..sort(),
    );
    widget.onQuietHoursChanged(settings);
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
    setState(() {
      _isApplyingUpdate = true;
      _updateProgress = 0.0;
    });
    final staged = await UpdateService().downloadAndStage(
      _updateInfo!,
      onProgress: (progress) {
        if (mounted) setState(() => _updateProgress = progress);
      },
    );
    if (!mounted) return;
    if (staged != null) {
      setState(() => _isApplyingUpdate = false);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          void restartNow() {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => UpdatingScreen(version: _updateInfo!.version),
              ),
              (_) => false,
            );
            UpdateService().launchUpdaterAndExit(staged);
          }

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): restartNow,
            },
            child: Focus(
              autofocus: true,
              child: AlertDialog(
                title: Text('Update Ready', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                content: Text(
                  'v${_updateInfo!.version} has been downloaded. Restart to apply the update.',
                  style: GoogleFonts.inter(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text('Later',
                        style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: restartNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Restart Now'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      setState(() => _isApplyingUpdate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update failed. Please try again later.')),
      );
    }
  }

  Future<void> _generateHealthReport() async {
    try {
      final reportFile = await ReportService().generateWeeklyUptimeReport(widget.devices);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Weekly report generated: ${reportFile.path}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              if (Platform.isWindows) {
                Process.run('cmd', ['/c', 'start', '', reportFile.path]);
              } else if (Platform.isMacOS) {
                Process.run('open', [reportFile.path]);
              } else {
                Process.run('xdg-open', [reportFile.path]);
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export cancelled.')));
      return;
    }

    try {
      await File(outputPath).writeAsString(csvData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV exported to $outputPath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e')));
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
          if (row.length < 2) { skipped++; continue; }

          final name = row[0].toString().trim();
          final address = row[1].toString().trim();
          final normalizedAddress = address.toLowerCase();
          final isInvalid = name.isEmpty || address.isEmpty;
          final isDuplicate =
              existingAddresses.contains(normalizedAddress) ||
              importedAddresses.contains(normalizedAddress);

          if (isInvalid || isDuplicate) { skipped++; continue; }

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
          SnackBar(content: Text('Imported ${newDevices.length} nodes. Skipped $skipped rows.')),
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
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.system_update_outlined),
                      title: Text(_updateInfo != null
                          ? 'Update Available: v${_updateInfo!.version}'
                          : _updateChecked ? 'You\'re up to date' : 'Check for Updates'),
                      subtitle: _updateInfo != null
                          ? (_isApplyingUpdate
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(value: _updateProgress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                                    const SizedBox(height: 4),
                                    Text('${(_updateProgress * 100).toStringAsFixed(0)}% downloaded',
                                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.grey)),
                                  ],
                                )
                              : Text(_updateInfo!.releaseNotes, maxLines: 3, overflow: TextOverflow.ellipsis))
                          : null,
                      trailing: _updateInfo != null
                          ? FilledButton(
                              onPressed: _isApplyingUpdate ? null : _applyUpdate,
                              child: _isApplyingUpdate
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                          ButtonSegment(value: ThemeMode.system, label: Text('System', style: TextStyle(fontSize: 12))),
                          ButtonSegment(value: ThemeMode.light, label: Text('Light', style: TextStyle(fontSize: 12))),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark', style: TextStyle(fontSize: 12))),
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
                        subtitle: const Text('Send alerts when devices go offline'),
                        value: _emailEnabled,
                        onChanged: (val) {
                          setState(() => _emailEnabled = val);
                          _saveEmailSettings();
                        },
                      ),
                      const Divider(),
                      TextField(
                        controller: _smtpController,
                        decoration: const InputDecoration(labelText: 'SMTP Server', hintText: 'smtp.gmail.com'),
                        onChanged: (_) => _saveEmailSettings(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _userController,
                        decoration: const InputDecoration(labelText: 'Username (Email)'),
                        onChanged: (_) => _saveEmailSettings(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passController,
                        decoration: const InputDecoration(labelText: 'Password / App Key'),
                        obscureText: true,
                        onChanged: (_) => _saveEmailSettings(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _recipientController,
                        decoration: const InputDecoration(labelText: 'Recipient Email'),
                        onChanged: (_) => _saveEmailSettings(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Note: For Gmail, use an "App Password" rather than your primary password.',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('WEBHOOK INTEGRATION'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Enable Webhook Alerts'),
                        subtitle: const Text('POST JSON on status changes'),
                        value: _webhookEnabled,
                        onChanged: (val) {
                          setState(() => _webhookEnabled = val);
                          _saveWebhookSettings();
                        },
                      ),
                      const Divider(),
                      DropdownButtonFormField<WebhookType>(
                        initialValue: _webhookType,
                        decoration: const InputDecoration(
                          labelText: 'Webhook Format',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        items: const [
                          DropdownMenuItem(value: WebhookType.generic, child: Text('Generic JSON')),
                          DropdownMenuItem(value: WebhookType.slack, child: Text('Slack')),
                          DropdownMenuItem(value: WebhookType.discord, child: Text('Discord')),
                          DropdownMenuItem(value: WebhookType.telegram, child: Text('Telegram Bot')),
                        ],
                        onChanged: (val) {
                          setState(() => _webhookType = val!);
                          _saveWebhookSettings();
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_webhookType == WebhookType.telegram) ...[
                        TextField(
                          controller: _telegramTokenController,
                          decoration: const InputDecoration(
                            labelText: 'Telegram Bot Token',
                            hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
                          ),
                          onChanged: (_) => _saveWebhookSettings(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _telegramChatIdController,
                          decoration: const InputDecoration(
                            labelText: 'Telegram Chat ID',
                            hintText: '-100123456789',
                          ),
                          onChanged: (_) => _saveWebhookSettings(),
                        ),
                      ] else
                        TextField(
                          controller: _webhookUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Webhook URL',
                            hintText: 'https://hooks.slack.com/services/...',
                          ),
                          onChanged: (_) => _saveWebhookSettings(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('QUIET HOURS / MAINTENANCE WINDOW'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Enable Quiet Hours'),
                        subtitle: const Text('Suppress notifications during scheduled times'),
                        value: _quietEnabled,
                        onChanged: (val) {
                          setState(() => _quietEnabled = val);
                          _saveQuietHours();
                        },
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              title: const Text('Start'),
                              subtitle: Text(_quietStart.format(context)),
                              trailing: const Icon(Icons.access_time),
                              onTap: () async {
                                final picked = await showTimePicker(context: context, initialTime: _quietStart);
                                if (picked != null) {
                                  setState(() => _quietStart = picked);
                                  _saveQuietHours();
                                }
                              },
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              title: const Text('End'),
                              subtitle: Text(_quietEnd.format(context)),
                              trailing: const Icon(Icons.access_time),
                              onTap: () async {
                                final picked = await showTimePicker(context: context, initialTime: _quietEnd);
                                if (picked != null) {
                                  setState(() => _quietEnd = picked);
                                  _saveQuietHours();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildDayChip(1, 'Mon'),
                          _buildDayChip(2, 'Tue'),
                          _buildDayChip(3, 'Wed'),
                          _buildDayChip(4, 'Thu'),
                          _buildDayChip(5, 'Fri'),
                          _buildDayChip(6, 'Sat'),
                          _buildDayChip(7, 'Sun'),
                        ],
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
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: const Text('Generate Weekly Health Report'),
                      subtitle: const Text('Create a PDF summary of all monitored nodes'),
                      onTap: _generateHealthReport,
                    ),
                    const Divider(height: 1),
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
                      subtitle: const Text('Import multiple nodes from CSV (Name, Address)'),
                      onTap: _importCSV,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('KEYBOARD SHORTCUTS'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildShortcutRow('Ctrl + N', 'Add new device'),
                      _buildShortcutRow('Ctrl + G', 'Create new group'),
                      _buildShortcutRow('Long Press', 'Enter multi-select mode'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayChip(int day, String label) {
    final isSelected = _quietDays.contains(day);
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            _quietDays.add(day);
          } else {
            _quietDays.remove(day);
          }
        });
        _saveQuietHours();
      },
    );
  }

  Widget _buildShortcutRow(String shortcut, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(shortcut, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Text(description, style: GoogleFonts.inter(fontSize: 13)),
        ],
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
