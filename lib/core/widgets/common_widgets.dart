import 'package:flutter/material.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (label) {
      'En uso' => (const Color(0xFFDCEAEF), AppColors.info),
      'Descansando' => (const Color(0xFFFBEBD0), AppColors.warning),
      'Agotado' || 'Enfermo' => (const Color(0xFFF6DEDB), AppColors.danger),
      'Vendido' || 'Fallecido' => (const Color(0xFFEFEDE8), AppColors.muted),
      _ => (AppColors.primaryLight, AppColors.primaryDark),
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: background,
      side: BorderSide.none,
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
    );
  }
}

class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key, required this.state});
  final SyncState state;
  @override
  Widget build(BuildContext context) {
    if (!state.isOnline) {
      return _banner(
        Icons.cloud_off_outlined,
        'Sin conexión. Tus datos se guardan en el dispositivo.',
        const Color(0xFFE9E3D9),
      );
    }
    if (state.pendingChanges > 0) {
      return _banner(
        Icons.cloud_upload_outlined,
        '${state.pendingChanges} cambios pendientes de sincronizar.',
        const Color(0xFFFBEBD0),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner(IconData icon, String text, Color color) => Container(
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 68, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}
