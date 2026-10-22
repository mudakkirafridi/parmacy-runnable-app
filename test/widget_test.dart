import 'package:pharmacy_hisab/core/bilingual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/data/app_store.dart';

void main() {
  testWidgets(
    'one sale field and profile categories replace customer entry actions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final app = AppStore();
      await app.init();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith((ref) => app)],
          child: const HisabApp(),
        ),
      );
      router.go('/entry/daily_sales');
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Cash sales'), findsNothing);
      expect(find.text('Customer returns'), findsNothing);
      router.go('/profiles');
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Zakat companies'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Customer credit sale'), findsNothing);
      router.go('/register/rent');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.text('Charge rent period'), findsNothing);
      expect(find.text('Security deposit'), findsNothing);
      expect(find.text(bilingual('Pay rent')), findsNothing);
      expect(find.text(bilingual('Kharcha / Expense')), findsWidgets);
    },
  );
}
