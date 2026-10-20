import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/ledger.dart';
import '../../data/app_store.dart';

class ReportData {
  final String pharmacy, title, from, to, person, note;
  final bool compactLoan;
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
    this.recordIds = const [],
    this.personIds = const [],
  });
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
            money(e['amount']),
            e['date'],
            '${e['reference'] ?? ''}${e['reversedBy'] != null ? ' (reversed)' : ''}',
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
    summary['Salary remaining'] = money(-sum(closing, 'salary:'));
    summary['Staff advance'] = money(sum(closing, 'salaryAdvance:'));
  }
  if (module == 'zakat') summary['Zakat paid'] = money(sum(period, 'zakat'));
  if (statement) {
    summary['Opening net balance'] = money(balance(before));
    summary['Closing net balance'] = money(balance(closing));
  }
  summary['Records'] = '${records.length}';
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
      pharmacy: a.settings['name'] ?? 'Family Pharmacy',
      title: 'Qarz',
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
      pharmacy: a.settings['name'] ?? 'Family Pharmacy',
      title: 'Qarz',
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
        ? 'Reversal: ${a.typeLabel(byId[e['reference']]?['type'] ?? 'reversal')}'
        : e['module'] == 'orders'
        ? 'Company order'
        : a.typeLabel(e['type']);
    final name = (a.entryName(e)).toString();
    rows.add([
      name.isEmpty ? (e['category'] ?? type) : name,
      '${reversal ? '- ' : ''}${money(e['amount'])}',
      e['date'],
      '$type${e['reversedBy'] != null ? ' (reversed)' : ''}${e['staffName'] == null ? '' : ' / ${e['staffName']}'}',
    ]);
  }
  return ReportData(
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
      money(before),
      type == 'supplier_return' ? '-' : money(reduction),
      type == 'supplier_return' ? money(reduction) : '-',
      money(before + delta),
      e['date'],
    ]);
  }
  return ReportData(
    pharmacy: a.settings['name'] ?? 'Family Pharmacy',
    title: 'Ograi',
    from: from,
    to: to,
    person: party.isEmpty ? '' : a.name(party),
    note: '',
    recordIds: ids,
    headers: [
      if (party.isEmpty) 'Company',
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

bool negativeMoney(String value) => RegExp(r'(^|\s)-\s*\d').hasMatch(value);

Future<List<pw.Font>>? _fonts;
Future<List<pw.Font>> reportFonts() => _fonts ??= Future.wait(
  [
    'assets/fonts/Inter.ttf',
    'assets/fonts/NotoSansArabic.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ].map((p) async => pw.Font.ttf(await rootBundle.load(p))),
);

pw.Widget pdfSummary(ReportData data, PdfColor pale, PdfColor blue) =>
    pw.Container(
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
                  pw.Text(item.key, style: const pw.TextStyle(fontSize: 11)),
                  pw.Text(
                    item.value,
                    style: pw.TextStyle(
                      fontSize: 13,
                      color: negativeMoney(item.value)
                          ? PdfColors.red700
                          : blue,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

Future<Uint8List> buildReportPdf(ReportData data) async {
  final fonts = await reportFonts(), doc = pw.Document();
  final navy = PdfColor.fromHex('#071943'),
      blue = PdfColor.fromHex('#005BEA'),
      pale = PdfColor.fromHex('#EDF4FD');
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
            pw.Text(
              data.pharmacy,
              style: pw.TextStyle(
                fontSize: 23,
                color: navy,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(data.title, style: pw.TextStyle(fontSize: 15, color: blue)),
            if (data.person.isNotEmpty)
              pw.Text(data.person, style: const pw.TextStyle(fontSize: 13)),
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
        if (!data.compactLoan) pdfSummary(data, pale, blue),
        pw.SizedBox(height: 14),
        if (data.note.isNotEmpty)
          pw.Text(
            data.note,
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
          ),
        pw.SizedBox(height: 14),
        if (data.rows.isEmpty) pw.Text('No records in this period.'),
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
                      child: pw.Text(
                        header,
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
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
                        child: pw.Text(
                          data.rows[index][col],
                          style: pw.TextStyle(
                            fontWeight: col == 0 || col == 1
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            fontSize: 9,
                            color: negativeMoney(data.rows[index][col])
                                ? PdfColors.red700
                                : navy,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        if (data.compactLoan) ...[
          pw.SizedBox(height: 14),
          pdfSummary(data, pale, blue),
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
      '${data.title}${data.person.isEmpty ? '' : ' / ${data.person}'}',
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
    canvas.drawRect(const Rect.fromLTWH(30, 155, 1380, 65), paint);
    var x = 45.0;
    for (var col = 0; col < data.headers.length; col++) {
      text(
        data.headers[col],
        x,
        173,
        widths[col] - 20,
        size: 23,
        color: Colors.white,
        bold: true,
      );
      x += widths[col];
    }
    var y = 235.0;
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
      text(item.key, 45, y, 800, bold: true);
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
    final height = (340 + rows.length * 100 + data.summary.length * 46)
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
    write(data.person.isEmpty ? 'Qarz' : data.person, 45, 95, 990, size: 30);
    final paint = Paint()..color = const Color(0xff005bea);
    canvas.drawRect(const Rect.fromLTWH(30, 150, 1020, 60), paint);
    final columns = data.headers.length == 3
        ? [45.0, 400.0, 730.0]
        : [45.0, 250.0, 615.0, 825.0];
    final widths = data.headers.length == 3
        ? [330.0, 315.0, 315.0]
        : [190.0, 350.0, 195.0, 210.0];
    for (var col = 0; col < data.headers.length; col++) {
      write(
        data.headers[col],
        columns[col],
        165,
        widths[col],
        color: Colors.white,
        size: 23,
      );
    }
    var y = 225.0;
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
      write(item.key, 45, y, 600, size: 25);
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
        text: '${data.title}${data.person.isEmpty ? '' : ' - ${data.person}'}',
      ),
    );
  } else {
    await Printing.sharePdf(
      bytes: await buildReportPdf(data),
      filename: '$safe.pdf',
    );
  }
}
