import 'dart:async';

typedef RevisionWriter = Future<void> Function();

/// Serializes durable writes and merges only writes that have not started.
/// Awaiting enqueue/flush never acknowledges a revision before its write commits.
class RevisionSaveQueue {
  RevisionSaveQueue({int persistedRevision = -1, this.onStateChanged})
      : _persistedRevision = persistedRevision,
        _requestedRevision = persistedRevision;

  final void Function()? onStateChanged;
  int _persistedRevision;
  int _requestedRevision;
  _PendingWrite? _pending;
  bool _writing = false;
  bool _scheduled = false;
  int? _activeRevision;
  Object? _lastError;
  StackTrace? _lastErrorStack;
  final _waiters = <_RevisionWaiter>[];

  int get persistedRevision => _persistedRevision;
  int get requestedRevision => _requestedRevision;
  int? get pendingRevision => _pending?.revision;
  bool get isWriting => _writing || _scheduled;
  bool get isDirty => _persistedRevision < _requestedRevision;
  Object? get lastError => _lastError;

  Future<int> enqueue(int revision, RevisionWriter write) {
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
    if (revision <= _persistedRevision) {
      return Future.value(_persistedRevision);
    }
    if (revision > _requestedRevision) _requestedRevision = revision;
    final waiter = _RevisionWaiter(revision);
    _waiters.add(waiter);
    if ((_activeRevision == null || revision > _activeRevision!) &&
        (_pending == null || revision >= _pending!.revision)) {
      _pending = _PendingWrite(revision, write);
    }
    _schedule();
    onStateChanged?.call();
    return waiter.completer.future;
  }

  Future<int> flush() {
    if (!isDirty) return Future.value(_persistedRevision);
    if (!_writing && !_scheduled && _pending == null) {
      return Future<int>.error(
        _lastError ?? StateError('Requested revision has not been persisted'),
        _lastErrorStack,
      );
    }
    final waiter = _RevisionWaiter(_requestedRevision);
    _waiters.add(waiter);
    _schedule();
    return waiter.completer.future;
  }

  void _schedule() {
    if (_writing || _scheduled || _pending == null) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_writing) return;
    _writing = true;
    onStateChanged?.call();
    try {
      while (_pending != null) {
        final task = _pending!;
        _pending = null;
        _activeRevision = task.revision;
        try {
          await task.write();
          if (task.revision > _persistedRevision) {
            _persistedRevision = task.revision;
          }
          _lastError = null;
          _lastErrorStack = null;
          _completeThrough(_persistedRevision);
        } catch (error, stack) {
          _lastError = error;
          _lastErrorStack = stack;
          _failThrough(task.revision, error, stack);
        }
        _activeRevision = null;
        onStateChanged?.call();
      }
    } finally {
      _writing = false;
      _activeRevision = null;
      onStateChanged?.call();
      _schedule();
    }
  }

  void _completeThrough(int revision) {
    final completed = _waiters.where((w) => w.revision <= revision).toList();
    _waiters.removeWhere((w) => w.revision <= revision);
    for (final waiter in completed) {
      waiter.completer.complete(revision);
    }
  }

  void _failThrough(int revision, Object error, StackTrace stack) {
    final failed = _waiters.where((w) => w.revision <= revision).toList();
    _waiters.removeWhere((w) => w.revision <= revision);
    for (final waiter in failed) {
      waiter.completer.completeError(error, stack);
    }
  }
}

class _PendingWrite {
  const _PendingWrite(this.revision, this.write);
  final int revision;
  final RevisionWriter write;
}

class _RevisionWaiter {
  _RevisionWaiter(this.revision);
  final int revision;
  final completer = Completer<int>();
}
