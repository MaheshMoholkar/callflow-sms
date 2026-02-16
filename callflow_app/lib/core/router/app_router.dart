import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/screens/phone_input_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/permissions_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/templates/screens/template_list_screen.dart';
import '../../features/templates/screens/template_edit_screen.dart';
import '../../features/landing/screens/landing_edit_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/rules/screens/rules_screen.dart';
import '../../shared/widgets/shell_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        builder: (context, state) => const PhoneInputScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/templates',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TemplateListScreen(),
            ),
          ),
          GoRoute(
            path: '/landing',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LandingEditScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/templates/edit',
        builder: (context, state) {
          final templateId = state.extra as int?;
          return TemplateEditScreen(templateId: templateId);
        },
      ),
      GoRoute(
        path: '/rules',
        builder: (context, state) => const RulesScreen(),
      ),
    ],
  );
});
