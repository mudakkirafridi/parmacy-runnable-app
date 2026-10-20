part of '../../ui/screens.dart';

const reportMenus = {
  'all': 'All reports',
  'company_bills': 'Company bills',
  'ograi': 'Pay company / Ograi',
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
    module = widget.initialModule == 'rent' ? 'expenses' : widget.initialModule;
    party = widget.initialParty ?? '';
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialModule != widget.initialModule ||
        oldWidget.initialParty != widget.initialParty) {
      module = widget.initialModule == 'rent'
          ? 'expenses'
          : widget.initialModule;
      party = widget.initialParty ?? '';
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    const menus = reportMenus;
    if (module == null) {
      return Frame(
        title: 'Reports',
        tab: 2,
        body: ListView(
          padding: const EdgeInsets.all(17),
          children: [
            big('Reports & statements', size: 25),
            const SizedBox(height: 6),
            for (final entry in menus.entries)
              if (entry.key == 'all' || a.can(reportModule(entry.key)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Tile(
                    onTap: () => c.push('/reports?module=${entry.key}'),
                    child: Row(
                      children: [
                        Icon(
                          entry.key == 'all'
                              ? Icons.dashboard_outlined
                              : icons[entry.key],
                          color: blue,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    }
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
            final row = data.rows[index - 1];
            final id = index <= data.recordIds.length
                ? data.recordIds[index - 1]
                : null;
            final entry = a.entries.where((e) => e['id'] == id).firstOrNull;
            return InkWell(
              onTap: index <= data.personIds.length
                  ? () => c.push(
                      '/reports?module=loans&party=${Uri.encodeComponent(data.personIds[index - 1])}',
                    )
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
                              color: negativeMoney(row[col])
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
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => c.canPop() ? c.pop() : c.go('/reports'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Choose another report'),
              ),
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
                      label: Text(from == '2000-01-01' ? 'First record' : from),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: c,
                          initialDate: DateTime.parse(from),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.parse(to),
                        );
                        if (d != null) {
                          setState(
                            () => from = d.toIso8601String().substring(0, 10),
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
              if (people.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('$module-$party'),
                  initialValue: party,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Person / company',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All people / companies'),
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: sharing ? null : () => share(false),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Share PDF'),
                    ),
                  ),
                  if (module != 'all') const SizedBox(width: 10),
                  if (module != 'all')
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: sharing ? null : () => share(true),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Share picture'),
                      ),
                    ),
                ],
              ),
              if (sharing)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 20),
              big('${data.rows.length} records', size: 20),
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
                          data.headers[col],
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
              if (data.rows.isEmpty) const Text('No records in this period.'),
            ],
          );
        },
      ),
    );
  }
}
