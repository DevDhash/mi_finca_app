import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _requestSignOut(BuildContext context, WidgetRef ref) async {
    try {
      final pendingChanges = await ref
          .read(syncRepositoryProvider)
          .pendingCount();
      if (!context.mounted) return;

      final shouldSignOut = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cerrar sesión'),
          content: Text(
            pendingChanges > 0
                ? 'Tienes $pendingChanges cambios sin sincronizar. Si cierras sesión ahora, podrían perderse de este dispositivo. ¿Deseas cerrar sesión de todas formas?'
                : '¿Estás seguro de que deseas cerrar tu sesión?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
      if (shouldSignOut != true || !context.mounted) return;

      await ref.read(authViewModelProvider.notifier).signOut();
      if (!context.mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cerrar la sesión. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(authViewModelProvider);
    final farmState = ref.watch(farmViewModelProvider);
    final syncState = ref.watch(syncViewModelProvider);

    Widget body;
    if (sessionState.hasError || farmState.hasError || syncState.hasError) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No se pudo cargar el perfil. Vuelve a intentarlo más tarde.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (!sessionState.hasValue ||
        !farmState.hasValue ||
        !syncState.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final session = sessionState.requireValue;
      final farm = farmState.requireValue;
      final sync = syncState.requireValue;
      final name = _valueOrFallback(session?.name, 'Usuario');
      final email = _valueOrFallback(session?.email, 'No registrado');

      body = ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ProfileHeader(name: name, email: email),
          const _SectionTitle('Mi cuenta'),
          _ProfileInfoCard(
            children: [
              _ProfileInfoRow(
                icon: Icons.person_outline_rounded,
                label: 'Nombre',
                value: name,
              ),
              _ProfileInfoRow(
                icon: Icons.email_outlined,
                label: 'Correo',
                value: email,
              ),
            ],
          ),
          const _SectionTitle('Mi finca'),
          _ProfileInfoCard(
            children: [
              _ProfileInfoRow(
                icon: Icons.agriculture_outlined,
                label: 'Nombre de la finca',
                value: _valueOrFallback(farm?.name, 'Mi Finca'),
              ),
              _ProfileInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Ubicación',
                value: _valueOrFallback(
                  farm?.location,
                  'Ubicación no registrada',
                ),
              ),
            ],
          ),
          const _SectionTitle('Sincronización'),
          _ProfileInfoCard(
            children: [
              _ProfileInfoRow(
                icon: sync.isOnline
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                label: 'Estado de conexión',
                value: sync.isOnline ? 'Con conexión' : 'Sin conexión',
              ),
              _ProfileInfoRow(
                icon: Icons.pending_actions_outlined,
                label: 'Cambios pendientes',
                value: '${sync.pendingChanges}',
              ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: () => _requestSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F2),
        centerTitle: true,
        title: const Text(
          'Perfil y ajustes',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  static String _valueOrFallback(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            child: const Icon(
              Icons.person_outline_rounded,
              size: 46,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            email,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.text,
      ),
    ),
  );
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 28, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.primaryDark),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
