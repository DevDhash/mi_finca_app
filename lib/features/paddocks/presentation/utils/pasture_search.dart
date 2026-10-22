import 'package:mi_finca_app/features/paddocks/domain/constants/pasture_types.dart';

/// Search keys only; never use this to rewrite a paddock's saved pasture.
String normalizePastureSearch(String value) {
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

final _pastureIndex = [
  for (final pasture in pastureTypes)
    (
      name: pasture.name,
      keys: [
        normalizePastureSearch(pasture.name),
        ...pasture.aliases.map(normalizePastureSearch),
      ],
    ),
];

List<String> searchPastureTypes(String text) {
  final query = normalizePastureSearch(text);
  if (query.isEmpty) return const [];
  final prefix = <String>[];
  final partial = <String>[];
  for (final pasture in _pastureIndex) {
    if (pasture.keys.any((key) => key.startsWith(query))) {
      prefix.add(pasture.name);
    } else if (pasture.keys.any((key) => key.contains(query))) {
      partial.add(pasture.name);
    }
  }
  return [...prefix, ...partial];
}
