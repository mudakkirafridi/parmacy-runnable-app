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
    final balances = <String, int>{}, day = <String, int>{};
    for (final e in a.entries) {
      if ((e['date'] as String).compareTo(date) > 0) continue;
      for (final effect in (e['effects'] as Json).entries) {
        balances[effect.key] =
            (balances[effect.key] ?? 0) + (effect.value as int);
        if (e['date'] == date) {
          day[effect.key] = (day[effect.key] ?? 0) + (effect.value as int);
        }
      }
    }
    int sum(Map<String, int> values, String prefix) => values.entries
        .where((e) => e.key.startsWith(prefix))
        .fold(0, (s, e) => s + e.value);
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
    Widget shortcut(String label, IconData icon, VoidCallback action) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Tile(
            onTap: action,
            child: Row(
              children: [
                Icon(icon, color: blue),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    a.tr(label),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
    return Frame(
      title: 'Pharmacy Hisab',
      tab: 0,
      actions: [
        IconButton(
          tooltip: 'Quick entry',
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
                  const Text(
                    'Cash balance',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  big(
                    money(balances['money:cash'] ?? 0),
                    size: 40,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 22),
            big(a.tr('Financial overview'), size: 22),
            const SizedBox(height: 5),
            Text(
              'Sale aur expense: selected day. Balances: ${dateLabel(date)} tak.',
              style: const TextStyle(fontSize: 12, color: Color(0xff60718f)),
            ),
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
                -sum(balances, 'supplier:'),
                Icons.local_shipping_outlined,
              ),
            const SizedBox(height: 22),
            big('Quick entry', size: 22),
            const SizedBox(height: 12),
            if (a.canPost('suppliers'))
              shortcut(
                'Pay company / Ograi',
                Icons.payments_outlined,
                () => c.push('/entry/supplier_payment'),
              ),
            if (a.canPost('orders'))
              shortcut(
                'Order',
                Icons.shopping_bag_outlined,
                () => orderDialog(c, a),
              ),
            if (a.canPost('suppliers'))
              shortcut(
                'Company bill',
                Icons.receipt_long_outlined,
                () => c.push('/entry/supplier_bill'),
              ),
            if (a.can('suppliers')) ...[
              const SizedBox(height: 18),
              big('All bills', size: 22),
              const SizedBox(height: 12),
              for (final bill in a.entries.where(
                (e) => e['type'] == 'supplier_bill' && e['reversedBy'] == null,
              ))
                entryTile(c, a, bill),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> quickEntrySheet(BuildContext c, AppStore a) async {
  final choice = await showModalBottomSheet<String>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Quick entry',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          for (final item in {
            'supplier_payment': 'Pay company / Ograi',
            'orders': 'Order',
            'supplier_bill': 'Company bill',
          }.entries)
            if (a.canPost(item.key == 'orders' ? 'orders' : 'suppliers'))
              ListTile(
                leading: Icon(
                  item.key == 'orders'
                      ? Icons.shopping_bag_outlined
                      : Icons.local_shipping_outlined,
                  color: blue,
                ),
                title: Text(item.value),
                onTap: () => Navigator.pop(ctx, item.key),
              ),
        ],
      ),
    ),
  );
  if (choice == null || !c.mounted) return;
  if (choice == 'orders') {
    orderDialog(c, a);
  } else {
    c.push('/entry/$choice');
  }
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
        title: const Text('Remove / reverse entry'),
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
            child: const Text('Cancel'),
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
