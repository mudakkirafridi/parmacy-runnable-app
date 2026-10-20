import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_hisab/core/ledger.dart';
import 'package:pharmacy_hisab/core/ownership.dart';

void main() {
  late Ledger ledger;
  late Json state;
  int id = 0;
  setUp(() {
    ledger = Ledger(
      jsonDecode(File('assets/transaction_types.json').readAsStringSync()),
    );
    state = ledger.empty();
    id = 0;
  });
  Json post(String type, int amount, {String? bill, Json extra = const {}}) {
    final result = ledger.post(state, {
      'id': 'entry-${id++}',
      'type': type,
      'amount': amount * 100,
      'party': 'person',
      'date': '2026-10-14',
      'account': 'cash',
      'target': 'bank',
      'reference': 'ref-$id',
      if (bill != null)
        'allocations': [
          {'id': bill, 'amount': amount * 100},
        ],
      ...extra,
    });
    state = result['state'];
    return result['entry'];
  }

  test('supplier bill installments and financial return remain correct', () {
    final b = post('supplier_bill', 300000);
    post('supplier_payment', 10000, bill: b['id']);
    post('supplier_payment', 25000, bill: b['id']);
    post('supplier_return', 15000, bill: b['id']);
    expect(state['balances']['supplier:person'], -25000000);
    expect(state['balances']['money:cash'], -3500000);
  });
  test('net sale is one amount, unique by day and has no cash effect', () {
    post('daily_sales', 53000);
    expect(state['balances']['netSales'], -5300000);
    expect(state['balances']['money:cash'], isNull);
    expect(() => post('daily_sales', 1), throwsStateError);
  });
  test('retired customer, return-sale and rent charge flows cannot post', () {
    for (final t in [
      'customer_sale',
      'customer_collection',
      'customer_return',
      'customer_refund',
      'writeoff',
      'opening_customer',
      'rent_accrual',
      'rent_deposit',
      'rent_apply',
    ]) {
      expect(() => post(t, 1), throwsStateError);
    }
    expect(
      () => post('daily_sales', 1, extra: {'cash': 100}),
      throwsStateError,
    );
  });
  test('rent is a direct expense and cash movement, without obligations', () {
    post('rent_payment', 15000);
    expect(state['balances']['expense:rent'], 1500000);
    expect(state['balances']['money:cash'], -1500000);
    expect(state['obligations'], isEmpty);
  });
  test('supplier advance application has no second cash movement', () {
    post('supplier_payment', 50, extra: {'allowAdvance': true});
    final b = post('supplier_bill', 100);
    post('supplier_apply', 50, bill: b['id']);
    expect(state['balances']['money:cash'], -5000);
    expect(state['obligations'][b['id']]['remaining'], 5000);
    expect(() => post('supplier_apply', 1, bill: b['id']), throwsStateError);
  });
  test('salary applies advance without double payment', () {
    post('salary_advance', 5000);
    final b = post('salary_accrual', 30000);
    post('salary_apply', 5000, bill: b['id']);
    post('salary_payment', 20000, bill: b['id']);
    expect(state['balances']['salary:person'], -500000);
    expect(state['balances']['money:cash'], -2500000);
  });
  test('ownership percentages must total 100', () {
    validateOwners(defaultOwners());
    expect(
      () => validateOwners([
        {'id': 'a', 'name': 'One', 'shareBps': 4000},
      ]),
      throwsStateError,
    );
    expect(
      () => validateOwners([
        {'id': 'a', 'name': 'A', 'shareBps': 5000},
        {'id': 'a', 'name': 'B', 'shareBps': 5000},
      ]),
      throwsStateError,
    );
  });
  test('money parsing remains exact', () {
    expect(paisa('1,234.56'), 123456);
    expect(() => paisa('1.001'), throwsFormatException);
  });
}
