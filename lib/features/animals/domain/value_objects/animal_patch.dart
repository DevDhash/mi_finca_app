/// Closed descriptive vocabulary: location, identity and photos are excluded.
enum AnimalField {
  code('code', 'code'),
  name('name', 'name'),
  type('type', 'type'),
  breed('breed', 'breed'),
  sex('sex', 'sex'),
  birthDate('birthDate', 'birth_date'),
  weight('weight', 'weight'),
  notes('notes', 'notes');

  const AnimalField(this.local, this.remote);
  final String local;
  final String remote;
}

class AnimalPatch {
  AnimalPatch(Map<AnimalField, Object?> values)
    : fields = Map.unmodifiable(values) {
    for (final e in fields.entries) {
      final v = e.value;
      final valid = switch (e.key) {
        AnimalField.name => v == null || v is String,
        AnimalField.birthDate => v == null || v is DateTime,
        AnimalField.weight => v == null || (v is num && v.isFinite && v >= 0),
        AnimalField.notes => v is String,
        _ => v is String && v.trim().isNotEmpty,
      };
      if (!valid) throw ArgumentError('Invalid animal field: ${e.key.name}');
    }
  }
  final Map<AnimalField, Object?> fields;
  Map<String, Object?> get localValues => {
    for (final e in fields.entries)
      e.key.local: e.value is DateTime
          ? (e.value as DateTime).toUtc().toIso8601String()
          : e.value,
  };
  Map<String, Object?> get remoteValues => {
    for (final e in fields.entries) e.key.remote: localValues[e.key.local],
  };
  factory AnimalPatch.fromLocal(Map<String, Object?> values) => AnimalPatch({
    for (final e in values.entries)
      AnimalField.values.singleWhere(
        (f) => f.local == e.key,
      ): e.key == 'birthDate' && e.value != null
          ? DateTime.parse(e.value as String)
          : e.value,
  });
}
