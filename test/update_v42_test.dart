import 'package:pharmacy_hisab/core/bilingual.dart';
import 'dart:async';
import 'update_v41_test.dart' show QueueStore;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/ui/native_credentials.dart';
import 'package:pharmacy_hisab/ui/screens.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/features/reports/report_document.dart';

class InterruptedEditStore extends QueueStore {
  bool pauseEdit = true;
  @override
  Future<dynamic> call(String operation, Json data) async {
    if (operation != 'correctExpense') return super.call(operation, data);
    if (offline) throw TimeoutException('Offline');
    final replacement = Json.from(data['entry']);
    await super.call('reverseEntry', {
      'id': data['reverseId'],
      'original': data['original'],
      'date': replacement['date'],
      'reason': 'Entry edited',
      'editTarget': replacement['id'],
    });
    if (pauseEdit) {
      pauseEdit = false;
      offline = true;
      throw TimeoutException('Interrupted after reversal');
    }
    return super.call('postEntry', {
      'entry': {
        ...replacement,
        'editedFrom': data['original'],
        'editReversal': data['reverseId'],
      },
    });
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppStore> fresh() async {
    final a = AppStore();
    await a.init();
    a.state = a.ledger.empty();
    a.entries = [];
    return a;
  }

  Json entry(String id, String type, int amount, {String party = 'staff'}) => {
    'id': id,
    'type': type,
    'amount': amount,
    'date': today(),
    'party': party,
    'account': 'cash',
    'reference': id,
    'allocations': <Json>[],
  };

  test(
    'native backspace edits never echo setText; old pending edits cannot undo a reset',
    () {
      final controller = TextEditingController();
      final writes = <String>[];
      final session = CredentialTextSession(
        controller,
        (text, epoch) => writes.add('$epoch:$text'),
      );
      for (final value in [
        'sample@321',
        'sample@32',
        'sample@3',
        'sample@',
        'sample@1',
      ]) {
        session.receive(value, 0);
        expect(controller.text, value);
      }
      expect(writes, isEmpty);
      controller.clear();
      expect(writes, ['1:']);
      session.receive('sample@3211', 0);
      expect(controller.text, isEmpty);
      session.receive('replacement', 1);
      expect(controller.text, 'replacement');
      session.receive('', 1);
      session.receive('person@example.con', 1);
      session.receive('person@example.c', 1);
      session.receive('person@example.com', 1);
      expect(controller.text, 'person@example.com');
      expect(writes, ['1:']);
      session.dispose();
      controller.dispose();
    },
  );

  test(
    'salary clears due before advance and reconciles legacy overlapping advances',
    () async {
      final a = await fresh();
      await a.submit(entry('due', 'salary_accrual', 500000));
      await a.submit(entry('pay', 'salary_payment', 1000000));
      expect(a.balance('salary:staff'), 0);
      expect(a.balance('salaryAdvance:staff'), 500000);
      expect(a.salaryDue('staff'), 0);
      expect(a.salaryCredit('staff'), 500000);
      expect(a.balance('money:cash'), -1000000);
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'pay-advance'),
        'Entry removed',
        today(),
      );
      expect(a.salaryCredit('staff'), 0);
      // Old releases allowed separate outstanding salary and unused advance.
      await a.submit(entry('due2', 'salary_accrual', 500000));
      final legacy = a.ledger.post(
        a.state,
        entry('legacy', 'salary_advance', 1000000),
      );
      a.state = legacy['state'];
      a.entries.insert(0, legacy['entry']);
      expect(a.salaryDue('staff'), 0);
      expect(a.salaryCredit('staff'), 500000);
      await a.submit(entry('pay2', 'salary_payment', 100000));
      expect(a.balance('salary:staff'), 0);
      expect(a.salaryCredit('staff'), 600000);
      expect(a.balance('money:cash'), -1600000);
      a.dispose();
    },
  );

  test(
    'editing bill, payment, loan and sale applies only the net change and supports later reversal',
    () async {
      final a = await fresh();
      Future<Json> edit(String id, int amount) async {
        final original = a.entries.firstWhere((e) => e['id'] == id);
        final next = a.replacementInput(
          original,
          amount: amount,
          date: today(),
          reference: original['reference'] ?? '',
          notes: 'updated',
          account: 'cash',
          party: original['party'] ?? '',
          category: original['category'] ?? 'Expense',
        );
        await a.correctExpense(original, next, 'Entry edited');
        return a.entries.firstWhere((e) => e['id'] == next['id']);
      }

      await a.submit(entry('bill', 'supplier_bill', 1000000, party: 'co'));
      final bill = await edit('bill', 500000);
      expect(a.balance('supplier:co'), -500000);
      await a.submit({
        ...entry('payment', 'supplier_payment', 200000, party: 'co'),
        'allocations': [
          {'id': bill['id'], 'amount': 200000},
        ],
      });
      final payment = await edit('payment', 100000);
      expect(a.balance('supplier:co'), -400000);
      expect(a.balance('money:cash'), -100000);
      await a.reverseEntry(payment, 'Entry removed', today());
      expect(a.balance('supplier:co'), -500000);
      expect(a.balance('money:cash'), 0);
      await a.submit(entry('loan', 'loan_lend', 1000000));
      await edit('loan', 500000);
      expect(a.balance('loanAsset:staff'), 500000);
      await a.submit(entry('sale', 'daily_sales', 1000000, party: ''));
      await edit('sale', 500000);
      expect(a.balance('netSales'), -500000);
      a.dispose();
    },
  );

  test(
    'an interrupted multi-bill edit rebases and retries without reversing or paying twice',
    () async {
      final a = InterruptedEditStore();
      await a.prepare();
      a.state = a.ledger.empty();
      a.entries = [];
      a.server = clone(a.snapshot());
      for (var n = 1; n <= 3; n++) {
        await a.submit(entry('b$n', 'supplier_bill', 100000, party: 'co'));
      }
      await a.submit({
        ...entry('p', 'supplier_payment', 250000, party: 'co'),
        'allocations': [
          {'id': 'b1', 'amount': 100000},
          {'id': 'b2', 'amount': 100000},
          {'id': 'b3', 'amount': 50000},
        ],
      });
      a.offline = false;
      await a.syncUploads();
      final original = a.entries.firstWhere((e) => e['id'] == 'p');
      final replacement = a.replacementInput(
        original,
        amount: 150000,
        date: today(),
        reference: 'p',
        notes: '',
        account: 'cash',
        party: 'co',
        category: 'Expense',
      );
      await a.correctExpense(original, replacement, 'Entry edited');
      await a.syncUploads();
      expect(
        (a.server['entries'] as List).any((e) => e['id'] == 'reverse-p'),
        true,
      );
      expect(
        (a.server['entries'] as List).any((e) => e['id'] == replacement['id']),
        false,
      );
      a.offline = false;
      await a.refresh();
      expect(a.balance('supplier:co'), -150000);
      expect(a.balance('money:cash'), -150000);
      await a.syncUploads();
      expect(a.pendingUploads, isEmpty);
      expect(a.balance('money:cash'), -150000);
      expect(
        (a.server['entries'] as List).where(
          (e) => e['id'] == replacement['id'],
        ),
        hasLength(1),
      );
      expect(
        a.entryVisible(a.entries.firstWhere((e) => e['id'] == 'p')),
        false,
      );
      a.dispose();
    },
  );

  testWidgets(
    'reversed detail is readable, active entry has Edit then Reverse, Home lists companies',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = AppStore();
      await tester.runAsync(a.init);
      await tester.runAsync(
        () => a.submit({
          'id': 'expense42',
          'type': 'expense',
          'amount': 50000,
          'date': today(),
          'account': 'cash',
          'category': 'Tea',
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => a)],
          child: const HisabApp(),
        ),
      );
      router.go('/');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(bilingual('Companies')), 400);
      await tester.pumpAndSettle();
      expect(find.text('All bills'), findsNothing);
      expect(find.text(bilingual('Companies')), findsOneWidget);
      await tester.ensureVisible(find.text('Khan Distributors').last);
      await tester.tap(find.text('Khan Distributors').last);
      await tester.pumpAndSettle();
      expect(
        find.text(bilingual('Pay company / Ograi report')),
        findsOneWidget,
      );
      expect(find.text(bilingual('Pay company / Ograi')), findsWidgets);
      Navigator.of(
        tester.element(find.text(bilingual('Pay company / Ograi report'))),
      ).pop();
      await tester.pumpAndSettle();
      final e = a.entries.firstWhere((e) => e['type'] == 'expense');
      final context = tester.element(find.byType(HomeScreen));
      entryDetails(context, a, e);
      await tester.pumpAndSettle();
      expect(find.text(bilingual('Edit')), findsOneWidget);
      expect(find.text(bilingual('Remove / reverse entry')), findsOneWidget);
      Navigator.of(tester.element(find.text(bilingual('Edit')))).pop();
      await tester.pumpAndSettle();
      await tester.runAsync(() => a.reverseEntry(e, 'Entry removed', today()));
      await tester.pumpAndSettle();
      final rev = a.entries.firstWhere((x) => x['id'] == e['reversedBy']);
      entryDetails(context, a, rev);
      await tester.pumpAndSettle();
      expect(find.textContaining('Reversal ·'), findsOneWidget);
      expect(find.text(rev['reference']), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Ograi includes same-day company bills and reversed bills carry a red-status label',
    () async {
      final a = await fresh();
      await a.submit(entry('b1', 'supplier_bill', 500000, party: 'co'));
      await a.submit(entry('b2', 'supplier_bill', 300000, party: 'co'));
      await a.submit({
        ...entry('p1', 'supplier_payment', 100000, party: 'co'),
        'allocations': [
          {'id': 'b1', 'amount': 100000},
        ],
      });
      final d = buildReportData(
        a,
        a.entries,
        '2000-01-01',
        today(),
        'Ograi',
        module: 'ograi',
        party: 'co',
      );
      expect(d.headers.first, 'Day bills');
      expect(d.rows.single.first, 'Rs 8,000');
      await a.reverseEntry(
        a.entries.firstWhere((e) => e['id'] == 'b2'),
        'Entry removed',
        today(),
      );
      final bills = buildReportData(
        a,
        a.entries.where((e) => e['type'] == 'supplier_bill').toList(),
        '2000-01-01',
        today(),
        'Bills',
        module: 'company_bills',
      );
      expect(bills.rows.any((r) => r[1].contains('Reversed')), true);
      expect(negativeMoney('Reversed · Rs 3,000'), true);
      a.dispose();
    },
  );
}
