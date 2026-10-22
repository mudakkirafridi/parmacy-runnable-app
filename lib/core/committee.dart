import 'ledger.dart';

class CommitteeProgress {
  final int paid, received, total, installment;
  final String frequency, start;
  CommitteeProgress(
    this.paid,
    this.received,
    this.total,
    this.installment,
    this.frequency,
    this.start,
  );
  factory CommitteeProgress.from(Json profile, List<Json> entries) =>
      all([profile], entries)[profile['id']]!;
  static Map<String, CommitteeProgress> all(
    Iterable<Json> profiles,
    List<Json> entries,
  ) {
    final byId = {for (final e in entries) e['id']: e},
        paid = <String, int>{},
        received = <String, int>{};
    for (final e in entries.where((e) => e['module'] == 'committee')) {
      final id = '${e['party']}',
          source = e['type'] == 'reversal' ? byId[e['reference']] : e;
      final delta = ((e['effects'] as Json?)?['committee:$id'] as int?) ?? 0;
      if (source?['type'] == 'committee_pay') {
        paid[id] = (paid[id] ?? 0) + delta;
      }
      if (source?['type'] == 'committee_receive') {
        received[id] = (received[id] ?? 0) - delta;
      }
    }
    return {
      for (final p in profiles)
        '${p['id']}': CommitteeProgress(
          paid[p['id']] ?? 0,
          received[p['id']] ?? 0,
          p['totalAmount'] as int? ?? 0,
          p['installmentAmount'] as int? ?? 0,
          p['frequency'] ?? 'Monthly',
          p['startDate'] ?? today(),
        ),
    };
  }

  int get remaining => (total - paid).clamp(0, 900000000000);
  int get balance => paid - received;
  String? get nextDate {
    if (remaining == 0 || installment <= 0) return null;
    final count = paid ~/ installment, anchor = DateTime.parse(start);
    final DateTime next;
    if (frequency == 'Monthly') {
      final month = DateTime(anchor.year, anchor.month + count, 1);
      final last = DateTime(month.year, month.month + 1, 0).day;
      next = DateTime(month.year, month.month, anchor.day.clamp(1, last));
    } else {
      next = anchor.add(
        Duration(days: count * (frequency == 'Weekly' ? 7 : 1)),
      );
    }
    return next.toIso8601String().substring(0, 10);
  }
}
