import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../data/app_store.dart';
import '../../ui/app_back_scope.dart';
import '../../ui/credential_editing.dart';

// PBKDF2 must not monopolise the Android UI isolate while entering a PIN.
Future<String> derivePinHash(Map<String, dynamic> args) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: args['iterations'] as int,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(args['pin'] as String)),
        nonce: List<int>.from(args['salt']),
      );
  return base64Encode(await key.extractBytes());
}

abstract class LockVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceLockVault implements LockVault {
  final FlutterSecureStorage storage;
  DeviceLockVault({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

abstract class BiometricGate {
  Future<bool> available();
  Future<bool> authenticate();
}

class DeviceBiometricGate implements BiometricGate {
  final LocalAuthentication auth = LocalAuthentication();
  @override
  Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      return (await auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() => auth.authenticate(
    localizedReason: 'Unlock Pharmacy Hisab',
    biometricOnly: true,
    persistAcrossBackgrounding: true,
  );
}

final appLockProvider = ChangeNotifierProvider<AppLockController>(
  (ref) => AppLockController(),
);

class AppLockController extends ChangeNotifier {
  final LockVault vault;
  final BiometricGate biometrics;
  final int iterations;
  final DateTime Function() now;
  AppLockController({
    LockVault? vault,
    BiometricGate? biometrics,
    this.iterations = 100000,
    DateTime Function()? now,
  }) : vault = vault ?? DeviceLockVault(),
       biometrics = biometrics ?? DeviceBiometricGate(),
       now = now ?? DateTime.now;
  String? scope, resetUser;
  Map<String, dynamic>? _record;
  bool locked = false, busy = false, biometricAvailable = false;
  bool _migrationAuthorized = false;
  bool get migrating => _migrationAuthorized;
  int get pinLength => needsSetup ? 4 : (_record?['length'] as int? ?? 6);
  bool get legacyPin => _record != null && (_record?['length'] ?? 6) != 4;
  bool get enabled => scope != null;
  bool get needsSetup => enabled && (_record == null || _migrationAuthorized);
  bool get biometricEnabled => _record?['biometric'] == true;
  String get key => 'pharmacy-lock-v2-$scope';
  int get cooldownSeconds {
    final until = _record?['until'] as int? ?? 0;
    return max(0, ((until - now().millisecondsSinceEpoch) / 1000).ceil());
  }

  Future<void> bind(String userId) async {
    busy = true;
    scope = userId;
    _migrationAuthorized = false;
    locked = true;
    _record = null;
    notifyListeners();
    try {
      final stored = await vault.read(key);
      if (stored != null) {
        _record = Map<String, dynamic>.from(jsonDecode(stored));
      }
      biometricAvailable = await biometrics.available();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> _hash(String pin, List<int> salt) async {
    return _derive(pin, salt, iterations);
  }

  Future<String> _derive(String pin, List<int> salt, int rounds) {
    final args = <String, dynamic>{
      'pin': pin,
      'salt': salt,
      'iterations': rounds,
    };
    return rounds >= 1000 ? compute(derivePinHash, args) : derivePinHash(args);
  }

  Future<void> _save() => vault.write(key, jsonEncode(_record));
  Future<void> setup(
    String pin,
    String confirmation, {
    bool useBiometric = false,
  }) async {
    if (busy) throw StateError('Please wait');
    if (!needsSetup) {
      throw StateError('Unlock with the existing PIN before changing security');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw StateError('Choose a 4-digit PIN');
    }
    if (pin != confirmation) throw StateError('PINs do not match');
    busy = true;
    notifyListeners();
    try {
      if (useBiometric &&
          (!biometricAvailable || !await biometrics.authenticate())) {
        throw StateError(
          'Fingerprint confirmation failed. You can keep using PIN.',
        );
      }
      final random = Random.secure(),
          salt = List<int>.generate(32, (_) => random.nextInt(256));
      _record = {
        'length': 4,
        'salt': base64Encode(salt),
        'hash': await _hash(pin, salt),
        'iterations': iterations,
        'biometric': useBiometric,
        'failures': 0,
        'until': 0,
      };
      await _save();
      _migrationAuthorized = false;
      locked = false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> unlockPin(String pin) async {
    if (_record == null) throw StateError('Set up a PIN first');
    if (busy) throw StateError('Please wait');
    if (cooldownSeconds > 0) {
      throw StateError('Too many attempts. Wait $cooldownSeconds seconds.');
    }
    busy = true;
    notifyListeners();
    try {
      final salt = base64Decode(_record!['salt']);
      final actual = base64Decode(
            await _derive(pin, salt, _record!['iterations'] as int),
          ),
          expected = base64Decode(_record!['hash']);
      var difference = actual.length ^ expected.length;
      for (var i = 0; i < min(actual.length, expected.length); i++) {
        difference |= actual[i] ^ expected[i];
      }
      if (difference != 0) {
        final failures = (_record!['failures'] as int? ?? 0) + 1;
        _record!['failures'] = failures;
        if (failures >= 5) {
          _record!['until'] = now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch;
          _record!['failures'] = 0;
        }
        await _save();
        throw StateError(
          cooldownSeconds > 0
              ? 'Too many attempts. Wait 60 seconds.'
              : 'Incorrect PIN',
        );
      }
      _record!['failures'] = 0;
      _record!['until'] = 0;
      await _save();
      _migrationAuthorized = legacyPin;
      locked = legacyPin;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> unlockBiometric() async {
    if (!biometricEnabled || !biometricAvailable) {
      throw StateError('Fingerprint unavailable. Use your PIN.');
    }
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      if (await biometrics.authenticate()) {
        _migrationAuthorized = legacyPin;
        locked = legacyPin;
      } else {
        throw StateError('Fingerprint not accepted. Use PIN or try again.');
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void lock() {
    if (enabled && !busy) {
      locked = true;
      notifyListeners();
    }
  }

  Future<void> setFingerprint(bool enabled) async {
    if (locked || needsSetup) throw StateError('Unlock first');
    if (enabled) {
      biometricAvailable = await biometrics.available();
      busy = true;
      notifyListeners();
      try {
        if (!biometricAvailable || !await biometrics.authenticate()) {
          throw StateError('Fingerprint unavailable or not accepted');
        }
      } finally {
        busy = false;
        notifyListeners();
      }
    }
    _record!['biometric'] = enabled;
    await _save();
    notifyListeners();
  }

  Future<void> changePin(String oldPin, String newPin, String confirm) async {
    if (!RegExp(r'^\d{4}$').hasMatch(newPin) || newPin != confirm) {
      throw StateError('Enter matching 4-digit PINs');
    }
    await unlockPin(oldPin);
    busy = true;
    notifyListeners();
    try {
      final random = Random.secure();
      final salt = List<int>.generate(32, (_) => random.nextInt(256));
      _record!['salt'] = base64Encode(salt);
      _record!['hash'] = await _hash(newPin, salt);
      _record!['iterations'] = iterations;
      _record!['length'] = 4;
      await _save();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clearSession() {
    scope = null;
    _migrationAuthorized = false;
    _record = null;
    locked = false;
    notifyListeners();
  }

  Future<void> resetAfterPasswordLogin(String uid) async {
    if (resetUser == uid) {
      await vault.delete('pharmacy-lock-v2-$uid');
      resetUser = null;
    }
    await bind(uid);
  }
}

class AppAccessGate extends ConsumerStatefulWidget {
  final Widget child;
  final Widget Function() login;
  const AppAccessGate({super.key, required this.child, required this.login});
  @override
  ConsumerState<AppAccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends ConsumerState<AppAccessGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(appLockProvider).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appProvider);
    final lock = ref.watch(appLockProvider);
    if (Firebase.apps.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      // Keep the login page alive until the authenticated user's device lock
      // is bound. Auth success alone must not expose the dashboard mid-login.
      if (user == null || lock.scope != user.uid) return widget.login();
    }
    if (lock.enabled && (lock.locked || lock.needsSetup)) {
      return const UnlockScreen();
    }
    return widget.child;
  }
}

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});
  @override
  ConsumerState<UnlockScreen> createState() => _UnlockState();
}

class _UnlockState extends ConsumerState<UnlockScreen> {
  final pin = TextEditingController(), confirmation = TextEditingController();
  bool fingerprint = false;
  final pinEditing = CredentialEditingFormatter(),
      confirmEditing = CredentialEditingFormatter();
  String? error;
  @override
  void dispose() {
    pin.dispose();
    confirmation.dispose();
    super.dispose();
  }

  bool submitting = false;
  bool? wasSetup;

  Future<void> run(Future<void> Function() action) async {
    if (submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      // Always clear failed credentials, including setup mismatches. Do not
      // access controllers after the gate has replaced/disposed this screen.
      if (mounted) {
        pin.clear();
        confirmation.clear();
        setState(() => submitting = false);
      }
    }
  }

  void digit(String value, AppLockController lock) {
    if (submitting || lock.busy || pin.text.length >= lock.pinLength) return;
    setState(() {
      error = null;
      pin.text += value;
    });
  }

  @override
  Widget build(BuildContext c) {
    final lock = ref.watch(appLockProvider), a = ref.watch(appProvider);
    final setup = lock.needsSetup, waiting = lock.busy || submitting;
    final compact = MediaQuery.sizeOf(c).height < 760;
    if (wasSetup != setup) {
      wasSetup = setup;
      fingerprint = setup && lock.biometricAvailable;
    }
    return AppBackScope(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: compact ? 8 : 18,
                ),
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xff005bea),
                    size: compact ? 32 : 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    a.ur ? 'فارمیسی حساب' : 'Pharmacy Hisab',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    setup
                        ? 'Create PIN'
                        : lock.legacyPin
                        ? 'Current 6-digit PIN'
                        : 'Enter PIN',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('unlock-pin'),
                    controller: pin,
                    enabled: !waiting,
                    autofocus: setup,
                    obscureText: true,
                    obscuringCharacter: '●',
                    enableSuggestions: false,
                    autocorrect: false,
                    enableInteractiveSelection: setup,
                    showCursor: setup,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 18),
                    maxLength: lock.pinLength,
                    keyboardType: setup
                        ? TextInputType.number
                        : TextInputType.none,
                    inputFormatters: [
                      pinEditing,
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (_) {
                      if (error != null) setState(() => error = null);
                    },
                    onSubmitted: (_) {
                      if (!setup &&
                          !waiting &&
                          pin.text.length == lock.pinLength) {
                        final value = pin.text;
                        run(() => lock.unlockPin(value));
                      }
                    },
                    decoration: const InputDecoration(counterText: ''),
                  ),
                  if (setup) ...[
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('confirm-pin'),
                      controller: confirmation,
                      enabled: !waiting,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        confirmEditing,
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Confirm PIN',
                        counterText: '',
                      ),
                    ),
                    if (lock.biometricAvailable)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fingerprint'),
                        value: fingerprint,
                        onChanged: waiting
                            ? null
                            : (v) => setState(() => fingerprint = v),
                      ),
                  ] else ...[
                    const SizedBox(height: 12),
                    for (final row in [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                      ['', '0', '⌫'],
                    ])
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 2 : 5,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final value in row)
                              SizedBox(
                                width: 70,
                                height: compact ? 48 : 62,
                                child: value.isEmpty
                                    ? const SizedBox.shrink()
                                    : TextButton(
                                        key: Key('pin-key-$value'),
                                        style: TextButton.styleFrom(
                                          shape: const CircleBorder(),
                                          backgroundColor: Theme.of(c)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: .07),
                                        ),
                                        onPressed: waiting
                                            ? null
                                            : () {
                                                if (value == '⌫') {
                                                  if (pin.text.isNotEmpty) {
                                                    setState(
                                                      () => pin.text = pin.text
                                                          .substring(
                                                            0,
                                                            pin.text.length - 1,
                                                          ),
                                                    );
                                                  }
                                                } else {
                                                  digit(value, lock);
                                                }
                                              },
                                        child: Text(
                                          value,
                                          style: const TextStyle(fontSize: 26),
                                        ),
                                      ),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const Key('unlock-submit'),
                    onPressed: waiting
                        ? null
                        : () {
                            final value = pin.text, confirm = confirmation.text;
                            if (value.length != lock.pinLength) {
                              setState(
                                () => error = 'Enter ${lock.pinLength} digits',
                              );
                              return;
                            }
                            run(
                              () => setup
                                  ? lock.setup(
                                      value,
                                      confirm,
                                      useBiometric: fingerprint,
                                    )
                                  : lock.unlockPin(value),
                            );
                          },
                    child: waiting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(setup ? 'Save PIN' : 'Unlock'),
                  ),
                  if (!setup &&
                      lock.biometricEnabled &&
                      lock.biometricAvailable) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('unlock-fingerprint'),
                      onPressed: waiting
                          ? null
                          : () => run(lock.unlockBiometric),
                      icon: const Icon(Icons.fingerprint, size: 28),
                      label: const Text('Use fingerprint'),
                    ),
                  ],
                  if (Firebase.apps.isNotEmpty)
                    TextButton(
                      onPressed: waiting
                          ? null
                          : () async {
                              final app = ref.read(appProvider);
                              lock.resetUser =
                                  FirebaseAuth.instance.currentUser?.uid;
                              lock.clearSession();
                              await app.signOut();
                            },
                      child: const Text('Forgot PIN?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override
  ConsumerState<SecurityScreen> createState() => _SecurityState();
}

class _SecurityState extends ConsumerState<SecurityScreen> {
  final oldPin = TextEditingController(),
      newPin = TextEditingController(),
      confirm = TextEditingController();
  String? message;
  final editing = List.generate(3, (_) => CredentialEditingFormatter());
  @override
  void dispose() {
    oldPin.dispose();
    newPin.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => message = 'Saved successfully');
    } catch (e) {
      if (mounted) {
        oldPin.clear();
        newPin.clear();
        confirm.clear();
        setState(() => message = e.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final lock = ref.watch(appLockProvider), a = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 86,
        title: Text(a.tr('PIN & fingerprint'), softWrap: true, maxLines: 2),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const Icon(Icons.fingerprint, size: 64, color: Color(0xff005bea)),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fingerprint unlock'),
                value: lock.biometricEnabled,
                onChanged: lock.busy
                    ? null
                    : (v) => run(() => lock.setFingerprint(v)),
              ),
              const Divider(),
              const Text(
                'Change 4-digit PIN',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              const SizedBox(height: 15),
              for (final f in [
                (oldPin, 'Current PIN'),
                (newPin, 'New PIN'),
                (confirm, 'Confirm new PIN'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: TextField(
                    controller: f.$1,
                    obscureText: true,
                    maxLength: f.$1 == oldPin ? lock.pinLength : 4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      editing[f.$1 == oldPin
                          ? 0
                          : f.$1 == newPin
                          ? 1
                          : 2],
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: f.$2,
                      counterText: '',
                    ),
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Text(message!),
                ),
              FilledButton(
                onPressed: lock.busy
                    ? null
                    : () => run(() async {
                        await lock.changePin(
                          oldPin.text,
                          newPin.text,
                          confirm.text,
                        );
                        oldPin.clear();
                        newPin.clear();
                        confirm.clear();
                      }),
                child: const Text('Save PIN'),
              ),
              const SizedBox(height: 15),
              OutlinedButton.icon(
                onPressed: lock.lock,
                icon: const Icon(Icons.lock_outline),
                label: Text(a.tr('Lock app')),
              ),
              if (!a.live)
                TextButton(
                  onPressed: () async {
                    await a.prefs.setBool('demo-lock-enabled', false);
                    lock.clearSession();
                    if (c.mounted) Navigator.pop(c);
                  },
                  child: const Text('Turn off demo lock'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
