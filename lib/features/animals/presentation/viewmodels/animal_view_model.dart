import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';

final animalViewModelProvider =
    NotifierProvider<AnimalViewModel, List<Animal>>(AnimalViewModel.new);

class AnimalViewModel extends Notifier<List<Animal>> {
  @override
  List<Animal> build() {
    return [];
  }

  void addAnimal(Animal animal) {
    state = [animal, ...state];
  }

  void removeAnimal(String id) {
    state = state.where((animal) => animal.id != id).toList();
  }
}