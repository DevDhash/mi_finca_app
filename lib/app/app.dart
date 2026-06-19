import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/state/app_controller.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/features/auth/presentation/auth_screens.dart';
import 'package:mi_finca_app/features/home/presentation/main_screens.dart';

class MiFincaApp extends ConsumerWidget {
  const MiFincaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Mi Finca',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: ref
        .watch(appControllerProvider)
        .when(
          loading: () => const SplashScreen(),
          error: (error, _) => StartupError(
            error: error,
            onRetry: () => ref.invalidate(appControllerProvider),
          ),
          data: (state) => state.session == null
              ? const AuthScreen()
              : state.farm == null
              ? const FarmSetupScreen()
              : const MainShell(),
        ),
  );
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: AppColors.primaryLight,
            child: Icon(Icons.grass, size: 52, color: AppColors.primaryDark),
          ),
          SizedBox(height: 18),
          Text(
            'Mi Finca',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 18),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}

class StartupError extends StatelessWidget {
  const StartupError({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text(
              'No pudimos abrir los datos locales.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    ),
  );
}
