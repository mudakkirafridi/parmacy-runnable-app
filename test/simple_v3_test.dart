import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/reports/report_document.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';
import 'package:pharmacy_hisab/main.dart';
import 'app_lock_test.dart' as fakes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'legacy six-digit PIN requires verification before migration to four digits',
    () async {
      final vault = fakes.MemoryVault(),
          salt = List<int>.generate(32, (i) => i);
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 10,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode('123456')), nonce: salt);
      vault.values['pharmacy-lock-v2-legacy'] = jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(await key.extractBytes()),
        'iterations': 10,
        'biometric': false,
        'failures': 0,
        'until': 0,
      });
      final lock = AppLockController(
        vault: vault,
        biometrics: fakes.FakeBiometric(),
        iterations: 10,
      );
      await lock.bind('legacy');
      expect(lock.pinLength, 6);
      await expectLater(lock.setup('4321', '4321'), throwsStateError);
      await lock.unlockPin('123456');
      expect(lock.locked, true);
      expect(lock.needsSetup, true);
      await lock.setup('4321', '4321');
      expect(lock.pinLength, 4);
      expect(lock.locked, false);
      await lock.bind('legacy');
      await expectLater(lock.unlockPin('123456'), throwsStateError);
      await lock.unlockPin('4321');
      expect(lock.locked, false);
    },
  );

  test(
    'orders do not change money, receive exactly one bill and reopen on reversal',
    () async {
      final a = AppStore();
      await a.init();
      final cash = a.balance('money:cash'),
          payable = a.balance('supplier:khan');
      final order = {
        'id': 'order-test',
        'party': 'khan',
        'companyName': 'Khan Distributors',
        'staffId': 'staff',
        'staffName': 'Ali',
        'date': today(),
        'amount': 800000,
        'notes': 'TEST medicines',
        'status': 'open',
        'billId': '',
        'billAmount': 0,
      };
      await a.saveOrder(order);
      expect(a.balance('money:cash'), cash);
      expect(a.balance('supplier:khan'), payable);
      final restarted = AppStore();
      await restarted.init();
      expect(restarted.orders.single['id'], 'order-test');
      await restarted.submit({
        'id': 'order-bill',
        'type': 'supplier_bill',
        'orderId': 'order-test',
        'party': 'khan',
        'date': today(),
        'amount': 780000,
        'reference': 'ORDER-B1',
      });
      expect(restarted.orders.single['status'], 'received');
      expect(restarted.balance('supplier:khan'), payable - 780000);
      await expectLater(
        restarted.submit({
          'id': 'duplicate-bill',
          'type': 'supplier_bill',
          'orderId': 'order-test',
          'party': 'khan',
          'date': today(),
          'amount': 780000,
          'reference': 'ORDER-B2',
        }),
        throwsStateError,
      );
      expect(restarted.balance('supplier:khan'), payable - 780000);
      await restarted.reverseEntry(
        restarted.entries.firstWhere((e) => e['id'] == 'order-bill'),
        'Duplicate entry',
        today(),
      );
      expect(restarted.orders.single['status'], 'open');
      expect(restarted.balance('supplier:khan'), payable);
      await restarted.saveOrder({
        ...restarted.orders.single,
        'status': 'cancelled',
      });
      expect(restarted.orders.single['status'], 'cancelled');
    },
  );

  test(
    'staff profile creates one salary period and supports corrected repost after reversal',
    () async {
      final a = AppStore();
      await a.init();
      final profile = {
        'id': 'new-staff',
        'name': 'Ali Khan',
        'module': 'salary',
        'rate': '30000',
        'active': true,
      };
      final cash = a.balance('money:cash'), period = today().substring(0, 7);
      await a.saveStaffProfile(
        profile,
        salaryPeriod: period,
        salaryAmount: 3000000,
      );
      expect(a.balance('salary:new-staff'), -3000000);
      expect(a.balance('money:cash'), cash);
      await expectLater(
        a.saveStaffProfile(
          profile,
          salaryPeriod: period,
          salaryAmount: 3000000,
        ),
        throwsStateError,
      );
      final salary = a.entries.firstWhere((e) => e['party'] == 'new-staff');
      await a.reverseEntry(salary, 'Wrong amount', today());
      await a.saveStaffProfile(
        profile,
        salaryPeriod: period,
        salaryAmount: 2800000,
      );
      expect(a.balance('salary:new-staff'), -2800000);
    },
  );

  test(
    'loan receipts are independent and both directions reverse exactly',
    () async {
      final a = AppStore();
      await a.init();
      a.state = a.ledger.empty();
      a.entries = [];
      await a.submit({
        'id': 'lend',
        'type': 'loan_lend',
        'party': 'person',
        'date': today(),
        'account': 'cash',
        'amount': 100000,
      });
      await a.submit({
        'id': 'repayment',
        'type': 'loan_collect',
        'party': 'person',
        'date': today(),
        'account': 'cash',
        'amount': 50000,
      });
      final lend = a.entries.firstWhere((e) => e['id'] == 'lend');
      await a.reverseEntry(lend, 'Duplicate entry', today());
      expect(a.balance('loanAsset:person'), -50000);
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'repayment'),
        'Duplicate entry',
        today(),
      );
      expect(a.balance('loanAsset:person'), 0);
    },
  );

  testWidgets('four digits wait for Unlock and open the saved session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppStore();
    await tester.runAsync(app.init);
    final lock = AppLockController(
      vault: fakes.MemoryVault(),
      biometrics: fakes.FakeBiometric(),
      iterations: 10,
    );
    await tester.runAsync(() async {
      await lock.bind('demo');
      await lock.setup('1234', '1234');
      lock.lock();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith((ref) => app),
          appLockProvider.overrideWith((ref) => lock),
        ],
        child: const MaterialApp(
          home: AppAccessGate(
            login: _login,
            child: Scaffold(body: Text('Unlocked home')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('unlock-pin')), '123');
    await tester.pump();
    expect(lock.locked, true);
    await tester.enterText(find.byKey(const Key('unlock-pin')), '1234');
    await tester.pumpAndSettle();
    expect(lock.locked, true);
    await tester.tap(find.byKey(const Key('unlock-submit')));
    await tester.pumpAndSettle();
    expect(lock.locked, false);
    expect(find.text('Unlocked home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'simple menus show orders and two loan actions, not removed actions',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppStore();
      await tester.runAsync(app.init);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => app)],
          child: const HisabApp(),
        ),
      );
      router.go('/');
      await tester.pumpAndSettle();
      expect(find.text('Due soon'), findsNothing);
      expect(find.text('Owners & shares'), findsNothing);
      expect(find.text('Financial overview'), findsOneWidget);
      router.go('/registers');
      await tester.pumpAndSettle();
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Zakat companies'), findsNothing);
      router.go('/register/loans');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register-add-entry')));
      await tester.pumpAndSettle();
      for (final label in ['Qarz', 'Qarz wosool']) {
        expect(find.widgetWithText(ListTile, label), findsOneWidget);
      }
      expect(find.text('Opening loan receivable'), findsNothing);
      expect(find.text('Opening loan payable'), findsNothing);
      Navigator.of(tester.element(find.widgetWithText(ListTile, 'Qarz'))).pop();
      await tester.pumpAndSettle();
      router.go('/reports');
      await tester.pumpAndSettle();
      expect(find.text('All reports'), findsOneWidget);
      expect(find.text('Loan reports'), findsOneWidget);
      expect(find.text('Export CSV'), findsNothing);
    },
  );

  testWidgets(
    'staff profile records the actual month due while preserving monthly rate',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppStore();
      await tester.runAsync(app.init);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => app)],
          child: const HisabApp(),
        ),
      );
      router.go('/profiles/salary');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add profile'));
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.enterText(field('Name *'), 'UI Staff');
      await tester.enterText(field('Monthly salary (Rs)'), '30000');
      await tester.enterText(field('Salary due this month (Rs)'), '15000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pumpAndSettle();
      final person = app.profiles.firstWhere((p) => p['name'] == 'UI Staff');
      expect(person['rate'], '30000');
      expect(app.balance('salary:${person['id']}'), -1500000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'receive bill from an order keeps the order link through review and posting',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppStore();
      await tester.runAsync(app.init);
      await tester.runAsync(
        () => app.saveOrder({
          'id': 'ui-order',
          'party': 'khan',
          'companyName': 'Khan Distributors',
          'staffId': 'staff',
          'staffName': 'Ali',
          'date': today(),
          'amount': 800000,
          'notes': 'UI TEST',
          'status': 'open',
          'billId': '',
          'billAmount': 0,
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => app)],
          child: const HisabApp(),
        ),
      );
      router.go('/register/orders');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bill received - add bill'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-reference')),
        'UI-BILL-1',
      );
      await tester.tap(find.text('Review entry').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and post'));
      await tester.pumpAndSettle();
      expect(app.orders.single['status'], 'received');
      expect(
        app.entries.firstWhere((e) => e['reference'] == 'UI-BILL-1')['orderId'],
        'ui-order',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'person statements include opening/closing balances, reversals and shareable files',
    () async {
      final a = AppStore();
      await a.init();
      a.entries = [];
      a.orders = [];
      a.state = a.ledger.empty();
      a.settings['name'] = 'Family Pharmacy - SAMPLE';
      a.profiles = [
        {'id': 'ali', 'name': 'Ali Khan', 'module': 'loans', 'active': true},
        {'id': 'ahmed', 'name': 'Ahmed', 'module': 'loans', 'active': true},
        {
          'id': 'company',
          'name': 'Khan Distributors',
          'module': 'suppliers',
          'active': true,
        },
      ];
      Future<void> post(
        String id,
        String type,
        int amount, {
        String party = 'ali',
        String? date,
        List<Json>? allocations,
      }) => a.submit({
        'id': id,
        'type': type,
        'amount': amount,
        'party': party,
        'date': date ?? today(),
        'account': 'cash',
        'reference': id,
        'allocations': allocations ?? [],
      });
      final earlier = DateTime.parse(
        today(),
      ).subtract(const Duration(days: 2)).toIso8601String().substring(0, 10);
      await post('lend', 'loan_lend', 500000, date: earlier);
      await post('collect', 'loan_collect', 200000);
      await post('duplicate', 'loan_lend', 100000);
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'duplicate'),
        'Duplicate entry',
        today(),
      );
      await post('private-other', 'loan_lend', 900000, party: 'ahmed');
      final rows = a.entries
          .where((e) => e['party'] == 'ali' && e['date'] == today())
          .toList();
      final loan = buildReportData(
        a,
        rows,
        today(),
        today(),
        'Loan statement',
        module: 'loans',
        party: 'ali',
      );
      expect(loan.summary, {'Net balance': 'Rs 3,000'});
      expect(loan.rows.toString(), isNot(contains('Ahmed')));
      expect(loan.note, isEmpty);
      expect(loan.headers, ['Date', 'Lena hai', 'Dena hai']);
      await post('bill', 'supplier_bill', 1000000, party: 'company');
      await post(
        'payment',
        'supplier_payment',
        200000,
        party: 'company',
        allocations: [
          {'id': 'bill', 'amount': 200000},
        ],
      );
      await post(
        'return',
        'supplier_return',
        100000,
        party: 'company',
        allocations: [
          {'id': 'bill', 'amount': 100000},
        ],
      );
      final company = buildReportData(
        a,
        a.entries.where((e) => e['party'] == 'company').toList(),
        today(),
        today(),
        'Supplier statement',
        module: 'suppliers',
        party: 'company',
      );
      expect(company.summary['Remaining payable'], 'Rs 7,000');
      final pdf = await buildReportPdf(loan),
          companyPdf = await buildReportPdf(company);
      expect(utf8.decode(pdf.take(4).toList()), '%PDF');
      expect(utf8.decode(companyPdf.take(4).toList()), '%PDF');
      expect(pdf.length, greaterThan(5000));
      final pictures = await buildReportPictures(loan);
      expect(pictures.length, 1);
      expect(pictures.single.take(4), [137, 80, 78, 71]);
      final longReport = ReportData(
        pharmacy: loan.pharmacy,
        compactLoan: true,
        title: 'Multi-page SAMPLE',
        from: loan.from,
        to: loan.to,
        person: loan.person,
        note: loan.note,
        headers: ['Date', 'Name', 'Lena hai', 'Dena hai'],
        summary: loan.summary,
        rows: List.generate(
          65,
          (i) => [today(), 'Record ${i + 1} - Ali Khan', 'Rs 100', 'Rs 3,000'],
        ),
      );
      final multiPdf = await buildReportPdf(longReport);
      expect(multiPdf.length, greaterThan(pdf.length));
      final twoPictures = await buildReportPictures(
        ReportData(
          pharmacy: loan.pharmacy,
          compactLoan: true,
          title: loan.title,
          from: loan.from,
          to: loan.to,
          person: loan.person,
          note: loan.note,
          headers: longReport.headers,
          summary: loan.summary,
          rows: longReport.rows.take(11).toList(),
        ),
      );
      expect(twoPictures.length, 2);
      if (const bool.fromEnvironment('WRITE_REPORT_SAMPLES')) {
        await Directory('design/report-qa').create(recursive: true);
        await File('design/report-qa/multi-page.pdf').writeAsBytes(multiPdf);
        final out = Directory(
          'C:/Users/mudakkir/Documents/Codex/2026-10-14/in/outputs',
        );
        await post('extra-receipt', 'loan_collect', 400000);
        final sample = buildReportData(
          a,
          a.entries.where((e) => e['party'] == 'ali').toList(),
          earlier,
          today(),
          'Qarz',
          module: 'loans',
          party: 'ali',
        );
        expect(sample.summary['Net balance'], 'Rs -1,000');
        await File(
          '${out.path}/Sample-Loan-Simple.pdf',
        ).writeAsBytes(await buildReportPdf(sample));
        await File(
          '${out.path}/loan-simple-preview.png',
        ).writeAsBytes((await buildReportPictures(sample)).single);
      }
    },
  );
}

Widget _login() => const Text('Login');
