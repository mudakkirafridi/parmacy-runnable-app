import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ownership.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/main.dart';
import 'package:pharmacy_hisab/ui/credential_editing.dart';
import 'package:pharmacy_hisab/ui/screens.dart';

TextEditingValue end(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('native composing and selection remain untouched through editing', () {
    final formatter = CredentialEditingFormatter();
    final composing = TextEditingValue(
      text: 'sample@178',
      selection: const TextSelection.collapsed(offset: 10),
      composing: const TextRange(start: 0, end: 10),
    );
    expect(
      formatter.formatEditUpdate(end('sample@1'), composing),
      same(composing),
    );
    var value = end('sample@178');
    for (final next in [
      'sample@17',
      'sample@1',
      'sample@12',
      '',
      '2',
      'pasted-value',
    ]) {
      final update = end(next);
      value = formatter.formatEditUpdate(value, update);
      expect(value, same(update));
    }
  });

  test('owner shares accept integer, decimal and trailing decimal point', () {
    for (final text in ['45', '45.', '45.0', '45.00', '45%']) {
      expect(parseOwnerShare(text), 4500);
    }
    validateOwners([
      {'id': 'a', 'name': 'A', 'shareBps': parseOwnerShare('45')},
      {'id': 'b', 'name': 'B', 'shareBps': parseOwnerShare('45.0')},
      {'id': 'c', 'name': 'C', 'shareBps': parseOwnerShare('10')},
    ]);
    expect(() => parseOwnerShare('45.123'), throwsFormatException);
    expect(
      () => validateOwners([
        {'id': 'a', 'name': 'A', 'shareBps': parseOwnerShare('45')},
      ]),
      throwsStateError,
    );
  });

  testWidgets('owner edit saves 45, 45.0 and 10 without a stale field value', (
    tester,
  ) async {
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
    router.go('/owners');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit owners'));
    await tester.tap(find.text('Edit owners'));
    await tester.pumpAndSettle();
    final ids = app.owners.map((e) => e['id']).toList();
    for (var i = 0; i < 3; i++) {
      await tester.enterText(
        find.byKey(ValueKey('owner-share-${ids[i]}')),
        ['45', '45.0', '10'][i],
      );
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(app.owners.map((e) => e['shareBps']).toList(), [4500, 4500, 1000]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long supplier headings wrap completely on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
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
    router.go('/entry/supplier_return');
    await tester.pumpAndSettle();
    final heading = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Confirmed return credit'),
    );
    expect(heading, findsOneWidget);
    final text = tester.widget<Text>(heading);
    expect(text.softWrap, true);
    expect(text.maxLines, isNull);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, greaterThan(58));
    expect(
      tester.getRect(heading).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'credential fields allow deletion and new key without restoring deleted suffix',
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
          child: MaterialApp(
            home: LoginScreen(authenticate: (_, _) async => 'user'),
          ),
        ),
      );
      for (final key in ['login-email', 'login-password']) {
        final field = find.byKey(Key(key));
        await tester.enterText(field, 'abbas@178');
        tester.testTextInput.updateEditingValue(end('abbas@17'));
        await tester.pump();
        tester.testTextInput.updateEditingValue(end('abbas@1'));
        await tester.pump();
        tester.testTextInput.updateEditingValue(end('abbas@12'));
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, 'abbas@12');
      }
      expect(tester.takeException(), isNull);
    },
  );
}
