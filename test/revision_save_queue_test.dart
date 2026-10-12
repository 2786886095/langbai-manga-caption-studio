import 'dart:async';

import 'package:bubble_caption_studio/src/revision_save_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending writes merge to newest and every caller waits for commit',
      () async {
    final queue = RevisionSaveQueue();
    final writes = <int>[];
    final gate = Completer<void>();
    var acknowledged = false;
    final first = queue.enqueue(1, () async => writes.add(1));
    final second = queue.enqueue(2, () async => writes.add(2));
    final third = queue.enqueue(3, () async {
      writes.add(3);
      await gate.future;
    });
    final flush = queue.flush().then((value) {
      acknowledged = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(writes, [3]);
    expect(acknowledged, isFalse);
    expect(queue.isDirty, isTrue);
    expect(queue.persistedRevision, -1);
    gate.complete();
    expect(await Future.wait([first, second, third, flush]), [3, 3, 3, 3]);
    expect(queue.isDirty, isFalse);
  });

  test('new revisions during a slow write run after it, never concurrently',
      () async {
    final queue = RevisionSaveQueue();
    final events = <String>[];
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final first = queue.enqueue(1, () async {
      events.add('start 1');
      await firstGate.future;
      events.add('commit 1');
    });
    await Future<void>.delayed(Duration.zero);
    final second = queue.enqueue(2, () async => events.add('obsolete 2'));
    final third = queue.enqueue(3, () async {
      events.add('start 3');
      await secondGate.future;
      events.add('commit 3');
    });
    final flushing = queue.flush();
    expect(events, ['start 1']);
    firstGate.complete();
    expect(await first, 1);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['start 1', 'commit 1', 'start 3']);
    expect(queue.persistedRevision, 1);
    expect(queue.isDirty, isTrue);
    secondGate.complete();
    expect(await second, 3);
    expect(await third, 3);
    expect(await flushing, 3);
  });

  test('failed writes reject enqueue and flush and remain dirty until retry',
      () async {
    final queue = RevisionSaveQueue(persistedRevision: 5);
    final error = StateError('disk full');
    final saved = queue.enqueue(6, () async => throw error);
    final flushed = queue.flush();
    await Future.wait([
      expectLater(saved, throwsA(same(error))),
      expectLater(flushed, throwsA(same(error))),
    ]);
    expect(queue.persistedRevision, 5);
    expect(queue.isDirty, isTrue);
    expect(queue.lastError, same(error));
    await expectLater(queue.flush(), throwsA(same(error)));
    expect(await queue.enqueue(6, () async {}), 6);
    expect(queue.lastError, isNull);
    expect(queue.isDirty, isFalse);
  });

  test('a failed old write does not acknowledge a newer pending write',
      () async {
    final queue = RevisionSaveQueue();
    final gate = Completer<void>();
    final first = queue.enqueue(1, () async {
      await gate.future;
      throw StateError('old write failed');
    });
    final failure = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final second = queue.enqueue(2, () async {});
    final flushed = queue.flush();
    gate.complete();
    await failure;
    expect(await second, 2);
    expect(await flushed, 2);
    expect(queue.persistedRevision, 2);
  });

  test('an older request never overwrites a newer in-flight snapshot',
      () async {
    final queue = RevisionSaveQueue();
    final gate = Completer<void>();
    final writes = <int>[];
    final newer = queue.enqueue(8, () async {
      writes.add(8);
      await gate.future;
    });
    await Future<void>.delayed(Duration.zero);
    final older = queue.enqueue(7, () async => writes.add(7));
    gate.complete();
    expect(await newer, 8);
    expect(await older, 8);
    expect(writes, [8]);
    expect(await queue.enqueue(8, () async => writes.add(80)), 8);
    expect(writes, [8]);
  });
}
