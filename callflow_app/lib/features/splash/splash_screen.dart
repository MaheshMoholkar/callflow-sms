import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/native/native_bridge.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_interceptor.dart';
import '../../core/database/app_database.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final shouldContinue = await _checkVersion();
    if (!shouldContinue) return;

    final hasToken = await AuthInterceptor.hasTokens();
    final db = ref.read(databaseProvider);
    final user = await db.getUser();
    if (!hasToken || user == null) {
      if (mounted) context.go('/auth/phone');
      return;
    }

    final allGranted = await _checkAllPermissions();
    if (!allGranted) {
      if (mounted) context.go('/auth/permissions');
      return;
    }

    if (mounted) context.go('/dashboard');
  }

  Future<bool> _checkAllPermissions() async {
    try {
      final permissions = [
        Permission.phone,
        Permission.contacts,
        Permission.sms,
        Permission.notification,
      ];
      for (final p in permissions) {
        if (!await p.isGranted) return false;
      }
      final bridge = ref.read(nativeBridgeProvider);
      if (!await bridge.isBatteryOptimizationDisabled()) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkVersion() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/app/version');
      final data = response.data['data'] as Map<String, dynamic>?;

      if (data != null && mounted) {
      final forceUpdate = data['force_update'] as bool? ?? false;
      final serverVersionCode =
          int.tryParse(data['version_code']?.toString() ?? '0') ?? 0;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (serverVersionCode > currentVersionCode) {
        return await _showUpdateDialog(
          force: forceUpdate,
          downloadUrl: data['download_url'] as String? ?? '',
          releaseNotes: data['release_notes'] as String? ?? '',
        );
      }
    }
    } catch (_) {}

    return true;
  }

  Future<bool> _showUpdateDialog({
    required bool force,
    required String downloadUrl,
    required String releaseNotes,
  }) async {
    bool shouldContinue = !force;

    await showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => AlertDialog(
        title: Text(force ? 'Update Required' : 'Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              force
                  ? 'A critical update is required to continue using CallFlow.'
                  : 'A new version of CallFlow is available.',
            ),
            if (releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: () {
                shouldContinue = true;
                Navigator.pop(ctx);
              },
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () async {
              if (downloadUrl.isNotEmpty) {
                final uri = Uri.parse(downloadUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (!force) {
                shouldContinue = true;
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    return shouldContinue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_in_talk,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'CallFlow',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Automated Call Follow-up',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
