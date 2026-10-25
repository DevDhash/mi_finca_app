/// Display order for the category selector.
abstract final class CattleCategories {
  static const sexes = <String, String?>{
    'Toro': 'Macho',
    'Vaca': 'Hembra',
    'Ternero': 'Macho',
    'Ternera': 'Hembra',
    'Torete': 'Macho',
    'Novilla': 'Hembra',
    'Otro': null,
  };

  static String? sexFor(String? category) => sexes[category];
}
