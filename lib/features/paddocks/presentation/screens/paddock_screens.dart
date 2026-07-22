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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Potreros'),
        actions: [
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
                        StatusChip(p.status),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${p.areaHectares} ha · $count animales · ${p.grassType}',
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
  DateTime? lastGrazingEndDate;
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
      lastGrazingEndDate = p.lastGrazingEndDate;
      status = p.status;
    }
  }

  @override
  void dispose() {
    name.dispose();
    area.dispose();
    grass.dispose();
    restDays.dispose();
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
            onChanged: (v) => setState(() => status = v!),
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

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    final now = DateTime.now();
    final old = widget.paddock;
    final requiredRestDays = int.tryParse(restDays.text.trim());
    final grazingEndDate = status == 'En uso'
        ? null
        : lastGrazingEndDate ?? (old?.status == 'En uso' ? now : null);
    final p = Paddock(
      id: old?.id ?? const Uuid().v4(),
      name: name.text.trim(),
      areaHectares: double.parse(area.text.replaceAll(',', '.')),
      pastureType: grass.text.trim().isEmpty ? null : grass.text.trim(),
      requiredRestDays: requiredRestDays,
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
                      StatusChip(p.status),
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
                      body:
                          'Actualmente tiene ${rotation.active!.animalCount} animales.',
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
                          ? 'Cumplió sus ${rotation.next!.requiredRestDays} días de descanso.'
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
          ...paddocks.map((p) {
            final elapsed = _elapsedRestDays(p, referenceDate);

            return Card(
              child: ListTile(
                leading: Icon(
                  p.status == 'En uso' ? Icons.pets : Icons.grass_outlined,
                  color: AppColors.primary,
                ),
                title: Text(p.name),
                subtitle: Text(
                  [
                    p.status,
                    if (p.requiredRestDays != null)
                      '${p.requiredRestDays} días requeridos',
                    if (elapsed != null) '$elapsed días de descanso',
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

int? _elapsedRestDays(Paddock paddock, DateTime referenceDate) {
  final lastGrazingEndDate = paddock.lastGrazingEndDate;
  if (lastGrazingEndDate == null) return null;

  return referenceDate.difference(lastGrazingEndDate).inDays;
}
