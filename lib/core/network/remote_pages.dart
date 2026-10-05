/// Keyset pagination continues until an empty page, even with a server cap
/// smaller than the requested limit. IDs must be unique and ordered ascending.
Future<List<Map<String, dynamic>>> readRemotePages(
  Future<List<Map<String, dynamic>>> Function(String? after) fetch,
) async {
  final result = <Map<String, dynamic>>[];
  String? after;
  while (true) {
    final page = await fetch(after);
    if (page.isEmpty) return result;
    final next = page.last['id'] as String;
    if (after != null && next.compareTo(after) <= 0) {
      throw StateError('La paginación no avanzó');
    }
    result.addAll(page);
    after = next;
  }
}
