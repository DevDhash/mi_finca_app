import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/constants/app_images.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/expense_screens.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int index = 0;
  bool _isFabOpen = false;

  @override
  Widget build(BuildContext context) {
    const pages = [
      DashboardScreen(),
      AnimalListScreen(),
      PaddockListScreen(),
      MoreScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: IndexedStack(index: index, children: pages),
              ),
              NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (v) {
                  _closeFab();
                  setState(() => index = v);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: _NavAssetIcon(path: AppImages.iconCabezaToro),
                    selectedIcon: _NavAssetIcon(
                      path: AppImages.iconCabezaToro,
                      selected: true,
                    ),
                    label: 'Animales',
                  ),
                  NavigationDestination(
                    icon: _NavAssetIcon(path: AppImages.iconPasto),
                    selectedIcon: _NavAssetIcon(
                      path: AppImages.iconPasto,
                      selected: true,
                    ),
                    label: 'Potreros',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz),
                    label: 'Más',
                  ),
                ],
              ),
            ],
          ),
          if (_isFabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFab,
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
          Positioned(
            right: 20,
            bottom: 86,
            child: _ExpandableFabMenu(
              isOpen: _isFabOpen,
              onToggle: _toggleFab,
              actions: [
                _FabMenuAction(
                  label: 'Registrar gasto',
                  iconPath: AppImages.iconGastos,
                  onTap: () {
                    _closeFab();
                    openExpenseForm(context);
                  },
                ),
                _FabMenuAction(
                  label: 'Agregar potrero',
                  iconPath: AppImages.iconPasto,
                  onTap: () {
                    _closeFab();
                    openPaddockForm(context);
                  },
                ),
                _FabMenuAction(
                  label: 'Mover lote',
                  iconPath: AppImages.iconCabezaToro,
                  onTap: () {
                    _closeFab();
                    setState(() => index = 1);
                  },
                ),
                _FabMenuAction(
                  label: 'Registrar animal',
                  iconPath: AppImages.iconVaca,
                  onTap: () {
                    _closeFab();
                    openAnimalForm(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFab() {
    setState(() {
      _isFabOpen = !_isFabOpen;
    });
  }

  void _closeFab() {
    if (!_isFabOpen) return;

    setState(() {
      _isFabOpen = false;
    });
  }
}

class _ExpandableFabMenu extends StatelessWidget {
  const _ExpandableFabMenu({
    required this.isOpen,
    required this.onToggle,
    required this.actions,
  });

  final bool isOpen;
  final VoidCallback onToggle;
  final List<_FabMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          child: isOpen
              ? Column(
                  key: const ValueKey('fab_actions'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: actions
                      .map(
                        (action) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _FabActionButton(action: action),
                        ),
                      )
                      .toList(),
                )
              : const SizedBox(key: ValueKey('fab_empty'), height: 0, width: 0),
        ),
        FloatingActionButton(
          heroTag: 'main_fab',
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          elevation: 8,
          shape: const CircleBorder(),
          onPressed: onToggle,
          child: AnimatedRotation(
            turns: isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(isOpen ? Icons.close : Icons.add, size: 34),
          ),
        ),
      ],
    );
  }
}

class _FabActionButton extends StatelessWidget {
  const _FabActionButton({required this.action});

  final _FabMenuAction action;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          elevation: 5,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: action.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                action.label,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: action.label,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primaryDark,
          elevation: 6,
          shape: const CircleBorder(),
          onPressed: action.onTap,
          child: action.iconPath != null
              ? _BrandAssetIcon(path: action.iconPath!, size: 25)
              : Icon(action.icon ?? Icons.add),
        ),
      ],
    );
  }
}

class _FabMenuAction {
  const _FabMenuAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconPath,
  });

  final String label;
  final IconData? icon;
  final String? iconPath;
  final VoidCallback onTap;
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authViewModelProvider).requireValue;
    final farm = ref.watch(farmViewModelProvider).requireValue;
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final monthlyTotal = ref.watch(monthlyExpenseTotalProvider);
    final sync = ref.watch(syncViewModelProvider).requireValue;

    final suggested =
        (paddocks.where((p) => p.status != 'En uso').toList()
              ..sort((a, b) => b.restDays.compareTo(a.restDays)))
            .firstOrNull;

    final availablePaddocks = paddocks
        .where((p) => p.status == 'Disponible')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F2),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HomeHero(
            farmName: farm?.name ?? 'Mi Finca',
            userName: session?.name ?? '',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: ConnectivityBanner(state: sync),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumen de la finca',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        iconPath: AppImages.iconVaca,
                        value: '${animals.length}',
                        label: 'Animales',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Metric(
                        iconPath: AppImages.iconPasto,
                        value: '$availablePaddocks/${paddocks.length}',
                        label: 'Potreros libres',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        iconPath: AppImages.iconGastos,
                        value: NumberFormat.compactCurrency(
                          locale: 'es_PE',
                          symbol: 'S/',
                        ).format(monthlyTotal),
                        label: 'Gastos del mes',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Metric(
                        icon: Icons.cloud_upload_outlined,
                        value: '${sync.pendingChanges}',
                        label: 'Cambios pendientes',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'Accesos rápidos',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _HomeActionCard(
                        iconPath: AppImages.iconVaca,
                        title: 'Registrar',
                        subtitle: 'Nuevo animal',
                        onTap: () => openAnimalForm(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HomeActionCard(
                        iconPath: AppImages.iconPasto,
                        title: 'Potrero',
                        subtitle: 'Crear espacio',
                        onTap: () => openPaddockForm(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _HomeActionCard(
                        iconPath: AppImages.iconCabezaToro,
                        title: 'Movimiento',
                        subtitle: 'Mover ganado',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AnimalListScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HomeActionCard(
                        iconPath: AppImages.iconGastos,
                        title: 'Gasto',
                        subtitle: 'Registrar costo',
                        onTap: () => openExpenseForm(context),
                      ),
                    ),
                  ],
                ),
                if (suggested != null) ...[
                  const SizedBox(height: 22),
                  Card(
                    color: const Color(0xFFFFF3D8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lightbulb_outline,
                          color: AppColors.warning,
                        ),
                      ),
                      title: Text(
                        '${suggested.name} puede estar listo para uso',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      subtitle: Text(
                        'Lleva ${suggested.restDays} días de descanso.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Registrados recientemente',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 10),
                if (animals.isEmpty)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Don Finca te recomienda registrar tu primer animal desde el botón +.',
                      ),
                    ),
                  )
                else
                  ...animals
                      .take(3)
                      .map(
                        (a) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AnimalListCard(
                            animal: a,
                            paddockName: paddocks
                                .where((p) => p.id == a.paddockId)
                                .firstOrNull
                                ?.name,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AnimalDetailScreen(animalId: a.id),
                              ),
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.farmName, required this.userName});

  final String farmName;
  final String userName;

  static const String _donFincaPath = AppImages.donFincaWelcome;

  @override
  Widget build(BuildContext context) {
    final greetingName = userName.trim().isEmpty ? '' : ', $userName';

    return Container(
      height: 290,
      decoration: const BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: 18,
              left: 22,
              right: 22,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      AppImages.iconCabezaToro,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      color: Colors.white,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.agriculture, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      farmName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 22,
              top: 80,
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Hola$greetingName!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Soy Don Finca',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu asistente para gestionar ganado, potreros y gastos.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -20,
              bottom: -8,
              child: Image.asset(
                _donFincaPath,
                height: 238,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox(
                    height: 220,
                    width: 150,
                    child: Icon(Icons.person, size: 90, color: Colors.white),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavAssetIcon extends StatelessWidget {
  const _NavAssetIcon({required this.path, this.selected = false});

  final String path;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: selected ? 28 : 25,
      height: selected ? 28 : 25,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.image_not_supported_outlined, size: selected ? 28 : 25),
    );
  }
}

class _BrandAssetIcon extends StatelessWidget {
  const _BrandAssetIcon({required this.path, this.size = 28});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.image_not_supported_outlined,
        size: size,
        color: AppColors.primaryDark,
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.iconPath,
  });

  final IconData? icon;
  final String? iconPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              child: iconPath != null
                  ? _BrandAssetIcon(path: iconPath!, size: 28)
                  : Icon(icon ?? Icons.circle, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    this.icon,
    this.iconPath,
  });

  final IconData? icon;
  final String? iconPath;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iconPath != null)
            _BrandAssetIcon(path: iconPath!, size: 30)
          else
            Icon(icon ?? Icons.circle, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          Text(label, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );
}

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Más')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _item(
          context,
          Icons.receipt_long,
          'Costos y bodega',
          'Gastos y resumen mensual',
          const ExpenseListScreen(),
        ),
        _item(
          context,
          Icons.insights,
          'Indicadores',
          'Una vista simple de tu finca',
          const IndicatorsScreen(),
        ),
        _item(
          context,
          Icons.cloud_sync,
          'Sincronización',
          'Conexión y cambios pendientes',
          const SyncScreen(),
        ),
        _item(
          context,
          Icons.person_outline,
          'Perfil y ajustes',
          'Datos de finca y sesión',
          const ProfileScreen(),
        ),
      ],
    ),
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(icon, color: AppColors.primaryDark),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      ),
    ),
  );
}

class IndicatorsScreen extends ConsumerWidget {
  const IndicatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final monthlyTotal = ref.watch(monthlyExpenseTotalProvider);
    final sync = ref.watch(syncViewModelProvider).requireValue;

    final avg = animals.where((a) => a.weight != null).toList();
    final average = avg.isEmpty
        ? 0
        : avg.fold<double>(0, (s, a) => s + a.weight!) / avg.length;

    final values = [
      ('Animales', '${animals.length}', AppImages.iconVaca),
      (
        'Costos del mes',
        NumberFormat.compactCurrency(
          locale: 'es_PE',
          symbol: 'S/',
        ).format(monthlyTotal),
        AppImages.iconGastos,
      ),
      (
        'Potreros libres',
        '${paddocks.where((p) => p.status == 'Disponible').length}',
        AppImages.iconPasto,
      ),
      (
        'Animales enfermos',
        '${animals.where((a) => a.status == 'Enfermo').length}',
        AppImages.iconVacuna,
      ),
      ('Peso promedio', '${average.toStringAsFixed(0)} kg', AppImages.iconToro),
      ('Cambios pendientes', '${sync.pendingChanges}', null),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Indicadores')),
      body: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: values
            .map(
              (v) => _Metric(
                iconPath: v.$3,
                icon: v.$3 == null ? Icons.cloud_upload : null,
                value: v.$2,
                label: v.$1,
              ),
            )
            .toList(),
      ),
    );
  }
}

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(syncViewModelProvider).requireValue;

    final icon = !d.isOnline
        ? Icons.cloud_off
        : d.isSyncing
        ? Icons.cloud_sync
        : d.pendingChanges > 0
        ? Icons.cloud_upload
        : Icons.cloud_done;

    final title = !d.isOnline
        ? 'Sin conexión'
        : d.isSyncing
        ? 'Sincronizando cambios…'
        : d.pendingChanges > 0
        ? '${d.pendingChanges} cambios pendientes'
        : 'Todo sincronizado';

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Icon(
              icon,
              size: 90,
              color: d.pendingChanges > 0
                  ? AppColors.warning
                  : AppColors.primary,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              d.lastSync == null
                  ? 'Todavía no se realizó una sincronización.'
                  : 'Última sincronización: ${d.lastSync!.day}/${d.lastSync!.month} ${d.lastSync!.hour}:${d.lastSync!.minute.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Simular conexión'),
              subtitle: const Text(
                'Se reemplaza por connectivity_plus al integrar el backend.',
              ),
              value: d.isOnline,
              onChanged: ref.read(syncViewModelProvider.notifier).setOnline,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: !d.isOnline || d.pendingChanges == 0 || d.isSyncing
                  ? null
                  : ref.read(syncViewModelProvider.notifier).syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authViewModelProvider).requireValue;
    final farm = ref.watch(farmViewModelProvider).requireValue;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil y ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
          const SizedBox(height: 14),
          Text(
            session?.name ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(session?.email ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.landscape),
              title: Text(farm?.name ?? ''),
              subtitle: Text(farm?.location ?? ''),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => ref.read(authViewModelProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
