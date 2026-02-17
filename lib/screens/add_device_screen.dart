import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pingit/models/device_model.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key, this.device, this.groups = const []});

  final Device? device;
  final List<DeviceGroup> groups;

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _tagsController;
  late TextEditingController _portController;

  late int _selectedInterval;
  late int _selectedThreshold;
  String? _selectedGroupId;
  late DeviceType _selectedType;
  late CheckType _selectedCheckType;

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
    _selectedInterval = widget.device?.interval ?? 10;
    _selectedThreshold = widget.device?.failureThreshold ?? 1;
    _selectedGroupId = widget.device?.groupId;
    _selectedType = widget.device?.type ?? DeviceType.server;
    _selectedCheckType = widget.device?.checkType ?? CheckType.icmp;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _tagsController.dispose();
    _portController.dispose();
    super.dispose();
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
        padding: const EdgeInsets.all(24),
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
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<CheckType>(
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
                              onChanged: (val) =>
                                  setState(() => _selectedCheckType = val!),
                            ),
                          ),
                          if (_selectedCheckType == CheckType.tcp) ...[
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 120,
                              child: _buildField(
                                _portController,
                                'Port',
                                Icons.numbers,
                                isRequired: true,
                              ),
                            ),
                          ],
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
                      _buildField(
                        _tagsController,
                        'Metadata Tags (comma separated)',
                        Icons.tag,
                        isRequired: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saveDevice,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isEditing ? 'Save Changes' : 'Create Node',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 12),
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
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.red.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
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
      final normalized =
          value.startsWith('http://') || value.startsWith('https://')
          ? value
          : 'https://$value';
      final uri = Uri.tryParse(normalized);
      return uri != null && uri.host.isNotEmpty;
    }

    final uriHost = Uri.tryParse('scheme://$value')?.host ?? '';
    final host = uriHost.isNotEmpty ? uriHost : value;
    return _hostLikePattern.hasMatch(host);
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
