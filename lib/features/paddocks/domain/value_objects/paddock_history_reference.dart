/// Read-only identity for history. Never an operational Paddock.
class PaddockHistoryReference {
  const PaddockHistoryReference({
    required this.id,
    this.name,
    this.isDeleted = false,
  });

  final String id;
  final String? name;
  final bool isDeleted;

  String get label {
    final knownName = name?.trim();
    final label = knownName == null || knownName.isEmpty
        ? 'Potrero $id'
        : knownName;
    return isDeleted ? '$label (eliminado)' : label;
  }
}
