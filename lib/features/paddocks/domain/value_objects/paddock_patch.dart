/// Closed field vocabulary. Identity and server timestamps are not editable.
enum PaddockField {
  name('name', 'name'),
  area('areaHectares', 'area'),
  pastureType('pastureType', 'pasture_type'),
  requiredRestDays('requiredRestDays', 'required_rest_days'),
  rotationOrder('rotationOrder', 'rotation_order'),
  status('status', 'status', operational: true),
  grazingStartDate('grazingStartDate', 'grazing_start_date', operational: true),
  plannedGrazingDays(
    'plannedGrazingDays',
    'planned_grazing_days',
    operational: true,
  ),
  lastGrazingEndDate(
    'lastGrazingEndDate',
    'last_grazing_end_date',
    operational: true,
  );

  const PaddockField(this.local, this.remote, {this.operational = false});
  final String local;
  final String remote;
  final bool operational;
}

class PaddockPatch {
  PaddockPatch(Map<PaddockField, Object?> fields)
    : fields = Map.unmodifiable(fields) {
    for (final entry in fields.entries) {
      final v = entry.value;
      final valid = switch (entry.key) {
        PaddockField.name => v is String && v.trim().isNotEmpty,
        PaddockField.area => v is num && v.isFinite && v >= 0,
        PaddockField.pastureType => v == null || v is String,
        PaddockField.requiredRestDays ||
        PaddockField.rotationOrder ||
        PaddockField.plannedGrazingDays => v == null || (v is int && v > 0),
        PaddockField.status => [
          'Disponible',
          'En uso',
          'Descansando',
          'Agotado',
        ].contains(v),
        PaddockField.grazingStartDate ||
        PaddockField.lastGrazingEndDate => v == null || v is DateTime,
      };
      if (!valid) throw ArgumentError('Invalid ${entry.key.name}');
    }
  }
  final Map<PaddockField, Object?> fields;
  bool get operational => fields.keys.any((f) => f.operational);
  Map<String, Object?> get localValues => {
    for (final e in fields.entries)
      e.key.local: e.value is DateTime
          ? (e.value as DateTime).toUtc().toIso8601String()
          : e.value,
  };
  Map<String, Object?> get remoteValues => {
    for (final e in fields.entries) e.key.remote: localValues[e.key.local],
  };
  factory PaddockPatch.fromLocal(Map<String, Object?> values) => PaddockPatch({
    for (final e in values.entries)
      PaddockField.values.singleWhere((f) => f.local == e.key):
          ['grazingStartDate', 'lastGrazingEndDate'].contains(e.key) &&
              e.value != null
          ? DateTime.parse(e.value as String)
          : e.value,
  });
}
