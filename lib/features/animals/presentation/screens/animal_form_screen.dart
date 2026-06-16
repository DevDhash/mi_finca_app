import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:uuid/uuid.dart';

class AnimalFormScreen extends ConsumerStatefulWidget {
  const AnimalFormScreen({super.key});

  @override
  ConsumerState<AnimalFormScreen> createState() => _AnimalFormScreenState();
}

class _AnimalFormScreenState extends ConsumerState<AnimalFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _earTagController = TextEditingController();
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();

  String _category = 'Vaca';
  String _sex = 'Hembra';
  String? _photoPath;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _earTagController.dispose();
    _nameController.dispose();
    _breedController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 75,
    );

    if (image == null) return;

    setState(() {
      _photoPath = image.path;
    });
  }

  void _saveAnimal() {
    if (!_formKey.currentState!.validate()) return;

    final animal = Animal(
      id: const Uuid().v4(),
      earTag: _earTagController.text.trim(),
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      category: _category,
      breed: _breedController.text.trim(),
      sex: _sex,
      photoPath: _photoPath,
      createdAt: DateTime.now(),
    );

    ref.read(animalViewModelProvider.notifier).addAnimal(animal);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = _photoPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar animal'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 64,
                backgroundImage:
                    photoPath != null ? FileImage(File(photoPath)) : null,
                child: photoPath == null
                    ? const Icon(
                        Icons.camera_alt,
                        size: 40,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Cámara'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galería'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _earTagController,
              decoration: const InputDecoration(
                labelText: 'Arete o código',
                hintText: 'Ejemplo: V-001',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa el arete o código del animal';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre opcional',
                hintText: 'Ejemplo: Lola',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Ternero', child: Text('Ternero')),
                DropdownMenuItem(value: 'Vaquilla', child: Text('Vaquilla')),
                DropdownMenuItem(value: 'Vaca', child: Text('Vaca')),
                DropdownMenuItem(value: 'Toro', child: Text('Toro')),
                DropdownMenuItem(value: 'Novillo', child: Text('Novillo')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _category = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _sex,
              decoration: const InputDecoration(
                labelText: 'Sexo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Hembra', child: Text('Hembra')),
                DropdownMenuItem(value: 'Macho', child: Text('Macho')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _sex = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _breedController,
              decoration: const InputDecoration(
                labelText: 'Raza',
                hintText: 'Ejemplo: Holstein, Brown Swiss, Gyr',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa la raza';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saveAnimal,
              icon: const Icon(Icons.save),
              label: const Text('Guardar animal'),
            ),
          ],
        ),
      ),
    );
  }
}