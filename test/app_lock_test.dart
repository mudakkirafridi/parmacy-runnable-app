import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';

class MemoryVault implements LockVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeBiometric implements BiometricGate {
  bool supported = true, accepted = true;
  @override
  Future<bool> available() async => supported;
  @override
  Future<bool> authenticate() async => accepted;
}

void main() {
  test(
    'PIN is salted/hashed, survives restart and is scoped to the user',
    () async {
      final vault = MemoryVault(), bio = FakeBiometric();
      final a = AppLockController(
        vault: vault,
        biometrics: bio,
        iterations: 10,
      );
      await a.bind('first');
      await a.setup('1234', '1234', useBiometric: true);
      expect(a.locked, false);
      expect(vault.values.values.single.contains('1234'), false);
      final b = AppLockController(
        vault: vault,
        biometrics: bio,
        iterations: 10,
      );
      await b.bind('first');
      expect(b.locked, true);
      expect(b.needsSetup, false);
      await b.unlockPin('1234');
      expect(b.locked, false);
      await b.bind('other-user');
      expect(b.needsSetup, true);
      expect(b.locked, true);
    },
  );
  test(
    'wrong PIN cooldown persists across restart; failed biometrics never unlock',
    () async {
      final vault = MemoryVault(), bio = FakeBiometric();
      var clock = DateTime(2026, 10, 15);
      final a = AppLockController(
        vault: vault,
        biometrics: bio,
        iterations: 10,
        now: () => clock,
      );
      await a.bind('user');
      await a.setup('1234', '1234', useBiometric: true);
      a.lock();
      for (var i = 0; i < 5; i++) {
        await expectLater(a.unlockPin('0000'), throwsStateError);
      }
      expect(a.locked, true);
      expect(a.cooldownSeconds, 60);
      final b = AppLockController(
        vault: vault,
        biometrics: bio,
        iterations: 10,
        now: () => clock,
      );
      await b.bind('user');
      await expectLater(b.unlockPin('1234'), throwsStateError);
      bio.accepted = false;
      await expectLater(b.unlockBiometric(), throwsStateError);
      expect(b.locked, true);
      clock = clock.add(const Duration(seconds: 61));
      await b.unlockPin('1234');
      expect(b.locked, false);
      b.lock();
      bio.accepted = true;
      await b.unlockBiometric();
      expect(b.locked, false);
    },
  );
  test(
    'changing PIN requires current PIN; fingerprint can be disabled',
    () async {
      final a = AppLockController(
        vault: MemoryVault(),
        biometrics: FakeBiometric(),
        iterations: 10,
      );
      await a.bind('user');
      await a.setup('1234', '1234', useBiometric: true);
      await expectLater(a.changePin('0000', '4321', '4321'), throwsStateError);
      await a.changePin('1234', '4321', '4321');
      a.lock();
      await expectLater(a.unlockPin('1234'), throwsStateError);
      await a.unlockPin('4321');
      await a.setFingerprint(false);
      expect(a.biometricEnabled, false);
    },
  );
}
