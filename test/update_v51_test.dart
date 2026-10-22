import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/core/bilingual.dart';
import 'package:pharmacy_hisab/features/reports/export.dart';
import 'package:pharmacy_hisab/ui/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppStore> setup() async {
    final a = AppStore();
    await a.init();
    a.entries.clear();
    a.profiles.clear();
    a.state = a.ledger.empty();
    await a.saveProfile({
      'id': 'plan',
      'module': 'committee',
      'name': 'Ali',
      'active': true,
      'totalAmount': 3000000,
      'installmentAmount': 100000,
      'frequency': 'Daily',
      'startDate': '2026-10-18',
    });
    return a;
  }

  Future<void> post(
    AppStore a,
    String id,
    String type,
    String date,
    int amount,
  ) => a.submit({
    'id': id,
    'type': type,
    'date': date,
    'party': 'plan',
    'account': 'cash',
    'amount': amount,
  });
  test(
    'installment table carries target balance, paid amount and remaining; receipts do not cancel unpaid installments',
    () async {
      final a = await setup();
      await post(a, 'p1', 'committee_pay', '2026-10-18', 100000);
      await post(a, 'p2', 'committee_pay', '2026-10-19', 200000);
      await post(a, 'income', 'committee_receive', '2026-10-20', 3000000);
      ReportData report() => buildReportData(
        a,
        a.entries,
        '2000-01-01',
        today(),
        'Installment',
        module: 'committee',
        party: 'plan',
      );
      var d = report();
      expect(d.headers, ['Balance', 'Paid', 'Received', 'Remaining', 'Date']);
      expect(d.rows[0], [
        'Rs 30,000',
        'Rs 1,000',
        '-',
        'Rs 29,000',
        '2026-10-18',
      ]);
      expect(d.rows[1], [
        'Rs 29,000',
        'Rs 2,000',
        '-',
        'Rs 27,000',
        '2026-10-19',
      ]);
      expect(d.rows[2], [
        'Rs 27,000',
        '-',
        'Rs 30,000',
        'Rs 27,000',
        '2026-10-20',
      ]);
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'p2'),
        'Entry removed',
        today(),
      );
      d = report();
      expect(d.rows.last[1], 'Rs -2,000');
      expect(d.rows.last[3], 'Rs 29,000');
      expect(d.summary['Remaining'], 'Rs 29,000');
      expect(latestReportData(d).recordIds.first, 'reverse-p2');
      expect(d.headers.any((s) => s.toLowerCase().contains('day')), false);
    },
  );
  test('financial labels use only the selected language', () async {
    final a = await setup();
    for (final type in [
      'committee_pay',
      'committee_receive',
      'loan_lend',
      'loan_collect',
      'expense',
      'capital',
      'withdrawal',
    ]) {
      a.ur = false;
      final en = a.typeLabel(type);
      a.ur = true;
      expect(a.typeLabel(type), urduLabels[entryNames[type]]);
      expect(RegExp(r'[\u0600-\u06ff]').hasMatch(en), false);
      expect(RegExp(r'[A-Za-z]').hasMatch(a.typeLabel(type)), false);
    }
    expect(bilingual('Committee / Qist'), 'Installment');
    expect(bilingual('Qarz wosool'), 'Loan received');
    expect(localizedLabel('Installment / قسط'), 'Installment');
    expect(localizedLabel('Installment / قسط', urdu: true), 'قسط');
    expect(a.tr('قسط'), 'قسط');
  });
  test(
    'report day headings handle Today, Yesterday and weekday without changing export data',
    () {
      expect(
        reportDayLabel('2026-10-21', currentDate: '2026-10-21'),
        contains('Today'),
      );
      expect(
        reportDayLabel('2026-10-20', currentDate: '2026-10-21'),
        contains('Yesterday'),
      );
      expect(
        reportDayLabel('2026-10-19', currentDate: '2026-10-21'),
        contains('Monday'),
      );
      expect(
        reportDayLabel('2026-10-21', currentDate: '2026-10-21', urdu: true),
        startsWith('آج · بدھ'),
      );
    },
  );
  Future<void> host(WidgetTester t, AppStore a) async {
    t.view.physicalSize = const Size(430, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => a)],
        child: const HisabApp(),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'Home and common entry switch language without mixed product labels',
    (t) async {
      final a = (await t.runAsync(setup))!;
      await host(t, a);
      router.go('/');
      await t.pumpAndSettle();
      expect(find.text('New entry'), findsOneWidget);
      expect(find.text('New profile'), findsOneWidget);
      expect(find.text('Cash balance'), findsOneWidget);
      a.toggleLanguage();
      await t.pumpAndSettle();
      expect(find.text('نیا اندراج'), findsOneWidget);
      expect(find.text('نیا پروفائل'), findsOneWidget);
      expect(find.text('نقد بیلنس'), findsOneWidget);
      expect(find.text('New entry'), findsNothing);
      router.go('/entry?type=committee_pay');
      await t.pumpAndSettle();
      expect(find.text('قسط ادا کی'), findsWidgets);
      expect(find.text('Installment paid'), findsNothing);
      final form = t.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('notebook-type-committee_pay')),
      );
      expect(form.decoration.labelText, 'اندراج کی قسم');
      a.toggleLanguage();
      await t.pumpAndSettle();
      expect(find.text('Installment paid'), findsWidgets);
      expect(find.text('قسط ادا کی'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'export labels capture the chosen language and preserve row data',
    () async {
      final a = await setup();
      await post(a, 'language-payment', 'committee_pay', '2026-10-21', 100000);
      final en = buildReportData(
        a,
        a.entries,
        '',
        '',
        'Installment',
        module: 'committee',
      );
      a.ur = true;
      final ur = buildReportData(
        a,
        a.entries,
        '',
        '',
        'Installment',
        module: 'committee',
      );
      expect(en.label(en.title), 'Installment');
      expect(ur.label(ur.title), 'قسط');
      expect(en.label('Remaining'), 'Remaining');
      expect(ur.label('Remaining'), 'بقایا');
      expect(ur.rows, en.rows);
      expect(latestReportData(ur).urdu, true);
      expect(latestReportData(en).urdu, false);
    },
  );
  testWidgets(
    'Home has two management actions and three navigation tabs, with no register or quick-entry menu',
    (t) async {
      final a = (await t.runAsync(setup))!;
      await host(t, a);
      router.go('/');
      await t.pumpAndSettle();
      final bar = t.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bar.items.length, 3);
      expect(bar.items.map((i) => i.label), [
        bilingual('Home'),
        bilingual('Reports'),
        bilingual('More'),
      ]);
      expect(find.text('Registers'), findsNothing);
      expect(find.text('Quick entry'), findsNothing);
      await t.tap(find.text(bilingual('New profile')));
      await t.pumpAndSettle();
      expect(router.state.uri.path, '/profiles');
      expect(find.text(bilingual('All profiles')), findsOneWidget);
      router.go('/registers');
      await t.pumpAndSettle();
      expect(router.state.uri.path, '/');
    },
  );
  testWidgets(
    'day headings occur once per date and report rows still open their matching entry',
    (t) async {
      final a = (await t.runAsync(setup))!;
      await t.runAsync(() async {
        await post(a, 'p1', 'committee_pay', today(), 100000);
        await post(a, 'p2', 'committee_pay', today(), 100000);
      });
      await host(t, a);
      router.go('/reports?module=committee&party=plan');
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).first, const Offset(0, -700));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey('day-heading-${today()}')), findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
      expect(find.text(bilingual('Balance')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'orders can be received as company bills from Reports without a register menu',
    (t) async {
      final a = (await t.runAsync(setup))!;
      await t.runAsync(() async {
        await a.saveProfile({
          'id': 'co',
          'module': 'suppliers',
          'name': 'Test Company',
          'active': true,
        });
        await a.saveOrder({
          'id': 'order51',
          'party': 'co',
          'companyName': 'Test Company',
          'staffId': 'manual-ali',
          'staffName': 'Ali',
          'date': today(),
          'amount': 800000,
          'notes': '',
          'status': 'open',
        });
      });
      await host(t, a);
      router.go('/reports?module=orders');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Test Company').last,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Test Company').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Receive bill'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notebook-type-supplier_bill')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('notebook-save')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, bilingual('Save')));
      await t.pumpAndSettle();
      expect(a.orders.single['status'], 'received');
      expect(a.balance('supplier:co'), -800000);
      expect(a.balance('money:cash'), 0);
      expect(t.takeException(), isNull);
    },
  );
}
