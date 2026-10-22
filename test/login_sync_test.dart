import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';
import 'package:pharmacy_hisab/ui/screens.dart';

class RemoteStore extends AppStore {
  RemoteStore({super.syncTimeout});
  final requests = <Completer<dynamic>>[];
  @override
  String get uid => live ? 'test-owner' : 'demo';
  @override
  Future<dynamic> call(String name, Json data) {
    expect(name, 'workspace');
    final request = Completer<dynamic>();
    requests.add(request);
    return request.future;
  }

  Json workspace(String marker) => {
    'state': ledger.empty(),
    'entries': [
      {'id': marker},
    ],
    'profiles': [],
    'config': {
      'name': 'Test pharmacy',
      'accounts': ['cash', 'bank'],
    },
    'member': {'role': 'owner', 'active': true},
    'allowed': ['sales', 'expenses'],
  };
}

class MemoryVault implements LockVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class NoFingerprint implements BiometricGate {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'connecting restores session without waiting for any network request',
    () async {
      final store = RemoteStore();
      await store.init();
      expect(store.entries, isNotEmpty); // Isolated demo seed.
      await store.connect('shop', refreshNow: false);
      expect(store.live, true);
      expect(store.entries, isEmpty);
      expect(store.requests, isEmpty);
      expect(store.syncing, false);
      expect(store.cached, false);
    },
  );

  test('sync has a deadline and retry succeeds without reconnecting', () async {
    final store = RemoteStore(syncTimeout: const Duration(milliseconds: 20));
    await store.init();
    await store.connect('shop', refreshNow: false);
    await store.refresh();
    expect(store.live, true);
    expect(store.syncing, false);
    expect(store.busy, false);
    expect(store.cached, false); // No cache exists on a first sign-in.
    expect(store.error, contains('Sync took too long'));
    final retry = store.refresh();
    store.requests.last.complete(store.workspace('fresh'));
    await retry;
    expect(store.entries.single['id'], 'fresh');
    expect(store.error, isNull);
    expect(store.syncing, false);
    store.requests.first.complete(store.workspace('stale'));
    await Future<void>.delayed(Duration.zero);
    expect(store.entries.single['id'], 'fresh');
  });

  test(
    'offline restart preserves the correct user cache and concurrent retry is deduplicated',
    () async {
      final first = RemoteStore();
      await first.init();
      await first.connect('shop', refreshNow: false);
      final load = first.refresh();
      final duplicate = first.refresh();
      expect(first.requests.length, 1);
      first.requests.single.complete(first.workspace('saved'));
      await Future.wait([load, duplicate]);

      final restarted = RemoteStore();
      await restarted.init();
      await restarted.connect('shop', refreshNow: false);
      expect(restarted.entries.single['id'], 'saved');
      final offline = restarted.refresh();
      restarted.requests.single.completeError(
        StateError('Network unavailable'),
      );
      await offline;
      expect(restarted.live, true);
      expect(restarted.cached, true);
      expect(restarted.entries.single['id'], 'saved');
      expect(restarted.syncing, false);
    },
  );

  test(
    'successful writes get a fresh read after an existing background sync',
    () async {
      final store = RemoteStore();
      await store.init();
      await store.connect('shop', refreshNow: false);
      final initial = store.refresh();
      final afterWrite = store.refresh(afterWrite: true);
      store.requests.first.complete(store.workspace('before-write'));
      await initial;
      await Future<void>.delayed(Duration.zero);
      expect(store.requests.length, 2);
      store.requests.last.complete(store.workspace('after-write'));
      await afterWrite;
      expect(store.entries.single['id'], 'after-write');
      expect(store.syncing, false);
    },
  );

  test('late network response cannot restore a signed-out workspace', () async {
    final store = RemoteStore();
    await store.init();
    await store.connect('shop', refreshNow: false);
    final load = store.refresh();
    await store.signOut();
    store.requests.single.complete(store.workspace('private-old-session'));
    await load;
    expect(store.live, false);
    expect(store.entries.any((e) => e['id'] == 'private-old-session'), false);
    expect(store.syncing, false);
  });

  testWidgets(
    'login finishes when PIN gate disposes the login widget and Firestore fails',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RemoteStore();
      await tester.runAsync(store.init);
      final lock = AppLockController(
        vault: MemoryVault(),
        biometrics: NoFingerprint(),
        iterations: 5,
      );
      await lock.bind('test-owner');
      await lock.setup('1234', '1234', useBiometric: false);
      lock.lock();
      var authenticated = false;
      var completed = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appProvider.overrideWith((ref) => store),
            appLockProvider.overrideWith((ref) => lock),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                final deviceLock = ref.watch(appLockProvider);
                if (authenticated &&
                    deviceLock.enabled &&
                    !deviceLock.passwordLoginPending) {
                  return const Scaffold(body: Text('PIN setup'));
                }
                return LoginScreen(
                  authenticate: (email, password) async {
                    authenticated = true;
                    return 'test-owner';
                  },
                  onSignedIn: () => completed++,
                );
              },
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'test-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      await tester.pump();
      expect(find.text('PIN setup'), findsOneWidget);
      expect(completed, 1);
      expect(store.live, true);
      expect(lock.scope, 'test-owner');
      expect(lock.locked, true);
      expect(store.requests.length, 1);
      store.requests.single.completeError(
        StateError('Firestore temporarily unavailable'),
      );
      await tester.pumpAndSettle();
      expect(store.live, true);
      expect(find.byKey(const Key('login-password')), findsNothing);
      expect(store.error, isNotNull);
      expect(store.syncing, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incorrect password stays on login and does not connect a store',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RemoteStore();
      await tester.runAsync(store.init);
      final lock = AppLockController(
        vault: MemoryVault(),
        biometrics: NoFingerprint(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appProvider.overrideWith((ref) => store),
            appLockProvider.overrideWith((ref) => lock),
          ],
          child: MaterialApp(
            home: LoginScreen(
              authenticate: (_, _) async {
                throw FirebaseAuthException(
                  code: 'invalid-credential',
                  message: 'Incorrect email or password',
                );
              },
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'wrong-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Incorrect email or password'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(store.live, false);
      expect(store.requests, isEmpty);
      expect(lock.enabled, false);
    },
  );
  testWidgets(
    'IME deletion and replacement retain only current credential text',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RemoteStore();
      await tester.runAsync(store.init);
      final lock = AppLockController(
        vault: MemoryVault(),
        biometrics: NoFingerprint(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appProvider.overrideWith((ref) => store),
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
      Future<void> edit(String key, List<String> values) async {
        final field = find.byKey(Key(key));
        await tester.showKeyboard(field);
        final config = tester.testTextInput.setClientArgs!;
        expect(
          (config['inputType'] as Map)['name'],
          'TextInputType.visiblePassword',
        );
        expect(config['autocorrect'], false);
        expect(config['enableSuggestions'], false);
        expect(config['enableIMEPersonalizedLearning'], false);
        for (final text in values) {
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
              composing: text.isEmpty
                  ? TextRange.empty
                  : TextRange(start: 0, end: text.length),
            ),
          );
          await tester.pump();
          expect(tester.widget<TextField>(field).controller!.text, text);
        }
      }

      await edit('login-email', [
        'person@example.con',
        'person@example.co',
        'person@example.c',
        'person@example.co',
        'person@example.com',
      ]);
      await edit('login-password', [
        'sample@178',
        'sample@17',
        'sample@1',
        'sample@12',
      ]);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      await edit('login-password', ['sample@1', 'sample@12', '', 'new-value']);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-password')))
            .controller!
            .text,
        isEmpty,
      );
      await edit('login-email', ['', 'a', 'a@example.com']);
      await edit('login-password', ['2', '', 'replacement']);
      expect(tester.takeException(), isNull);
    },
  );
}
