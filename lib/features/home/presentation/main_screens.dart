import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/constants/app_images.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/expense_screens.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/domain/usecases/calculate_paddock_rotation.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';
import 'package:mi_finca_app/core/formatters/currency_formatter.dart';

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
                    icon: Icon(
                      Icons.home_outlined,

                      color: AppColors.primaryDark,
                    ),

                    selectedIcon: Icon(
                      Icons.home,

                      color: AppColors.primaryDark,
                    ),

                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: _NavAssetIcon(path: AppImages.iconToro),
                    selectedIcon: _NavAssetIcon(
                      path: AppImages.iconToro,
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
                  iconPath: AppImages.iconMovimientoGanado,
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
          child: _BrandAssetIcon(path: action.iconPath, size: 25),
        ),
      ],
    );
  }
}

class _FabMenuAction {
  const _FabMenuAction({
    required this.label,
    required this.iconPath,
    required this.onTap,
  });
  final String label;
  final String iconPath;
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

    final referenceDate = DateTime.now();
    final rotation = const CalculatePaddockRotation()(
      paddocks: paddocks,
      animals: animals,
      referenceDate: referenceDate,
    );

    final availablePaddocks = paddocks
        .where((p) => _isPaddockAvailableNow(p, referenceDate))
        .length;

    final activeRotation = rotation.active;

    final needsRotationOrder = _needsRotationOrder(paddocks);

    final hasGrazingAlert =
        activeRotation?.hasGrazingPlan == true &&
        (activeRotation!.isOverdue ||
            activeRotation.isDueToday ||
            activeRotation.isDueSoon);

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
                        value: CurrencyFormatter.compactSoles(monthlyTotal),
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
                        iconPath: AppImages.iconMovimientoGanado,
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
                const SizedBox(height: 22),

                _PaddockStatusSection(
                  rotation: rotation,
                  availablePaddocksCount: availablePaddocks,
                  totalPaddocksCount: paddocks.length,
                ),

                if (needsRotationOrder) ...[
                  const SizedBox(height: 14),
                  const _RotationOrderAlertCard(),
                ],

                if (hasGrazingAlert) ...[
                  const SizedBox(height: 14),
                  _GrazingAlertCard(active: activeRotation),
                ],

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
    final cleanUserName = userName.trim();

    final firstName = cleanUserName.isEmpty
        ? ''
        : cleanUserName.split(RegExp(r'\s+')).first;

    final greetingName = firstName.isEmpty ? '' : ', $firstName';

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
              top: 10,
              left: 22,
              right: 22,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Transform.scale(
                        scale: 2.6,
                        child: Image.asset(
                          AppImages.miFincaIcono,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.agriculture,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
              top: 74,
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Hola$greetingName!',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
              right: 3,
              bottom: -8,
              child: Image.asset(
                _donFincaPath,
                height: 260,
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
    required this.iconPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String iconPath;
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
              child: Transform.scale(
                scale: iconPath == AppImages.iconMovimientoGanado ? 1.75 : 1,
                child: _BrandAssetIcon(path: iconPath, size: 28),
              ),
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

class _PaddockStatusSection extends StatelessWidget {
  const _PaddockStatusSection({
    required this.rotation,
    required this.availablePaddocksCount,
    required this.totalPaddocksCount,
  });

  final PaddockRotationSummary rotation;
  final int availablePaddocksCount;
  final int totalPaddocksCount;

  @override
  Widget build(BuildContext context) {
    final active = rotation.active;
    final next = rotation.next;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estado actual de potreros',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Revisa dónde está el ganado y qué potrero usar después.',
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 12),
          _PaddockStatusRow(
            icon: Icons.grass_outlined,
            label: 'Ahora',
            title: active == null ? 'Sin potrero activo' : active.paddock.name,
            detail: active == null
                ? 'Asigna ganado'
                : _activePaddockStatusText(active),
            color: AppColors.primaryDark,
          ),
          const Divider(height: 18),
          _PaddockStatusRow(
            icon: Icons.autorenew,
            label: 'Siguiente',
            title: next == null
                ? 'Sin cálculo'
                : next.isReady
                ? next.paddock.name
                : '${next.paddock.name} en ${next.remainingRestDays} días',
            detail: next == null
                ? 'Configura descansos'
                : next.isReady
                ? 'Listo para mover ganado'
                : 'Próximo recomendado',
            color: next?.isReady == true
                ? AppColors.primary
                : AppColors.warning,
          ),
          const Divider(height: 18),
          _PaddockStatusRow(
            icon: Icons.check_circle_outline,
            label: 'Listos',
            title: '$availablePaddocksCount/$totalPaddocksCount potreros',
            detail: availablePaddocksCount == 1
                ? '1 potrero disponible'
                : '$availablePaddocksCount potreros disponibles',
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _PaddockStatusRow extends StatelessWidget {
  const _PaddockStatusRow({
    required this.icon,
    required this.label,
    required this.title,
    required this.color,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String title;
  final Color color;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 54),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _GrazingAlertCard extends StatefulWidget {
  const _GrazingAlertCard({required this.active});

  final ActivePaddockRotation active;

  @override
  State<_GrazingAlertCard> createState() => _GrazingAlertCardState();
}

class _RotationOrderAlertCard extends StatelessWidget {
  const _RotationOrderAlertCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.reorder_rounded, color: AppColors.warning),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orden de rotación pendiente',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Configura el orden de tus potreros para que la próxima rotación siga tu recorrido real.',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrazingAlertCardState extends State<_GrazingAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _pulse = Tween<double>(
      begin: 0.08,
      end: 0.22,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _GrazingAlertCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final isOverdue = active.isOverdue;
    final color = isOverdue ? AppColors.danger : AppColors.warning;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final alpha = _pulse.value;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: alpha + 0.18)),
          ),
          child: child,
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isOverdue ? Icons.priority_high : Icons.warning_amber_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _grazingAlertTitle(active),
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _grazingAlertBody(active),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _activePaddockStatusText(ActivePaddockRotation active) {
  final animalText = 'Actualmente tiene ${active.animalCount} animales.';
  if (!active.hasGrazingPlan) return animalText;

  final remainingDays = active.remainingGrazingDays!;
  if (remainingDays < 0) {
    return '$animalText Lleva ${active.elapsedGrazingDays} días en uso.';
  }

  if (remainingDays == 0) {
    return '$animalText Termina su uso hoy.';
  }

  return '$animalText Faltan $remainingDays días de uso.';
}

String _grazingAlertTitle(ActivePaddockRotation active) {
  if (active.isOverdue) return 'Traslado atrasado';
  if (active.isDueToday) return 'Traslado para hoy';

  return 'Rotación próxima';
}

String _grazingAlertBody(ActivePaddockRotation active) {
  final remainingDays = active.remainingGrazingDays!;
  if (remainingDays < 0) {
    final overdueDays = remainingDays.abs();
    return overdueDays == 1
        ? 'El potrero superó el uso planeado por 1 día.'
        : 'El potrero superó el uso planeado por $overdueDays días.';
  }

  if (remainingDays == 0) {
    return 'El uso planeado termina hoy. Revisa el próximo potrero.';
  }

  return remainingDays == 1
      ? 'Falta 1 día para mover el ganado.'
      : 'Faltan $remainingDays días para mover el ganado.';
}

bool _isPaddockAvailableNow(Paddock paddock, DateTime referenceDate) {
  if (paddock.status == 'Disponible') return true;
  if (paddock.status != 'Descansando') return false;

  final requiredRestDays = paddock.requiredRestDays;
  final lastGrazingEndDate = paddock.lastGrazingEndDate;
  if (requiredRestDays == null ||
      requiredRestDays <= 0 ||
      lastGrazingEndDate == null ||
      lastGrazingEndDate.isAfter(referenceDate)) {
    return false;
  }

  return requiredRestDays -
          referenceDate.difference(lastGrazingEndDate).inDays <=
      0;
}

bool _needsRotationOrder(List<Paddock> paddocks) {
  return paddocks.length > 1 &&
      paddocks.any((paddock) => paddock.rotationOrder == null);
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
        CurrencyFormatter.compactSoles(monthlyTotal),
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
    final sync = ref.watch(syncViewModelProvider).requireValue;

    final isSynced = sync.pendingChanges == 0 && sync.isOnline;
    final isOffline = !sync.isOnline;
    final isPending = sync.pendingChanges > 0 && sync.isOnline;

    final icon = isOffline
        ? Icons.cloud_off_rounded
        : sync.isSyncing
        ? Icons.cloud_sync_rounded
        : isPending
        ? Icons.cloud_upload_rounded
        : Icons.cloud_done_rounded;

    final title = isOffline
        ? 'Modo sin conexión'
        : sync.isSyncing
        ? 'Sincronizando cambios'
        : isPending
        ? '${sync.pendingChanges} cambios pendientes'
        : 'Todo sincronizado';

    final description = isOffline
        ? 'Puedes seguir registrando datos. Se guardarán localmente y se subirán cuando vuelvas a tener conexión.'
        : isPending
        ? 'Hay cambios guardados en el dispositivo que aún no se han subido a Supabase.'
        : 'Tus datos locales están sincronizados con Supabase.';

    final iconColor = isOffline
        ? AppColors.muted
        : isPending
        ? AppColors.warning
        : AppColors.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 28),
              child: Column(
                children: [
                  Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 68, color: iconColor),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _SyncInfoRow(
                    icon: Icons.pending_actions_rounded,
                    label: 'Cambios pendientes',
                    value: '${sync.pendingChanges}',
                  ),
                  const Divider(height: 26),
                  _SyncInfoRow(
                    icon: Icons.schedule_rounded,
                    label: 'Última sincronización',
                    value: sync.lastSync == null
                        ? 'Aún no realizada'
                        : '${sync.lastSync!.day}/${sync.lastSync!.month}/${sync.lastSync!.year} ${sync.lastSync!.hour}:${sync.lastSync!.minute.toString().padLeft(2, '0')}',
                  ),
                  const Divider(height: 26),
                  _SyncInfoRow(
                    icon: sync.isOnline
                        ? Icons.wifi_rounded
                        : Icons.wifi_off_rounded,
                    label: 'Estado de conexión',
                    value: sync.isOnline ? 'Con conexión' : 'Sin conexión',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text(
              'Modo offline manual',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Úsalo para probar cómo responde la app cuando no hay internet.',
            ),
            value: !sync.isOnline,
            onChanged: (offline) {
              ref.read(syncViewModelProvider.notifier).setOnline(!offline);
            },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed:
                !sync.isOnline || sync.pendingChanges == 0 || sync.isSyncing
                ? null
                : ref.read(syncViewModelProvider.notifier).syncNow,
            icon: sync.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(
              sync.isSyncing ? 'Sincronizando...' : 'Sincronizar ahora',
            ),
          ),
          const SizedBox(height: 10),
          if (isSynced)
            const Text(
              'No hay acciones pendientes por realizar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            )
          else if (isOffline)
            const Text(
              'Cuando vuelvas a estar en línea, podrás sincronizar los cambios pendientes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

class _SyncInfoRow extends StatelessWidget {
  const _SyncInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(icon, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _requestSignOut(BuildContext context, WidgetRef ref) async {
    final pendingChanges = await ref
        .read(syncRepositoryProvider)
        .pendingCount();

    if (!context.mounted) return;

    final shouldSignOut =
        pendingChanges == 0 ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Cambios sin sincronizar'),
                content: const Text(
                  'Hay cambios sin sincronizar. Si cierras sesión ahora, se perderán de este dispositivo.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ) ==
            true;

    if (!shouldSignOut || !context.mounted) return;

    await ref.read(authViewModelProvider.notifier).signOut();

    if (!context.mounted) return;

    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

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
            onPressed: () => _requestSignOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
