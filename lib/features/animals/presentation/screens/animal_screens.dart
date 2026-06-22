import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AnimalListScreen extends ConsumerStatefulWidget {
  const AnimalListScreen({super.key});
  @override
  ConsumerState<AnimalListScreen> createState() => _AnimalListScreenState();
}

class _AnimalListScreenState extends ConsumerState<AnimalListScreen> {
  String query = '';
  String type = 'Todos';
  @override
  Widget build(BuildContext context) {
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final items = animals
        .where(
          (a) =>
              (type == 'Todos' || a.type == type) &&
              '${a.name} ${a.code} ${a.breed}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Animales')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              hintText: 'Buscar por nombre o código',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: ['Todos', 'Vaca', 'Toro', 'Ternero', 'Novillo']
                  .map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(v),
                        selected: type == v,
                        onSelected: (_) => setState(() => type = v),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.pets,
                    message: query.isEmpty
                        ? 'Aún no tienes animales registrados. Toca el botón para agregar el primero.'
                        : 'No se encontraron resultados.',
                    actionLabel: 'Registrar animal',
                    onAction: () => openAnimalForm(context),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => AnimalListCard(
                      animal: items[i],
                      paddockName: paddocks
                          .where((p) => p.id == items[i].paddockId)
                          .firstOrNull
                          ?.name,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AnimalDetailScreen(animalId: items[i].id),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class AnimalListCard extends StatelessWidget {
  const AnimalListCard({
    super.key,
    required this.animal,
    this.paddockName,
    required this.onTap,
  });
  final Animal animal;
  final String? paddockName;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.all(12),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.primaryLight,
        backgroundImage: animal.photoPath == null
            ? null
            : FileImage(File(animal.photoPath!)),
        child: animal.photoPath == null
            ? const Icon(Icons.pets, color: AppColors.primaryDark)
            : null,
      ),
      title: Text(
        animal.displayName,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      subtitle: Text('${animal.code} · ${paddockName ?? 'Sin potrero'}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [StatusChip(animal.status)],
      ),
    ),
  );
}

Future<void> openAnimalForm(BuildContext context, [Animal? animal]) =>
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnimalFormScreen(animal: animal)),
    );

class AnimalFormScreen extends ConsumerStatefulWidget {
  const AnimalFormScreen({super.key, this.animal});
  final Animal? animal;
  @override
  ConsumerState<AnimalFormScreen> createState() => _AnimalFormScreenState();
}

class _AnimalFormScreenState extends ConsumerState<AnimalFormScreen> {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController();
  final name = TextEditingController();
  final breed = TextEditingController();
  final weight = TextEditingController();
  final notes = TextEditingController();
  int step = 0;
  String type = 'Vaca';
  String sex = 'Hembra';
  String? paddockId;
  String? photoPath;
  DateTime? birthDate;
  @override
  void initState() {
    super.initState();
    final a = widget.animal;
    if (a != null) {
      code.text = a.code;
      name.text = a.name ?? '';
      breed.text = a.breed;
      weight.text = a.weight?.toString() ?? '';
      notes.text = a.notes;
      type = a.type;
      sex = a.sex;
      paddockId = a.paddockId;
      photoPath = a.photoPath;
      birthDate = a.birthDate;
    }
  }

  @override
  void dispose() {
    for (final c in [code, name, breed, weight, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (image == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory(
      path.join(directory.path, 'animal_photos'),
    );
    await photoDirectory.create(recursive: true);
    final target = path.join(
      photoDirectory.path,
      '${const Uuid().v4()}${path.extension(image.path)}',
    );
    await File(image.path).copy(target);
    if (mounted) setState(() => photoPath = target);
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) {
      setState(() => step = 0);
      return;
    }
    final now = DateTime.now();
    final old = widget.animal;
    final animal = Animal(
      id: old?.id ?? const Uuid().v4(),
      code: code.text.trim(),
      name: name.text.trim().isEmpty ? null : name.text.trim(),
      type: type,
      breed: breed.text.trim(),
      sex: sex,
      photoPath: photoPath,
      birthDate: birthDate,
      weight: double.tryParse(weight.text.replaceAll(',', '.')),
      paddockId: paddockId,
      notes: notes.text.trim(),
      status: old?.status ?? 'Activo',
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await ref.read(animalViewModelProvider.notifier).save(animal);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✓ Animal guardado')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.animal == null ? 'Registrar animal' : 'Editar animal',
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (step > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => step--),
                    child: const Text('Atrás'),
                  ),
                ),
              if (step > 0) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: step < 2 ? () => setState(() => step++) : save,
                  child: Text(step < 2 ? 'Siguiente' : 'Guardar animal'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: List.generate(
                3,
                (i) => Expanded(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= step ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (step == 0) ...[
              Center(
                child: GestureDetector(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    builder: (_) => SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.camera_alt),
                            title: const Text('Tomar foto'),
                            onTap: () {
                              Navigator.pop(context);
                              pick(ImageSource.camera);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_library),
                            title: const Text('Elegir de galería'),
                            onTap: () {
                              Navigator.pop(context);
                              pick(ImageSource.gallery);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 62,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: photoPath == null
                        ? null
                        : FileImage(File(photoPath!)),
                    child: photoPath == null
                        ? const Icon(Icons.add_a_photo, size: 38)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: code,
                decoration: const InputDecoration(
                  labelText: 'Nombre o código *',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Ingresa un nombre o código'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nombre opcional'),
              ),
              const SizedBox(height: 14),
              const Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: ['Vaca', 'Toro', 'Ternero', 'Novillo', 'Otro']
                    .map(
                      (v) => ChoiceChip(
                        label: Text(v),
                        selected: type == v,
                        onSelected: (_) => setState(() => type = v),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: breed,
                decoration: const InputDecoration(labelText: 'Raza *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Ingresa la raza' : null,
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Hembra', label: Text('Hembra')),
                  ButtonSegment(value: 'Macho', label: Text('Macho')),
                ],
                selected: {sex},
                onSelectionChanged: (v) => setState(() => sex = v.first),
              ),
            ],
            if (step == 1) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha de nacimiento aproximada'),
                subtitle: Text(
                  birthDate == null
                      ? 'No indicada'
                      : '${birthDate!.day}/${birthDate!.month}/${birthDate!.year}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    initialDate: birthDate ?? DateTime.now(),
                  );
                  if (d != null) setState(() => birthDate = d);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Peso estimado',
                  suffixText: 'kg',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: paddockId,
                decoration: const InputDecoration(labelText: 'Potrero actual'),
                items: paddocks
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => paddockId = v),
              ),
            ],
            if (step == 2) ...[
              TextFormField(
                controller: notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observaciones opcionales',
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Confirma los datos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${name.text.isEmpty ? code.text : name.text} · $type',
                      ),
                      Text('${breed.text} · $sex'),
                      Text(
                        'Peso: ${weight.text.isEmpty ? 'No indicado' : '${weight.text} kg'}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AnimalDetailScreen extends ConsumerWidget {
  const AnimalDetailScreen({super.key, required this.animalId});
  final String animalId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animalState = ref.watch(animalViewModelProvider).requireValue;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final animal = animalState.animals.firstWhere((a) => a.id == animalId);
    final paddock = paddocks.where((p) => p.id == animal.paddockId).firstOrNull;
    final moves = animalState.movements
        .where((m) => m.animalId == animalId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(animal.displayName),
        actions: [
          IconButton(
            onPressed: () => openAnimalForm(context, animal),
            icon: const Icon(Icons.edit),
            tooltip: 'Editar',
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: paddocks.length < 2
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MoveAnimalScreen(animalId: animalId),
                    ),
                  ),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Mover de potrero'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 72,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: animal.photoPath == null
                  ? null
                  : FileImage(File(animal.photoPath!)),
              child: animal.photoPath == null
                  ? const Icon(Icons.pets, size: 54)
                  : null,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            animal.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          Center(child: StatusChip(animal.status)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Código', animal.code),
                  _row('Tipo', animal.type),
                  _row('Raza', animal.breed),
                  _row('Sexo', animal.sex),
                  _row(
                    'Peso',
                    animal.weight == null
                        ? 'No indicado'
                        : '${animal.weight} kg',
                  ),
                  _row('Potrero', paddock?.name ?? 'Sin asignar'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Historial de movimientos'),
            children: moves.isEmpty
                ? [const ListTile(title: Text('Sin movimientos registrados'))]
                : moves
                      .map(
                        (m) => ListTile(
                          leading: const Icon(Icons.swap_horiz),
                          title: Text(
                            paddocks
                                    .where((p) => p.id == m.toPaddockId)
                                    .firstOrNull
                                    ?.name ??
                                'Potrero',
                          ),
                          subtitle: Text(
                            '${m.date.day}/${m.date.month}/${m.date.year}',
                          ),
                        ),
                      )
                      .toList(),
          ),
          ExpansionTile(
            title: const Text('Observaciones'),
            children: [
              ListTile(
                title: Text(
                  animal.notes.isEmpty ? 'Sin observaciones' : animal.notes,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class MoveAnimalScreen extends ConsumerStatefulWidget {
  const MoveAnimalScreen({super.key, required this.animalId});
  final String animalId;
  @override
  ConsumerState<MoveAnimalScreen> createState() => _MoveAnimalScreenState();
}

class _MoveAnimalScreenState extends ConsumerState<MoveAnimalScreen> {
  String? destination;
  DateTime date = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final animal = animals.firstWhere((a) => a.id == widget.animalId);
    final options = paddocks.where((p) => p.id != animal.paddockId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Mover de potrero')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Mover a ${animal.displayName}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: destination,
            decoration: const InputDecoration(labelText: 'Potrero destino'),
            items: options
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            onChanged: (v) => setState(() => destination = v),
          ),
          const SizedBox(height: 14),
          ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text('Fecha del movimiento'),
            subtitle: Text('${date.day}/${date.month}/${date.year}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDate: date,
              );
              if (d != null) setState(() => date = d);
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: destination == null
                ? null
                : () async {
                    await ref
                        .read(animalViewModelProvider.notifier)
                        .move(animal, destination!, date);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Movimiento registrado'),
                        ),
                      );
                    }
                  },
            child: const Text('Confirmar movimiento'),
          ),
        ],
      ),
    );
  }
}
