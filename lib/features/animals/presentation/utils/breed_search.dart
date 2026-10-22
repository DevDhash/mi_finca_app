import 'package:mi_finca_app/features/animals/domain/constants/cattle_breeds.dart';

/// Search keys only; never use this to rewrite an animal's saved breed.
String normalizeBreedSearch(String value) {
  const accented = 'áàâäãåéèêëíìîïóòôöõúùûüñç';
  const plain = 'aaaaaaeeeeiiiiooooouuuunc';
  final lower = value.toLowerCase();
  final result = StringBuffer();
  for (final rune in lower.runes) {
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final char = String.fromCharCode(rune);
    final index = accented.indexOf(char);
    result.write(index < 0 ? char : plain[index]);
  }
  return result.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

final _breedIndex = [
  for (final breed in cattleBreeds)
    (
      name: breed.name,
      keys: [
        normalizeBreedSearch(breed.name),
        ...breed.aliases.map(normalizeBreedSearch),
      ],
    ),
];

List<String> searchCattleBreeds(String text) {
  final query = normalizeBreedSearch(text);
  if (query.isEmpty) return const [];
  final prefix = <String>[];
  final partial = <String>[];
  for (final breed in _breedIndex) {
    if (breed.keys.any((key) => key.startsWith(query))) {
      prefix.add(breed.name);
    } else if (breed.keys.any((key) => key.contains(query))) {
      partial.add(breed.name);
    }
  }
  return [...prefix, ...partial];
}
