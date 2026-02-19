import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';

class LandingEditScreen extends ConsumerStatefulWidget {
  const LandingEditScreen({super.key});

  @override
  ConsumerState<LandingEditScreen> createState() => _LandingEditScreenState();
}

class _LandingEditScreenState extends ConsumerState<LandingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final List<TextEditingController> _descriptionPointControllers = [];
  final _whatsappController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _locationController = TextEditingController();

  String? _imageUrl;
  String? _pendingImagePath;
  bool _removeImageOnSave = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descriptionPointControllers.add(TextEditingController());
    _loadLanding();
  }

  @override
  void dispose() {
    _headlineController.dispose();
    for (final controller in _descriptionPointControllers) {
      controller.dispose();
    }
    _whatsappController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _youtubeController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadLanding() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    await _loadWebsiteUrlFromCache();

    try {
      final response = await api.get('/landing');
      _applyLandingResponse(response.data);
    } on DioException catch (e) {
      // Older backend versions may respond 404 when landing is not created yet.
      // Treat this as an empty state so users can create content.
      if (e.response?.statusCode == 404) {
        await _loadLocationFromProfile(api);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load website details: $e')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load website details: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyLandingResponse(dynamic body) {
    if (body is! Map) return;
    final data = body['data'];
    if (data is! Map) return;

    final payload = Map<String, dynamic>.from(data);
    final landing = payload['landing'] is Map
        ? Map<String, dynamic>.from(payload['landing'] as Map)
        : <String, dynamic>{};

    _headlineController.text = landing['headline'] as String? ?? '';
    _setDescriptionPointsFromRaw(landing['description'] as String? ?? '');
    _whatsappController.text = landing['whatsapp_url'] as String? ?? '';
    _facebookController.text = landing['facebook_url'] as String? ?? '';
    _instagramController.text = landing['instagram_url'] as String? ?? '';
    _youtubeController.text = landing['youtube_url'] as String? ?? '';
    _emailController.text = landing['email'] as String? ?? '';
    _setWebsiteUrlFromUserId(_extractInt(landing['user_id']));
    _imageUrl = landing['image_url'] as String?;
    _locationController.text = payload['location_url'] as String? ?? '';
  }

  Future<void> _loadWebsiteUrlFromCache() async {
    try {
      final user = await ref.read(databaseProvider).getUser();
      _setWebsiteUrlFromUserId(user?.id);
    } catch (_) {}
  }

  Future<void> _loadLocationFromProfile(ApiClient api) async {
    try {
      final response = await api.get('/user/profile');
      final body = response.data;
      if (body is! Map) return;
      final data = body['data'];
      if (data is! Map) return;
      final user = data['user'];
      if (user is! Map) return;
      _setWebsiteUrlFromUserId(_extractInt(user['id']));
      _locationController.text = user['location_url'] as String? ?? '';
    } catch (_) {
      // No-op: location field can remain empty if profile fetch fails.
    }
  }

  int? _extractInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<String> _descriptionPointsFromRaw(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .map(
          (line) => line.replaceFirst(
            RegExp(r'^(?:[-*\u2022]\s+|\d+[.)]\s+)'),
            '',
          ),
        )
        .where((line) => line.isNotEmpty)
        .toList();
  }

  String _normalizedDescriptionPayload() {
    final points = _descriptionPointControllers
        .map((controller) => controller.text)
        .join('\n');
    return _descriptionPointsFromRaw(points).join('\n');
  }

  void _setDescriptionPointsFromRaw(String raw) {
    final points = _descriptionPointsFromRaw(raw);
    final values = points.isEmpty ? [''] : points;

    for (final controller in _descriptionPointControllers) {
      controller.dispose();
    }

    _descriptionPointControllers
      ..clear()
      ..addAll(
        values.map((point) => TextEditingController(text: point)),
      );

    if (mounted && !_loading) {
      setState(() {});
    }
  }

  void _addDescriptionPoint([String initialValue = '']) {
    setState(() {
      _descriptionPointControllers
          .add(TextEditingController(text: initialValue));
    });
  }

  void _removeDescriptionPoint(int index) {
    if (_descriptionPointControllers.length == 1) {
      _descriptionPointControllers.first.clear();
      return;
    }

    final controller = _descriptionPointControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  void _setWebsiteUrlFromUserId(int? userId) {
    if (!mounted || userId == null) return;
    final base = landingBaseUrl.endsWith('/')
        ? landingBaseUrl.substring(0, landingBaseUrl.length - 1)
        : landingBaseUrl;
    _websiteController.text = '$base/$userId';
  }

  Future<void> _copyWebsiteUrl() async {
    final url = _websiteController.text.trim();
    if (url.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Website URL copied')),
    );
  }

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

  Future<(String, String)> _uploadLandingImage(
    ApiClient api,
    String imagePath,
  ) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imagePath,
        filename: p.basename(imagePath),
      ),
    });

    final response = await api.post('/landing/upload-image', data: formData);
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

  Future<void> _upsertLanding(
    ApiClient api,
    Map<String, dynamic> payload,
  ) async {
    try {
      await api.put('/landing', data: payload);
      return;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
    }

    try {
      await api.put('/landing/', data: payload);
      return;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
    }

    // Backward compatibility for deployments using POST for upsert.
    await api.post('/landing', data: payload);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final api = ref.read(apiClientProvider);

      String? effectiveImageUrl = _imageUrl;
      String? effectiveImageKey;

      if (_pendingImagePath != null) {
        final upload = await _uploadLandingImage(api, _pendingImagePath!);
        effectiveImageUrl = upload.$1;
        effectiveImageKey = upload.$2;
      } else if (_removeImageOnSave) {
        effectiveImageUrl = null;
        effectiveImageKey = null;
      }

      final payload = {
        'headline': _headlineController.text.trim(),
        'description': _normalizedDescriptionPayload(),
        'image_url': effectiveImageUrl,
        'image_key': effectiveImageKey,
        'whatsapp_url': _whatsappController.text.trim(),
        'facebook_url': _facebookController.text.trim(),
        'instagram_url': _instagramController.text.trim(),
        'youtube_url': _youtubeController.text.trim(),
        'email': _emailController.text.trim(),
        'website_url': _websiteController.text.trim(),
        'location_url': _locationController.text.trim(),
      };

      await _upsertLanding(api, payload);

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        context.pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Website details saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving website details: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildWebsiteUrlCard(BuildContext context) {
    final websiteUrl = _websiteController.text.trim();
    if (websiteUrl.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Website URL',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          SelectableText(websiteUrl),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _copyWebsiteUrl,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy URL'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _headlineController,
            decoration: const InputDecoration(
              labelText: 'Headline',
              hintText: 'Your business headline',
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 2,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Description Points',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: _addDescriptionPoint,
                icon: const Icon(Icons.add),
                label: const Text('Add Point'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...List.generate(_descriptionPointControllers.length, (index) {
            final isOnlyRow = _descriptionPointControllers.length == 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14, right: 8),
                    child: Text('${index + 1}.'),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _descriptionPointControllers[index],
                      decoration: InputDecoration(
                        hintText: 'Point ${index + 1}',
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        if (index == _descriptionPointControllers.length - 1 &&
                            _descriptionPointControllers[index]
                                .text
                                .trim()
                                .isNotEmpty) {
                          _addDescriptionPoint();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: isOnlyRow ? 'Clear point' : 'Remove point',
                    onPressed: () => _removeDescriptionPoint(index),
                    icon: Icon(
                      isOnlyRow ? Icons.clear : Icons.remove_circle_outline,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_descriptionPointControllers.length == 1)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Use Add Point for separate bullet lines.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 4),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Website Image',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (_pendingImagePath != null &&
              File(_pendingImagePath!).existsSync())
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_pendingImagePath!),
                    height: 180,
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
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
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
          const SizedBox(height: 20),
          TextFormField(
            controller: _whatsappController,
            decoration: const InputDecoration(
              labelText: 'WhatsApp URL',
              hintText: 'https://wa.me/91xxxxxxxxxx',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _facebookController,
            decoration: const InputDecoration(
              labelText: 'Facebook URL',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _instagramController,
            decoration: const InputDecoration(
              labelText: 'Instagram URL',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _youtubeController,
            decoration: const InputDecoration(
              labelText: 'YouTube URL',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Maps URL',
              hintText: 'Google Maps link',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Website Details'),
          ),
          const SizedBox(height: 16),
          _buildWebsiteUrlCard(context),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Website')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Website')),
      body: _buildEditForm(context),
    );
  }
}
