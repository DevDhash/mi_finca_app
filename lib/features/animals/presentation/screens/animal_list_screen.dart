import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_form_screen.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/animals/presentation/widgets/animal_card.dart';

class AnimalListScreen extends ConsumerWidget {
  const AnimalListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(animalViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ganado'),
      ),
      body: animals.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aún no tienes animales registrados.\nPresiona + para agregar el primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: animals.length,
              itemBuilder: (context, index) {
                return AnimalCard(animal: animals[index]);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AnimalFormScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }
}