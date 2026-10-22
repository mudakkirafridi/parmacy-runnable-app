import 'package:pharmacy_hisab/core/bilingual.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/ui/screens.dart';

void main() {
  testWidgets('all registers, payment, Urdu and dark screens render', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in [('Inter', 'Inter'), ('NotoArabic', 'NotoSansArabic')]) {
      final loader = FontLoader(font.$1)
        ..addFont(rootBundle.load('assets/fonts/${font.$2}.ttf'));
      await loader.load();
    }
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    await store.init();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => store)],
        child: RepaintBoundary(key: boundary, child: const HisabApp()),
      ),
    );
    Future<void> snapshot(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('design/verified').create(recursive: true);
        await File(
          'design/verified/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    await snapshot('dashboard');
    await tester.drag(find.byType(ListView).first, const Offset(0, -1700));
    await tester.pumpAndSettle();
    await snapshot('home-quick-v41');
    router.go('/register/suppliers');
    await snapshot('suppliers');
    router.go('/register/orders');
    await snapshot('orders');
    router.go('/entry/supplier_payment?party=khan');
    await snapshot('pay-supplier');
    tester.view.physicalSize = const Size(360, 800);
    router.go('/entry/supplier_return');
    await snapshot('supplier-return-title');
    tester.view.physicalSize = const Size(430, 900);
    for (final module in [
      'customers',
      'salary',
      'rent',
      'loans',
      'zakat',
      'sales',
      'expenses',
      'cashbook',
      'owner',
    ]) {
      router.go('/register/$module');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (module == 'salary' ||
          module == 'loans' ||
          module == 'cashbook' ||
          module == 'expenses') {
        await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
        await snapshot('$module-footer-v41');
      }
    }
    for (final type in [
      'daily_sales',
      'salary_accrual',
      'supplier_bill',
      'expense',
      'rent_payment',
    ]) {
      router.go('/entry/$type');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    router.go('/reports');
    await snapshot('reports');
    router.go('/reports?module=all');
    await snapshot('all-reports-pdf-v41');
    router.go('/reports?module=loans&party=loan');
    await snapshot('loan-report');
    router.go('/reports?module=ograi&party=khan');
    await snapshot('ograi-report');
    router.go('/reports?module=company_bills');
    await snapshot('company-bills-report');
    router.go('/profiles');
    await snapshot('profiles-v4');
    router.go('/entry/salary_payment?party=staff');
    await snapshot('salary-payment-v4');
    router.go('/entry/loan_collect?party=loan');
    await snapshot('qarz-wosool-v4');
    store.profiles.insert(0, {
      'id': 'staff42',
      'module': 'salary',
      'name': 'Umar42',
      'active': true,
      'visible': 1,
    });
    await tester.runAsync(
      () => store.submit({
        'id': 'due42',
        'type': 'salary_accrual',
        'party': 'staff42',
        'amount': 500000,
        'date': '2026-10-20',
        'reference': '2026-10',
        'allocations': [],
      }),
    );
    router.go('/entry/salary_payment?party=staff42');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('entry-amount')), '10000');
    await snapshot('salary-preview-v42');
    await tester.runAsync(
      () => store.submit({
        'id': 'pay42',
        'type': 'salary_payment',
        'party': 'staff42',
        'account': 'cash',
        'amount': 1000000,
        'date': '2026-10-20',
        'allocations': [],
      }),
    );
    router.go('/register/salary');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Umar42');
    await snapshot('salary-net-v42');
    await tester.runAsync(
      () => store.submit({
        'id': 'expense42',
        'type': 'expense',
        'category': 'Lunch',
        'account': 'cash',
        'amount': 50000,
        'date': '2026-10-20',
      }),
    );
    final expense = store.entries.firstWhere((e) => e['id'] == 'expense42');
    await tester.runAsync(
      () => store.reverseEntry(expense, 'Entry removed', '2026-10-20'),
    );
    router.go('/reports?module=expenses');
    await tester.pumpAndSettle();
    entryDetails(
      tester.element(find.byType(ReportsScreen)),
      store,
      store.entries.firstWhere((e) => e['id'] == 'reverse-expense42'),
    );
    await snapshot('reversal-v42');
    Navigator.of(tester.element(find.text(bilingual('Original entry')))).pop();
    await tester.pumpAndSettle();
    router.go('/more');
    await snapshot('more-v411');
    await tester.drag(find.byType(ListView).first, const Offset(0, -680));
    await snapshot('more-security-v411');
    router.go('/login');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set / reset PIN'));
    await snapshot('login-inline-pin-v43');
    router.go('/');
    await tester.pumpAndSettle();
    store.toggleDark();
    router.go('/more');
    await snapshot('more-dark-v411');
    store.toggleDark();
    store.toggleLanguage();
    router.go('/more');
    await snapshot('more-urdu-v411');
    router.go('/');
    await snapshot('urdu');
    store.toggleDark();
    await snapshot('urdu-dark');
  });
}
