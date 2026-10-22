part of '../../ui/screens.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomeScreen> {
  late String date;
  @override
  void initState() {
    super.initState();
    date = ref.read(appProvider).live ? today() : '2026-10-14';
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    final balances = Map<String, int>.from(a.state['balances'] ?? {}),
        day = <String, int>{};
    for (final e in a.entries) {
      for (final effect in (e['effects'] as Json).entries) {
        if (e['date'] == date) {
          day[effect.key] = (day[effect.key] ?? 0) + (effect.value as int);
        }
      }
    }
    int sum(Map<String, int> values, String prefix) => values.entries
        .where((e) => e.key.startsWith(prefix))
        .fold(0, (s, e) => s + e.value);
    final committees = CommitteeProgress.all(
      a.profiles.where((p) => p['module'] == 'committee'),
      a.entries,
    );
    final net =
        -(day['netSales'] ?? 0) - (day['sales'] ?? 0) - (day['returns'] ?? 0);
    Widget card(
      String title,
      int amount,
      IconData icon, {
      Color color = blue,
    }) => Tile(
      padding: const EdgeInsets.all(15),
      color: a.dark ? null : pale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(a.tr(title)),
          const SizedBox(height: 5),
          FittedBox(child: big(money(amount), size: 24, color: color)),
        ],
      ),
    );
    return Frame(
      title: 'Pharmacy Hisab',
      tab: 0,
      actions: [
        IconButton(
          tooltip: a.tr('New entry'),
          onPressed: () => quickEntrySheet(c, a),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: a.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(17),
          children: [
            Text(
              a.settings['name'] ?? 'Family Pharmacy',
              style: const TextStyle(fontSize: 18, color: Color(0xff60718f)),
            ),
            const SizedBox(height: 15),
            Tile(
              color: a.dark ? null : pale,
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: DateTime.parse(date),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.parse(today()),
                );
                if (d != null) {
                  setState(() => date = d.toIso8601String().substring(0, 10));
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: blue),
                  const SizedBox(width: 12),
                  Expanded(child: Text(dateLabel(date))),
                  const Icon(Icons.expand_more),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Tile(
              color: blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LocalizedText(
                    'Cash balance',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  big(
                    money(balances['money:cash'] ?? 0),
                    size: 40,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.account_balance_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${a.tr('Bank')}  ${money(balances['money:bank'] ?? 0)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white30, height: 24),
                  Text(
                    '${a.tr('Cash + Bank')}  ${money(sum(balances, 'money:'))}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (a.owner && a.canPost('cashbook'))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => actualBalanceDialog(c, a),
                  icon: const Icon(Icons.balance, size: 18),
                  label: const LocalizedText('Set actual balance'),
                ),
              ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => c.push('/entry'),
                icon: const Icon(Icons.add),
                label: const LocalizedText('New entry'),
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => c.push('/profiles'),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(a.tr('New profile')),
            ),
            const SizedBox(height: 18),
            big(a.tr('Financial overview'), size: 22),
            const SizedBox(height: 5),
            const SizedBox(height: 12),
            if (a.can('expenses'))
              card(
                'Expenses today',
                sum(day, 'expense:'),
                Icons.receipt_long_outlined,
                color: orange,
              ),
            const SizedBox(height: 10),
            if (a.can('cashbook'))
              Row(
                children: [
                  Expanded(
                    child: card(
                      'Daily net sale',
                      net,
                      Icons.payments_outlined,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: card(
                      'Bank balance',
                      balances['money:bank'] ?? 0,
                      Icons.account_balance_outlined,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            if (a.can('loans'))
              Row(
                children: [
                  Expanded(
                    child: card(
                      'Qarz baqaya',
                      loanTotal(balances),
                      Icons.call_received,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: card(
                      'Jama raqam',
                      loanTotal(balances, credit: true),
                      Icons.call_made,
                      color: orange,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            if (a.can('suppliers'))
              card(
                'Supplier payable',
                balances.entries
                    .where((e) => e.key.startsWith('supplier:'))
                    .fold<int>(0, (sum, e) => sum + max(0, -e.value)),
                Icons.local_shipping_outlined,
              ),
            if (a.can('salary')) ...[
              const SizedBox(height: 10),
              card(
                'Salary remaining',
                (balances.keys
                        .where(
                          (k) =>
                              k.startsWith('salary:') ||
                              k.startsWith('salaryAdvance:'),
                        )
                        .map((k) => k.substring(k.indexOf(':') + 1))
                        .toSet())
                    .fold<int>(0, (n, id) => n + a.salaryDue(id)),
                Icons.badge_outlined,
                color: orange,
              ),
            ],
            if (a.can('committee')) ...[
              const SizedBox(height: 10),
              Tile(
                color: a.dark ? null : pale,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    big('Committee / Qist', size: 18),
                    const SizedBox(height: 8),
                    pair(
                      'Qist di',
                      money(
                        committees.values.fold<int>(0, (n, p) => n + p.paid),
                      ),
                    ),
                    pair(
                      'Raqam mili',
                      money(
                        committees.values.fold<int>(
                          0,
                          (n, p) => n + p.received,
                        ),
                      ),
                    ),
                    pair(
                      'Qistain baqi',
                      money(
                        committees.values.fold<int>(
                          0,
                          (n, p) => n + p.remaining,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            if (a.can('suppliers')) ...[
              const SizedBox(height: 18),
              big('Companies', size: 22),
              const SizedBox(height: 12),
              for (final company in a.profiles.where(
                (p) =>
                    p['module'] == 'suppliers' &&
                    p['active'] != false &&
                    p['visible'] != 0,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Tile(
                    onTap: () => companyActions(c, a, company),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined, color: blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            company['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        Text(
                          money(
                            max(0, -a.balance('supplier:${company['id']}')),
                          ),
                          style: const TextStyle(
                            color: blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> quickEntrySheet(BuildContext c, AppStore a) async {
  c.push('/entry');
}

Future<void> reverseDialog(BuildContext c, AppStore a, Json entry) async {
  const reason = 'Entry removed';
  bool saving = false;
  String? error;
  final linked = a.entries
      .where(
        (e) =>
            e['reversedBy'] == null &&
            e['type'] != 'reversal' &&
            (e['allocations'] as List? ?? []).any(
              (x) => x['id'] == entry['id'],
            ),
      )
      .toList();
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const LocalizedText('Remove / reverse entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${a.typeLabel(entry['type'])} - ${money(entry['amount'])}'),
            const SizedBox(height: 12),
            for (final e in linked)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  entryDetails(c, a, e);
                },
                child: Text('${a.typeLabel(e['type'])} ${money(e['amount'])}'),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(ctx),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      await a.reverseEntry(entry, reason, today());
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        set(() {
                          saving = false;
                          error = e.toString().replaceFirst('Bad state: ', '');
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving...' : 'Confirm reversal'),
          ),
        ],
      ),
    ),
  );
}

Future<void> companyActions(BuildContext c, AppStore a, Json company) async {
  final choice = await showModalBottomSheet<String>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                big(company['name'], size: 23),
                pair(
                  'Remaining balance',
                  money(max(0, -a.balance('supplier:${company['id']}'))),
                ),
              ],
            ),
          ),
          if (a.canPost('suppliers'))
            ListTile(
              leading: const Icon(Icons.payments_outlined, color: blue),
              title: const LocalizedText('Company payment'),
              onTap: () => Navigator.pop(ctx, 'pay'),
            ),
          ListTile(
            leading: const Icon(Icons.summarize_outlined, color: blue),
            title: const LocalizedText('Company payments'),
            onTap: () => Navigator.pop(ctx, 'report'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !c.mounted) return;
  final id = Uri.encodeComponent(company['id']);
  c.push(
    choice == 'pay'
        ? '/entry?type=supplier_payment&party=$id'
        : '/reports?module=ograi&party=$id',
  );
}

Future<void> actualBalanceDialog(BuildContext c, AppStore a) async {
  final counted = TextEditingController();
  String account = 'cash';
  bool saving = false;
  String? error;
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const LocalizedText('Actual balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: account,
              decoration: InputDecoration(labelText: a.tr('Account')),
              items: [
                for (final key in a.state['accounts'])
                  DropdownMenuItem(
                    value: key as String,
                    child: Text(
                      key == 'cash'
                          ? 'Cash'
                          : key == 'bank'
                          ? 'Bank'
                          : key,
                    ),
                  ),
              ],
              onChanged: (v) => set(() => account = v!),
            ),
            const SizedBox(height: 12),
            pair('Current record', money(a.balance('money:$account'))),
            const SizedBox(height: 12),
            TextField(
              key: const Key('actual-balance'),
              controller: counted,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: a.tr('Actual amount'),
                prefixText: 'Rs ',
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(ctx),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    try {
                      final delta =
                          paisa(counted.text) - a.balance('money:$account');
                      set(() => saving = true);
                      if (delta != 0) {
                        await a.submit({
                          'id': const Uuid().v4(),
                          'type': delta > 0 ? 'balance_in' : 'balance_out',
                          'amount': delta.abs(),
                          'account': account,
                          'date': today(),
                          'notes': 'Actual balance check',
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        set(() {
                          saving = false;
                          error = e.toString().replaceFirst('Bad state: ', '');
                        });
                      }
                    }
                  },
            child: const LocalizedText('Save balance'),
          ),
        ],
      ),
    ),
  );
  counted.dispose();
}
