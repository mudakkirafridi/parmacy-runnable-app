import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/ledger.dart';
import '../../core/bilingual.dart';
import '../../core/committee.dart';
import '../../data/app_store.dart';

class ReportData {
  final String pharmacy, title, from, to, person, note;
  final bool compactLoan, urdu;
  final List<String> headers;
  final List<String> recordIds, personIds;
  final List<List<String>> rows;
  final Map<String, String> summary;
  ReportData({
    required this.pharmacy,
    required this.title,
    required this.from,
    required this.to,
    required this.person,
    required this.note,
    required this.headers,
    required this.rows,
    required this.summary,
    this.compactLoan = false,
    this.urdu = false,
    this.recordIds = const [],
    this.personIds = const [],
  });
  String label(String value) => localizedLabel(value, urdu: urdu);
}

ReportData buildReportData(
  AppStore a,
  List<Json> records,
  String from,
  String to,
  String title, {
  String module = 'all',
  String party = '',
  List<Json>? historySource,
}) {
  if (module == 'committee') {
    return buildInstallmentReport(
      a,
      records,
      from,
      to,
      party: party,
      historySource: historySource,
    );
  }
  if (module == 'ograi') {
    return buildOgraiReport(
      a,
      records,
      from,
      to,
      party: party,
      historySource: historySource,
    );
  }
  if (module == 'company_bills') {
    final rows = [...records]..sort((a, b) => a['date'].compareTo(b['date']));
    return ReportData(
      urdu: a.ur,
      pharmacy: a.settings['name'] ?? 'Family Pharmacy',
      title: 'Company bills',
      from: from,
      to: to,
      person: party.isEmpty ? '' : a.name(party),
      note: '',
      recordIds: [for (final e in rows) '${e['id']}'],
      headers: ['Company', 'Amount', 'Date', 'Bill no.'],
      rows: [
        for (final e in rows)
          [
            a.entryName(e),
            '${e['reversedBy'] != null ? '${a.tr('Reversed')} · ' : ''}${money(e['amount'])}',
            e['date'],
            '${e['reference'] ?? ''}${e['reversedBy'] != null ? ' (${a.tr('Reversed')})' : ''}',
          ],
      ],
      summary: {
        'Total bills': money(
          rows
              .where((e) => e['reversedBy'] == null)
              .fold<int>(0, (n, e) => n + (e['amount'] as int)),
        ),
      },
    );
  }
  final history = (historySource ?? a.entries)
      .where(
        (e) =>
            e['date'].compareTo(to) <= 0 &&
            (module == 'all' ||
                (module == 'cashbook'
                    ? (e['effects'] as Json).keys.any(
                        (k) => k.startsWith('money:'),
                      )
                    : module == 'expenses'
                    ? (e['effects'] as Json).keys.any(
                        (k) => k.startsWith('expense:'),
                      )
                    : e['module'] == module)) &&
            (party.isEmpty || e['party'] == party),
      )
      .toList();
  final before = <String, int>{},
      closing = <String, int>{},
      period = <String, int>{};
  for (final e in history) {
    for (final effect in (e['effects'] as Json).entries) {
      closing[effect.key] = (closing[effect.key] ?? 0) + (effect.value as int);
      if (e['date'].compareTo(from) < 0) {
        before[effect.key] = (before[effect.key] ?? 0) + (effect.value as int);
      } else {
        period[effect.key] = (period[effect.key] ?? 0) + (effect.value as int);
      }
    }
  }
  int sum(Map<String, int> source, String prefix) => source.entries
      .where((e) => e.key.startsWith(prefix))
      .fold(0, (s, e) => s + e.value);
  int net(Map<String, int> source) =>
      -(source['netSales'] ?? 0) -
      (source['sales'] ?? 0) -
      (source['returns'] ?? 0);
  final summary = <String, String>{};
  final person = party.isEmpty ? '' : a.name(party);
  final statement = party.isNotEmpty && ['loans', 'suppliers'].contains(module);
  int balance(Map<String, int> source) => module == 'suppliers'
      ? -(source['supplier:$party'] ?? 0)
      : (source['loanAsset:$party'] ?? 0) + (source['loanDebt:$party'] ?? 0);
  const note = '';
  if (module == 'loans') {
    summary['Qarz baqaya'] = money(loanTotal(closing));
    summary['Jama'] = money(loanTotal(closing, credit: true));
  } else if (module == 'suppliers') {
    summary['Remaining payable'] = money(-sum(closing, 'supplier:'));
  } else if (module == 'orders') {
    summary['Total order value'] = money(
      records.fold<int>(0, (s, e) => s + (e['amount'] as int)),
    );
    summary['Pending orders'] =
        '${records.where((e) => e['status'] == 'open').length}';
  } else {
    if (module == 'all' || module == 'sales') {
      summary['Net sale (period)'] = money(net(period));
    }
    if (module == 'all' ||
        module == 'expenses' ||
        module == 'rent' ||
        module == 'salary') {
      summary['Expenses (period)'] = money(sum(period, 'expense:'));
    }
    if (module == 'all' || module == 'cashbook') {
      summary['Cash movement (period)'] = money(period['money:cash'] ?? 0);
      summary['Bank movement (period)'] = money(period['money:bank'] ?? 0);
    }
    if (module == 'all') {
      summary['Qarz baqaya'] = money(loanTotal(closing));
      summary['Jama'] = money(loanTotal(closing, credit: true));
    }
  }
  if (module == 'salary') {
    final staff = <String>{
      for (final key in closing.keys.where(
        (k) => k.startsWith('salary:') || k.startsWith('salaryAdvance:'),
      ))
        key.substring(key.indexOf(':') + 1),
    };
    var due = 0, advance = 0;
    for (final id in staff) {
      final net =
          -(closing['salary:$id'] ?? 0) - (closing['salaryAdvance:$id'] ?? 0);
      if (net > 0) {
        due += net;
      } else {
        advance -= net;
      }
    }
    summary['Salary remaining'] = money(due);
    summary['Staff advance'] = money(advance);
  }
  if (module == 'zakat') summary['Zakat paid'] = money(sum(period, 'zakat'));
  if (statement) {
    summary['Opening net balance'] = money(balance(before));
    summary['Closing net balance'] = money(balance(closing));
  }
  if (module == 'committee') {
    final plans = a.profiles.where(
      (p) => p['module'] == 'committee' && (party.isEmpty || p['id'] == party),
    );
    var paid = 0, received = 0, remaining = 0;
    for (final c in CommitteeProgress.all(
      plans,
      historySource ?? a.entries,
    ).values) {
      paid += c.paid;
      received += c.received;
      remaining += c.remaining;
    }
    summary.clear();
    summary.addAll({
      'Qist di': money(paid),
      'Committee mili': money(received),
      'Qistain baqi': money(remaining),
    });
  }
  if (module == 'all') {
    final balances = Json.from(a.state['balances']);
    final staffIds = <String>{
      for (final key in balances.keys.where(
        (k) => k.startsWith('salary:') || k.startsWith('salaryAdvance:'),
      ))
        key.substring(key.indexOf(':') + 1),
    };
    var salary = 0, companies = 0;
    for (final id in staffIds) {
      final due =
          -(balances['salary:$id'] as int? ?? 0) -
          (balances['salaryAdvance:$id'] as int? ?? 0);
      if (due > 0) salary += due;
    }
    for (final e in balances.entries.where(
      (e) => e.key.startsWith('supplier:'),
    )) {
      if ((e.value as int) < 0) companies -= e.value as int;
    }
    summary.clear();
    summary.addAll({
      'Qarz baqaya': money(loanTotal(balances)),
      'Remaining salary': money(salary),
      'Remaining company payments': money(companies),
    });
  } else {
    summary['Records'] = '${records.length}';
  }
  final chronology = {
    for (var i = 0; i < a.entries.length; i++) a.entries[i]['id']: i,
  };
  final sorted = List<Json>.from(records)
    ..sort((x, y) {
      final d = x['date'].compareTo(y['date']) as int;
      if (d != 0) return d;
      final time = '${x['createdAt'] ?? ''}'.compareTo(
        '${y['createdAt'] ?? ''}',
      );
      if (time != 0) return time;
      return (chronology[y['id']] ?? 0).compareTo(chronology[x['id']] ?? 0);
    });
  if (module == 'loans' && party.isEmpty) {
    final totals = <String, List<int>>{};
    final originals = {for (final e in a.entries) e['id']: e};
    for (final e in sorted) {
      final id = '${e['party']}';
      if (id.isEmpty) continue;
      final reversed = e['type'] == 'reversal';
      final source = reversed ? originals[e['reference']] ?? e : e;
      final out = [
        'loan_lend',
        'loan_repay',
        'opening_loan_asset',
      ].contains(source['type']);
      final amount = (e['amount'] as int) * (reversed ? -1 : 1);
      final row = totals.putIfAbsent(id, () => [0, 0]);
      row[out ? 0 : 1] += amount;
    }
    final ids = totals.keys.toList()
      ..sort(
        (x, y) => a.name(x).toLowerCase().compareTo(a.name(y).toLowerCase()),
      );
    final positions = loanPositions(closing);
    return ReportData(
      urdu: a.ur,
      pharmacy: a.settings['name'] ?? 'Family Pharmacy',
      title: 'Loans',
      from: from,
      to: to,
      person: '',
      note: '',
      compactLoan: true,
      headers: ['Name', 'Qarz', 'Qarz wosool', 'Balance'],
      personIds: ids,
      rows: [
        for (final id in ids)
          [
            a.name(id),
            money(totals[id]![0]),
            money(totals[id]![1]),
            money(positions[id] ?? 0),
          ],
      ],
      summary: {
        'Net balance': money(positions.values.fold<int>(0, (a, b) => a + b)),
      },
    );
  }
  if (module == 'loans') {
    final rows = <List<String>>[];
    final originals = {for (final e in a.entries) e['id']: e};
    for (final e in sorted) {
      final reversing = e['type'] == 'reversal';
      final source = reversing ? originals[e['reference']] ?? e : e;
      final out = [
        'loan_lend',
        'loan_repay',
        'opening_loan_asset',
      ].contains(source['type']);
      final amount = (e['amount'] as int) * (reversing ? -1 : 1);
      rows.add([
        e['date'],
        if (party.isEmpty)
          '${a.name(e['party'])}${reversing ? ' (reverse)' : ''}',
        out ? money(amount) : '-',
        out ? '-' : money(amount),
      ]);
    }
    final loanSummary = <String, String>{
      'Net balance': money(
        sum(closing, 'loanAsset:') + sum(closing, 'loanDebt:'),
      ),
    };
    return ReportData(
      urdu: a.ur,
      pharmacy: a.settings['name'] ?? 'Family Pharmacy',
      title: 'Loans',
      from: from == '2000-01-01' && sorted.isNotEmpty
          ? sorted.first['date']
          : from,
      to: to,
      person: person,
      note: '',
      compactLoan: true,
      recordIds: [for (final e in sorted) '${e['id']}'],
      headers: ['Date', if (party.isEmpty) 'Name', 'Lena hai', 'Dena hai'],
      rows: rows,
      summary: loanSummary,
    );
  }
  final rows = <List<String>>[];
  final byId = {for (final e in a.entries) e['id']: e};
  for (final e in sorted) {
    final reversal = e['type'] == 'reversal';
    final type = reversal
        ? '${a.tr('Reversal')}: ${a.typeLabel(byId[e['reference']]?['type'] ?? 'reversal')}'
        : e['module'] == 'orders'
        ? a.tr('Company order')
        : a.typeLabel(e['type']);
    final name = (a.entryName(e)).toString();
    rows.add([
      name.isEmpty ? (e['category'] ?? type) : name,
      '${reversal ? '- ' : ''}${money(e['amount'])}',
      e['date'],
      '$type${e['reversedBy'] != null ? ' (${a.tr('Reversed')})' : ''}${e['staffName'] == null ? '' : ' / ${e['staffName']}'}',
    ]);
  }
  return ReportData(
    urdu: a.ur,
    pharmacy: a.settings['name'] ?? 'Family Pharmacy',
    title: title,
    from: from,
    to: to,
    person: person,
    note: note,
    recordIds: [for (final e in sorted) '${e['id']}'],
    headers: ['Name', 'Amount', 'Date', 'Entry'],
    rows: rows,
    summary: summary,
  );
}

ReportData buildOgraiReport(
  AppStore a,
  List<Json> records,
  String from,
  String to, {
  String party = '',
  List<Json>? historySource,
}) {
  final all = historySource ?? a.entries;
  final byId = {for (final e in all) e['id']: e};
  final rank = {for (var i = 0; i < all.length; i++) all[i]['id']: i};
  final history =
      all
          .where(
            (e) =>
                e['module'] == 'suppliers' &&
                e['date'].compareTo(to) <= 0 &&
                (party.isEmpty || e['party'] == party),
          )
          .toList()
        ..sort((x, y) {
          final date = x['date'].compareTo(y['date']) as int;
          if (date != 0) return date;
          final time = '${x['createdAt'] ?? ''}'.compareTo(
            '${y['createdAt'] ?? ''}',
          );
          return time != 0
              ? time
              : (rank[y['id']] ?? 0).compareTo(rank[x['id']] ?? 0);
        });
  final selected = records.map((e) => e['id']).toSet(),
      balances = <String, int>{};
  final rows = <List<String>>[], ids = <String>[];
  final shownDays = <String>{};
  for (final e in history) {
    final id = '${e['party']}';
    final before = balances[id] ?? 0;
    final delta = -((e['effects'] as Json?)?['supplier:$id'] as int? ?? 0);
    balances[id] = before + delta;
    final reverse = e['type'] == 'reversal';
    final type = reverse ? (byId[e['reference']]?['type']) : e['type'];
    if (![
          'supplier_payment',
          'supplier_return',
          'supplier_refund',
        ].contains(type) ||
        !selected.contains(e['id']) ||
        e['date'].compareTo(from) < 0) {
      continue;
    }
    ids.add(e['id']);
    final reduction = -delta;
    rows.add([
      if (party.isEmpty) a.entryName(e),
      shownDays.add('$id:${e['date']}')
          ? money(
              history
                  .where(
                    (b) =>
                        b['type'] == 'supplier_bill' &&
                        b['party'] == id &&
                        b['date'] == e['date'] &&
                        b['reversedBy'] == null,
                  )
                  .fold<int>(0, (n, b) => n + (b['amount'] as int)),
            )
          : '-',
      money(before),
      type == 'supplier_return' ? '-' : money(reduction),
      type == 'supplier_return' ? money(reduction) : '-',
      money(before + delta),
      e['date'],
    ]);
  }
  return ReportData(
    urdu: a.ur,
    pharmacy: a.settings['name'] ?? 'Family Pharmacy',
    title: 'Ograi',
    from: from,
    to: to,
    person: party.isEmpty ? '' : a.name(party),
    note: '',
    recordIds: ids,
    headers: [
      if (party.isEmpty) 'Company',
      'Day bills',
      'Before',
      'Paid',
      'Return',
      'Remaining',
      'Date',
    ],
    rows: rows,
    summary: {
      'Remaining': money(balances.values.fold<int>(0, (a, b) => a + b)),
    },
  );
}

ReportData buildInstallmentReport(
  AppStore a,
  List<Json> records,
  String from,
  String to, {
  String party = '',
  List<Json>? historySource,
}) {
  final all = historySource ?? a.entries,
      byId = {for (final e in (historySource ?? a.entries)) e['id']: e};
  final rank = {for (var i = 0; i < all.length; i++) all[i]['id']: i};
  final history =
      all
          .where(
            (e) =>
                e['module'] == 'committee' &&
                (party.isEmpty || e['party'] == party) &&
                '${e['date']}'.compareTo(to) <= 0,
          )
          .toList()
        ..sort((x, y) {
          final d = '${x['date']}'.compareTo('${y['date']}');
          if (d != 0) return d;
          final t = '${x['createdAt'] ?? ''}'.compareTo(
            '${y['createdAt'] ?? ''}',
          );
          return t != 0
              ? t
              : (rank[y['id']] ?? 0).compareTo(rank[x['id']] ?? 0);
        });
  final plans = {
    for (final p in a.profiles.where((p) => p['module'] == 'committee'))
      p['id']: p,
  };
  final paid = <String, int>{},
      selected = records.map((e) => e['id']).toSet(),
      rows = <List<String>>[],
      ids = <String>[];
  for (final e in history) {
    final id = '${e['party']}', total = plans[id]?['totalAmount'] as int? ?? 0;
    final before = total - (paid[id] ?? 0),
        source = e['type'] == 'reversal' ? byId[e['reference']] : e;
    final delta = ((e['effects'] as Json?)?['committee:$id'] as int?) ?? 0;
    final pay = source?['type'] == 'committee_pay';
    if (pay) paid[id] = (paid[id] ?? 0) + delta;
    if (!selected.contains(e['id']) || '${e['date']}'.compareTo(from) < 0) {
      continue;
    }
    ids.add(e['id']);
    rows.add([
      if (party.isEmpty) a.entryName(e),
      money(before),
      pay ? money(delta) : '-',
      pay ? '-' : money(-delta),
      money(total - (paid[id] ?? 0)),
      e['date'],
    ]);
  }
  final progress = CommitteeProgress.all(
    plans.values.where((p) => party.isEmpty || p['id'] == party),
    all,
  );
  return ReportData(
    urdu: a.ur,
    pharmacy: a.settings['name'] ?? 'Family Pharmacy',
    title: 'Installment',
    from: from,
    to: to,
    person: party.isEmpty ? '' : a.name(party),
    note: '',
    headers: [
      if (party.isEmpty) 'Name',
      'Balance',
      'Paid',
      'Received',
      'Remaining',
      'Date',
    ],
    rows: rows,
    recordIds: ids,
    summary: {
      'Total amount': money(
        progress.values.fold<int>(0, (n, p) => n + p.total),
      ),
      'Paid': money(progress.values.fold<int>(0, (n, p) => n + p.paid)),
      'Received': money(progress.values.fold<int>(0, (n, p) => n + p.received)),
      'Remaining': money(
        progress.values.fold<int>(0, (n, p) => n + p.remaining),
      ),
    },
  );
}

ReportData latestReportData(ReportData data) {
  final dateCol = data.headers.indexOf('Date');
  if (dateCol < 0) return data;
  final order = List.generate(data.rows.length, (i) => i)
    ..sort((x, y) {
      final d = data.rows[y][dateCol].compareTo(data.rows[x][dateCol]);
      return d != 0 ? d : y.compareTo(x);
    });
  final dayCol = data.headers.indexOf('Day bills'),
      companyCol = data.headers.indexOf('Company');
  String dayKey(List<String> row) =>
      '${companyCol < 0 ? data.person : row[companyCol]}:${row[dateCol]}';
  final totals = <String, String>{};
  if (dayCol >= 0) {
    for (final row in data.rows) {
      if (row[dayCol] != '-') totals[dayKey(row)] = row[dayCol];
    }
  }
  final seen = <String>{};
  final rows = <List<String>>[];
  for (final i in order) {
    final row = [...data.rows[i]];
    if (dayCol >= 0) {
      row[dayCol] = seen.add(dayKey(row)) ? totals[dayKey(row)] ?? '-' : '-';
    }
    rows.add(row);
  }
  return ReportData(
    urdu: data.urdu,
    pharmacy: data.pharmacy,
    title: data.title,
    from: data.from,
    to: data.to,
    person: data.person,
    note: data.note,
    headers: data.headers,
    rows: rows,
    summary: data.summary,
    compactLoan: data.compactLoan,
    recordIds: [
      for (final i in order)
        if (i < data.recordIds.length) data.recordIds[i],
    ],
    personIds: [
      for (final i in order)
        if (i < data.personIds.length) data.personIds[i],
    ],
  );
}

bool negativeMoney(String value) =>
    RegExp(r'(^|\s)-\s*\d').hasMatch(value) ||
    value.toLowerCase().contains('revers');

Future<List<pw.Font>>? _fonts;
Future<List<pw.Font>> reportFonts() => _fonts ??= Future.wait(
  [
    'assets/fonts/Inter.ttf',
    'assets/fonts/NotoSansArabic.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ].map((p) async => pw.Font.ttf(await rootBundle.load(p))),
);

// Flutter's text shaper keeps mixed English/Urdu labels correct in exported PDFs.
// Amounts and dates remain native PDF text.
class PdfLabels {
  final images = <String, (pw.MemoryImage, double, double)>{};
  String key(String value, double size, double width, int color, bool bold) =>
      '$value|$size|$width|$color|$bold';
  bool arabic(String value) => RegExp(r'[\u0600-\u06ff]').hasMatch(value);
  Future<void> prepare(
    String value, {
    double size = 11,
    double width = 300,
    int color = 0xff071943,
    bool bold = false,
  }) async {
    if (!arabic(value)) return;
    final k = key(value, size, width, color, bold);
    if (images.containsKey(k)) return;
    const scale = 4.0;
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoArabic'],
          fontSize: size * scale,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: Color(color),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width * scale);
    final rec = ui.PictureRecorder(), canvas = Canvas(rec);
    painter.paint(canvas, Offset.zero);
    final picture = rec.endRecording();
    final img = await picture.toImage(
      painter.width.ceil().clamp(1, 10000),
      painter.height.ceil().clamp(1, 10000),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    images[k] = (
      pw.MemoryImage(bytes!.buffer.asUint8List()),
      painter.width / scale,
      painter.height / scale,
    );
    img.dispose();
    picture.dispose();
  }

  pw.Widget text(
    String value, {
    double size = 11,
    double width = 300,
    int color = 0xff071943,
    bool bold = false,
  }) {
    final image = images[key(value, size, width, color, bold)];
    if (image != null) {
      return pw.Image(image.$1, width: image.$2, height: image.$3);
    }
    return pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: PdfColor(
          ((color >> 16) & 255) / 255,
          ((color >> 8) & 255) / 255,
          (color & 255) / 255,
        ),
      ),
    );
  }
}

pw.Widget pdfSummary(
  ReportData data,
  PdfColor pale,
  PdfColor blue,
  PdfLabels labels,
) => pw.Container(
  padding: const pw.EdgeInsets.all(12),
  decoration: pw.BoxDecoration(
    color: pale,
    borderRadius: pw.BorderRadius.circular(7),
  ),
  child: pw.Column(
    children: [
      for (final item in data.summary.entries)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              labels.text(data.label(item.key)),
              pw.Text(
                item.value,
                style: pw.TextStyle(
                  fontSize: 13,
                  color: negativeMoney(item.value) ? PdfColors.red700 : blue,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
    ],
  ),
);

pw.TextDirection pdfDirection(String value) =>
    RegExp(r'[\u0600-\u06ff]').hasMatch(value)
    ? pw.TextDirection.rtl
    : pw.TextDirection.ltr;

Future<Uint8List> buildReportPdf(ReportData data) async {
  final fonts = await reportFonts(), doc = pw.Document();
  await (_pictureFonts ??= _loadPictureFonts());
  final labels = PdfLabels(),
      bodyWidth =
          (data.headers.length > 5
              ? PdfPageFormat.a4.landscape.width
              : PdfPageFormat.a4.width) -
          64;
  final weights = [
        for (final h in data.headers)
          ['Name', 'Company', 'Entry'].contains(h) ? 1.6 : 1.0,
      ],
      weight = data.headers.fold<double>(
        0,
        (n, h) => n + (['Name', 'Company', 'Entry'].contains(h) ? 1.6 : 1),
      );
  await labels.prepare(data.pharmacy, size: 23, width: bodyWidth, bold: true);
  await labels.prepare(
    data.label(data.title),
    size: 15,
    width: bodyWidth,
    color: 0xff005bea,
  );
  await labels.prepare(data.person, size: 13, width: bodyWidth);
  await labels.prepare(data.label('No records in this period.'));
  for (final k in data.summary.keys) {
    await labels.prepare(data.label(k));
  }
  for (var col = 0; col < data.headers.length; col++) {
    final width = bodyWidth * weights[col] / weight - 16;
    await labels.prepare(
      data.label(data.headers[col]),
      size: 10,
      width: width,
      color: 0xffffffff,
    );
    for (final row in data.rows) {
      await labels.prepare(
        row[col],
        size: 9,
        width: width,
        bold: col < 2,
        color: negativeMoney(row[col]) ? 0xffb71c1c : 0xff071943,
      );
    }
  }
  final blue = PdfColor.fromHex('#005BEA'), pale = PdfColor.fromHex('#EDF4FD');
  doc.addPage(
    pw.MultiPage(
      maxPages: 1000,
      pageFormat: data.headers.length > 5
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(
        base: fonts[0],
        bold: fonts[2],
        fontFallback: [fonts[1]],
      ),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            labels.text(data.pharmacy, size: 23, width: bodyWidth, bold: true),
            pw.SizedBox(height: 5),
            labels.text(
              data.label(data.title),
              size: 15,
              width: bodyWidth,
              color: 0xff005bea,
            ),
            if (data.person.isNotEmpty)
              labels.text(data.person, size: 13, width: bodyWidth),
            pw.SizedBox(height: 6),
            pw.SizedBox(height: 8),
            pw.Divider(color: blue),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        if (!data.compactLoan) pdfSummary(data, pale, blue, labels),
        pw.SizedBox(height: 14),
        if (data.note.isNotEmpty)
          pw.Text(
            data.note,
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
          ),
        pw.SizedBox(height: 14),
        if (data.rows.isEmpty)
          labels.text(data.label('No records in this period.')),
        if (data.rows.isNotEmpty)
          pw.Table(
            columnWidths: {
              for (var col = 0; col < data.headers.length; col++)
                col: pw.FlexColumnWidth(
                  data.headers[col] == 'Name' ||
                          data.headers[col] == 'Company' ||
                          data.headers[col] == 'Entry'
                      ? 1.6
                      : 1,
                ),
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .3),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: blue),
                children: [
                  for (final header in data.headers)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: labels.text(
                        data.label(header),
                        size: 10,
                        width:
                            bodyWidth *
                                weights[data.headers.indexOf(header)] /
                                weight -
                            16,
                        color: 0xffffffff,
                      ),
                    ),
                ],
              ),
              for (var index = 0; index < data.rows.length; index++)
                pw.TableRow(
                  decoration: index.isOdd
                      ? pw.BoxDecoration(color: pale)
                      : null,
                  children: [
                    for (var col = 0; col < data.rows[index].length; col++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: labels.text(
                          data.rows[index][col],
                          size: 9,
                          width: bodyWidth * weights[col] / weight - 16,
                          bold: col < 2,
                          color: negativeMoney(data.rows[index][col])
                              ? 0xffb71c1c
                              : 0xff071943,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        if (data.compactLoan) ...[
          pw.SizedBox(height: 14),
          pdfSummary(data, pale, blue, labels),
        ],
      ],
    ),
  );
  return doc.save();
}

Future<void>? _pictureFonts;
Future<void> _loadPictureFonts() async {
  final latin = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
  final arabic = FontLoader('NotoArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
  await Future.wait([latin.load(), arabic.load()]);
}

Future<List<Uint8List>> buildReportPictures(ReportData data) async {
  await (_pictureFonts ??= _loadPictureFonts());
  return buildTablePictures(data);
}

Future<List<Uint8List>> buildTablePictures(ReportData data) async {
  if (data.rows.length > 400) throw StateError('Select fewer dates or use PDF');
  const width = 1440.0;
  final output = <Uint8List>[];
  final count = data.rows.isEmpty ? 1 : (data.rows.length / 10).ceil();
  for (var page = 0; page < count; page++) {
    final rows = data.rows.skip(page * 10).take(10).toList();
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    void text(
      String value,
      double x,
      double y,
      double max, {
      double size = 25,
      Color color = const Color(0xff071943),
      bool bold = false,
    }) {
      final t = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoArabic'],
            fontSize: size,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max);
      t.paint(canvas, Offset(x, y));
    }

    text(data.pharmacy, 45, 35, 1350, size: 38, bold: true);
    text(
      '${data.label(data.title)}${data.person.isEmpty ? '' : ' / ${data.person}'}',
      45,
      95,
      1350,
      size: 29,
      color: const Color(0xff005bea),
    );
    final weights = [
      for (final h in data.headers)
        ['Name', 'Company', 'Entry'].contains(h) ? 1.6 : 1.0,
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);
    final widths = [for (final w in weights) 1350 * w / total];
    final paint = Paint()..color = const Color(0xff005bea);
    var headerHeight = 65.0;
    for (var i = 0; i < data.headers.length; i++) {
      final p = TextPainter(
        text: TextSpan(
          text: data.label(data.headers[i]),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoArabic'],
            fontSize: 23,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: widths[i] - 20);
      if (p.height + 30 > headerHeight) headerHeight = p.height + 30;
    }
    canvas.drawRect(Rect.fromLTWH(30, 155, 1380, headerHeight), paint);
    var x = 45.0;
    for (var col = 0; col < data.headers.length; col++) {
      text(
        data.label(data.headers[col]),
        x,
        173,
        widths[col] - 20,
        size: 23,
        color: Colors.white,
        bold: true,
      );
      x += widths[col];
    }
    var y = 155 + headerHeight + 15;
    for (final row in rows) {
      var height = 75.0;
      for (var col = 0; col < row.length; col++) {
        final t = TextPainter(
          text: TextSpan(
            text: row[col],
            style: const TextStyle(
              fontSize: 25,
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoArabic'],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: widths[col] - 20);
        if (t.height + 28 > height) height = t.height + 28;
      }
      paint.color = const Color(0xffedf4fd);
      canvas.drawRect(Rect.fromLTWH(30, y, 1380, height), paint);
      x = 45;
      for (var col = 0; col < row.length; col++) {
        text(
          row[col],
          x,
          y + 14,
          widths[col] - 20,
          bold: col == 0,
          color: negativeMoney(row[col])
              ? Colors.red.shade700
              : const Color(0xff071943),
        );
        x += widths[col];
      }
      y += height + 6;
    }
    y += 25;
    for (final item in data.summary.entries) {
      text(data.label(item.key), 45, y, 800, bold: true);
      text(
        item.value,
        1020,
        y,
        375,
        bold: true,
        color: negativeMoney(item.value)
            ? Colors.red.shade700
            : const Color(0xff005bea),
      );
      y += 48;
    }
    text('${page + 1}/$count', 1300, y + 10, 100, size: 20);
    final picture = recorder.endRecording(),
        image = await picture.toImage(width.toInt(), (y + 80).ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    output.add(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  }
  return output;
}

Future<List<Uint8List>> buildLoanPictures(ReportData data) async {
  final result = <Uint8List>[];
  if (data.rows.length > 400) throw StateError('Select fewer dates or use PDF');
  final pages = data.rows.isEmpty ? 1 : (data.rows.length / 10).ceil();
  for (var page = 0; page < pages; page++) {
    final rows = data.rows.skip(page * 10).take(10).toList();
    var height = (340 + rows.length * 100 + data.summary.length * 46)
        .toDouble();
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    void write(
      String value,
      double x,
      double y,
      double width, {
      double size = 25,
      Color color = const Color(0xff071943),
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoArabic'],
            fontSize: size,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: width);
      painter.paint(canvas, Offset(x, y));
    }

    write(data.pharmacy, 45, 35, 990, size: 36);
    write(
      data.person.isEmpty ? data.label('Loans') : data.person,
      45,
      95,
      990,
      size: 30,
    );
    final paint = Paint()..color = const Color(0xff005bea);

    final columns = data.headers.length == 3
        ? [45.0, 400.0, 730.0]
        : [45.0, 250.0, 615.0, 825.0];
    final widths = data.headers.length == 3
        ? [330.0, 315.0, 315.0]
        : [190.0, 350.0, 195.0, 210.0];
    var headerHeight = 60.0;
    for (var col = 0; col < data.headers.length; col++) {
      final t = TextPainter(
        text: TextSpan(
          text: data.label(data.headers[col]),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoArabic'],
            fontSize: 23,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: widths[col]);
      if (t.height + 30 > headerHeight) headerHeight = t.height + 30;
    }
    height += headerHeight - 60;
    canvas.drawRect(Rect.fromLTWH(30, 150, 1020, headerHeight), paint);
    for (var col = 0; col < data.headers.length; col++) {
      write(
        data.label(data.headers[col]),
        columns[col],
        165,
        widths[col],
        color: Colors.white,
        size: 23,
      );
    }
    var y = 150 + headerHeight + 15;
    for (final row in rows) {
      paint.color = const Color(0xffedf4fd);
      canvas.drawRect(Rect.fromLTWH(30, y - 5, 1020, 90), paint);
      for (var col = 0; col < data.headers.length; col++) {
        write(
          row[col],
          columns[col],
          y + 8,
          widths[col],
          size: 23,
          color: negativeMoney(row[col])
              ? Colors.red.shade700
              : const Color(0xff071943),
        );
      }
      y += 100;
    }
    y += 15;
    for (final item in data.summary.entries) {
      write(data.label(item.key), 45, y, 600, size: 25);
      write(
        item.value,
        735,
        y,
        300,
        size: 26,
        color: negativeMoney(item.value)
            ? Colors.red.shade700
            : const Color(0xff005bea),
      );
      y += 46;
    }
    write('${page + 1}/$pages', 950, height - 45, 90, size: 20);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1080, height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    result.add(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  }
  return result;
}

Future<void> shareReport(ReportData data, {bool picture = false}) async {
  final safe = 'hisab-${data.from}-${data.to}';
  if (picture) {
    final pages = await buildReportPictures(data);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (var i = 0; i < pages.length; i++)
            XFile.fromData(
              pages[i],
              mimeType: 'image/png',
              name: '$safe-${i + 1}.png',
            ),
        ],
        text:
            '${data.label(data.title)}${data.person.isEmpty ? '' : ' - ${data.person}'}',
      ),
    );
  } else {
    await Printing.sharePdf(
      bytes: await buildReportPdf(data),
      filename: '$safe.pdf',
    );
  }
}
