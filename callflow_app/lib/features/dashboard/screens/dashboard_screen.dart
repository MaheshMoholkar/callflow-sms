import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/core_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-sync on load
    Future.microtask(
        () => ref.read(syncProvider).pullConfig().catchError((_) {}));
  }

  Future<void> _refresh() async {
    try {
      await ref.read(syncProvider).pullConfig();
    } catch (_) {}
    ref.invalidate(callsTodayProvider);
    ref.invalidate(smsSentTodayProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final isRunning = ref.watch(serviceRunningProvider);
    final user = ref.watch(currentUserProvider);
    final callsToday = ref.watch(callsTodayProvider);
    final smsSent = ref.watch(smsSentTodayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CallFlow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              try {
                await ref.read(syncProvider).pullConfig();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Synced successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sync failed: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Plan banner
            user.when(
              data: (u) {
                if (u == null) return const SizedBox.shrink();
                final plan = u.plan;
                final isExpired = u.planExpiresAt != null &&
                    u.planExpiresAt!.isBefore(DateTime.now());
                if (plan == 'none' || isExpired) {
                  return Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isExpired
                                  ? 'Your plan has expired'
                                  : 'No active plan - messaging is disabled',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),

            // Service toggle
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isRunning
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      child: Icon(
                        isRunning ? Icons.phone_in_talk : Icons.phone_disabled,
                        color: isRunning
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Call Detection',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            isRunning ? 'Active' : 'Inactive',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: isRunning
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isRunning,
                      onChanged: (_) =>
                          ref.read(serviceRunningProvider.notifier).toggle(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats grid
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Calls Today',
                    value: callsToday.asData?.value.toString() ?? '0',
                    icon: Icons.call,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'SMS Sent',
                    value: smsSent.asData?.value.toString() ?? '0',
                    icon: Icons.sms,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick actions
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.tune,
                    label: 'Configure Rules',
                    onTap: () => context.push('/rules'),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon,
                  color: Theme.of(context).colorScheme.primary, size: 32),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
