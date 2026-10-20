import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/reports/report_document.dart';
import 'package:pharmacy_hisab/main.dart';

class UploadStore extends AppStore {
  final uploads = <Completer<dynamic>>[];
  final sent = <Json>[];
  @override
  String get uid => live ? 'queue-test' : 'demo';
  @override
  Future<dynamic> call(String operation, Json data) {
    if (operation == 'workspace') return Future.error(StateError('offline'));
    sent.add(clone(data));
    final task = Completer<dynamic>();
    uploads.add(task);
    return task.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'local company save returns before upload; restart keeps queue; newer edit survives acknowledgment',
    () async {
      final a = UploadStore();
      await a.init();
      await a.connect('test', refreshNow: false);
      a.member = {'role': 'owner', 'active': true};
      await a.saveProfile({
        'id': 'c',
        'module': 'suppliers',
        'name': 'CareBaby',
        'active': true,
      });
      expect(a.people('suppliers').single['name'], 'CareBaby');
      expect(a.pendingCount, 1);
      expect(a.uploads.single.isCompleted, false);
      final restarted = UploadStore();
      await restarted.init();
      await restarted.connect('test', refreshNow: false);
      expect(restarted.people('suppliers').single['name'], 'CareBaby');
      expect(restarted.pendingCount, 1);
      await a.saveProfile({
        'id': 'c',
        'module': 'suppliers',
        'name': 'CareBaby updated',
        'active': true,
      });
      final sync = a.syncUploads();
      a.uploads.first.complete({'ok': true});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(a.pendingCount, 1);
      expect(a.uploads.length, 2);
      a.uploads.last.complete({'ok': true});
      await sync;
      expect(a.pendingCount, 0);
      expect(a.people('suppliers').single['name'], 'CareBaby updated');
      a.dispose();
      restarted.dispose();
    },
  );
  test(
    'profile bin balance guard, force, restore and purge keep journal and historical name',
    () async {
      final a = AppStore();
      await a.init();
      final p = a.profiles.firstWhere((p) => p['id'] == 'loan');
      final count = a.entries.length, balance = a.balance('loanAsset:loan');
      await expectLater(a.removeProfile(p), throwsStateError);
      await a.removeProfile(p, force: true);
      expect(a.people('loans'), isEmpty);
      expect(a.profiles.firstWhere((p) => p['id'] == 'loan')['visible'], 0);
      await a.restoreProfile(a.profiles.firstWhere((p) => p['id'] == 'loan'));
      expect(a.people('loans').length, 1);
      await a.removeProfile(p, force: true);
      await a.purgeProfile(a.profiles.firstWhere((p) => p['id'] == 'loan'));
      expect(a.entries.length, count);
      expect(a.balance('loanAsset:loan'), balance);
      expect(a.name('loan'), p['name']);
      expect(a.profiles.firstWhere((p) => p['id'] == 'loan')['purged'], true);
    },
  );
  test(
    'ograi has running opening, payment, return and remaining; reversal restores balance',
    () async {
      final a = AppStore();
      await a.init();
      a.entries = [];
      a.state = a.ledger.empty();
      a.profiles = [
        {
          'id': 'care',
          'module': 'suppliers',
          'name': 'CareBaby',
          'active': true,
        },
      ];
      Future<void> post(
        String id,
        String type,
        int amount,
        String date, {
        List<Json> allocations = const [],
      }) => a.submit({
        'id': id,
        'type': type,
        'party': 'care',
        'account': 'cash',
        'date': date,
        'amount': amount,
        'reference': id,
        'allocations': allocations,
      });
      await post('1', 'supplier_bill', 5000000, '2026-10-01');
      await post(
        '2',
        'supplier_payment',
        1000000,
        '2026-10-02',
        allocations: [
          {'id': '1', 'amount': 1000000},
        ],
      );
      await post(
        '3',
        'supplier_payment',
        1000000,
        '2026-10-03',
        allocations: [
          {'id': '1', 'amount': 1000000},
        ],
      );
      await post(
        '4',
        'supplier_return',
        500000,
        '2026-10-04',
        allocations: [
          {'id': '1', 'amount': 500000},
        ],
      );
      final report = buildReportData(
        a,
        a.entries,
        '2000-01-01',
        today(),
        'Ograi',
        module: 'ograi',
        party: 'care',
      );
      expect(report.rows, [
        ['Rs 50,000', 'Rs 10,000', '-', 'Rs 40,000', '2026-10-02'],
        ['Rs 40,000', 'Rs 10,000', '-', 'Rs 30,000', '2026-10-03'],
        ['Rs 30,000', '-', 'Rs 5,000', 'Rs 25,000', '2026-10-04'],
      ]);
      expect(report.summary['Remaining'], 'Rs 25,000');
      expect(a.nextBillNumber('care'), '2');
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == '4'),
        '',
        today(),
      );
      final reversed = buildReportData(
        a,
        a.entries,
        '2000-01-01',
        today(),
        'Ograi',
        module: 'ograi',
        party: 'care',
      );
      expect(reversed.summary['Remaining'], 'Rs 30,000');
      if (const bool.fromEnvironment('WRITE_V4_SAMPLES')) {
        final out = Directory('design/v4');
        await out.create(recursive: true);
        await File(
          '${out.path}/Sample-Ograi.pdf',
        ).writeAsBytes(await buildReportPdf(report));
        await File(
          '${out.path}/Sample-Ograi.png',
        ).writeAsBytes((await buildReportPictures(report)).single);
        final bills = buildReportData(
          a,
          a.entries.where((e) => e['type'] == 'supplier_bill').toList(),
          '2000-01-01',
          today(),
          'Company bills',
          module: 'company_bills',
        );
        await File(
          '${out.path}/Sample-Company-Bills.pdf',
        ).writeAsBytes(await buildReportPdf(bills));
        await File(
          '${out.path}/Sample-Company-Bills.png',
        ).writeAsBytes((await buildReportPictures(bills)).single);
      }
    },
  );
  test('salary uses oldest unpaid periods without allocation UI', () async {
    final a = AppStore();
    await a.init();
    final rows = a.salaryAllocations('staff', 500000);
    expect(rows, [
      {'id': 'salary-month', 'amount': 500000},
    ]);
    expect(() => a.salaryAllocations('staff', 600000), throwsStateError);
  });
  testWidgets(
    'profile add button, salary balance and editable bill number are visible',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = AppStore();
      await tester.runAsync(a.init);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => a)],
          child: const HisabApp(),
        ),
      );
      router.go('/profiles');
      await tester.pumpAndSettle();
      expect(find.text('Add profile'), findsOneWidget);
      await tester.tap(find.text('Add profile'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
      await tester.pumpAndSettle();
      router.go('/entry/salary_payment?party=staff');
      await tester.pumpAndSettle();
      expect(find.text('Remaining salary'), findsOneWidget);
      expect(find.text('Allocate to bill'), findsNothing);
      router.go('/entry/supplier_bill?party=khan');
      await tester.pumpAndSettle();
      expect(find.text('Bill number'), findsOneWidget);
      expect(find.text('Due date'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('entry-reference')),
            )
            .controller!
            .text,
        '1',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
