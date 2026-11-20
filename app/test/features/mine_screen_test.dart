import 'dart:async';

import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/mine/my_reports_screen.dart';
import 'package:aldia_app/features/outbox/outbox_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/memory_draft_store.dart';
import '../widgets/harness.dart';

DraftRecord _draft(String id) => DraftRecord(
  id: id,
  step: 'category',
  position: const LatLng(14.6, -90.5),
  createdAt: DateTime.now().toUtc(),
  categoryId: 'graffiti',
);

class _ControlledDraftStore extends MemoryDraftStore {
  Completer<List<DraftRecord>>? firstLoad;
  bool failDelete = false;
  int loads = 0;

  @override
  Future<List<DraftRecord>> loadAll() async {
    loads++;
    if (loads == 1 && firstLoad != null) return firstLoad!.future;
    return super.loadAll();
  }

  @override
  Future<void> delete(String id) async {
    if (failDelete) throw StateError('storage unavailable');
    await super.delete(id);
  }
}

class _FailingOutbox extends FakeOutbox {
  _FailingOutbox(super.entries);

  Object? error = StateError('storage unavailable');

  @override
  Object? get persistenceError => error;

  @override
  Future<void> retry() async {
    retries++;
    throw StateError('storage unavailable');
  }
}

void main() {
  testWidgets('empty state invites the first report', (tester) async {
    await tester.pumpWidget(
      harness(home: const MyReportsScreen(), repository: repositoryWith()),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.emptyMine), findsOneWidget);
    expect(find.text(S.firstReport), findsOneWidget);
  });

  testWidgets(
    'outbox shows waiting status, retries and confirms deletion once',
    (tester) async {
      final outbox = FakeOutbox([OutboxEntry(draft: _draft('q1'))]);
      await tester.pumpWidget(
        harness(
          home: const MyReportsScreen(),
          repository: repositoryWith(),
          outbox: outbox,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(S.waitingNetwork), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      await tester.tap(find.text(S.retryNow));
      expect(outbox.retries, 1);

      await tester.tap(find.text(S.delete));
      await tester.pumpAndSettle();
      expect(find.text(S.deleteOutboxQuestion), findsOneWidget);
      expect(outbox.removed, isEmpty);
      await tester.tap(find.text(S.delete).last);
      await tester.pumpAndSettle();
      expect(outbox.removed, ['q1']);
      expect(find.text(S.waitingNetwork), findsNothing);
    },
  );

  testWidgets('a queued report with a lost photo offers no retry', (
    tester,
  ) async {
    final outbox = FakeOutbox([
      OutboxEntry(draft: _draft('q1'), missingPhoto: true),
    ]);
    await tester.pumpWidget(
      harness(
        home: const MyReportsScreen(),
        repository: repositoryWith(),
        outbox: outbox,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.missingPhoto), findsOneWidget);
    expect(find.text(S.retryNow), findsNothing);
  });

  testWidgets('drafts sit above sent reports; delete asks once', (
    tester,
  ) async {
    final drafts = MemoryDraftStore();
    await drafts.save(_draft('d1'));
    await tester.pumpWidget(
      harness(
        home: const MyReportsScreen(),
        repository: repositoryWith(byId: {detailId: stateJson('resuelto')}),
        drafts: drafts,
      ),
    );
    await tester.pumpAndSettle();

    final draftY = tester.getTopLeft(find.text(S.savedDrafts)).dy;
    final sentY = tester.getTopLeft(find.text(S.sentReports)).dy;
    expect(draftY, lessThan(sentY));
    expect(find.textContaining('Resuelto'), findsWidgets);

    await tester.tap(find.text(S.deleteDraft));
    await tester.pumpAndSettle();
    expect(find.text(S.deleteDraftQuestion), findsOneWidget);
    expect(drafts.records, isNotEmpty);
    await tester.tap(find.text(S.delete).last);
    await tester.pumpAndSettle();
    expect(drafts.records, isEmpty);
  });

  testWidgets(
    'slow then failed draft loading never shows a false empty state',
    (tester) async {
      final drafts = _ControlledDraftStore()
        ..firstLoad = Completer<List<DraftRecord>>();
      await tester.pumpWidget(
        harness(
          home: const MyReportsScreen(),
          repository: repositoryWith(),
          drafts: drafts,
        ),
      );
      await tester.pump();
      expect(find.text(S.firstReport), findsNothing);

      drafts.firstLoad!.completeError(StateError('read failed'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudieron cargar los borradores.'),
        findsOneWidget,
      );
      expect(find.text(S.firstReport), findsNothing);

      await tester.tap(find.text(S.retry));
      await tester.pumpAndSettle();
      expect(find.text(S.firstReport), findsOneWidget);
    },
  );

  testWidgets(
    'failed draft delete retains its card and queue retry is visible',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final drafts = _ControlledDraftStore()..failDelete = true;
      await drafts.save(_draft('d-error'));
      final outbox = _FailingOutbox([OutboxEntry(draft: _draft('q-error'))]);
      await tester.pumpWidget(
        harness(
          home: const MyReportsScreen(),
          repository: repositoryWith(),
          drafts: drafts,
          outbox: outbox,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(S.storageError), findsOneWidget);
      expect(find.text(S.waitingNetwork), findsOneWidget);

      await tester.tap(find.text(S.deleteDraft));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.delete).last);
      await tester.pumpAndSettle();
      expect(find.text(S.savedDrafts), findsOneWidget);
      expect(find.text(S.storageError), findsWidgets);

      // The failed delete is reported in a snackbar, which temporarily covers
      // the inline queue-persistence retry action.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final retry = find.widgetWithText(TextButton, S.retry).first;
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(outbox.retries, 1);
      expect(find.text(S.storageError), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
