import 'package:mi_finca_app/features/animals/domain/entities/animal.dart';

/// Shared rules for a new registration and the complete form draft.
abstract final class AnimalRegistration {
  static String? codeError(String value) =>
      value.trim().isEmpty ? 'Ingresa un código o arete' : null;
  static String? typeError(String? value) =>
      value == null || value.trim().isEmpty
      ? 'Selecciona el tipo de animal'
      : null;
  static String? breedError(String value) =>
      value.trim().isEmpty ? 'Selecciona o ingresa una raza' : null;
  static String? sexError(String? value) =>
      value == null || value.trim().isEmpty
      ? 'Selecciona el sexo del animal'
      : null;
  static double? parseWeight(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));
  static bool validWeight(double? value) =>
      value == null || (value.isFinite && value >= 0);
  static String? weightError(String value) {
    if (value.trim().isEmpty) return null;
    final parsed = parseWeight(value);
    return parsed == null || !validWeight(parsed)
        ? 'Ingresa un peso numérico, finito y mayor o igual que cero'
        : null;
  }

  static void validateNew(Animal animal) {
    final errors = [
      codeError(animal.code),
      typeError(animal.type),
      breedError(animal.breed),
      sexError(animal.sex),
      if (!validWeight(animal.weight)) 'Peso inválido',
    ].whereType<String>();
    if (errors.isNotEmpty) throw FormatException(errors.join('. '));
  }
}
