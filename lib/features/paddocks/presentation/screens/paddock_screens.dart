import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/paddocks/domain/entities/paddock.dart';
import 'package:mi_finca_app/features/paddocks/domain/usecases/calculate_paddock_rotation.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:uuid/uuid.dart';

class PaddockListScreen extends ConsumerWidget {
  const PaddockListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final referenceDate = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Potreros'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PaddockRotationOrderScreen(),
              ),
            ),
            icon: const Icon(Icons.reorder),
            tooltip: 'Orden de rotación',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RotationScreen()),
            ),
            icon: const Icon(Icons.timeline),
            tooltip: 'Rotación',
          ),
        ],
      ),
      body: paddocks.isEmpty
          ? EmptyState(
              icon: Icons.grass,
              message:
                  'No hay potreros creados todavía. Empieza por el potrero donde están tus animales hoy.',
              actionLabel: 'Agregar potrero',
              onAction: () => openPaddockForm(context),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: paddocks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final p = paddocks[i];
                final count = animals.where((a) => a.paddockId == p.id).length;
                final restStatus = _paddockRestStatus(p, referenceDate);
                final restSummary = _paddockRestSummary(p, restStatus);
                return Card(
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaddockDetailScreen(paddockId: p.id),
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        StatusChip(_paddockDisplayStatus(p, restStatus)),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        [
                          '${p.areaHectares} ha',
                          '$count animales',
                          if (p.grassType.isNotEmpty) p.grassType,
                          if (p.rotationOrder != null)
                            'Orden ${p.rotationOrder}',
                          if (restSummary.isNotEmpty) restSummary,
                        ].join(' · '),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
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
                    'Ruta configurada para la rotación del ganado.',
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
                      if (newIndex > oldIndex) newIndex -= 1;

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

Future<void> openPaddockForm(BuildContext context, [Paddock? paddock]) =>
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaddockFormScreen(paddock: paddock)),
    );

class PaddockFormScreen extends ConsumerStatefulWidget {
  const PaddockFormScreen({super.key, this.paddock});
  final Paddock? paddock;
  @override
  ConsumerState<PaddockFormScreen> createState() => _PaddockFormScreenState();
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
    final p = widget.paddock;
    if (p != null) {
      name.text = p.name;
      area.text = p.areaHectares.toString();
      grass.text = p.grassType;
      restDays.text = p.requiredRestDays?.toString() ?? '';
      plannedGrazingDays.text = p.plannedGrazingDays?.toString() ?? '';
      lastGrazingEndDate = p.lastGrazingEndDate;
      grazingStartDate = p.grazingStartDate;
      status = p.status;
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
  Widget build(BuildContext context) => Scaffold(
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
            decoration: const InputDecoration(labelText: 'Nombre del potrero'),
            validator: req,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: area,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Área',
              suffixText: 'hectáreas',
            ),
            validator: (v) =>
                double.tryParse(v?.replaceAll(',', '.') ?? '') == null
                ? 'Ingresa un área válida'
                : null,
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
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return null;

              final parsed = int.tryParse(value);
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
              validator: (v) {
                if (status != 'En uso') return null;

                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Configura los días de uso';

                final parsed = int.tryParse(value);
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
            items: [
              'Disponible',
              'En uso',
              'Descansando',
              'Agotado',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) {
              setState(() {
                status = v!;
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
  String? req(String? v) =>
      v == null || v.trim().isEmpty ? 'Este dato es necesario' : null;

  Future<void> pickLastGrazingEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: lastGrazingEndDate ?? now,
    );

    if (picked != null && mounted) {
      setState(() => lastGrazingEndDate = picked);
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
      setState(() => grazingStartDate = picked);
    }
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    final now = DateTime.now();
    final old = widget.paddock;
    final requiredRestDays = int.tryParse(restDays.text.trim());
    final plannedDays = int.tryParse(plannedGrazingDays.text.trim());
    final grazingEndDate = status == 'En uso'
        ? null
        : lastGrazingEndDate ?? (old?.status == 'En uso' ? now : null);
    final activeStartDate = status == 'En uso' ? grazingStartDate ?? now : null;
    final p = Paddock(
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
    await ref.read(paddockViewModelProvider.notifier).save(p);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✓ Potrero guardado')));
    }
  }
}

class PaddockDetailScreen extends ConsumerWidget {
  const PaddockDetailScreen({super.key, required this.paddockId});
  final String paddockId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final p = paddocks.firstWhere((p) => p.id == paddockId);
    final referenceDate = DateTime.now();
    final elapsedRestDays = _elapsedRestDays(p, referenceDate);
    final restStatus = _paddockRestStatus(p, referenceDate);
    final animals = ref
        .watch(animalViewModelProvider)
        .requireValue
        .animals
        .where((a) => a.paddockId == p.id)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            onPressed: () => openPaddockForm(context, p),
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
                          p.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      StatusChip(_paddockDisplayStatus(p, restStatus)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${p.areaHectares} hectáreas · ${p.grassType}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.requiredRestDays == null
                        ? 'Descanso requerido sin configurar'
                        : 'Descanso requerido: ${p.requiredRestDays} días',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (p.lastGrazingEndDate != null)
                    Text(
                      '$elapsedRestDays días desde la salida del ganado',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  if (p.status != 'En uso') ...[
                    const SizedBox(height: 8),
                    Text(
                      _paddockRestSummary(p, restStatus),
                      style: TextStyle(
                        color: restStatus.isReady
                            ? AppColors.primaryDark
                            : AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (p.status == 'En uso' && p.grazingStartDate != null)
                    Text(
                      _activeGrazingStatusText(p, referenceDate),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  if (_canAdjustRest(p) && p.lastGrazingEndDate != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _showAdjustRestDialog(
                          context: context,
                          ref: ref,
                          paddock: p,
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
              (a) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.pets)),
                  title: Text(a.displayName),
                  subtitle: Text(a.code),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RotationScreen extends ConsumerWidget {
  const RotationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final referenceDate = DateTime.now();
    final rotation = const CalculatePaddockRotation()(
      paddocks: paddocks,
      animals: animals,
      referenceDate: referenceDate,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Rotación de potreros')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: AppColors.primaryLight,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: rotation.active == null
                  ? const _RotationMessage(
                      title: 'No hay un potrero en uso',
                      body:
                          'Asigna el ganado a un potrero para iniciar el pastoreo.',
                    )
                  : _RotationMessage(
                      title:
                          'Potrero ${rotation.active!.paddock.name} se está usando',
                      body: _activeRotationBody(rotation.active!),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: const Color(0xFFFFF3D8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: rotation.next == null
                  ? const _RotationMessage(
                      title: 'No hay una próxima rotación calculada',
                      body: 'Configura el tiempo de descanso de tus potreros.',
                    )
                  : _RotationMessage(
                      title: rotation.next!.isReady
                          ? 'Potrero ${rotation.next!.paddock.name} está listo para la rotación'
                          : 'Potrero ${rotation.next!.paddock.name} estará listo en ${rotation.next!.remainingRestDays} días',
                      body: rotation.next!.isReady
                          ? rotation.next!.hasRestRequirement
                                ? 'Cumplió sus ${rotation.next!.requiredRestDays} días de descanso.'
                                : 'Está disponible para recibir ganado.'
                          : 'Será el próximo potrero disponible para la rotación.',
                    ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Orden de revisión',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._sortPaddocksByRotationOrder(paddocks).map((p) {
            final elapsed = _elapsedRestDays(p, referenceDate);
            final restStatus = _paddockRestStatus(p, referenceDate);
            final restSummary = _paddockRestSummary(p, restStatus);

            return Card(
              child: ListTile(
                leading: Icon(
                  p.status == 'En uso' ? Icons.pets : Icons.grass_outlined,
                  color: AppColors.primary,
                ),
                title: Text(p.name),
                subtitle: Text(
                  [
                    _paddockDisplayStatus(p, restStatus),
                    if (p.requiredRestDays != null)
                      '${p.requiredRestDays} días requeridos',
                    if (elapsed != null) '$elapsed días de descanso',
                    if (restSummary.isNotEmpty) restSummary,
                  ].join(' · '),
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          const Text(
            'En este MVP, los movimientos se registran desde el detalle de cada animal.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _RotationMessage extends StatelessWidget {
  const _RotationMessage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.text,
        ),
      ),
      const SizedBox(height: 6),
      Text(body, style: const TextStyle(color: AppColors.muted, height: 1.3)),
    ],
  );
}

class _PaddockRestStatus {
  const _PaddockRestStatus({
    required this.elapsedDays,
    required this.remainingDays,
  });

  final int? elapsedDays;
  final int? remainingDays;

  bool get hasRestPlan => elapsedDays != null && remainingDays != null;
  bool get isReady => hasRestPlan && remainingDays! <= 0;
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
  if (paddock.status == 'En uso') return '';
  if (paddock.status == 'Agotado') return 'Fuera de rotación';
  if (paddock.status == 'Disponible') return 'Listo para recibir ganado';

  if (!restStatus.hasRestPlan) {
    return 'Descanso sin configurar';
  }

  final remainingDays = restStatus.remainingDays!;
  if (remainingDays > 0) {
    return remainingDays == 1
        ? 'Falta 1 día de descanso'
        : 'Faltan $remainingDays días de descanso';
  }

  if (remainingDays == 0) return 'Descanso cumplido hoy';

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
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext, int.parse(controller.text.trim()));
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  );

  controller.dispose();
  if (newRestDays == null) return;

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
  if (lastGrazingEndDate == null) return null;

  return referenceDate.difference(lastGrazingEndDate).inDays;
}

String _activeRotationBody(ActivePaddockRotation active) {
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

String _activeGrazingStatusText(Paddock paddock, DateTime referenceDate) {
  final elapsedDays = referenceDate
      .difference(paddock.grazingStartDate!)
      .inDays;
  final plannedDays = paddock.plannedGrazingDays;

  if (plannedDays == null || plannedDays <= 0) {
    return 'En uso desde hace $elapsedDays días';
  }

  final remainingDays = plannedDays - elapsedDays;
  if (remainingDays < 0) return 'En uso desde hace $elapsedDays días';
  if (remainingDays == 0) return 'Termina su uso hoy';

  return 'En uso desde hace $elapsedDays días · faltan $remainingDays días';
}

List<Paddock> _sortPaddocksByRotationOrder(List<Paddock> paddocks) {
  final originalIndexes = <String, int>{
    for (var i = 0; i < paddocks.length; i++) paddocks[i].id: i,
  };
  final sorted = [...paddocks];

  sorted.sort((a, b) {
    final aOrder = a.rotationOrder;
    final bOrder = b.rotationOrder;

    if (aOrder != null && bOrder != null) {
      final order = aOrder.compareTo(bOrder);
      if (order != 0) return order;
    } else if (aOrder != null) {
      return -1;
    } else if (bOrder != null) {
      return 1;
    }

    return originalIndexes[a.id]!.compareTo(originalIndexes[b.id]!);
  });

  return sorted;
}
