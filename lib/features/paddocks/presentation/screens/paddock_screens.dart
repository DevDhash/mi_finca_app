import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/constants/app_images.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:uuid/uuid.dart';

class PaddockListScreen extends ConsumerWidget {
  const PaddockListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final referenceDate = DateTime.now();
    final orderedPaddocks = _sortPaddocksByRotationOrder(paddocks);

    final activeCount = paddocks.where((p) => p.status == 'En uso').length;

    final readyCount = paddocks
        .where(
          (p) =>
              _paddockDisplayStatus(p, _paddockRestStatus(p, referenceDate)) ==
              'Disponible',
        )
        .length;

    final orderedCount = paddocks.where((p) => p.rotationOrder != null).length;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,

        title: const Text(
          'Potreros',

          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: paddocks.isEmpty
          ? EmptyState(
              icon: Icons.grass,
              message:
                  'No hay potreros creados todavía. Empieza por el potrero donde están tus animales hoy.',
              actionLabel: 'Agregar potrero',
              onAction: () => openPaddockForm(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                const _PaddockRotationBanner(),
                const SizedBox(height: 16),
                _PaddockOrderOverview(
                  totalCount: paddocks.length,
                  orderedCount: orderedCount,
                  activeCount: activeCount,
                  readyCount: readyCount,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Ruta de rotación',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _RotationOrderButton(
                      needsAttention: orderedCount < paddocks.length,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaddockRotationOrderScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Consulta el orden de recorrido del ganado y selecciona un potrero para ver su configuración.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                ...orderedPaddocks.asMap().entries.map((entry) {
                  final index = entry.key;
                  final paddock = entry.value;

                  final animalCount = animals
                      .where((animal) => animal.paddockId == paddock.id)
                      .length;

                  final restStatus = _paddockRestStatus(paddock, referenceDate);

                  final restSummary = _paddockRestSummary(paddock, restStatus);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PaddockRouteCard(
                      paddock: paddock,
                      orderIndex: index,
                      animalCount: animalCount,
                      displayStatus: _paddockDisplayStatus(paddock, restStatus),
                      restSummary: restSummary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PaddockDetailScreen(paddockId: paddock.id),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _PaddockRotationBanner extends StatelessWidget {
  const _PaddockRotationBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Ganado pastoreando en una ruta de rotación de potreros',
      child: Container(
        width: double.infinity,
        height: 155,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
          image: const DecorationImage(
            image: AssetImage(AppImages.bannerRotacionPotreros),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}

class _PaddockOrderOverview extends StatelessWidget {
  const _PaddockOrderOverview({
    required this.totalCount,
    required this.orderedCount,
    required this.activeCount,
    required this.readyCount,
  });

  final int totalCount;
  final int orderedCount;
  final int activeCount;
  final int readyCount;

  @override
  Widget build(BuildContext context) {
    final orderText = orderedCount == totalCount
        ? 'Revisa el estado general de tus potreros'
        : '$orderedCount de $totalCount potreros tienen orden';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado de potreros',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            orderText,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PaddockOverviewItem(
                  value: '$activeCount',
                  label: 'En uso',
                  color: AppColors.info,
                ),
              ),
              Expanded(
                child: _PaddockOverviewItem(
                  value: '$readyCount',
                  label: 'Listos',
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: _PaddockOverviewItem(
                  value: '$totalCount',
                  label: 'Total',
                  color: AppColors.earth,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaddockOverviewItem extends StatelessWidget {
  const _PaddockOverviewItem({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _RotationOrderButton extends StatefulWidget {
  const _RotationOrderButton({
    required this.needsAttention,
    required this.onPressed,
  });

  final bool needsAttention;
  final VoidCallback onPressed;

  @override
  State<_RotationOrderButton> createState() => _RotationOrderButtonState();
}

class _RotationOrderButtonState extends State<_RotationOrderButton>
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
  void didUpdateWidget(covariant _RotationOrderButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (widget.needsAttention && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.needsAttention && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.needsAttention
        ? AppColors.danger
        : AppColors.primaryDark;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final alpha = widget.needsAttention ? _pulse.value : 0.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(12),
            border: widget.needsAttention
                ? Border.all(color: color.withValues(alpha: alpha + 0.18))
                : null,
          ),
          child: child,
        );
      },
      child: TextButton.icon(
        onPressed: widget.onPressed,
        icon: Icon(Icons.reorder_rounded, size: 18, color: color),
        label: Text('Ordenar', style: TextStyle(color: color)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PaddockRouteCard extends StatelessWidget {
  const _PaddockRouteCard({
    required this.paddock,
    required this.orderIndex,
    required this.animalCount,
    required this.displayStatus,
    required this.restSummary,
    required this.onTap,
  });

  final Paddock paddock;
  final int orderIndex;
  final int animalCount;
  final String displayStatus;
  final String restSummary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasOrder = paddock.rotationOrder != null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: hasOrder
                      ? AppColors.primaryDark
                      : const Color(0xFFEFEDE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  hasOrder ? '${orderIndex + 1}' : '-',
                  style: TextStyle(
                    color: hasOrder ? Colors.white : AppColors.muted,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            paddock.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(displayStatus),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _PaddockFact(
                          icon: Icons.square_foot,
                          text: '${paddock.areaHectares} ha',
                        ),
                        _PaddockAssetFact(
                          imagePath: AppImages.iconVaca,
                          text: '$animalCount animales',
                        ),
                        if (paddock.grassType.isNotEmpty)
                          _PaddockFact(
                            icon: Icons.grass_outlined,
                            text: paddock.grassType,
                          ),
                        if (!hasOrder)
                          const _PaddockFact(
                            icon: Icons.low_priority,
                            text: 'Sin orden',
                          ),
                      ],
                    ),
                    if (restSummary.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        restSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: displayStatus == 'Disponible'
                              ? AppColors.primaryDark
                              : AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaddockFact extends StatelessWidget {
  const _PaddockFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _PaddockAssetFact extends StatelessWidget {
  const _PaddockAssetFact({required this.imagePath, required this.text});

  final String imagePath;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          imagePath,
          width: 16,
          height: 16,
          fit: BoxFit.contain,
          color: AppColors.muted,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.pets_outlined, size: 15, color: AppColors.muted),
        ),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class PaddockRotationOrderScreen extends ConsumerWidget {
  const PaddockRotationOrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paddocks = _sortPaddocksByRotationOrder(
      ref.watch(paddockViewModelProvider).requireValue,
    );

    final referenceDate = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Orden de rotación')),
      body: paddocks.isEmpty
          ? EmptyState(
              icon: Icons.reorder,
              message:
                  'Agrega potreros para configurar el recorrido de rotación.',
              actionLabel: 'Agregar potrero',
              onAction: () => openPaddockForm(context),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    'Arrastra los potreros y ordénalos según tu manejo de rotación.',
                    style: TextStyle(color: AppColors.muted, height: 1.3),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: paddocks.length,
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) async {
                      final reordered = [...paddocks];

                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }

                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);

                      await ref
                          .read(paddockViewModelProvider.notifier)
                          .updateRotationOrder(
                            reordered.map((paddock) => paddock.id).toList(),
                          );
                    },
                    itemBuilder: (context, index) {
                      final paddock = paddocks[index];

                      final restStatus = _paddockRestStatus(
                        paddock,
                        referenceDate,
                      );

                      final restSummary = _paddockRestSummary(
                        paddock,
                        restStatus,
                      );

                      return Padding(
                        key: ValueKey(paddock.id),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primaryLight,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              paddock.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusChip(
                                    _paddockDisplayStatus(paddock, restStatus),
                                  ),
                                  if (paddock.requiredRestDays != null)
                                    Text(
                                      '${paddock.requiredRestDays} días de descanso',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  if (restSummary.isNotEmpty)
                                    Text(
                                      restSummary,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

Future<void> openPaddockForm(BuildContext context, [Paddock? paddock]) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PaddockFormScreen(paddock: paddock)),
  );
}

class PaddockFormScreen extends ConsumerStatefulWidget {
  const PaddockFormScreen({super.key, this.paddock});

  final Paddock? paddock;

  @override
  ConsumerState<PaddockFormScreen> createState() {
    return _PaddockFormScreenState();
  }
}

class _PaddockFormScreenState extends ConsumerState<PaddockFormScreen> {
  final key = GlobalKey<FormState>();
  final name = TextEditingController();
  final area = TextEditingController();
  final grass = TextEditingController();
  final restDays = TextEditingController();
  final plannedGrazingDays = TextEditingController();

  DateTime? lastGrazingEndDate;
  DateTime? grazingStartDate;

  String status = 'Disponible';

  @override
  void initState() {
    super.initState();

    final paddock = widget.paddock;

    if (paddock != null) {
      name.text = paddock.name;
      area.text = paddock.areaHectares.toString();
      grass.text = paddock.grassType;
      restDays.text = paddock.requiredRestDays?.toString() ?? '';
      plannedGrazingDays.text = paddock.plannedGrazingDays?.toString() ?? '';
      lastGrazingEndDate = paddock.lastGrazingEndDate;
      grazingStartDate = paddock.grazingStartDate;
      status = paddock.status;
    }
  }

  @override
  void dispose() {
    name.dispose();
    area.dispose();
    grass.dispose();
    restDays.dispose();
    plannedGrazingDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.paddock == null ? 'Agregar potrero' : 'Editar potrero',
        ),
      ),
      body: Form(
        key: key,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nombre del potrero',
              ),
              validator: req,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: area,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Área',
                suffixText: 'hectáreas',
              ),
              validator: (value) {
                final parsed = double.tryParse(
                  value?.replaceAll(',', '.') ?? '',
                );

                if (parsed == null) {
                  return 'Ingresa un área válida';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: grass,
              decoration: const InputDecoration(labelText: 'Tipo de pastura'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: restDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Descanso requerido',
                suffixText: 'días',
              ),
              validator: (value) {
                final cleanValue = value?.trim() ?? '';

                if (cleanValue.isEmpty) {
                  return null;
                }

                final parsed = int.tryParse(cleanValue);

                if (parsed == null || parsed <= 0) {
                  return 'Ingresa una cantidad mayor a cero';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            if (status == 'En uso') ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.login_outlined),
                title: const Text('Fecha de entrada del ganado'),
                subtitle: Text(
                  grazingStartDate == null
                      ? 'Sin fecha registrada'
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(grazingStartDate!),
                ),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: pickGrazingStartDate,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: plannedGrazingDays,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Uso planeado',
                  suffixText: 'días',
                ),
                validator: (value) {
                  if (status != 'En uso') {
                    return null;
                  }

                  final cleanValue = value?.trim() ?? '';

                  if (cleanValue.isEmpty) {
                    return 'Configura los días de uso';
                  }

                  final parsed = int.tryParse(cleanValue);

                  if (parsed == null || parsed <= 0) {
                    return 'Ingresa una cantidad mayor a cero';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
            ],
            ListTile(
              enabled: status != 'En uso',
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Fecha de salida del ganado'),
              subtitle: Text(
                status == 'En uso'
                    ? 'No aplica mientras el potrero está en uso'
                    : lastGrazingEndDate == null
                    ? 'Sin fecha registrada'
                    : MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(lastGrazingEndDate!),
              ),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: pickLastGrazingEndDate,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: ['Disponible', 'En uso', 'Descansando', 'Agotado']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  status = value;

                  if (status == 'En uso') {
                    grazingStartDate ??= DateTime.now();
                    lastGrazingEndDate = null;
                  }
                });
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: save,
              child: Text(
                widget.paddock == null ? 'Agregar potrero' : 'Guardar cambios',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? req(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Este dato es necesario';
    }

    return null;
  }

  Future<void> pickLastGrazingEndDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: lastGrazingEndDate ?? now,
    );

    if (picked != null && mounted) {
      setState(() {
        lastGrazingEndDate = picked;
      });
    }
  }

  Future<void> pickGrazingStartDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: grazingStartDate ?? now,
    );

    if (picked != null && mounted) {
      setState(() {
        grazingStartDate = picked;
      });
    }
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final old = widget.paddock;

    final requiredRestDays = int.tryParse(restDays.text.trim());

    final plannedDays = int.tryParse(plannedGrazingDays.text.trim());

    final grazingEndDate = status == 'En uso'
        ? null
        : lastGrazingEndDate ?? (old?.status == 'En uso' ? now : null);

    final activeStartDate = status == 'En uso' ? grazingStartDate ?? now : null;

    final paddock = Paddock(
      id: old?.id ?? const Uuid().v4(),
      name: name.text.trim(),
      areaHectares: double.parse(area.text.replaceAll(',', '.')),
      pastureType: grass.text.trim().isEmpty ? null : grass.text.trim(),
      requiredRestDays: requiredRestDays,
      rotationOrder: old?.rotationOrder,
      grazingStartDate: activeStartDate,
      plannedGrazingDays: status == 'En uso' ? plannedDays : null,
      status: status,
      lastGrazingEndDate: grazingEndDate,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );

    await ref.read(paddockViewModelProvider.notifier).save(paddock);

    if (!mounted) {
      return;
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✓ Potrero guardado')));
  }
}

class PaddockDetailScreen extends ConsumerWidget {
  const PaddockDetailScreen({super.key, required this.paddockId});

  final String paddockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;

    final paddock = paddocks.firstWhere((paddock) => paddock.id == paddockId);

    final referenceDate = DateTime.now();

    final elapsedRestDays = _elapsedRestDays(paddock, referenceDate);

    final restStatus = _paddockRestStatus(paddock, referenceDate);

    final animals = ref
        .watch(animalViewModelProvider)
        .requireValue
        .animals
        .where((animal) => animal.paddockId == paddock.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(paddock.name),
        actions: [
          IconButton(
            onPressed: () => openPaddockForm(context, paddock),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          paddock.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      StatusChip(_paddockDisplayStatus(paddock, restStatus)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${paddock.areaHectares} hectáreas · ${paddock.grassType}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paddock.requiredRestDays == null
                        ? 'Descanso requerido sin configurar'
                        : 'Descanso requerido: ${paddock.requiredRestDays} días',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (paddock.lastGrazingEndDate != null)
                    Text(
                      '$elapsedRestDays días desde la salida del ganado',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  if (paddock.status != 'En uso') ...[
                    const SizedBox(height: 8),
                    Text(
                      _paddockRestSummary(paddock, restStatus),
                      style: TextStyle(
                        color: restStatus.isReady
                            ? AppColors.primaryDark
                            : AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (paddock.status == 'En uso' &&
                      paddock.grazingStartDate != null)
                    Text(
                      _activeGrazingStatusText(paddock, referenceDate),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  if (_canAdjustRest(paddock) &&
                      paddock.lastGrazingEndDate != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _showAdjustRestDialog(
                          context: context,
                          ref: ref,
                          paddock: paddock,
                          restStatus: restStatus,
                        ),
                        icon: const Icon(Icons.more_time),
                        label: const Text('Ajustar descanso'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Animales asignados (${animals.length})',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (animals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Este potrero no tiene animales asignados.'),
              ),
            )
          else
            ...animals.map(
              (animal) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.pets)),
                  title: Text(animal.displayName),
                  subtitle: Text(animal.code),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaddockRestStatus {
  const _PaddockRestStatus({
    required this.elapsedDays,
    required this.remainingDays,
  });

  final int? elapsedDays;
  final int? remainingDays;

  bool get hasRestPlan {
    return elapsedDays != null && remainingDays != null;
  }

  bool get isReady {
    return hasRestPlan && remainingDays! <= 0;
  }
}

_PaddockRestStatus _paddockRestStatus(Paddock paddock, DateTime referenceDate) {
  final requiredRestDays = paddock.requiredRestDays;
  final lastGrazingEndDate = paddock.lastGrazingEndDate;

  if (requiredRestDays == null ||
      requiredRestDays <= 0 ||
      lastGrazingEndDate == null ||
      lastGrazingEndDate.isAfter(referenceDate)) {
    return const _PaddockRestStatus(elapsedDays: null, remainingDays: null);
  }

  final elapsedDays = referenceDate.difference(lastGrazingEndDate).inDays;

  return _PaddockRestStatus(
    elapsedDays: elapsedDays,
    remainingDays: requiredRestDays - elapsedDays,
  );
}

String _paddockDisplayStatus(Paddock paddock, _PaddockRestStatus restStatus) {
  if (paddock.status == 'Descansando' && restStatus.isReady) {
    return 'Disponible';
  }

  return paddock.status;
}

String _paddockRestSummary(Paddock paddock, _PaddockRestStatus restStatus) {
  if (paddock.status == 'En uso') {
    return '';
  }

  if (paddock.status == 'Agotado') {
    return 'Fuera de rotación';
  }

  if (paddock.status == 'Disponible') {
    return 'Listo para recibir ganado';
  }

  if (!restStatus.hasRestPlan) {
    return 'Descanso sin configurar';
  }

  final remainingDays = restStatus.remainingDays!;

  if (remainingDays > 0) {
    return remainingDays == 1
        ? 'Falta 1 día de descanso'
        : 'Faltan $remainingDays días de descanso';
  }

  if (remainingDays == 0) {
    return 'Descanso cumplido hoy';
  }

  final readyDays = remainingDays.abs();

  return readyDays == 1 ? 'Listo hace 1 día' : 'Listo hace $readyDays días';
}

bool _canAdjustRest(Paddock paddock) {
  return paddock.status == 'Descansando' || paddock.status == 'Disponible';
}

Future<void> _showAdjustRestDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Paddock paddock,
  required _PaddockRestStatus restStatus,
}) async {
  final controller = TextEditingController(
    text:
        paddock.requiredRestDays?.toString() ??
        ((restStatus.elapsedDays ?? 0) + 7).toString(),
  );

  final formKey = GlobalKey<FormState>();

  final newRestDays = await showDialog<int>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Ajustar descanso'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Descanso requerido',
              suffixText: 'días',
            ),
            validator: (value) {
              final parsed = int.tryParse(value?.trim() ?? '');

              if (parsed == null || parsed <= 0) {
                return 'Ingresa una cantidad mayor a cero';
              }

              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }

              Navigator.pop(dialogContext, int.parse(controller.text.trim()));
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  );

  controller.dispose();

  if (newRestDays == null) {
    return;
  }

  final now = DateTime.now();

  await ref
      .read(paddockViewModelProvider.notifier)
      .save(
        paddock.copyWith(
          requiredRestDays: newRestDays,
          status: 'Descansando',
          updatedAt: now,
        ),
      );

  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Descanso actualizado')));
  }
}

int? _elapsedRestDays(Paddock paddock, DateTime referenceDate) {
  final lastGrazingEndDate = paddock.lastGrazingEndDate;

  if (lastGrazingEndDate == null) {
    return null;
  }

  return referenceDate.difference(lastGrazingEndDate).inDays;
}

String _activeGrazingStatusText(Paddock paddock, DateTime referenceDate) {
  final elapsedDays = referenceDate
      .difference(paddock.grazingStartDate!)
      .inDays;

  final plannedDays = paddock.plannedGrazingDays;

  if (plannedDays == null || plannedDays <= 0) {
    return 'En uso desde hace $elapsedDays días';
  }

  final remainingDays = plannedDays - elapsedDays;

  if (remainingDays < 0) {
    return 'En uso desde hace $elapsedDays días';
  }

  if (remainingDays == 0) {
    return 'Termina su uso hoy';
  }

  return 'En uso desde hace $elapsedDays días · faltan $remainingDays días';
}

List<Paddock> _sortPaddocksByRotationOrder(List<Paddock> paddocks) {
  final originalIndexes = <String, int>{
    for (var index = 0; index < paddocks.length; index++)
      paddocks[index].id: index,
  };

  final sorted = [...paddocks];

  sorted.sort((first, second) {
    final firstOrder = first.rotationOrder;
    final secondOrder = second.rotationOrder;

    if (firstOrder != null && secondOrder != null) {
      final orderComparison = firstOrder.compareTo(secondOrder);

      if (orderComparison != 0) {
        return orderComparison;
      }
    } else if (firstOrder != null) {
      return -1;
    } else if (secondOrder != null) {
      return 1;
    }

    return originalIndexes[first.id]!.compareTo(originalIndexes[second.id]!);
  });

  return sorted;
}
