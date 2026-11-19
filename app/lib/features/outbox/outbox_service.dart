import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/report.dart';
import '../../services/connectivity_service.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';

class OutboxEntry {
  const OutboxEntry({required this.draft, this.missingPhoto = false});

  final DraftRecord draft;
  final bool missingPhoto;
  int get attempts => draft.queueAttempts;
  DateTime? get nextAttemptAt => draft.nextAttemptAt;
}

abstract interface class OutboxService implements Listenable {
  List<OutboxEntry> get entries;
  Object? get persistenceError;
  Future<void> initialize();

  /// Returns the immediate server result, or null when it remains queued.
  Future<Report?> enqueue(DraftRecord draft);
  Future<void> retry();
  Future<void> remove(String id);
}

abstract interface class RetryScheduler {
  void schedule(Duration delay, void Function() callback);
  void cancel();
}

class TimerRetryScheduler implements RetryScheduler {
  Timer? _timer;

  @override
  void schedule(Duration delay, void Function() callback) {
    cancel();
    _timer = Timer(delay, callback);
  }

  @override
  void cancel() => _timer?.cancel();
}

/// Persist-before-send delivery with one immutable key per queued report.
/// Timers run while the app process lives; initialization resumes after restart.
class DurableOutbox extends ChangeNotifier implements OutboxService {
  DurableOutbox({
    required this._store,
    required this._connectivity,
    required this._send,
    DateTime Function()? now,
    RetryScheduler? scheduler,
  }) : _now = now ?? DateTime.now,
       _scheduler = scheduler ?? TimerRetryScheduler();

  final DraftStore _store;
  final ConnectivityService _connectivity;
  final Future<Report> Function(DraftRecord) _send;
  final DateTime Function() _now;
  final RetryScheduler _scheduler;
  final List<OutboxEntry> _entries = [];
  StreamSubscription<bool>? _subscription;
  Future<void> _pending = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;
  Object? _persistenceError;

  @override
  List<OutboxEntry> get entries => List.unmodifiable(_entries);

  @override
  Object? get persistenceError => _persistenceError;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> initialize() => _serial(() async {
    if (_initialized) return;
    await _connectivity.initialize();
    final drafts = await _store.loadAll();
    for (final draft in drafts) {
      _entries.add(
        OutboxEntry(
          draft: draft,
          missingPhoto: await _store.readPhoto(draft) == null,
        ),
      );
    }
    _initialized = true;
    _subscription = _connectivity.changes.listen((online) {
      if (online) {
        _backgroundRetry();
      } else {
        _scheduler.cancel();
      }
    });
    _changed();
    await _flush();
  });

  @override
  Future<Report?> enqueue(DraftRecord draft) => _serial(() async {
    if (!_entries.any((entry) => entry.draft.id == draft.id)) {
      final photo = await _store.readPhoto(draft);
      // Own a separate copy: removing the editable draft cannot erase the queue.
      final path = photo == null
          ? draft.photoPath
          : await _store.storePhoto(draft.id, photo);
      final queued = draft.copyWith(photoPath: path, clearRetry: true);
      await _store.save(queued);
      _entries.add(OutboxEntry(draft: queued, missingPhoto: photo == null));
      _changed();
    }
    final sent = await _flush();
    return sent[draft.id];
  });

  @override
  Future<void> retry() => _serial(() async {
    await _flush();
    _persistenceError = null;
    _changed();
  });

  void _backgroundRetry() {
    unawaited(
      retry().catchError((Object error) {
        // Keep the persisted entry and surface disk failures to the UI. Network
        // failures are already represented by each entry's retry deadline.
        _persistenceError = error;
        _changed();
      }),
    );
  }

  Future<Map<String, Report>> _flush() async {
    final sent = <String, Report>{};
    _scheduler.cancel();
    if (!_connectivity.isOnline || _disposed) return sent;
    for (final entry in List<OutboxEntry>.of(_entries)) {
      final draft = entry.draft;
      if (entry.missingPhoto) continue;
      final due = draft.nextAttemptAt;
      if (due != null && due.isAfter(_now())) continue;
      if (await _store.readPhoto(draft) == null) {
        _replace(OutboxEntry(draft: draft, missingPhoto: true));
        continue;
      }
      try {
        final report = await _send(draft);
        await _store.delete(draft.id);
        _entries.removeWhere((item) => item.draft.id == draft.id);
        sent[draft.id] = report;
      } catch (_) {
        final attempts = draft.queueAttempts + 1;
        final delay = Duration(
          seconds: math.min(300, 2 << math.min(8, attempts - 1)),
        );
        final waiting = draft.copyWith(
          queueAttempts: attempts,
          nextAttemptAt: _now().add(delay),
        );
        await _store.save(waiting);
        _replace(OutboxEntry(draft: waiting));
      }
      _changed();
      if (!_connectivity.isOnline || _disposed) break;
    }
    _schedule();
    _changed();
    return sent;
  }

  void _replace(OutboxEntry value) {
    final index = _entries.indexWhere(
      (entry) => entry.draft.id == value.draft.id,
    );
    if (index >= 0) _entries[index] = value;
  }

  void _schedule() {
    if (_disposed || !_connectivity.isOnline) return;
    final times =
        _entries
            .where((entry) => !entry.missingPhoto)
            .map((entry) => entry.nextAttemptAt ?? _now())
            .toList()
          ..sort();
    if (times.isEmpty) return;
    final delay = times.first.difference(_now());
    _scheduler.schedule(delay.isNegative ? Duration.zero : delay, () {
      _backgroundRetry();
    });
  }

  @override
  Future<void> remove(String id) => _serial(() async {
    await _store.delete(id);
    _entries.removeWhere((entry) => entry.draft.id == id);
    _scheduler.cancel();
    _schedule();
    _changed();
  });

  @override
  void dispose() {
    _disposed = true;
    _scheduler.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
