part of '../../ui/screens.dart';

const reportMenus = {
  'all': 'All reports',
  'committee': 'Installment',
  'company_bills': 'Company bills',
  'ograi': 'Company payment',
  'loans': 'Loan reports',
  'expenses': 'Expense reports',
  'suppliers': 'Company reports',
  'orders': 'Order reports',
  'sales': 'Sale reports',
  'salary': 'Salary reports',
  'zakat': 'Zakat reports',
  'cashbook': 'Cashbook reports',
  'owner': 'Owner reports',
};
String reportModule(String module) =>
    ['ograi', 'company_bills'].contains(module) ? 'suppliers' : module;

class ReportsScreen extends ConsumerStatefulWidget {
  final String? initialModule, initialParty;
  const ReportsScreen({super.key, this.initialModule, this.initialParty});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<ReportsScreen> {
  String? module;
  String party = '', from = '2000-01-01', to = today(), search = '';
  bool sharing = false;
  @override
  void initState() {
    super.initState();
    module = widget.initialModule == 'rent'
        ? 'expenses'
        : widget.initialModule ?? 'all';
    party = widget.initialParty ?? '';
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialModule != widget.initialModule ||
        oldWidget.initialParty != widget.initialParty) {
      module = widget.initialModule == 'rent'
          ? 'expenses'
          : widget.initialModule ?? 'all';
      party = widget.initialParty ?? '';
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    const menus = reportMenus;
    final raw = <Json>[
      if (module != 'orders') ...a.entries,
      if (module == 'orders' || module == 'all')
        ...a.orders.map(
          (o) => <String, dynamic>{
            ...o,
            'module': 'orders',
            'type': 'order',
            'partyName': o['companyName'],
            'effects': <String, dynamic>{},
          },
        ),
    ];
    final periodRecords = raw
        .where(
          (e) =>
              a.entryVisible(e) &&
              (module == 'all' ||
                  (module == 'cashbook'
                      ? (e['effects'] as Json).keys.any(
                          (k) => k.startsWith('money:'),
                        )
                      : module == 'expenses'
                      ? (e['effects'] as Json).keys.any(
                          (k) => k.startsWith('expense:'),
                        )
                      : module == 'company_bills'
                      ? e['type'] == 'supplier_bill'
                      : e['module'] == reportModule(module!))) &&
              e['date'].compareTo(from) >= 0 &&
              e['date'].compareTo(to) <= 0 &&
              (party.isEmpty || e['party'] == party) &&
              '${a.name(e['party'])} ${e['reference']} ${e['category']} ${e['notes']}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    final people = {
      for (final p in a.profiles.where(
        (p) =>
            module == 'all' ||
            p['module'] ==
                (module == 'orders' ? 'suppliers' : reportModule(module!)),
      ))
        p['id'].toString(): p['name'].toString(),
    };
    if (party.isNotEmpty) people.putIfAbsent(party, () => a.name(party));
    final data = buildReportData(
      a,
      periodRecords,
      from,
      to,
      menus[module] ?? 'Report',
      module: module!,
      party: party,
    );
    final display = latestReportData(data);
    Future<void> share(bool picture) async {
      if (sharing) return;
      setState(() => sharing = true);
      try {
        await shareReport(data, picture: picture);
      } catch (e) {
        if (c.mounted) toast(c, e.toString());
      } finally {
        if (mounted) setState(() => sharing = false);
      }
    }

    return Frame(
      title: menus[module] ?? 'Reports',
      tab: 2,
      body: ListView.builder(
        padding: const EdgeInsets.all(17),
        itemCount: data.rows.length + 1,
        itemBuilder: (context, index) {
          if (index > 0) {
            final row = display.rows[index - 1];
            final id = index <= display.recordIds.length
                ? display.recordIds[index - 1]
                : null;
            final entry = a.entries.where((e) => e['id'] == id).firstOrNull;
            final order = a.orders.where((e) => e['id'] == id).firstOrNull;
            final dateCol = display.headers.indexOf('Date');
            final newDay =
                dateCol >= 0 &&
                (index == 1 ||
                    display.rows[index - 2][dateCol] != row[dateCol]);
            final tile = InkWell(
              onTap: index <= display.personIds.length
                  ? () => c.push(
                      '/reports?module=loans&party=${Uri.encodeComponent(display.personIds[index - 1])}',
                    )
                  : order != null
                  ? () => orderDetails(c, a, order)
                  : entry == null
                  ? null
                  : () => entryDetails(c, a, entry),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: index.isOdd
                      ? (a.dark ? const Color(0xff142441) : pale)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.blueGrey.withValues(alpha: .15),
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < data.headers.length; col++)
                      Expanded(
                        flex: col == 0 ? 3 : 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Text(
                            data.headers[col] == 'Date'
                                ? DateFormat(
                                    'dd/MM/yy',
                                  ).format(DateTime.parse(row[col]))
                                : row[col],
                            style: TextStyle(
                              fontSize: col == 0 && data.headers.length <= 4
                                  ? 14
                                  : 11,
                              fontWeight: col < 2
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color:
                                  entry?['reversedBy'] != null ||
                                      entry?['type'] == 'reversal' ||
                                      negativeMoney(row[col])
                                  ? Colors.red
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (newDay)
                  Padding(
                    key: ValueKey('day-heading-${row[dateCol]}'),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: a.dark
                              ? const Color(0xff263b59)
                              : const Color(0xffe8edf5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          reportDayLabel(row[dateCol], urdu: a.ur),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                tile,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('report-type-$module'),
                initialValue: module,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: a.tr('Report'),
                  prefixIcon: Icon(Icons.summarize_outlined, color: blue),
                ),
                items: [
                  for (final e in menus.entries.where(
                    (e) => e.key == 'all' || a.can(reportModule(e.key)),
                  ))
                    DropdownMenuItem(value: e.key, child: Text(a.tr(e.value))),
                ],
                onChanged: (v) => setState(() {
                  module = v!;
                  party = '';
                  search = '';
                }),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const LocalizedText('Date / search'),
                children: [
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final preset in [
                        'All time',
                        'Today',
                        'This month',
                        'This year',
                      ])
                        ActionChip(
                          label: Text(preset),
                          onPressed: () {
                            final now = DateTime.parse(today());
                            setState(() {
                              to = today();
                              from = preset == 'All time'
                                  ? '2000-01-01'
                                  : preset == 'Today'
                                  ? today()
                                  : preset == 'This month'
                                  ? '${today().substring(0, 7)}-01'
                                  : '${now.year}-01-01';
                            });
                          },
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            from == '2000-01-01' ? 'First record' : from,
                          ),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate: DateTime.parse(from),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.parse(to),
                            );
                            if (d != null) {
                              setState(
                                () =>
                                    from = d.toIso8601String().substring(0, 10),
                              );
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(to),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate: DateTime.parse(to),
                              firstDate: DateTime.parse(from),
                              lastDate: DateTime.parse(today()),
                            );
                            if (d != null) {
                              setState(
                                () => to = d.toIso8601String().substring(0, 10),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (people.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('$module-$party'),
                  initialValue: party,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: a.tr('Person / company'),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: LocalizedText('All people / companies'),
                    ),
                    for (final p in people.entries)
                      DropdownMenuItem(
                        value: p.key,
                        child: Text(p.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => party = v!),
                ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('report-search-$module'),
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                onChanged: (v) => setState(() => search = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, bill or notes',
                ),
              ),
              const SizedBox(height: 14),
              Tile(
                color: a.dark ? null : pale,
                child: Column(
                  children: [
                    for (final e in data.summary.entries)
                      pair(
                        {
                              'Remaining salary': 'Salary remaining',
                              'Remaining company payments':
                                  'Remaining company payments',
                            }[e.key] ??
                            e.key,
                        e.value,
                        bold:
                            e.key.contains('Closing') ||
                            e.key.contains('Remaining'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: module == 'all' ? 64 : 84,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 68),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoArabic'],
                            fontWeight: FontWeight.w700,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                        ),
                        onPressed: sharing ? null : () => share(false),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const LocalizedText('Share PDF'),
                      ),
                    ),
                    if (module != 'all') const SizedBox(width: 10),
                    if (module != 'all')
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 68),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoArabic'],
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                          onPressed: sharing ? null : () => share(true),
                          icon: const Icon(Icons.image_outlined),
                          label: const LocalizedText('Share picture'),
                        ),
                      ),
                  ],
                ),
              ),
              if (sharing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 20),
              big('${data.rows.length} ${a.tr('Records')}', size: 20),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                color: blue,
                child: Row(
                  children: [
                    for (var col = 0; col < data.headers.length; col++)
                      Expanded(
                        flex: col == 0 ? 3 : 2,
                        child: Text(
                          a.tr(data.headers[col]),
                          style: TextStyle(
                            fontSize: data.headers.length > 4 ? 9 : 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              if (data.rows.isEmpty)
                const LocalizedText('No records in this period.'),
            ],
          );
        },
      ),
    );
  }
}

String reportDayLabel(String date, {String? currentDate, bool urdu = false}) {
  final d = DateTime.parse(date),
      current = DateTime.parse(currentDate ?? today());
  final prefix = date == (currentDate ?? today())
      ? localizedLabel('Today', urdu: urdu)
      : d == current.subtract(const Duration(days: 1))
      ? localizedLabel('Yesterday', urdu: urdu)
      : '';
  final day = localizedLabel(DateFormat('EEEE').format(d), urdu: urdu);
  return '${prefix.isEmpty ? '' : '$prefix · '}$day\n${DateFormat('dd MMM yyyy').format(d)}';
}
