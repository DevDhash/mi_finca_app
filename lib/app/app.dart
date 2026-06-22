import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/auth/presentation/auth_screens.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/home/presentation/main_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

class MiFincaApp extends ConsumerWidget {
  const MiFincaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Mi Finca',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const _AppBootstrap(),
  );
}

class _AppBootstrap extends ConsumerWidget {
  const _AppBootstrap();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authViewModelProvider);
    if (auth.hasError) {
      return StartupError(
        error: auth.error!,
        onRetry: () => ref.invalidate(authViewModelProvider),
      );
    }
    if (auth.isLoading) return const SplashScreen();
    if (auth.value == null) return const AuthScreen();
    final farm = ref.watch(farmViewModelProvider);
    if (farm.hasError) {
      return StartupError(
        error: farm.error!,
        onRetry: () => ref.invalidate(farmViewModelProvider),
      );
    }
    if (farm.isLoading) return const SplashScreen();
    if (farm.value == null) return const FarmSetupScreen();
    final modules = [
      ref.watch(animalViewModelProvider),
      ref.watch(paddockViewModelProvider),
      ref.watch(expenseViewModelProvider),
      ref.watch(syncViewModelProvider),
    ];
    final error = modules.where((value) => value.hasError).firstOrNull;
    if (error != null) {
      return StartupError(
        error: error.error!,
        onRetry: () {
          ref.invalidate(animalViewModelProvider);
          ref.invalidate(paddockViewModelProvider);
          ref.invalidate(expenseViewModelProvider);
          ref.invalidate(syncViewModelProvider);
        },
      );
    }
    if (modules.any((value) => value.isLoading)) return const SplashScreen();
    return const MainShell();
  }
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
