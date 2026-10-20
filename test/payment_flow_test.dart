import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/data/app_store.dart';

void main() {
  testWidgets(
    'review and confirm supplier installment updates statement once',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      await store.init();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => store)],
          child: const HisabApp(),
        ),
      );
      router.go('/entry/supplier_payment?party=khan');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-amount')),
        '10000',
      );
      await tester.tap(find.text('Review payment'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm and post'), findsOneWidget);
      await tester.tap(find.text('Confirm and post'));
      await tester.pumpAndSettle();
      expect(store.balance('supplier:khan'), -24000000);
      expect(store.drafts, isEmpty);
      expect(find.text('Rs 240,000'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
