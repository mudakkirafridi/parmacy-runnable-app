import 'package:pharmacy_hisab/core/bilingual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/core/committee.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/features/reports/export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppStore> fresh() async {
    final a = AppStore();
    await a.init();
    a.entries.clear();
    a.profiles.clear();
    a.state = a.ledger.empty();
    return a;
  }

  test(
    'cash and bank account for sales, spending, loan recovery, owners and committee without counting bills as cash',
    () async {
      final a = await fresh();
      Future<void> post(
        String type,
        int amount, {
        String account = 'cash',
        String party = '',
        String? category,
      }) => a.submit({
        'id': 'e${a.entries.length}',
        'type': type,
        'date': today(),
        'amount': amount * 100,
        'account': account,
        'party': party,
        'reference': 'bill1',
        'category': ?category,
      });
      await post('opening_cash', 10000);
      await post('opening_cash', 5000, account: 'bank');
      await post('daily_sale_cash', 3000); // cash 13,000
      await post('expense', 1000, category: 'Rent'); // cash 12,000
      await post(
        'expense',
        500,
        account: 'bank',
        category: 'Lunch',
      ); // bank 4,500
      await post('loan_lend', 2000, party: 'ali');
      await post('loan_collect', 1000, party: 'ali'); // cash 11,000
      final owner = a.owners.first['id'] as String;
      await post('capital', 4000, party: owner);
      await post(
        'withdrawal',
        500,
        account: 'bank',
        party: owner,
      ); // cash15,000 bank4,000
      await post('committee_pay', 1000, party: 'committee');
      await post(
        'committee_receive',
        6000,
        account: 'bank',
        party: 'committee',
      ); // cash14,000 bank10,000
      await post('supplier_bill', 2000, party: 'company'); // no cash movement
      await a.submit({
        'id': 'payment',
        'type': 'supplier_payment',
        'party': 'company',
        'account': 'bank',
        'date': today(),
        'amount': 100000,
        'allocations': a.allocateOldest('suppliers', 'company', 100000),
      });
      expect(a.balance('money:cash'), 1400000);
      expect(a.balance('money:bank'), 900000);
      expect(a.balance('supplier:company'), -100000);
      expect(loanTotal(a.state['balances']), 100000);
      final bankExpense = a.entries.firstWhere(
        (e) => e['type'] == 'expense' && e['account'] == 'bank',
      );
      await a.reverseEntry(bankExpense, 'Entry removed', today());
      expect(a.balance('money:bank'), 950000);
      expect(a.balance('money:cash'), 1400000);
    },
  );
  test(
    'new daily sale shares uniqueness with old records and edits/reverses cash exactly once',
    () async {
      final a = await fresh();
      await a.submit({
        'id': 'sale',
        'type': 'daily_sale_cash',
        'date': today(),
        'amount': 1000000,
        'account': 'bank',
      });
      expect(a.balance('money:bank'), 1000000);
      expect(
        () => a.ledger.post(a.state, {
          'id': 'old',
          'type': 'daily_sales',
          'date': today(),
          'amount': 1,
        }),
        throwsStateError,
      );
      final e = a.entries.first;
      await a.correctExpense(
        e,
        a.replacementInput(
          e,
          amount: 500000,
          date: today(),
          reference: '',
          notes: '',
          account: 'bank',
          party: '',
          category: 'Expense',
        ),
        'Entry edited',
      );
      expect(a.balance('money:bank'), 500000);
      expect(a.netSalesTotal, 500000);
      final current = a.entries.firstWhere(
        (e) => e['type'] == 'daily_sale_cash' && e['reversedBy'] == null,
      );
      await a.reverseEntry(current, 'Entry removed', today());
      expect(a.balance('money:bank'), 0);
      expect(a.netSalesTotal, 0);
    },
  );
  test(
    'committee payout does not clear unpaid contributions and reversal restores schedule',
    () async {
      final a = await fresh();
      final p = <String, dynamic>{
        'id': 'c',
        'module': 'committee',
        'name': 'Ali committee',
        'totalAmount': 3000000,
        'installmentAmount': 1000000,
        'frequency': 'Monthly',
        'startDate': '2026-01-31',
      };
      a.profiles.add(p);
      CommitteeProgress progress() => CommitteeProgress.from(p, a.entries);
      await a.submit({
        'id': 'q1',
        'type': 'committee_pay',
        'date': '2026-01-31',
        'amount': 1000000,
        'party': 'c',
        'account': 'cash',
      });
      expect(progress().nextDate, '2026-02-28');
      await a.submit({
        'id': 'win',
        'type': 'committee_receive',
        'date': '2026-02-01',
        'amount': 3000000,
        'party': 'c',
        'account': 'bank',
      });
      expect(progress().remaining, 2000000);
      expect(progress().received, 3000000);
      expect(progress().balance, -2000000);
      await a.submit({
        'id': 'q2',
        'type': 'committee_pay',
        'date': '2026-02-28',
        'amount': 500000,
        'party': 'c',
        'account': 'cash',
      });
      expect(progress().nextDate, '2026-02-28');
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'q2'),
        'Entry removed',
        today(),
      );
      expect(progress().paid, 1000000);
      expect(progress().remaining, 2000000);
      p['frequency'] = 'Weekly';
      expect(progress().nextDate, '2026-02-07');
      p['frequency'] = 'Daily';
      expect(progress().nextDate, '2026-02-01');
      final report = buildReportData(
        a,
        a.entries.where((e) => e['module'] == 'committee').toList(),
        '2000-01-01',
        today(),
        'Committee',
        module: 'committee',
        party: 'c',
      );
      expect(report.summary['Remaining'], 'Rs 20,000');
      expect(report.summary['Received'], 'Rs 30,000');
    },
  );
  test(
    'legacy sale stays auditable and actual balance can be set and reversed',
    () async {
      final a = await fresh();
      await a.submit({
        'id': 'legacy',
        'type': 'daily_sales',
        'date': '2026-10-14',
        'amount': 1000000,
      });
      expect(a.balance('money:cash'), 0);
      await a.submit({
        'id': 'count',
        'type': 'balance_in',
        'date': today(),
        'amount': 700000,
        'account': 'cash',
      });
      expect(a.balance('money:cash'), 700000);
      expect(a.netSalesTotal, 1000000);
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'count'),
        'Entry removed',
        today(),
      );
      expect(a.balance('money:cash'), 0);
      expect(a.netSalesTotal, 1000000);
      expect(a.entries.firstWhere((e) => e['id'] == 'legacy')['effects'], {
        'salesControl': 1000000,
        'netSales': -1000000,
      });
    },
  );
  test(
    'committee profile validates amounts and is durable in local storage',
    () async {
      final a = await fresh();
      final p = <String, dynamic>{
        'id': 'plan',
        'module': 'committee',
        'name': 'Ali committee',
        'totalAmount': 3000000,
        'installmentAmount': 100000,
        'frequency': 'Weekly',
        'startDate': today(),
        'active': true,
      };
      await expectLater(
        a.saveProfile({...p, 'installmentAmount': 4000000}),
        throwsStateError,
      );
      await a.saveProfile(p);
      expect(a.people('committee').single['frequency'], 'Weekly');
      final b = AppStore();
      await b.init();
      expect(b.people('committee').single['installmentAmount'], 100000);
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

  Future<void> select(WidgetTester t, String label, String value) async {
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == label,
          )
          .last,
    );
    await t.pumpAndSettle();
    if (find.text(value).evaluate().isEmpty) {
      await t.scrollUntilVisible(
        find.text(value),
        -220,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await t.tap(find.text(value).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'one entry form changes fields and resets person when changing type',
    (t) async {
      final a = (await t.runAsync(fresh))!;
      a.profiles.addAll([
        {
          'id': 'co',
          'module': 'suppliers',
          'name': 'Company A',
          'active': true,
        },
        {'id': 'staff', 'module': 'salary', 'name': 'Ali', 'active': true},
      ]);
      await host(t, a);
      router.go('/entry');
      await t.pumpAndSettle();
      await select(t, bilingual('Entry type'), bilingual('Company bill'));
      expect(find.text(bilingual('Select company')), findsWidgets);
      expect(find.text(bilingual('Bill number')), findsOneWidget);
      await select(t, bilingual('Select company'), 'Company A');
      await select(t, bilingual('Entry type'), bilingual('Salary di'));
      expect(find.text(bilingual('Select staff')), findsWidgets);
      expect(find.text(bilingual('Bill number')), findsNothing);
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<String> &&
                    w.decoration.labelText == bilingual('Select staff'),
              ),
            )
            .initialValue,
        isNull,
      );
      await select(t, bilingual('Entry type'), bilingual('Daily sale'));
      expect(find.text(bilingual('Cash / Bank')), findsOneWidget);
      expect(find.text(bilingual('Select staff')), findsNothing);
      await t.enterText(find.byKey(const Key('notebook-amount')), '2500');
      await t.tap(find.byKey(const Key('notebook-save')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, bilingual('Save')));
      await t.pumpAndSettle();
      expect(a.balance('money:cash'), 250000);
      expect(a.netSalesTotal, 250000);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'reports open All reports with a single selector and profiles use one category form',
    (t) async {
      final a = (await t.runAsync(fresh))!;
      await host(t, a);
      router.go('/reports');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-type-all')), findsOneWidget);
      expect(find.text('Reports & statements'), findsNothing);
      await select(t, bilingual('Report'), bilingual('Committee / Qist'));
      expect(
        find.byKey(const ValueKey('report-type-committee')),
        findsOneWidget,
      );
      router.go('/profiles');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, bilingual('Add profile')));
      await t.pumpAndSettle();
      await select(t, bilingual('Profile type'), bilingual('Committee / Qist'));
      expect(find.text(bilingual('Har qist (Rs)')), findsOneWidget);
      expect(find.text(bilingual('Qist schedule')), findsOneWidget);
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await t.enterText(field(bilingual('Name *')), 'UI committee');
      await t.enterText(field(bilingual('Committee total (Rs)')), '30000');
      await t.enterText(field(bilingual('Har qist (Rs)')), '1000');
      await t.tap(find.widgetWithText(FilledButton, bilingual('Save profile')));
      await t.pumpAndSettle();
      expect(a.people('committee').single['name'], 'UI committee');
      expect(a.people('committee').single['totalAmount'], 3000000);

      expect(t.takeException(), isNull);
    },
  );
}
