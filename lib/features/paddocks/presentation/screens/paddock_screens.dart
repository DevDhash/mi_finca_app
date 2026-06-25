import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
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
  String status = 'Disponible';
  @override
  void initState() {
    super.initState();
    final p = widget.paddock;
    if (p != null) {
      name.text = p.name;
      area.text = p.areaHectares.toString();
      grass.text = p.grassType;
      status = p.status;
    }
  }

  @override
  void dispose() {
    name.dispose();
    area.dispose();
    grass.dispose();
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
            decoration: const InputDecoration(labelText: 'Tipo de pasto'),
            validator: req,
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
  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    final now = DateTime.now();
    final old = widget.paddock;
    final p = Paddock(
      id: old?.id ?? const Uuid().v4(),
      name: name.text.trim(),
      areaHectares: double.parse(area.text.replaceAll(',', '.')),
      grassType: grass.text.trim(),
      status: status,
      lastUsedAt: old?.lastUsedAt,
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
                  if (p.lastUsedAt != null)
                    Text(
                      '${p.restDays} días desde el último uso',
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
    final candidates = paddocks.where((p) => p.status != 'En uso').toList()
      ..sort((a, b) => b.restDays.compareTo(a.restDays));
    final suggested = candidates.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Rotación de potreros')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (suggested != null)
            Card(
              color: AppColors.primaryLight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Potrero sugerido',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      suggested.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Descansó ${suggested.restDays} días · sugerencia local del MVP',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Orden de uso',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paddocks.length,
              separatorBuilder: (_, _) =>
                  const Icon(Icons.arrow_forward, color: AppColors.muted),
              itemBuilder: (_, i) {
                final p = paddocks[i];
                return SizedBox(
                  width: 130,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            p.status == 'En uso' ? Icons.pets : Icons.grass,
                            color: AppColors.primary,
                          ),
                          Text(
                            p.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            p.status,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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
