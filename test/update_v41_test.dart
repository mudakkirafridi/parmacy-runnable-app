import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/reports/report_document.dart';
import 'package:pharmacy_hisab/main.dart';

class QueueStore extends AppStore {
  Json server = {};
  bool offline = true, commitThenTimeout = false;
  final committed = <String>[];
  @override
  String get uid => live ? 'offline-owner' : 'demo';
  @override
  Future<dynamic> call(String operation, Json data) async {
    if (offline) throw TimeoutException('Offline');
    if (operation == 'workspace') return clone(server);
    if (operation == 'postEntry') {
      final entry = Json.from(data['entry']);
      if ((server['entries'] as List).any((e) => e['id'] == entry['id'])) {
        return {'repeated': true};
      }
      final result = ledger.post(server['state'], entry);
      server['state'] = result['state'];
      (server['entries'] as List).insert(0, result['entry']);
      committed.add(entry['id']);
      if (commitThenTimeout) {
        commitThenTimeout = false;
        offline = true;
        throw TimeoutException('Response lost after commit');
      }
      return {'id': entry['id']};
    }
    if (operation == 'reverseEntry') {
      if ((server['entries'] as List).any((e) => e['id'] == data['id'])) {
        return {'repeated': true};
      }
      final original = (server['entries'] as List).firstWhere(
        (e) => e['id'] == data['original'],
      );
      final result = ledger.reverse(server['state'], Json.from(original), data);
      server['state'] = result['state'];
      original['reversedBy'] = data['id'];
      (server['entries'] as List).insert(0, result['entry']);
      return {'id': data['id']};
    }
    if (operation == 'saveProfile') return {'ok': true};
    throw StateError('Unsupported test operation $operation');
  }

  Future<void> prepare() async {
    await init();
    server = clone(snapshot());
    server['allowed'] = [
      'sales',
      'expenses',
      'suppliers',
      'salary',
      'loans',
      'cashbook',
    ];
    final cached = clone(server);
    await connect('queue', refreshNow: false);
    restore(cached);
    await persist();
  }
}

Json expense(String id, int amount) => {
  'id': id,
  'type': 'expense',
  'date': today(),
  'account': 'cash',
  'amount': amount,
  'category': 'Tea',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'financial entry saves offline, survives restart, syncs once, and reversal queues',
    () async {
      final a = QueueStore();
      await a.prepare();
      final before = a.balance('money:cash');
      await a.submit(expense('offline-expense', 12000));
      await a.syncUploads();
      expect(a.balance('money:cash'), before - 12000);
      expect(a.pendingCount, 1);
      expect(a.server['entries'].length, a.entries.length - 1);
      final b = QueueStore();
      b.server = clone(a.server);
      await b.init();
      await b.connect('queue', refreshNow: false);
      expect(b.pendingCount, 1);
      expect(b.balance('money:cash'), before - 12000);
      b.offline = false;
      await b.syncUploads();
      await b.refresh();
      expect(b.pendingCount, 0);
      expect(b.committed, ['offline-expense']);
      expect(b.balance('money:cash'), before - 12000);
      await b.submit(expense('offline-expense', 12000));
      expect(b.committed.length, 1);
      b.offline = true;
      await b.reverseEntry(
        b.entries.firstWhere((e) => e['id'] == 'offline-expense'),
        '',
        today(),
      );
      await b.syncUploads();
      expect(b.balance('money:cash'), before);
      expect(b.pendingCount, 1);
      b.offline = false;
      await b.syncUploads();
      await b.refresh();
      expect(b.pendingCount, 0);
      expect(b.balance('money:cash'), before);
      a.dispose();
      b.dispose();
    },
  );
  test(
    'unknown commit response retries same id without double money effect',
    () async {
      final a = QueueStore();
      await a.prepare();
      a.offline = false;
      a.commitThenTimeout = true;
      final before = a.balance('money:cash');
      await a.submit(expense('unknown', 50000));
      await a.syncUploads();
      expect(a.pendingCount, 1);
      expect(a.committed, ['unknown']);
      a.offline = false;
      await a.syncUploads();
      await a.refresh();
      expect(a.pendingCount, 0);
      expect(a.committed, ['unknown']);
      expect(a.balance('money:cash'), before - 50000);
      a.dispose();
    },
  );
  test(
    'server conflict remains reviewable and rejected effects do not inflate balances',
    () async {
      final a = QueueStore();
      await a.prepare();
      final serverSale = {
        'id': 'other-device-sale',
        'type': 'daily_sales',
        'date': today(),
        'amount': 500000,
      };
      final posted = a.ledger.post(a.server['state'], serverSale);
      a.server['state'] = posted['state'];
      (a.server['entries'] as List).insert(0, posted['entry']);
      await a.submit({
        'id': 'local-sale',
        'type': 'daily_sales',
        'date': today(),
        'amount': 900000,
      });
      await a.syncUploads();
      a.offline = false;
      await a.syncUploads();
      await a.refresh();
      expect(a.uploadIssues.length, 1);
      expect(a.entries.where((e) => e['id'] == 'local-sale'), isEmpty);
      expect(a.entries.where((e) => e['id'] == 'other-device-sale').length, 1);
      await a.discardFailedUpload('local-sale');
      expect(a.uploadIssues, isEmpty);
      expect(a.pendingCount, 0);
      a.dispose();
    },
  );
  test(
    'FIFO automatically pays five bills with safe three-allocation server chunks',
    () async {
      final a = AppStore();
      await a.init();
      a.entries = [];
      a.state = a.ledger.empty();
      for (var n = 1; n <= 5; n++) {
        await a.submit({
          'id': 'b$n',
          'type': 'supplier_bill',
          'party': 'khan',
          'reference': '$n',
          'date': '2026-10-${n.toString().padLeft(2, '0')}',
          'amount': 100000,
        });
      }
      final allocations = a.allocateOldest('suppliers', 'khan', 450000);
      expect(allocations.map((a) => a['id']), ['b1', 'b2', 'b3', 'b4', 'b5']);
      expect(allocations.last['amount'], 50000);
      final x = {
        'id': 'five-pay',
        'type': 'supplier_payment',
        'party': 'khan',
        'account': 'cash',
        'date': today(),
        'amount': 450000,
        'allocations': allocations,
      };
      await a.submit(x);
      expect(a.balance('supplier:khan'), -50000);
      expect(a.balance('money:cash'), -450000);
      expect(a.entries.where((e) => e['type'] == 'supplier_payment').length, 2);
      expect(
        a.entries
            .where((e) => e['type'] == 'supplier_payment')
            .every((e) => (e['allocations'] as List).length <= 3),
        true,
      );
      await a.submit(x);
      expect(a.balance('money:cash'), -450000);
      expect(
        a
            .bills('suppliers', 'khan')
            .where((b) => b['remaining'] > 0)
            .single['id'],
        'b5',
      );
    },
  );
  test(
    'unique spelling gets 02 suffix and legacy duplicate ids/names do not duplicate loan people',
    () async {
      final a = AppStore();
      await a.init();
      await a.saveProfile({
        'id': 'a',
        'module': 'loans',
        'name': 'Abbas',
        'active': true,
      });
      await a.saveProfile({
        'id': 'b',
        'module': 'loans',
        'name': ' Abbas ',
        'active': true,
      });
      await a.saveProfile({
        'id': 'c',
        'module': 'loans',
        'name': 'abbas',
        'active': true,
      });
      expect(a.name('b'), 'Abbas02');
      expect(a.name('c'), 'abbas03');
      final cached = clone(a.snapshot());
      cached['profiles'] = [
        {'id': 'p1', 'name': 'Customer 02', 'module': 'loans', 'active': true},
        {'id': 'p2', 'name': 'Customer 02', 'module': 'loans', 'active': true},
        {'id': 'p1', 'name': 'Customer 02', 'module': 'loans', 'active': true},
      ];
      a.restore(cached);
      expect(a.profiles.length, 2);
      expect(a.profiles.map((p) => p['name']).toSet().length, 2);
      a.state = a.ledger.empty();
      a.entries = [];
      for (final x in [
        {'id': 'l', 'type': 'loan_lend', 'amount': 500000},
        {'id': 'r', 'type': 'loan_collect', 'amount': 100000},
      ]) {
        await a.submit({
          ...x,
          'party': 'p1',
          'date': today(),
          'account': 'cash',
        });
      }
      final report = buildReportData(
        a,
        a.entries,
        '2000-01-01',
        today(),
        'Loan report',
        module: 'loans',
      );
      expect(report.rows.length, 1);
      expect(report.rows.single, [
        'Customer 02',
        'Rs 5,000',
        'Rs 1,000',
        'Rs 4,000',
      ]);
      expect(report.personIds, ['p1']);
    },
  );
  test(
    'legacy duplicate keeps the name of the profile with financial history',
    () async {
      final a = AppStore();
      await a.init();
      final copy = clone(a.snapshot());
      copy['profiles'] = [
        {
          'id': 'a-unused',
          'module': 'loans',
          'name': 'customer 02',
          'active': true,
        },
        {
          'id': 'z-used',
          'module': 'loans',
          'name': 'customer 02',
          'active': true,
        },
      ];
      copy['entries'] = [
        {
          'id': 'history',
          'party': 'z-used',
          'type': 'loan_lend',
          'module': 'loans',
          'amount': 10000,
          'date': today(),
          'effects': {'loanAsset:z-used': 10000, 'money:cash': -10000},
        },
      ];
      a.restore(copy);
      expect(a.name('z-used'), 'customer 02');
      expect(a.name('a-unused'), 'customer 03');
      expect(a.entries.single['party'], 'z-used');
    },
  );

  testWidgets(
    'register footer stays fixed after scrolling; sale/expense open directly and reports respect sharing choice',
    (tester) async {
      tester.view.physicalSize = const Size(390, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = AppStore();
      await tester.runAsync(a.init);
      for (var i = 0; i < 45; i++) {
        final x = a.ledger.post(a.state, expense('scroll-$i', 100));
        a.state = x['state'];
        a.entries.add(x['entry']);
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => a)],
          child: const HisabApp(),
        ),
      );
      for (final module in [
        'salary',
        'loans',
        'expenses',
        'cashbook',
        'suppliers',
        'sales',
        'zakat',
        'orders',
        'owner',
      ]) {
        router.go('/register/$module');
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('register-add-entry'));
        expect(button, findsOneWidget);
        final position = tester.getRect(button);
        expect(position.bottom, lessThanOrEqualTo(850));
        await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
        await tester.pumpAndSettle();
        expect(tester.getRect(button), position);
      }
      router.go('/register/sales');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register-add-entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('net-daily-sale')), findsOneWidget);
      router.go('/register/expenses');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register-add-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Record expense'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      router.go('/reports?module=all');
      await tester.pumpAndSettle();
      expect(find.text('Share picture'), findsNothing);
      expect(find.text('Share PDF'), findsOneWidget);
      router.go('/reports?module=loans');
      await tester.pumpAndSettle();
      expect(find.text('Share picture'), findsOneWidget);
      router.go('/more');
      await tester.pumpAndSettle();
      expect(find.text('Synced'), findsNothing);
      expect(find.text('Production sign in'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
