import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/data/app_store.dart';
import 'package:pharmacy_hisab/features/security/app_lock.dart';
import 'package:pharmacy_hisab/main.dart';
import 'app_lock_test.dart' as fakes;

void main() {
  testWidgets('PIN keypad and Unlock remain visible on a small phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    SharedPreferences.setMockInitialValues({});
    final app = AppStore();
    await tester.runAsync(app.init);
    final lock = AppLockController(
      vault: fakes.MemoryVault(),
      biometrics: fakes.FakeBiometric(),
      iterations: 10,
    );
    await tester.runAsync(() async {
      await lock.bind('demo');
      await lock.setup('1234', '1234', useBiometric: true);
      lock.lock();
    });
    final boundary = GlobalKey();
    for (final size in [const Size(430, 900), const Size(360, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appProvider.overrideWith((ref) => app),
            appLockProvider.overrideWith((ref) => lock),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: theme(false, false),
              home: const UnlockScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.byKey(const Key('unlock-submit'))).dy,
        lessThan(size.height),
      );
      expect(
        tester.getBottomRight(find.byKey(const Key('unlock-fingerprint'))).dy,
        lessThan(size.height),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('design/verified').create(recursive: true);
        await File(
          'design/verified/pin-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}
