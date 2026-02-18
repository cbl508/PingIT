import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/ping_service.dart';

class _Preset {
  final String name;
  final String address;
  final CheckType checkType;
  final DeviceType deviceType;

  const _Preset(this.name, this.address, this.checkType, this.deviceType);
}

const _presets = <_Preset>[
  _Preset('Cloudflare DNS', '1.1.1.1', CheckType.icmp, DeviceType.cloud),
  _Preset('Google DNS', '8.8.8.8', CheckType.icmp, DeviceType.cloud),
  _Preset('Quad9 DNS', '9.9.9.9', CheckType.icmp, DeviceType.cloud),
  _Preset('OpenDNS', '208.67.222.222', CheckType.icmp, DeviceType.cloud),
  _Preset('Google.com', 'google.com', CheckType.http, DeviceType.website),
  _Preset('Cloudflare.com', 'cloudflare.com', CheckType.http, DeviceType.website),
  _Preset('GitHub', 'github.com', CheckType.http, DeviceType.website),
  _Preset('AWS EC2 (us-east-1)', 'ec2.us-east-1.amazonaws.com', CheckType.http, DeviceType.cloud),
];

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({
    super.key,
    this.device,
    this.groups = const [],
    this.existingDevices = const [],
  });

  final Device? device;
  final List<DeviceGroup> groups;
  final List<Device> existingDevices;

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _tagsController;
  late TextEditingController _portController;
  late TextEditingController _latencyThresholdController;
  late TextEditingController _packetLossThresholdController;

  late int _selectedInterval;
  late int _selectedThreshold;
  String? _selectedGroupId;
  late DeviceType _selectedType;
  late CheckType _selectedCheckType;
  DateTime? _maintenanceUntil;
  _Preset? _selectedPreset;
  
  // Connection Testing State
  bool _isTesting = false;
  String? _testResult;
  Color? _testStatusColor;

  final List<int> _intervalOptions = [5, 10, 30, 60, 300, 600];
  final List<int> _thresholdOptions = [1, 2, 3, 5, 10];
  static final RegExp _hostLikePattern = RegExp(r'^[A-Za-z0-9.-]+$');

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device?.name ?? '');
    _addressController = TextEditingController(
      text: widget.device?.address ?? '',
    );
    _tagsController = TextEditingController(
      text: widget.device?.tags.join(', ') ?? '',
    );
    _portController = TextEditingController(
      text: widget.device?.port?.toString() ?? '80',
    );
    _latencyThresholdController = TextEditingController(
      text: widget.device?.latencyThreshold?.toStringAsFixed(0) ?? '',
    );
    _packetLossThresholdController = TextEditingController(
      text: widget.device?.packetLossThreshold?.toStringAsFixed(0) ?? '',
    );
    _selectedInterval = widget.device?.interval ?? 10;
    _selectedThreshold = widget.device?.failureThreshold ?? 1;
    _selectedGroupId = widget.device?.groupId;
    _selectedType = widget.device?.type ?? DeviceType.server;
    _selectedCheckType = widget.device?.checkType ?? CheckType.icmp;
    _maintenanceUntil = widget.device?.maintenanceUntil;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _tagsController.dispose();
    _portController.dispose();
    _latencyThresholdController.dispose();
    _packetLossThresholdController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    // Basic validation before testing
    final address = _addressController.text.trim();
    if (address.isEmpty || !_isValidAddress(address)) {
      setState(() {
        _testResult = 'Invalid Address';
        _testStatusColor = Colors.red;
      });
      return;
    }

    final port = _selectedCheckType == CheckType.tcp
        ? int.tryParse(_portController.text.trim())
        : null;
        
    if (_selectedCheckType == CheckType.tcp && port == null) {
      setState(() {
        _testResult = 'Invalid Port';
        _testStatusColor = Colors.red;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = 'Testing connection...';
      _testStatusColor = Colors.grey;
    });

    try {
      // Create a temporary device object for the check
      final tempDevice = Device(
        name: 'Temp',
        address: address,
        checkType: _selectedCheckType,
        port: port,
      );

      final result = await PingService().performSingleCheck(tempDevice);

      if (!mounted) return;

      if (result.status == DeviceStatus.online) {
        setState(() {
          _testResult = 'Online (${result.latency?.toStringAsFixed(0)}ms)';
          _testStatusColor = Colors.green;
        });
      } else if (result.status == DeviceStatus.degraded) {
        setState(() {
           _testResult = 'Degraded (${result.latency?.toStringAsFixed(0)}ms, ${result.packetLoss.toStringAsFixed(0)}% loss)';
           _testStatusColor = Colors.orange;
        });
      } else {
        setState(() {
           final extra = result.responseCode != null ? 'HTTP ${result.responseCode}' : 'Unreachable';
           _testResult = 'Offline ($extra)';
           _testStatusColor = Colors.red;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = 'Error: $e';
        _testStatusColor = Colors.red;
      });
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _saveDevice() {
    if (_formKey.currentState!.validate()) {
      final trimmedName = _nameController.text.trim();
      final trimmedAddress = _addressController.text.trim();
      final tags = _tagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final port = _selectedCheckType == CheckType.tcp
          ? int.tryParse(_portController.text)
          : null;

      final latencyThreshold = double.tryParse(_latencyThresholdController.text.trim());
      final packetLossThreshold = double.tryParse(_packetLossThresholdController.text.trim());

      if (widget.device != null) {
        widget.device!.name = trimmedName;
        widget.device!.address = trimmedAddress;
        widget.device!.interval = _selectedInterval;
        widget.device!.failureThreshold = _selectedThreshold;
        widget.device!.tags = tags;
        widget.device!.groupId = _selectedGroupId;
        widget.device!.type = _selectedType;
        widget.device!.checkType = _selectedCheckType;
        widget.device!.port = port;
        widget.device!.latencyThreshold = latencyThreshold;
        widget.device!.packetLossThreshold = packetLossThreshold;
        widget.device!.maintenanceUntil = _maintenanceUntil;
        Navigator.of(context).pop(widget.device);
      } else {
        final newDevice = Device(
          name: trimmedName,
          address: trimmedAddress,
          interval: _selectedInterval,
          failureThreshold: _selectedThreshold,
          tags: tags,
          groupId: _selectedGroupId,
          type: _selectedType,
          checkType: _selectedCheckType,
          port: port,
          latencyThreshold: latencyThreshold,
          packetLossThreshold: packetLossThreshold,
          maintenanceUntil: _maintenanceUntil,
        );
        Navigator.of(context).pop(newDevice);
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Host?',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete ${widget.device?.name}? All history will be lost.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).pop('delete');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckTypeDropdown() {
    return DropdownButtonFormField<CheckType>(
      initialValue: _selectedCheckType,
      style: GoogleFonts.inter(
        color: Theme.of(context).textTheme.bodyMedium?.color,
      ),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.check_circle_outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelText: 'Check Type',
      ),
      items: const [
        DropdownMenuItem(
          value: CheckType.icmp,
          child: Text('ICMP (Standard Ping)'),
        ),
        DropdownMenuItem(
          value: CheckType.tcp,
          child: Text('TCP Socket (Service)'),
        ),
        DropdownMenuItem(
          value: CheckType.http,
          child: Text('HTTP/S (Web & API)'),
        ),
      ],
      onChanged: (val) => setState(() => _selectedCheckType = val!),
    );
  }

  Widget _buildLatencyThresholdField() {
    return TextFormField(
      controller: _latencyThresholdController,
      keyboardType: TextInputType.number,
      style: GoogleFonts.inter(),
      decoration: InputDecoration(
        labelText: 'Latency Threshold (ms)',
        labelStyle: GoogleFonts.inter(),
        prefixIcon: const Icon(Icons.speed),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        helperText: 'Mark degraded above this latency',
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return null;
        final v = double.tryParse(val.trim());
        if (v == null || v <= 0) return 'Must be a positive number';
        if (v > 10000) return 'Maximum is 10,000ms';
        return null;
      },
    );
  }

  Widget _buildPacketLossThresholdField() {
    return TextFormField(
      controller: _packetLossThresholdController,
      keyboardType: TextInputType.number,
      style: GoogleFonts.inter(),
      decoration: InputDecoration(
        labelText: 'Packet Loss Threshold (%)',
        labelStyle: GoogleFonts.inter(),
        prefixIcon: const Icon(Icons.leak_add),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        helperText: 'Mark degraded above this loss %',
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return null;
        final v = double.tryParse(val.trim());
        if (v == null || v < 0 || v > 100) return 'Must be 0-100';
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.device != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Infrastructure' : 'New Monitor Node',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _confirmDelete,
              tooltip: 'Delete Device',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionCard(
                    context,
                    title: 'Basic Information',
                    icon: Icons.info_outline,
                    children: [
                      if (!isEditing) ...[
                        DropdownButtonFormField<_Preset?>(
                          initialValue: _selectedPreset,
                          style: GoogleFonts.inter(
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.playlist_add_check_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            labelText: 'Preconfigured',
                          ),
                          items: [
                            DropdownMenuItem<_Preset?>(
                              value: null,
                              child: Text('Custom (Manual Entry)',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  )),
                            ),
                            ..._presets.map(
                              (p) => DropdownMenuItem<_Preset?>(
                                value: p,
                                child: Text(p.name,
                                    style: GoogleFonts.inter(fontSize: 13)),
                              ),
                            ),
                          ],
                          onChanged: (preset) {
                            setState(() {
                              _selectedPreset = preset;
                              if (preset != null) {
                                _nameController.text = preset.name;
                                _addressController.text = preset.address;
                                _selectedCheckType = preset.checkType;
                                _selectedType = preset.deviceType;
                                _portController.text = '80';
                              } else {
                                _nameController.clear();
                                _addressController.clear();
                                _selectedCheckType = CheckType.icmp;
                                _selectedType = DeviceType.server;
                                _portController.text = '80';
                              }
                              _testResult = null;
                              _testStatusColor = null;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildField(
                        _nameController,
                        'Display Name',
                        Icons.badge_outlined,
                        isRequired: true,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        _addressController,
                        'Address',
                        Icons.link,
                        enabled: !isEditing,
                        isRequired: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    context,
                    title: 'Monitoring Configuration',
                    icon: Icons.settings_input_component,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isStacked = constraints.maxWidth < 450;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!isStacked && _selectedCheckType == CheckType.tcp)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _buildCheckTypeDropdown(),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 1,
                                      child: _buildField(
                                        _portController,
                                        'Port',
                                        Icons.numbers,
                                        isRequired: true,
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                _buildCheckTypeDropdown(),
                                if (_selectedCheckType == CheckType.tcp) ...[
                                  const SizedBox(height: 16),
                                  _buildField(
                                    _portController,
                                    'Port',
                                    Icons.numbers,
                                    isRequired: true,
                                  ),
                                ],
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // Test Connection Section
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow, size: 16),
                            label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          if (_testResult != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _testStatusColor?.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _testStatusColor?.withValues(alpha: 0.2) ?? Colors.transparent),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.terminal_outlined, size: 14, color: _testStatusColor),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _testResult!,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: _testStatusColor, 
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    context,
                    title: 'Organization',
                    icon: Icons.folder_open,
                    children: [
                      DropdownButtonFormField<DeviceType>(
                        initialValue: _selectedType,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.category_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelText: 'Device Role',
                        ),
                        items: DeviceType.values
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Row(
                                  children: [
                                    Icon(_getIconForType(t), size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      t.name.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedType = val!),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedGroupId,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.folder_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelText: 'Assign to Group',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Global Workspace'),
                          ),
                          ...widget.groups.map(
                            (g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedGroupId = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    context,
                    title: 'Advanced Settings',
                    icon: Icons.tune,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _selectedInterval,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.timer_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelText: 'Polling Rate',
                        ),
                        items: _intervalOptions
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text('$s seconds'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedInterval = val!),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedThreshold,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.repeat_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelText: 'Alert Threshold',
                          helperText: 'Consecutive failures before alerting',
                        ),
                        items: _thresholdOptions
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t == 1 ? '1 failure (immediate)' : '$t consecutive failures'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedThreshold = val!),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isStacked = constraints.maxWidth < 500;
                          return Column(
                            children: [
                              if (isStacked) ...[
                                _buildLatencyThresholdField(),
                                const SizedBox(height: 16),
                                _buildPacketLossThresholdField(),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildLatencyThresholdField()),
                                    const SizedBox(width: 16),
                                    Expanded(child: _buildPacketLossThresholdField()),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildMaintenanceWindowPicker(),
                      const SizedBox(height: 16),
                      _buildField(
                        _tagsController,
                        'Metadata Tags (comma separated)',
                        Icons.tag,
                        isRequired: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    context,
                    title: 'Advanced Monitoring',
                    icon: Icons.security_outlined,
                    children: [
                      if (_selectedCheckType == CheckType.http) ...[
                        TextFormField(
                          initialValue: widget.device?.keyword,
                          style: GoogleFonts.inter(),
                          decoration: InputDecoration(
                            labelText: 'Content Keyword Match',
                            prefixIcon: const Icon(Icons.find_in_page_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            helperText: 'Alert if this text is missing from the response body',
                          ),
                          onChanged: (v) => widget.device?.keyword = v,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: widget.device?.sslExpiryWarningDays?.toString() ?? '14',
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.inter(),
                          decoration: InputDecoration(
                            labelText: 'SSL Expiry Warning (Days)',
                            prefixIcon: const Icon(Icons.lock_clock_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            helperText: 'Alert when certificate has fewer than X days left',
                          ),
                          onChanged: (v) => widget.device?.sslExpiryWarningDays = int.tryParse(v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        initialValue: widget.device?.dnsExpectedIp,
                        style: GoogleFonts.inter(),
                        decoration: InputDecoration(
                          labelText: 'Expected DNS IP',
                          prefixIcon: const Icon(Icons.dns_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          helperText: 'Verify that resolution matches this IP',
                        ),
                        onChanged: (v) => widget.device?.dnsExpectedIp = v,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionCard(
                    context,
                    title: 'Integrations',
                    icon: Icons.integration_instructions_outlined,
                    children: [
                      TextFormField(
                        initialValue: widget.device?.discordWebhookUrl,
                        style: GoogleFonts.inter(),
                        decoration: InputDecoration(
                          labelText: 'Discord Webhook URL (Node Specific)',
                          prefixIcon: const Icon(Icons.discord),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (v) => widget.device?.discordWebhookUrl = v,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: widget.device?.slackWebhookUrl,
                        style: GoogleFonts.inter(),
                        decoration: InputDecoration(
                          labelText: 'Slack Webhook URL (Node Specific)',
                          prefixIcon: const Icon(Icons.alternate_email),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (v) => widget.device?.slackWebhookUrl = v,
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: _saveDevice,
                    icon: Icon(isEditing ? Icons.save : Icons.add_moderator),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    label: Text(
                      isEditing ? 'Save Changes' : 'Create Monitor Node',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _confirmDelete,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                      label: Text(
                        'Delete Node',
                        style: GoogleFonts.inter(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF0F172A).withValues(alpha: 0.5) 
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool enabled = true,
    bool isRequired = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: label == 'Port' ? TextInputType.number : TextInputType.text,
      style: GoogleFonts.inter(),
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: GoogleFonts.inter(),
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: !enabled,
      ),
      validator: (val) {
        final value = val?.trim() ?? '';
        if (isRequired && value.isEmpty) return 'Required field';
        if (value.isEmpty) return null;

        if (label == 'Address') {
          if (!_isValidAddress(value)) {
            return _selectedCheckType == CheckType.http
                ? 'Enter a valid host or URL'
                : 'Enter a valid host or IP';
          }
          // Duplicate address check (case insensitive)
          final normalizedValue = value.toLowerCase();
          final isDuplicate = widget.existingDevices.any((d) {
            // Allow own address when editing
            if (widget.device != null && d.id == widget.device!.id) return false;
            return d.address.trim().toLowerCase() == normalizedValue;
          });
          if (isDuplicate) {
            return 'This address is already being monitored';
          }
        }

        if (label == 'Port' && _selectedCheckType == CheckType.tcp) {
          final port = int.tryParse(value);
          if (port == null || port < 1 || port > 65535) {
            return 'Port must be between 1 and 65535';
          }
        }

        return null;
      },
    );
  }

  bool _isValidAddress(String value) {
    if (_selectedCheckType == CheckType.http) {
      // Must be a valid URL format for HTTP
      final normalized =
          value.startsWith('http://') || value.startsWith('https://')
          ? value
          : 'http://$value'; // Default to http for validation if missing
          
      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty) return false;
      
      // Ensure it has a dot (e.g., localhost.com or at least localhost)
      // Actually localhost is valid without dot.
      return true;
    } else {
      // ICMP or TCP: Must be hostname or IP, no scheme/path
      if (value.contains('://') || value.contains('/')) return false;
      return _hostLikePattern.hasMatch(value);
    }
  }

  Widget _buildMaintenanceWindowPicker() {
    final hasWindow = _maintenanceUntil != null && _maintenanceUntil!.isAfter(DateTime.now());
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Maintenance Window',
        labelStyle: GoogleFonts.inter(),
        prefixIcon: const Icon(Icons.construction_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        helperText: 'Suppress alerts during scheduled maintenance',
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasWindow
                  ? 'Until ${DateFormat('MMM dd, yyyy HH:mm').format(_maintenanceUntil!)}'
                  : 'No maintenance scheduled',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: hasWindow ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (hasWindow)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() => _maintenanceUntil = null),
              tooltip: 'Clear',
            ),
          TextButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _maintenanceUntil ?? DateTime.now().add(const Duration(hours: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: _maintenanceUntil != null
                    ? TimeOfDay.fromDateTime(_maintenanceUntil!)
                    : TimeOfDay.now(),
              );
              if (time == null || !mounted) return;
              setState(() {
                _maintenanceUntil = DateTime(date.year, date.month, date.day, time.hour, time.minute);
              });
            },
            child: Text(hasWindow ? 'Change' : 'Schedule'),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(DeviceType type) {
    switch (type) {
      case DeviceType.server:
        return Icons.dns;
      case DeviceType.database:
        return Icons.storage;
      case DeviceType.router:
        return Icons.router;
      case DeviceType.workstation:
        return Icons.computer;
      case DeviceType.iot:
        return Icons.memory;
      case DeviceType.website:
        return Icons.language;
      case DeviceType.cloud:
        return Icons.cloud;
    }
  }
}
