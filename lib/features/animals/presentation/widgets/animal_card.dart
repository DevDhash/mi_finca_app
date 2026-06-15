import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';

class AnimalCard extends StatelessWidget {
  final Animal animal;

  const AnimalCard({
    super.key,
    required this.animal,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage:
              animal.photoPath != null ? FileImage(File(animal.photoPath!)) : null,
          child: animal.photoPath == null ? const Icon(Icons.pets) : null,
        ),
        title: Text(
          animal.earTag,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${animal.category} • ${animal.breed} • ${animal.sex}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}