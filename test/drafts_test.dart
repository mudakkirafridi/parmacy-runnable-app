import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmacy_hisab/data/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('draft survives restart and retry posts only once', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppStore();
    await a.init();
    final x = {
      'id': 'persist-operation',
      'type': 'expense',
      'date': '2026-10-20',
      'amount': 10000,
      'account': 'cash',
      'category': 'Electricity',
    };
    await a.saveDraft(x);
    final b = AppStore();
    await b.init();
    expect(b.drafts.single['id'], 'persist-operation');
    await b.submit(x);
    await b.submit(x);
    expect(b.entries.where((e) => e['id'] == 'persist-operation').length, 1);
    expect(b.drafts, isEmpty);
  });
}
