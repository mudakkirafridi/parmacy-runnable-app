import 'package:pharmacy_hisab/core/bilingual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/reports/report_document.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';
import 'package:pharmacy_hisab/ui/screens.dart';
import 'package:pharmacy_hisab/main.dart';
import 'login_sync_test.dart' as fixtures;

class ImmediateStore extends fixtures.RemoteStore {
  @override
  Future<dynamic> call(String name, Json data) async {
    if (name == 'workspace') return workspace('ready')..['entries'] = [];
    throw StateError('Unexpected operation $name');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(430, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<AppStore> fresh() async {
    final a = AppStore();
    await a.init();
    a.state = a.ledger.empty();
    a.entries = [];
    return a;
  }

  Json input(
    String id,
    String type,
    int amount,
    String date, {
    String party = '',
  }) => {
    'id': id,
    'type': type,
    'amount': amount,
    'date': date,
    'party': party,
    'account': 'cash',
    'reference': id,
    'allocations': <Json>[],
  };
  Future<void> tap(WidgetTester t, String text) async {
    final f = find.widgetWithText(FilledButton, text);
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  test(
    'daily bill totals occur once per company/day in exports and first displayed row in app',
    () async {
      final a = await fresh();
      await a.submit(
        input('bill14', 'supplier_bill', 8000000, '2026-10-14', party: 'khan'),
      );
      for (final id in ['pay14a', 'pay14b']) {
        await a.submit({
          ...input(
            id,
            'supplier_payment',
            1000000,
            '2026-10-14',
            party: 'khan',
          ),
          'allocations': [
            {'id': 'bill14', 'amount': 1000000},
          ],
        });
      }
      await a.submit(
        input('bill20', 'supplier_bill', 6000000, '2026-10-20', party: 'khan'),
      );
      for (final id in ['pay20a', 'pay20b']) {
        await a.submit({
          ...input(
            id,
            'supplier_payment',
            1000000,
            '2026-10-20',
            party: 'khan',
          ),
          'allocations': [
            {'id': 'bill14', 'amount': 1000000},
          ],
        });
      }
      final report = buildReportData(
        a,
        a.entries,
        '2000-01-01',
        today(),
        'Ograi',
        module: 'ograi',
        party: 'khan',
      );
      expect(report.rows.map((r) => r[0]), [
        'Rs 80,000',
        '-',
        'Rs 60,000',
        '-',
      ]);
      final display = latestReportData(report);
      expect(display.rows.map((r) => r[0]), [
        'Rs 60,000',
        '-',
        'Rs 80,000',
        '-',
      ]);
      expect(display.recordIds.first, 'pay20b');
      expect(report.recordIds.first, 'pay14a');
      expect(report.rows.map((r) => r.last), [
        '2026-10-14',
        '2026-10-14',
        '2026-10-20',
        '2026-10-20',
      ]);
      a.dispose();
    },
  );

  test(
    'All reports has only pharmacy-wide remaining loan, salary and company totals',
    () async {
      final a = await fresh();
      await a.submit(
        input('loan', 'loan_lend', 200000, '2026-10-20', party: 'loan'),
      );
      await a.submit(
        input('salary', 'salary_accrual', 500000, '2026-10-20', party: 'staff'),
      );
      await a.submit(
        input('bill', 'supplier_bill', 800000, '2026-10-20', party: 'khan'),
      );
      final report = buildReportData(
        a,
        [],
        '2026-10-14',
        '2026-10-14',
        'All reports',
        module: 'all',
      );
      expect(report.summary, {
        'Qarz baqaya': 'Rs 2,000',
        'Remaining salary': 'Rs 5,000',
        'Remaining company payments': 'Rs 8,000',
      });
      a.dispose();
    },
  );

  test(
    'daily sale edit preserves its transaction identity and label',
    () async {
      final a = await fresh();
      await a.submit(input('sale', 'daily_sales', 1000000, '2026-10-20'));
      final source = a.entries.single;
      final replacement = a.replacementInput(
        source,
        amount: 500000,
        date: '2026-10-20',
        reference: 'sale',
        notes: '',
        account: 'cash',
        party: '',
        category: 'Expense',
      );
      await a.correctExpense(source, replacement, 'Entry edited');
      final current = a.entries.firstWhere((e) => e['id'] == replacement['id']);
      expect(current['type'], 'daily_sales');
      expect(current.containsKey('category'), false);
      expect(a.entryName(current), a.typeLabel('daily_sales'));
      expect(a.entryName(current), bilingual('Daily sale'));
      a.dispose();
    },
  );

  testWidgets(
    'Home balances include later dates while sale and expense stay on selected day',
    (t) async {
      size(t);
      final a = await t.runAsync(fresh);
      final store = a!;
      await t.runAsync(() async {
        await store.submit(
          input('opening', 'opening_cash', 1000000, '2026-10-14'),
        );
        await store.submit({
          ...input('bank', 'opening_cash', 300000, '2026-10-20'),
          'account': 'bank',
        });
        await store.submit(
          input('loan', 'loan_lend', 200000, '2026-10-20', party: 'loan'),
        );
        await store.submit({
          ...input('expense14', 'expense', 100000, '2026-10-14'),
          'category': 'Tea',
        });
        await store.submit({
          ...input('expense20', 'expense', 50000, '2026-10-20'),
          'category': 'Lunch',
        });
        await store.submit(
          input('sale14', 'daily_sales', 5300000, '2026-10-14'),
        );
        await store.submit(
          input('bill20', 'supplier_bill', 800000, '2026-10-20', party: 'khan'),
        );
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => store)],
          child: const HisabApp(),
        ),
      );
      router.go('/');
      await t.pumpAndSettle();
      expect(find.text('Rs 6,500'), findsOneWidget);
      expect(find.text('Rs 3,000'), findsOneWidget);
      expect(find.text('Rs 53,000'), findsOneWidget);
      expect(find.text('Rs 1,000'), findsOneWidget);
      await t.drag(find.byType(ListView).first, const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.text('Rs 2,000'), findsOneWidget);
      expect(find.text('Rs 8,000'), findsWidgets);
    },
  );

  testWidgets(
    'fresh entry forms have empty party selection with matching labels',
    (t) async {
      size(t);
      final a = AppStore();
      await t.runAsync(a.init);
      await t.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => a)],
          child: const HisabApp(),
        ),
      );
      for (final pair in [
        ('supplier_bill', 'Select company'),
        ('supplier_payment', 'Select company'),
        ('supplier_return', 'Select company'),
        ('salary_payment', 'Select staff'),
        ('loan_lend', 'Select person'),
      ]) {
        router.go('/entry/${pair.$1}');
        await t.pumpAndSettle();
        expect(
          t
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).first,
              )
              .initialValue,
          isNull,
        );
        expect(find.text(bilingual(pair.$2)), findsWidgets);
      }
      router.go('/entry/supplier_payment?party=khan');
      await t.pumpAndSettle();
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .initialValue,
        'khan',
      );
      expect(t.takeException(), isNull);
    },
  );

  Future<void> loginHost(
    WidgetTester t,
    ImmediateStore store,
    AppLockController lock,
    Future<String> Function(String, String) authenticate,
    VoidCallback done,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith((ref) => store),
          appLockProvider.overrideWith((ref) => lock),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (c, ref, child) {
              final l = ref.watch(appLockProvider);
              if (l.enabled && !l.passwordLoginPending && !l.needsSetup) {
                return l.locked
                    ? const UnlockScreen()
                    : const Scaffold(body: Text('Signed in'));
              }
              return LoginScreen(authenticate: authenticate, onSignedIn: done);
            },
          ),
        ),
      ),
    );
  }

  Future<void> pins(WidgetTester t) async {
    await t.enterText(find.byKey(const Key('login-new-pin')), '4321');
    await t.enterText(find.byKey(const Key('login-confirm-pin')), '4321');
  }

  testWidgets(
    'first login creates PIN inline and later unlock remains the same page',
    (t) async {
      size(t);
      final store = ImmediateStore();
      await t.runAsync(store.init);
      final lock = AppLockController(
        vault: fixtures.MemoryVault(),
        biometrics: fixtures.NoFingerprint(),
        iterations: 5,
      );
      var calls = 0, done = 0;
      await loginHost(t, store, lock, (_, _) async {
        calls++;
        return 'test-owner';
      }, () => done++);
      await t.enterText(find.byKey(const Key('login-password')), 'valid-pass');
      await tap(t, 'Sign in');
      expect(calls, 1);
      expect(done, 0);
      expect(find.byType(UnlockScreen), findsNothing);
      expect(find.text('Create 4-digit PIN'), findsOneWidget);
      await pins(t);
      await tap(t, 'Save PIN');
      expect(done, 1);
      expect(calls, 1);
      expect(lock.needsSetup, false);
      expect(lock.passwordLoginPending, false);
      expect(find.text('Signed in'), findsOneWidget);
      lock.lock();
      await t.pumpAndSettle();
      expect(find.byType(UnlockScreen), findsOneWidget);
      expect(find.byKey(const Key('unlock-pin')), findsOneWidget);
      await lock.unlockPin('4321');
      await t.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
    },
  );
  testWidgets(
    'PIN reset needs valid password and is entered below credentials before login',
    (t) async {
      size(t);
      final store = ImmediateStore();
      await t.runAsync(store.init);
      final vault = fixtures.MemoryVault();
      final lock = AppLockController(
        vault: vault,
        biometrics: fixtures.NoFingerprint(),
        iterations: 5,
      );
      await lock.bind('test-owner');
      await lock.setup('1234', '1234');
      final old = vault.values['pharmacy-lock-v2-test-owner'];
      lock.resetUser = 'test-owner';
      lock.clearSession();
      var allow = false, done = 0;
      await loginHost(t, store, lock, (_, _) async {
        if (!allow) throw StateError('Incorrect password');
        return 'test-owner';
      }, () => done++);
      expect(find.text('Create 4-digit PIN'), findsOneWidget);
      await pins(t);
      await t.enterText(find.byKey(const Key('login-password')), 'wrong');
      await tap(t, 'Sign in');
      expect(vault.values['pharmacy-lock-v2-test-owner'], old);
      expect(done, 0);
      expect(lock.passwordLoginPending, false);
      allow = true;
      await t.enterText(find.byKey(const Key('login-password')), 'correct');
      await tap(t, 'Sign in');
      expect(done, 1);
      expect(vault.values['pharmacy-lock-v2-test-owner'], isNot(old));
      expect(find.byType(UnlockScreen), findsNothing);
      lock.lock();
      await lock.unlockPin('4321');
      expect(lock.locked, false);
    },
  );
}
