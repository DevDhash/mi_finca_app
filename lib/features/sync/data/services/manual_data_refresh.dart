/// Outcome of an explicit refresh; transport failures never mean convergence.
class ManualRefreshResult {
  ManualRefreshResult(Map<String, Object> failures)
    : failures = Map.unmodifiable(failures);
  final Map<String, Object> failures;
  bool get complete => failures.isEmpty;
}

/// Coordinates existing push, snapshot and merge protocols without owning ACKs.
class ManualDataRefresh {
  ManualDataRefresh({
    required this.validate,
    required this.push,
    required this.tombstones,
    required this.downloads,
    required this.reload,
    required this.saveSuccess,
    this.snapshots,
    this.updatePending,
    this.merges = const {},
  });
  final Future<void> Function()? snapshots;
  final Future<void> Function()? updatePending;
  final Map<String, Future<void> Function()> merges;
  final Future<void> Function() validate;
  final Future<void> Function() push;
  final Future<void> Function() tombstones;
  final Map<String, Future<void> Function()> downloads;
  final Future<void> Function() reload;
  final Future<void> Function() saveSuccess;
  Future<ManualRefreshResult>? _active;

  Future<ManualRefreshResult> refresh() =>
      _active ??= _run().whenComplete(() => _active = null);

  Future<ManualRefreshResult> _run() async {
    final failures = <String, Object>{};
    Future<bool> phase(
      String name,
      Future<void> Function() action, {
      bool verifyAfter = true,
    }) async {
      try {
        await validate();
        await action();
        if (verifyAfter) await validate();
        return true;
      } catch (error) {
        failures[name] = error;
        return false;
      }
    }

    try {
      if (await phase('conexión', validate)) {
        await phase('envío', push);
        if (await phase('eliminaciones', tombstones) &&
            (snapshots == null || await phase('snapshots', snapshots!))) {
          final downloaded = <String>{};
          for (final entry in downloads.entries) {
            if (!await phase('sesión', validate)) break;
            if (await phase(entry.key, entry.value)) downloaded.add(entry.key);
          }
          for (final entry in merges.entries) {
            if (downloaded.contains(entry.key)) {
              await phase('merge ${entry.key}', entry.value);
            }
          }
          await phase('eliminaciones finales', tombstones);
        }
      }
    } finally {
      // Reload only SQLite, including safe partial merges and terminal deletes.
      await phase('pantalla', reload);
      if (updatePending != null) await phase('pendientes', updatePending!);
    }
    if (failures.isEmpty) {
      // saveSuccess validates inside its transaction; avoid failure after commit.
      await phase('fecha', saveSuccess, verifyAfter: false);
    }
    return ManualRefreshResult(failures);
  }
}
