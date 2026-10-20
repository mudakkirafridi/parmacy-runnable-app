import 'dart:convert';
import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
String money(num paisa) => 'Rs ${NumberFormat('#,##0.##').format(paisa / 100)}';
int paisa(String text) {
  final s = text.replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
    throw const FormatException('Enter a valid amount, up to 2 decimal places');
  }
  final p = s.split('.');
  return int.parse(p[0]) * 100 +
      (p.length == 1 ? 0 : int.parse(p[1].padRight(2, '0')));
}

String today() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 5))
    .toIso8601String()
    .substring(0, 10);
Json clone(Json value) => jsonDecode(jsonEncode(value)) as Json;

Map<String, int> loanPositions(Map<String, dynamic> balances) {
  final people = <String, int>{};
  for (final e in balances.entries) {
    if (e.key.startsWith('loanAsset:') || e.key.startsWith('loanDebt:')) {
      final id = e.key.substring(e.key.indexOf(':') + 1);
      people[id] = (people[id] ?? 0) + (e.value as int);
    }
  }
  return people;
}

int loanTotal(Map<String, dynamic> balances, {bool credit = false}) =>
    loanPositions(balances).values
        .where((n) => credit ? n < 0 : n > 0)
        .fold(0, (sum, n) => sum + (credit ? -n : n));

class Ledger {
  final Json types;
  Ledger(this.types);
  Json empty() => {
    'balances': <String, dynamic>{},
    'obligations': <String, dynamic>{},
    'unique': <String, dynamic>{},
    'closed': <String, dynamic>{},
    'accounts': ['cash', 'bank'],
    'unallocated': <String, dynamic>{},
  };
  Never fail(String s) => throw StateError(s);
  bool safe(dynamic n) => n is int && n >= 0 && n <= 900000000000;
  Json post(Json previous, Json input) {
    final s = clone(previous), x = clone(input), t = types[x['type']] as Json?;
    if (t == null) fail('Unknown transaction');
    if (t['retired'] == true) fail('This entry type has been removed');
    final b = s['balances'] as Json, obs = s['obligations'] as Json;
    if (t['onePerDay'] == true &&
        [
          'cash',
          'bank',
          'returns',
          'refundCash',
          'refundBank',
          'retained',
          'credits',
          'reductions',
        ].any(x.containsKey)) {
      fail('Enter only the net daily sale from Abuzar');
    }
    if ((s['closed'] as Json).keys.any((d) => d.compareTo(x['date']) >= 0)) {
      fail('Day is closed. Use an owner correction on an open date.');
    }
    if (!safe(x['amount']) || (t['allowZero'] != true && x['amount'] <= 0)) {
      fail('Enter a positive amount');
    }
    final template = '${t['debit']}${t['credit']}';
    if ((template.contains('{party}') || t['partyRequired'] == true) &&
        (x['party'] ?? '').isEmpty) {
      fail('Select a person or supplier');
    }
    if (template.contains('{account}') &&
        !(s['accounts'] as List).contains(x['account'])) {
      fail('Select a payment account');
    }
    if (x['type'] == 'transfer' &&
        (x['account'] == x['target'] ||
            !(s['accounts'] as List).contains(x['target']))) {
      fail('Select a different destination account');
    }
    if ((t['period'] == true || t['obligation'] == true) &&
        (x['reference'] ?? '').isEmpty) {
      fail('Bill, period or shift reference required');
    }
    final unique = t['onePerDay'] == true
        ? '${x['type']}:${x['date']}'
        : t['obligation'] == true || t['period'] == true
        ? '${x['type']}:${x['party'] ?? ''}:${x['type'] == 'daily_sales' ? '${x['date']}:' : ''}${x['reference']}'
        : null;
    if (unique != null) {
      if (s['unique'][unique] != null) {
        fail('This bill or period is already posted');
      }
      s['unique'][unique] = x['id'];
    }
    final effects = <String, dynamic>{};
    void add(String a, int n) {
      effects[a] = (effects[a] as int? ?? 0) + n;
    }

    String resolve(String a) =>
        a.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => '${x[m[1]] ?? ''}');
    final debit = resolve(t['debit']), credit = resolve(t['credit']);
    add(debit, x['amount']);
    add(credit, -(x['amount'] as int));
    if (t['limit'] == true) {
      final a = ['customer_collection', 'writeoff'].contains(x['type'])
          ? credit
          : x['type'] == 'loan_collect'
          ? credit
          : debit;
      final available =
          (b[a] as int? ?? 0) * (x['type'] == 'loan_repay' ? -1 : 1);
      if (x['amount'] > available &&
          !(x['type'] == 'customer_collection' && x['allowAdvance'] == true)) {
        fail('Amount exceeds outstanding; explicitly allow customer advance');
      }
    }
    if (t['requireCredit'] == true) {
      final a = x['type'] == 'supplier_refund' ? credit : debit;
      final available =
          (b[a] as int? ?? 0) * (x['type'] == 'supplier_refund' ? 1 : -1);
      if (x['amount'] > available) fail('Refund exceeds available credit');
    }
    if (x['type'] == 'salary_apply' && x['amount'] > (b[credit] ?? 0)) {
      fail('Insufficient salary advance');
    }
    var allocated = 0;
    for (final a in x['allocations'] ?? []) {
      final bill = obs[a['id']];
      if (bill == null ||
          bill['party'] != x['party'] ||
          bill['module'] != t['module'] ||
          !safe(a['amount']) ||
          a['amount'] <= 0) {
        fail('Invalid bill allocation');
      }
      if (t['creditReturn'] != true && a['amount'] > bill['remaining']) {
        fail('Allocation exceeds outstanding balance');
      }
      bill['remaining'] -= a['amount'];
      allocated += a['amount'] as int;
    }
    if (allocated > (x['amount'] as int)) fail('Allocation exceeds payment');
    if (t['allocate'] == true &&
        allocated < x['amount'] &&
        t['creditReturn'] != true &&
        x['allowAdvance'] != true) {
      fail('Allocate the payment or explicitly allow an advance');
    }
    if ((x['type'] == 'salary_apply' || t['applyCredit'] == true) &&
        allocated != x['amount']) {
      fail('Allocate the full salary advance');
    }
    final unallocated =
        s.putIfAbsent('unallocated', () => <String, dynamic>{}) as Json;
    final advanceKey = 'supplier:${x['party'] ?? ''}';
    final available = unallocated[advanceKey] as int? ?? 0;
    final int advanceDelta =
        ['supplier_payment', 'supplier_return'].contains(x['type'])
        ? x['amount'] - allocated
        : x['type'] == 'supplier_apply'
        ? -(x['amount'] as int)
        : x['type'] == 'supplier_refund'
        ? -(x['amount'] < available ? x['amount'] as int : available)
        : 0;
    if (available + advanceDelta < 0) fail('Unallocated advance insufficient');
    if (advanceDelta != 0) unallocated[advanceKey] = available + advanceDelta;
    x['advanceDelta'] = advanceDelta;
    if (t['obligation'] == true) {
      obs[x['id']] = {
        'id': x['id'],
        'party': x['party'],
        'module': t['module'],
        'reference': x['reference'],
        'original': x['amount'],
        'remaining': x['amount'],
        'date': x['date'],
        'due': x['due'] ?? x['date'],
      };
    }
    if (effects.values.fold<int>(0, (a, n) => a + (n as int)) != 0) {
      fail('Unbalanced transaction');
    }
    for (final a in effects.keys) {
      b[a] = (b[a] ?? 0) + effects[a];
    }
    return {
      'state': s,
      'entry': {
        ...x,
        'effects': effects,
        'module': t['module'],
        'unique': unique,
        'status': 'posted',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'createdBy': 'demo-owner',
      },
    };
  }

  Json reverse(Json previous, Json original, Json input) {
    if ((input['reason'] ?? '').trim().isEmpty) {
      fail('Correction reason required');
    }
    if (original['reversedBy'] != null || original['type'] == 'reversal') {
      fail('Entry already reversed');
    }
    final s = clone(previous);
    if ((s['closed'] as Json).keys.any(
      (d) => d.compareTo(input['date']) >= 0,
    )) {
      fail('Use an open correction date');
    }
    final own = s['obligations'][original['id']];
    if (own != null && own['remaining'] != own['original']) {
      fail('Reverse linked allocations first');
    }
    s['obligations'].remove(original['id']);
    for (final a in original['allocations'] ?? []) {
      final bill = s['obligations'][a['id']];
      if (bill == null) {
        fail('Linked bill is missing. Refresh records and retry.');
      }
      bill['remaining'] =
          (bill['remaining'] as int? ?? 0) + (a['amount'] as int);
    }
    final effects = <String, dynamic>{};
    for (final a in (original['effects'] as Json).keys) {
      effects[a] = -original['effects'][a];
      s['balances'][a] = (s['balances'][a] as int? ?? 0) + (effects[a] as int);
    }
    final person = original['party'] ?? '';
    if (original['type'] == 'salary_advance' &&
        (s['balances']['salaryAdvance:$person'] ?? 0) < 0) {
      fail('Pehle salary mein apply kiya gaya advance reverse karein.');
    }
    final unallocated =
        s.putIfAbsent('unallocated', () => <String, dynamic>{}) as Json;
    final key = 'supplier:${original['party'] ?? ''}';
    final delta = original['advanceDelta'] as int? ?? 0;
    if (delta != 0) {
      final remaining = (unallocated[key] as int? ?? 0) - delta;
      if (remaining < 0) fail('Reverse linked advance applications first');
      unallocated[key] = remaining;
    }
    if (original['unique'] != null) s['unique'].remove(original['unique']);
    return {
      'state': s,
      'entry': {
        ...input,
        'type': 'reversal',
        'module': original['module'],
        'amount': original['amount'],
        'party': original['party'] ?? '',
        'reference': original['id'],
        'effects': effects,
        'status': 'posted',
        'createdBy': 'demo-owner',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    };
  }
}
