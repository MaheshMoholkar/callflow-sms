import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

class WebsiteDetailsScreen extends ConsumerStatefulWidget {
  const WebsiteDetailsScreen({super.key});

  @override
  ConsumerState<WebsiteDetailsScreen> createState() =>
      _WebsiteDetailsScreenState();
}

class _WebsiteDetailsScreenState extends ConsumerState<WebsiteDetailsScreen> {
  bool _loading = true;

  String _headline = '';
  List<String> _descriptionPoints = const [];
  String _whatsappUrl = '';
  String _facebookUrl = '';
  String _instagramUrl = '';
  String _youtubeUrl = '';
  String _email = '';
  String _locationUrl = '';
  String _websiteUrl = '';
  String? _imageUrl;
  bool _appendWebsiteUrlToSms = false;
  bool _updatingSmsAppendSetting = false;

  @override
  void initState() {
    super.initState();
    _loadWebsiteDetails();
  }

  Future<void> _loadWebsiteDetails() async {
    if (mounted) setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    await _loadWebsiteUrlFromCache();
    await _loadAppendWebsiteUrlSetting();

    try {
      final response = await api.get('/landing');
      _applyLandingResponse(response.data);
    } on DioException catch (e) {
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

  Future<void> _loadAppendWebsiteUrlSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(appendWebsiteUrlToSmsPrefKey) ?? false;
      if (!mounted) return;
      setState(() => _appendWebsiteUrlToSms = value);
    } catch (_) {
      // Keep default false if preferences read fails.
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

    final userId = _extractInt(landing['user_id']);
    final mappedWebsiteUrl = _buildWebsiteUrl(userId);

    if (!mounted) return;
    setState(() {
      _headline = landing['headline'] as String? ?? '';
      _descriptionPoints =
          _descriptionPointsFromRaw(landing['description'] as String? ?? '');
      _whatsappUrl = landing['whatsapp_url'] as String? ?? '';
      _facebookUrl = landing['facebook_url'] as String? ?? '';
      _instagramUrl = landing['instagram_url'] as String? ?? '';
      _youtubeUrl = landing['youtube_url'] as String? ?? '';
      _email = landing['email'] as String? ?? '';
      _imageUrl = landing['image_url'] as String?;
      _locationUrl = payload['location_url'] as String? ?? '';
      if (mappedWebsiteUrl.isNotEmpty) {
        _websiteUrl = mappedWebsiteUrl;
      }
    });
  }

  Future<void> _loadWebsiteUrlFromCache() async {
    try {
      final user = await ref.read(databaseProvider).getUser();
      final cachedWebsiteUrl = _buildWebsiteUrl(user?.id);
      if (cachedWebsiteUrl.isNotEmpty && mounted) {
        setState(() => _websiteUrl = cachedWebsiteUrl);
      }
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

      final userId = _extractInt(user['id']);
      final mappedWebsiteUrl = _buildWebsiteUrl(userId);
      if (!mounted) return;
      setState(() {
        if (mappedWebsiteUrl.isNotEmpty) {
          _websiteUrl = mappedWebsiteUrl;
        }
        _locationUrl = user['location_url'] as String? ?? '';
      });
    } catch (_) {
      // No-op: optional values can remain empty.
    }
  }

  int? _extractInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _buildWebsiteUrl(int? userId) {
    if (userId == null) return '';
    final base = landingBaseUrl.endsWith('/')
        ? landingBaseUrl.substring(0, landingBaseUrl.length - 1)
        : landingBaseUrl;
    return '$base/$userId';
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

  bool _hasConfiguredDetails() {
    return _headline.trim().isNotEmpty ||
        _descriptionPoints.isNotEmpty ||
        (_imageUrl?.trim().isNotEmpty ?? false) ||
        _whatsappUrl.trim().isNotEmpty ||
        _facebookUrl.trim().isNotEmpty ||
        _instagramUrl.trim().isNotEmpty ||
        _youtubeUrl.trim().isNotEmpty ||
        _email.trim().isNotEmpty ||
        _locationUrl.trim().isNotEmpty;
  }

  Future<void> _copyWebsiteUrl() async {
    final url = _websiteUrl.trim();
    if (url.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Website URL copied')),
    );
  }

  Future<void> _openEditScreen() async {
    final result = await context.push<bool>('/landing/edit');
    if (!mounted) return;
    await _loadWebsiteDetails();
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Website details saved')),
      );
    }
  }

  Future<void> _updateAppendWebsiteUrlSetting(bool enabled) async {
    final previousValue = _appendWebsiteUrlToSms;
    setState(() {
      _appendWebsiteUrlToSms = enabled;
      _updatingSmsAppendSetting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(appendWebsiteUrlToSmsPrefKey, enabled);
      await ref.read(syncProvider).pushLocalConfigToNative();
    } catch (e) {
      if (mounted) {
        setState(() => _appendWebsiteUrlToSms = previousValue);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update SMS setting: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingSmsAppendSetting = false);
      }
    }
  }

  Widget _buildDetailBlock({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          SelectableText(value),
        ],
      ),
    );
  }

  Widget _buildWebsiteUrlCard() {
    final websiteUrl = _websiteUrl.trim();
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

  Widget _buildSmsAppendToggleCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile.adaptive(
        title: const Text('Append website URL to SMS'),
        subtitle:
            const Text('Add your website link at the end of SMS templates.'),
        value: _appendWebsiteUrlToSms,
        onChanged:
            _updatingSmsAppendSetting ? null : _updateAppendWebsiteUrlSetting,
      ),
    );
  }

  Widget _buildBody() {
    final hasDetails = _hasConfiguredDetails();
    final headline = _headline.trim();
    final whatsappUrl = _whatsappUrl.trim();
    final facebookUrl = _facebookUrl.trim();
    final instagramUrl = _instagramUrl.trim();
    final youtubeUrl = _youtubeUrl.trim();
    final email = _email.trim();
    final locationUrl = _locationUrl.trim();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!hasDetails)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No website details added yet. Tap Edit to add details.',
            ),
          ),
        if (_imageUrl != null && _imageUrl!.trim().isNotEmpty) ...[
          Text(
            'Website Image',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Unable to preview image'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (headline.isNotEmpty)
          _buildDetailBlock(
            label: 'Headline',
            value: headline,
          ),
        if (_descriptionPoints.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Description Points',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                ..._descriptionPoints.map(
                  (point) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $point'),
                  ),
                ),
              ],
            ),
          ),
        if (whatsappUrl.isNotEmpty)
          _buildDetailBlock(
            label: 'WhatsApp URL',
            value: whatsappUrl,
          ),
        if (facebookUrl.isNotEmpty)
          _buildDetailBlock(
            label: 'Facebook URL',
            value: facebookUrl,
          ),
        if (instagramUrl.isNotEmpty)
          _buildDetailBlock(
            label: 'Instagram URL',
            value: instagramUrl,
          ),
        if (youtubeUrl.isNotEmpty)
          _buildDetailBlock(
            label: 'YouTube URL',
            value: youtubeUrl,
          ),
        if (email.isNotEmpty)
          _buildDetailBlock(
            label: 'Email',
            value: email,
          ),
        if (locationUrl.isNotEmpty)
          _buildDetailBlock(
            label: 'Maps URL',
            value: locationUrl,
          ),
        _buildSmsAppendToggleCard(),
        _buildWebsiteUrlCard(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Website'),
        actions: [
          TextButton.icon(
            onPressed: _openEditScreen,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }
}
