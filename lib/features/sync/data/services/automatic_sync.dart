import 'dart:async';

/// Foreground scheduler. Pending data remains in SQLite across process death.
class AutomaticSync {
  AutomaticSync({
    required this.sync,
    required this.pendingCount,
    required Stream<void> changes,
    this.debounce = const Duration(milliseconds: 350),
    this.delays = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
    ],
  }) {
    _subscription = changes.listen((_) => trigger());
  }
  final Future<void> Function() sync;
  final Future<int> Function() pendingCount;
  final List<Duration> delays;
  final Duration debounce;
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;
  bool enabled = false;
  int _failures = 0;

  void setEnabled(bool value) {
    final changed = value != enabled;
    enabled = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
    } else if (changed) {
      trigger(resetBackoff: true);
    }
  }

  void trigger({bool resetBackoff = false}) {
    if (_disposed || !enabled) return;
    if (resetBackoff) {
      _failures = 0;
      _timer?.cancel();
      _timer = null;
    }
    // Writes made by the worker must not bypass its backoff.
    if (_running || _timer != null) return;
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed || !enabled || _running) return;
    _running = true;
    var remaining = true;
    try {
      if (await pendingCount() > 0 && enabled && !_disposed) await sync();
      remaining = await pendingCount() > 0;
    } catch (_) {
      remaining = true;
    } finally {
      _running = false;
    }
    if (_disposed || !enabled) return;
    if (remaining) {
      final delay = delays[_failures.clamp(0, delays.length - 1)];
      _failures++;
      _timer = Timer(delay, () {
        _timer = null;
        unawaited(_run());
      });
    } else {
      _failures = 0;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription.cancel());
  }
}
