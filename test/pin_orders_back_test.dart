import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';
import 'package:pharmacy_hisab/main.dart';
import 'app_lock_test.dart' as fakes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'production PIN hash remains compatible after a device session restart',
    () async {
      final vault = fakes.MemoryVault();
      final first = AppLockController(
        vault: vault,
        biometrics: fakes.FakeBiometric(),
      );
      await first.bind('owner');
      // Leading zeroes must survive storage and unlock exactly as entered.
      await first.setup('0123', '0123', useBiometric: true);
      final restarted = AppLockController(
        vault: vault,
        biometrics: fakes.FakeBiometric(),
      );
      await restarted.bind('owner');
      expect(restarted.locked, true);
      await expectLater(restarted.unlockPin('1230'), throwsStateError);
      expect(restarted.locked, true);
      await restarted.unlockPin('0123');
      expect(restarted.locked, false);
      restarted.lock();
      await restarted.unlockBiometric();
      expect(restarted.locked, false);
    },
  );

  testWidgets(
    'wrong PIN clears, keypad retries unlock, and background relocks',
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
      await tester.runAsync(() async {
        await lock.bind('owner');
        await lock.setup('0123', '0123', useBiometric: true);
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
              login: login,
              child: Scaffold(body: Text('Private home')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('pin-key-9')));
        await tester.pump();
      }
      expect(lock.locked, true);
      await tester.tap(find.byKey(const Key('unlock-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect PIN'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('unlock-pin')))
            .controller!
            .text,
        isEmpty,
      );
      expect(lock.locked, true);
      for (final digit in ['0', '1', '2', '3']) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('unlock-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Private home'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(lock.locked, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unlock-fingerprint')));
      await tester.pumpAndSettle();
      expect(find.text('Private home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('setup mismatch clears both PINs and successful retry saves', (
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
    await tester.runAsync(() => lock.bind('owner'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith((ref) => app),
          appLockProvider.overrideWith((ref) => lock),
        ],
        child: const MaterialApp(
          home: AppAccessGate(login: login, child: Text('Private home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unlock-pin')), '1234');
    await tester.enterText(find.byKey(const Key('confirm-pin')), '4321');
    await tester.tap(find.byKey(const Key('unlock-submit')));
    await tester.pumpAndSettle();
    expect(find.text('PINs do not match'), findsOneWidget);
    for (final key in ['unlock-pin', 'confirm-pin']) {
      expect(
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text,
        isEmpty,
      );
    }
    await tester.enterText(find.byKey(const Key('unlock-pin')), '1234');
    await tester.enterText(find.byKey(const Key('confirm-pin')), '1234');
    await tester.tap(find.byKey(const Key('unlock-submit')));
    await tester.pumpAndSettle();
    expect(lock.locked, false);
    expect(lock.biometricEnabled, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order accepts a typed name without creating a salary profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppStore();
    await tester.runAsync(app.init);
    app.profiles.removeWhere((p) => p['module'] == 'salary');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: const HisabApp(),
      ),
    );
    router.go('/register/orders');
    await tester.pumpAndSettle();
    await tester.tap(find.text('New order'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khan Distributors').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('order-person')), 'Umar');
    await tester.enterText(find.byKey(const Key('order-amount')), '8000');
    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();
    expect(app.orders.single['companyName'], 'Khan Distributors');
    expect(app.orders.single['staffName'], 'Umar');
    expect(app.orders.single['amount'], 800000);
    expect(app.people('salary'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone Back returns one step and two Home backs request exit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppStore();
    await tester.runAsync(app.init);
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: const HisabApp(),
      ),
    );
    router.go('/registers');
    await tester.pumpAndSettle();
    router.push('/register/orders');
    await tester.pumpAndSettle();
    await tester.tap(find.text('New order'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('New company order'), findsNothing);
    expect(router.state.uri.path, '/register/orders');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/registers');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget login() => const Text('Login');
