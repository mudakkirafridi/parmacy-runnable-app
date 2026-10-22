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
import 'package:pharmacy_hisab/features/reports/export.dart';

void main() {
  testWidgets('notebook forms, committee report, PDF and phone sizes render', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('NotoArabic', 'assets/fonts/NotoSansArabic.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
    SharedPreferences.setMockInitialValues({});
    final a = AppStore();
    await t.runAsync(a.init);
    await t.runAsync(() async {
      await a.saveProfile({
        'id': 'qa-committee',
        'module': 'committee',
        'name': 'Abbas Committee',
        'active': true,
        'totalAmount': 3000000,
        'installmentAmount': 100000,
        'frequency': 'Weekly',
        'startDate': '2026-10-01',
      });
      await a.submit({
        'id': 'qa-q1',
        'type': 'committee_pay',
        'party': 'qa-committee',
        'account': 'cash',
        'date': '2026-10-01',
        'amount': 100000,
      });
      await a.submit({
        'id': 'qa-q2',
        'type': 'committee_pay',
        'party': 'qa-committee',
        'account': 'cash',
        'date': '2026-10-08',
        'amount': 100000,
      });
      await a.submit({
        'id': 'qa-receive',
        'type': 'committee_receive',
        'party': 'qa-committee',
        'account': 'bank',
        'date': '2026-10-10',
        'amount': 3000000,
      });
    });
    final key = GlobalKey();
    await t.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => a)],
        child: RepaintBoundary(key: key, child: const HisabApp()),
      ),
    );
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('design/v5').create(recursive: true);
        await File(
          'design/v5/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    router.go('/');
    await shot('home');
    await t.drag(find.byType(ListView).first, const Offset(0, -650));
    await shot('home-balances');
    for (final type in [
      'daily_sale_cash',
      'expense',
      'supplier_bill',
      'committee_pay',
    ]) {
      router.go(
        '/entry?type=$type${type == 'committee_pay' ? '&party=qa-committee' : ''}',
      );
      await t.pumpAndSettle();
      expect(find.byType(NotebookEntryScreen), findsOneWidget);
      expect(find.byKey(ValueKey('notebook-type-$type')), findsOneWidget);
      await shot('entry-$type');
    }
    t.view.physicalSize = const Size(360, 800);
    router.go('/entry?type=committee_pay&party=qa-committee');
    await shot('committee-small');
    t.view.physicalSize = const Size(430, 900);
    router.go('/reports');
    await shot('all-reports');
    router.go('/reports?module=committee&party=qa-committee');
    await shot('committee-report');
    await t.drag(find.byType(ListView).first, const Offset(0, -650));
    await shot('installment-rows');
    router.go('/profiles');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, bilingual('Add profile')));
    await shot('profile');
    Navigator.of(t.element(find.byType(AlertDialog))).pop();
    await t.pumpAndSettle();
    router.go('/entry?type=expense');
    a.toggleDark();
    await shot('entry-dark');
    a.toggleDark();
    a.toggleLanguage();
    t.view.physicalSize = const Size(360, 800);
    router.go('/entry?type=committee_pay&party=qa-committee');
    await shot('installment-urdu');
    a.toggleLanguage();
    await t.runAsync(() async {
      final data = buildReportData(
        a,
        a.entries.where((e) => e['module'] == 'committee').toList(),
        '2000-01-01',
        '2026-10-21',
        'Committee / Qist',
        module: 'committee',
        party: 'qa-committee',
      );
      await File(
        'design/v5/Sample-Committee.pdf',
      ).writeAsBytes(await buildReportPdf(data));
      final pictures = await buildReportPictures(data);
      await File('design/v5/Sample-Committee.png').writeAsBytes(pictures.first);
      a.ur = true;
      final urdu = buildReportData(
        a,
        a.entries.where((e) => e['module'] == 'committee').toList(),
        '2000-01-01',
        '2026-10-21',
        'Installment',
        module: 'committee',
        party: 'qa-committee',
      );
      await File(
        'design/v5/Installment-Urdu.pdf',
      ).writeAsBytes(await buildReportPdf(urdu));
      await File(
        'design/v5/Installment-Urdu.png',
      ).writeAsBytes((await buildReportPictures(urdu)).first);
    });
  });
}
