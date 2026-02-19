import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';
import '../providers/rules_provider.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  double _delaySeconds = 0;

  // SMS
  bool _smsEnabled = false;
  int? _smsIncomingTemplateId;
  int? _smsOutgoingTemplateId;
  int? _smsMissedTemplateId;

  // Unique per day
  bool _uniquePerDay = true;

  // Excluded numbers
  final _excludedNumbers = <String>[];
  final _excludedController = TextEditingController();

  // Working hours
  bool _workingHoursEnabled = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);

  // Contact filter
  String _contactFilter = 'all';

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _excludedController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final db = ref.read(databaseProvider);
    final smsTemplates = await db.getTemplatesByChannel('sms');
    final rule = await db.getRule();
    if (rule != null) {
      try {
        final config = jsonDecode(rule.configJson) as Map<String, dynamic>;
        setState(() {
          _delaySeconds = (config['delay_seconds'] as int? ?? 0).toDouble();

          final sms = config['sms'] as Map<String, dynamic>?;
          if (sms != null) {
            _smsEnabled = sms['enabled'] as bool? ?? false;
            _smsIncomingTemplateId = _normalizeTemplateId(
              _parseTemplateId(sms['incoming_template_id']),
              smsTemplates,
            );
            _smsOutgoingTemplateId = _normalizeTemplateId(
              _parseTemplateId(sms['outgoing_template_id']),
              smsTemplates,
            );
            _smsMissedTemplateId = _normalizeTemplateId(
              _parseTemplateId(sms['missed_template_id']),
              smsTemplates,
            );
          }

          _uniquePerDay = config['unique_per_day'] as bool? ?? true;

          final excluded = config['excluded_numbers'] as List<dynamic>?;
          if (excluded != null) {
            _excludedNumbers.addAll(excluded.map((e) => e.toString()));
          }

          final wh = config['working_hours'] as Map<String, dynamic>?;
          if (wh != null) {
            _workingHoursEnabled = wh['enabled'] as bool? ?? false;
            final start = wh['start_time'] as String? ?? '09:00';
            final end = wh['end_time'] as String? ?? '18:00';
            final startParts = start.split(':');
            final endParts = end.split(':');
            _startTime = TimeOfDay(
              hour: int.tryParse(startParts[0]) ?? 9,
              minute: int.tryParse(startParts[1]) ?? 0,
            );
            _endTime = TimeOfDay(
              hour: int.tryParse(endParts[0]) ?? 18,
              minute: int.tryParse(endParts[1]) ?? 0,
            );
          }

          final cf = config['contact_filter'] as Map<String, dynamic>?;
          if (cf != null) {
            _contactFilter = cf['mode'] as String? ?? 'all';
          }
        });
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  int? _parseTemplateId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int? _normalizeTemplateId(int? storedId, List<Template> templates) {
    if (storedId == null) return null;
    final matchesCanonical =
        templates.any((t) => (t.serverId ?? t.id) == storedId);
    if (matchesCanonical) return storedId;

    final localMatch = templates.where((t) => t.id == storedId).firstOrNull;
    if (localMatch != null) {
      return localMatch.serverId ?? localMatch.id;
    }
    return null;
  }

  Map<String, dynamic> _buildConfig() {
    return {
      'delay_seconds': _delaySeconds.toInt(),
      'unique_per_day': _uniquePerDay,
      'sms': {
        'enabled': _smsEnabled,
        if (_smsIncomingTemplateId != null)
          'incoming_template_id': _smsIncomingTemplateId,
        if (_smsOutgoingTemplateId != null)
          'outgoing_template_id': _smsOutgoingTemplateId,
        if (_smsMissedTemplateId != null)
          'missed_template_id': _smsMissedTemplateId,
      },
      'excluded_numbers': _excludedNumbers,
      if (_workingHoursEnabled)
        'working_hours': {
          'enabled': true,
          'start_time':
              '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
          'end_time':
              '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
          'timezone': 'Asia/Kolkata',
        },
      'contact_filter': {
        'mode': _contactFilter,
      },
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final configJson = jsonEncode(_buildConfig());
      final db = ref.read(databaseProvider);
      await db.upsertRule(RulesCompanion(
        configJson: drift.Value(configJson),
        isSynced: const drift.Value(false),
        updatedAt: drift.Value(DateTime.now()),
      ));

      // Push to server
      final sync = ref.read(syncProvider);
      await sync.pushRuleConfig(configJson);

      // Push to native bridge using shared sync path so all config flags stay in sync.
      await sync.pushLocalConfigToNative();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving rules: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final smsTemplates = ref.watch(smsTemplatesProvider);
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rules')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        label: _saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save Rules'),
        icon: _saving ? null : const Icon(Icons.save),
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 16, 16, 80), // Extra padding for FAB
        children: [
          // SMS Templates card
          const _SectionHeader(icon: Icons.sms, title: 'SMS Templates'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable SMS'),
                  subtitle: const Text('Send SMS after calls'),
                  value: _smsEnabled,
                  onChanged: (v) => setState(() => _smsEnabled = v),
                ),
                if (_smsEnabled)
                  smsTemplates.when(
                    data: (templates) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          _TemplateDropdown(
                            label: 'Incoming Call',
                            icon: Icons.call_received,
                            callType: 'incoming',
                            value: _smsIncomingTemplateId,
                            templates: templates,
                            onChanged: (v) =>
                                setState(() => _smsIncomingTemplateId = v),
                          ),
                          const SizedBox(height: 12),
                          _TemplateDropdown(
                            label: 'Outgoing Call',
                            icon: Icons.call_made,
                            callType: 'outgoing',
                            value: _smsOutgoingTemplateId,
                            templates: templates,
                            onChanged: (v) =>
                                setState(() => _smsOutgoingTemplateId = v),
                          ),
                          const SizedBox(height: 12),
                          _TemplateDropdown(
                            label: 'Missed Call',
                            icon: Icons.call_missed,
                            callType: 'missed',
                            value: _smsMissedTemplateId,
                            templates: templates,
                            onChanged: (v) =>
                                setState(() => _smsMissedTemplateId = v),
                          ),
                        ],
                      ),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Error loading templates'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Timing card
          const _SectionHeader(icon: Icons.timer_outlined, title: 'Timing'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Delay After Call'),
                  trailing: Text(
                    '${_delaySeconds.toInt()}s',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Slider(
                    value: _delaySeconds,
                    min: 0,
                    max: 60,
                    divisions: 12,
                    label: '${_delaySeconds.toInt()}s',
                    onChanged: (v) => setState(() => _delaySeconds = v),
                  ),
                ),
                const Divider(height: 0),
                SwitchListTile(
                  title: const Text('Once Per Number Per Day'),
                  subtitle: const Text('Skip if already messaged today'),
                  value: _uniquePerDay,
                  onChanged: (v) => setState(() => _uniquePerDay = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Working Hours card
          const _SectionHeader(
              icon: Icons.schedule_outlined, title: 'Working Hours'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Restrict to Working Hours'),
                  subtitle: const Text('Only send during business hours'),
                  value: _workingHoursEnabled,
                  onChanged: (v) => setState(() => _workingHoursEnabled = v),
                ),
                if (_workingHoursEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _TimeButton(
                            label: 'Start',
                            time: _startTime,
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _startTime,
                              );
                              if (time != null) {
                                setState(() => _startTime = time);
                              }
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(Icons.arrow_forward,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Expanded(
                          child: _TimeButton(
                            label: 'End',
                            time: _endTime,
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _endTime,
                              );
                              if (time != null) {
                                setState(() => _endTime = time);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Filters card
          const _SectionHeader(icon: Icons.filter_list, title: 'Filters'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Contact filter
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child:
                      Text('Contact Filter', style: theme.textTheme.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(
                          value: 'contacts_only', label: Text('Contacts')),
                      ButtonSegment(
                          value: 'non_contacts_only',
                          label: Text('Non-contacts')),
                    ],
                    selected: {_contactFilter},
                    onSelectionChanged: (s) =>
                        setState(() => _contactFilter = s.first),
                  ),
                ),
                const Divider(height: 24),

                // Excluded numbers
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Excluded Numbers',
                      style: theme.textTheme.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _excludedController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            hintText: 'Add phone number',
                            isDense: true,
                            prefixIcon: Icon(Icons.phone, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {
                          final number = _excludedController.text.trim();
                          if (number.isNotEmpty) {
                            setState(() => _excludedNumbers.add(number));
                            _excludedController.clear();
                          }
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                if (_excludedNumbers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _excludedNumbers
                          .map((n) => Chip(
                                label: Text(n),
                                onDeleted: () =>
                                    setState(() => _excludedNumbers.remove(n)),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 2),
          Text(time.format(context),
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _TemplateDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String callType;
  final int? value;
  final List<Template> templates;
  final ValueChanged<int?> onChanged;

  const _TemplateDropdown({
    required this.label,
    required this.icon,
    required this.callType,
    required this.value,
    required this.templates,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filtered =
        templates.where((t) => t.type == callType || t.type == 'all').toList();
    return DropdownButtonFormField<int?>(
      initialValue:
          filtered.any((t) => (t.serverId ?? t.id) == value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: Icon(icon, size: 20),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('None'),
        ),
        ...filtered.map((t) => DropdownMenuItem<int?>(
              value: t.serverId ?? t.id,
              child: Text(t.name, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: onChanged,
    );
  }
}
