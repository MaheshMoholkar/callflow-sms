import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

class TemplateEditScreen extends ConsumerStatefulWidget {
  final int? templateId;

  const TemplateEditScreen({super.key, this.templateId});

  @override
  ConsumerState<TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TemplateEditScreenState extends ConsumerState<TemplateEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bodyController = TextEditingController();
  String _channel = 'sms';
  String _type = 'incoming';
  String? _imageUrl;
  String? _pendingImagePath;
  bool _removeImageOnSave = false;
  bool _isLoading = false;
  Template? _existing;

  static const _variables = [
    '{contact_name}',
    '{business_name}',
    '{phone_number}',
    '{call_duration}',
    '{date}',
    '{time}',
    '{landing_url}',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _loadTemplate();
    }
  }

  Future<void> _loadTemplate() async {
    final db = ref.read(databaseProvider);
    final templates = await db.getTemplates();
    final template =
        templates.where((t) => t.id == widget.templateId).firstOrNull;
    if (template != null && mounted) {
      setState(() {
        _existing = template;
        _nameController.text = template.name;
        _bodyController.text = template.body;
        _channel = template.channel;
        _type = template.type;
        _imageUrl = template.imagePath;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _insertVariable(String variable) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      variable,
    );
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + variable.length,
      ),
    );
  }

  int get _smsCharCount {
    final body = _bodyController.text;
    return body.length;
  }

  int get _smsParts {
    final len = _smsCharCount;
    if (len <= 160) return 1;
    return (len / 153).ceil();
  }

  bool get _showImagePicker => _channel == 'sms';

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (mounted) {
        setState(() {
          _pendingImagePath = picked.path;
          _removeImageOnSave = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  void _removeImage() {
    setState(() {
      _pendingImagePath = null;
      _imageUrl = null;
      _removeImageOnSave = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final db = ref.read(databaseProvider);
      final api = ref.read(apiClientProvider);
      final name = _nameController.text.trim();
      final body = _bodyController.text;
      final language = _existing?.language ?? 'en';
      final isDefault = _existing?.isDefault ?? false;

      String? effectiveImageUrl = _imageUrl;
      String? effectiveImageKey;
      if (_pendingImagePath != null) {
        final upload = await _uploadTemplateImage(api, _pendingImagePath!);
        effectiveImageUrl = upload.$1;
        effectiveImageKey = upload.$2;
      } else if (_removeImageOnSave) {
        effectiveImageUrl = null;
        effectiveImageKey = null;
      }

      int? serverId = _existing?.serverId;
      var source = _existing?.source ?? 'local';
      var isSynced = _existing?.isSynced ?? false;
      String? warningMessage;

      final payload = {
        'name': name,
        'body': body,
        'type': _type,
        'channel': _channel,
        'image_url': effectiveImageUrl,
        'image_key': effectiveImageKey,
        'language': language,
        'is_default': isDefault,
      };

      try {
        if (serverId != null) {
          await api.put('/template/$serverId', data: payload);
          source = 'server';
          isSynced = true;
        } else {
          final response = await api.post('/template', data: payload);
          final createdServerId = _extractTemplateId(response.data);
          if (createdServerId != null && createdServerId > 0) {
            serverId = createdServerId;
            source = 'server';
            isSynced = true;
          } else {
            source = 'local';
            isSynced = false;
            warningMessage =
                'Template saved locally. Server sync failed (missing template ID).';
          }
        }
      } catch (e) {
        if (serverId != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to sync template: $e')),
            );
          }
          return;
        }
        source = 'local';
        isSynced = false;
        warningMessage = 'Template saved locally. Server sync failed.';
      }

      if (_existing != null) {
        await db.updateTemplate(TemplatesCompanion(
          id: drift.Value(_existing!.id),
          serverId: drift.Value(serverId),
          name: drift.Value(name),
          body: drift.Value(body),
          type: drift.Value(_type),
          channel: drift.Value(_channel),
          imagePath: drift.Value(effectiveImageUrl),
          language: drift.Value(language),
          isDefault: drift.Value(isDefault),
          source: drift.Value(source),
          isSynced: drift.Value(isSynced),
          updatedAt: drift.Value(DateTime.now()),
        ));
      } else {
        await db.insertTemplate(TemplatesCompanion.insert(
          serverId: drift.Value(serverId),
          name: name,
          body: body,
          type: _type,
          channel: _channel,
          imagePath: drift.Value(effectiveImageUrl),
          language: drift.Value(language),
          isDefault: drift.Value(isDefault),
          source: drift.Value(source),
          isSynced: drift.Value(isSynced),
        ));
      }

      // Template text/image changes must be pushed to native immediately
      // so active rules use the latest template body without requiring rule re-save.
      await ref.read(syncProvider).pushLocalConfigToNative();

      if (mounted && warningMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warningMessage)),
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    if (_existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: const Text('Are you sure you want to delete this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      final serverId = _existing!.serverId;
      if (serverId != null) {
        final api = ref.read(apiClientProvider);
        try {
          await api.delete('/template/$serverId');
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete template: $e')),
            );
          }
          return;
        }
      }
      await db.deleteTemplate(_existing!.id);
      await ref.read(syncProvider).pushLocalConfigToNative();
      if (mounted) context.pop();
    }
  }

  Future<(String, String)> _uploadTemplateImage(
    ApiClient api,
    String imagePath,
  ) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imagePath,
        filename: p.basename(imagePath),
      ),
    });

    final response = await api.post('/template/upload-image', data: formData);
    final body = response.data;
    if (body is! Map) {
      throw Exception('Invalid upload response');
    }
    final data = body['data'];
    if (data is! Map) {
      throw Exception('Missing upload data');
    }
    final imageUrl = data['image_url'] as String?;
    final imageKey = data['image_key'] as String?;
    if (imageUrl == null ||
        imageUrl.isEmpty ||
        imageKey == null ||
        imageKey.isEmpty) {
      throw Exception('Upload response missing image URL/key');
    }
    return (imageUrl, imageKey);
  }

  int? _extractTemplateId(dynamic responseBody) {
    if (responseBody is! Map) return null;
    final data = responseBody['data'];
    if (data is! Map) return null;
    final id = data['id'];
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _existing != null;
    const showSmsCounter = true; // Always show for SMS-only
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Template' : 'New Template'),
        actions: [
          if (isEditing && !(_existing?.isDefault ?? false))
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Template Name',
                hintText: 'e.g. Follow-up After Incoming Call',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),

            const SizedBox(height: 16),

            // Image picker for SMS link previews
            if (_showImagePicker) ...[
              Text('Attach Image (optional)',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              if (_pendingImagePath != null &&
                  File(_pendingImagePath!).existsSync())
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_pendingImagePath!),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filled(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _removeImage,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                )
              else if (_imageUrl != null && _imageUrl!.isNotEmpty)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _imageUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 150,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Unable to preview image'),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filled(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _removeImage,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Pick Image'),
                ),
              const SizedBox(height: 6),
              Text(
                'Image URL will be added above the SMS text when sending.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],

            // Type selector
            Text('Call Type', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'incoming', label: Text('Incoming')),
                ButtonSegment(value: 'outgoing', label: Text('Outgoing')),
                ButtonSegment(value: 'missed', label: Text('Missed')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),

            // Message body
            TextFormField(
              controller: _bodyController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Message Body',
                hintText: 'Type your message template here...',
                alignLabelWithHint: true,
                counterText:
                    '$_smsCharCount/918 chars, $_smsParts part${_smsParts > 1 ? 's' : ''}',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Body is required' : null,
              onChanged: (_) => setState(() {}),
            ),
            if (showSmsCounter && _smsCharCount > 918)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'SMS body exceeds 918 character limit',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Variable chips
            Text('Insert Variable',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _variables
                  .map((v) => ActionChip(
                        label: Text(v),
                        onPressed: () => _insertVariable(v),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 32),

            FilledButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditing ? 'Save Changes' : 'Create Template'),
            ),
          ],
        ),
      ),
    );
  }
}
