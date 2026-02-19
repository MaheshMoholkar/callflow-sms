import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/network/api_client.dart';

class LandingEditScreen extends ConsumerStatefulWidget {
  const LandingEditScreen({super.key});

  @override
  ConsumerState<LandingEditScreen> createState() => _LandingEditScreenState();
}

class _LandingEditScreenState extends ConsumerState<LandingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final _descriptionController = TextEditingController();
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
    _loadLanding();
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _descriptionController.dispose();
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
          SnackBar(content: Text('Failed to load landing page: $e')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load landing page: $e')),
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
    _descriptionController.text = landing['description'] as String? ?? '';
    _whatsappController.text = landing['whatsapp_url'] as String? ?? '';
    _facebookController.text = landing['facebook_url'] as String? ?? '';
    _instagramController.text = landing['instagram_url'] as String? ?? '';
    _youtubeController.text = landing['youtube_url'] as String? ?? '';
    _emailController.text = landing['email'] as String? ?? '';
    _websiteController.text = landing['website_url'] as String? ?? '';
    _imageUrl = landing['image_url'] as String?;
    _locationController.text = payload['location_url'] as String? ?? '';
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
      _locationController.text = user['location_url'] as String? ?? '';
    } catch (_) {
      // No-op: location field can remain empty if profile fetch fails.
    }
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
    if (imageUrl == null || imageUrl.isEmpty || imageKey == null || imageKey.isEmpty) {
      throw Exception('Upload response missing image URL/key');
    }
    return (imageUrl, imageKey);
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
        'description': _descriptionController.text.trim(),
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

      await api.put('/landing', data: payload);

      setState(() {
        _imageUrl = effectiveImageUrl;
        _pendingImagePath = null;
        _removeImageOnSave = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Landing page saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving landing page: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Landing Page')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Landing Page'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _headlineController,
              decoration: const InputDecoration(
                labelText: 'Headline',
                hintText: 'Your business headline',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe your business',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            Text('Landing Image',
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
              controller: _websiteController,
              decoration: const InputDecoration(
                labelText: 'Website URL',
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
                  : const Text('Save Landing Page'),
            ),
          ],
        ),
      ),
    );
  }
}
