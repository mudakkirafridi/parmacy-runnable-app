import 'package:pharmacy_hisab/core/bilingual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/reports/report_document.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/ui/screens.dart';
import 'app_lock_test.dart' as fakes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'reverse works with real module partitions that omit cash balances',
    () async {
      final app = AppStore();
      await app.init();
      for (final type in [
        'zakat',
        'expense',
        'salary_advance',
        'loan_lend',
        'loan_collect',
      ]) {
        final posted = app.ledger.post(app.ledger.empty(), {
          'id': 'original-$type',
          'type': type,
          'party': 'person',
          'amount': 60000,
          'account': 'cash',
          'category': 'Rent',
          'date': today(),
        });
        final partition = clone(posted['state']);
        (partition['balances'] as Json).removeWhere(
          (key, value) => key.startsWith('money:'),
        );
        final result = app.ledger.reverse(partition, posted['entry'], {
          'id': 'reverse-$type',
          'reason': 'Duplicate entry',
          'date': today(),
        });
        for (final effect in (posted['entry']['effects'] as Json).entries) {
          expect(
            result['entry']['effects'][effect.key],
            -(effect.value as int),
          );
          if (!effect.key.startsWith('money:')) {
            expect(result['state']['balances'][effect.key], 0);
          }
        }
        expect(
          (partition['balances'] as Json).keys.any(
            (key) => key.startsWith('money:'),
          ),
          false,
        );
      }
    },
  );

  test(
    'staff money uses Qarz wosool without prior debt and has a short statement',
    () async {
      final app = AppStore();
      await app.init();
      app.state = app.ledger.empty();
      app.entries = [];
      app.profiles = [
        {'id': 'umar', 'name': 'Umar', 'module': 'loans', 'active': true},
      ];
      await app.submit({
        'id': 'in',
        'type': 'loan_collect',
        'party': 'umar',
        'amount': 200000,
        'account': 'cash',
        'date': today(),
      });
      await app.submit({
        'id': 'out',
        'type': 'loan_lend',
        'party': 'umar',
        'amount': 100000,
        'account': 'cash',
        'date': today(),
      });
      expect(app.balance('money:cash'), 100000);
      expect(loanTotal(app.state['balances'], credit: true), 100000);
      final data = buildReportData(
        app,
        app.entries,
        today(),
        today(),
        'Report',
        module: 'loans',
        party: 'umar',
      );
      expect(data.summary, {'Net balance': 'Rs -1,000'});
      expect(data.headers, ['Date', 'Lena hai', 'Dena hai']);
      expect(data.note, isEmpty);
      expect(data.rows.every((row) => row.length == 3), true);
      await app.reverseEntry(
        app.entries.firstWhere((e) => e['id'] == 'in'),
        'Duplicate entry',
        today(),
      );
      expect(app.balance('money:cash'), -100000);
      expect(loanTotal(app.state['balances']), 100000);
    },
  );

  testWidgets(
    'failed login and keyboard deletion never restore old credential text',
    (tester) async {
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appProvider.overrideWith((ref) => app),
            appLockProvider.overrideWith((ref) => lock),
          ],
          child: MaterialApp(
            home: LoginScreen(
              authenticate: (_, _) async =>
                  throw StateError('Incorrect email or password'),
            ),
          ),
        ),
      );
      final email = find.byKey(const Key('login-email')),
          password = find.byKey(const Key('login-password'));
      await tester.enterText(email, 'wrong@gmail.com');
      await tester.enterText(password, 'wrong123');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      expect(find.byIcon(Icons.close), findsNothing);
      for (final field in [email, password]) {
        final widget = tester.widget<TextField>(field);
        expect(widget.autocorrect, false);
        expect(widget.enableSuggestions, false);
        expect(widget.enableIMEPersonalizedLearning, false);
        expect(widget.autofillHints, isNull);
        await tester.enterText(field, 'oldwrong');
        await tester.showKeyboard(field);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          ),
        );
        await tester.pump();
        tester.testTextInput.enterText('7');
        await tester.pump();
        app.toggleDark();
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, '7');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rent is an expense category and report Back returns to the menu',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
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
      router.go('/registers');
      await tester.pumpAndSettle();
      expect(find.text(bilingual('Rent')), findsNothing);
      expect(expenseCategories, contains('Rent'));
      router.go('/reports');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-type-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(bilingual('Loan reports')).last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );
}
