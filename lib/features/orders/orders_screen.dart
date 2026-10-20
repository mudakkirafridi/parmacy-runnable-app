part of '../../ui/screens.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersState();
}

class _OrdersState extends ConsumerState<OrdersScreen> {
  String status = 'open', search = '';
  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    final orders =
        a.orders
            .where(
              (o) =>
                  (status == 'all' || o['status'] == status) &&
                  '${o['companyName']} ${o['staffName']} ${o['notes']}'
                      .toLowerCase()
                      .contains(search.toLowerCase()),
            )
            .toList()
          ..sort((x, y) => y['date'].compareTo(x['date']));
    return Frame(
      title: 'Orders',
      bottom: a.canPost('orders')
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('register-add-entry'),
                  onPressed: () => orderDialog(c, a),
                  icon: const Icon(Icons.add),
                  label: const Text('New order'),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Company ya staff ka naam',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['open', 'received', 'cancelled', 'all'])
                ChoiceChip(
                  label: Text(
                    {
                      'open': 'Pending',
                      'received': 'Bill received',
                      'cancelled': 'Cancelled',
                      'all': 'All',
                    }[s]!,
                  ),
                  selected: status == s,
                  onSelected: (_) => setState(() => status = s),
                ),
            ],
          ),
          if (a.people('suppliers').isEmpty)
            TextButton(
              onPressed: () => profileDialog(c, a, 'suppliers'),
              child: const Text('Add company'),
            ),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No orders yet'),
            ),
          for (final order in orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Tile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    big(
                      order['companyName'] ?? a.name(order['party']),
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    pair('Order amount', money(order['amount'])),
                    Text('Order by: ${order['staffName']}'),
                    Text('Date: ${dateLabel(order['date'])}'),
                    if ((order['notes'] ?? '').isNotEmpty) Text(order['notes']),
                    if (order['status'] == 'received') ...[
                      pair(
                        'Bill received',
                        money(order['billAmount'] ?? order['amount']),
                      ),
                      TextButton(
                        onPressed: () {
                          final bill = a.entries
                              .where((e) => e['id'] == order['billId'])
                              .firstOrNull;
                          if (bill != null) entryDetails(c, a, bill);
                        },
                        child: const Text('View bill / reverse'),
                      ),
                    ],
                    if (order['status'] == 'open' &&
                        a.canPost('suppliers')) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Bill received - add bill'),
                        onPressed: () => c.push(
                          '/entry/supplier_bill',
                          extra: {
                            'id': const Uuid().v4(),
                            'type': 'supplier_bill',
                            'orderId': order['id'],
                            'date': today(),
                            'party': order['party'],
                            'amount': order['amount'],
                            'reference': '',
                            'notes': 'Order by ${order['staffName']}',
                            'allocations': [],
                          },
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => orderDialog(c, a, existing: order),
                            child: const Text('Edit order'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: c,
                                builder: (ctx) => AlertDialog(
                                  title: const Text(
                                    'Cancel duplicate / wrong order?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Keep order'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Cancel order'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true && c.mounted) {
                                await perform(
                                  c,
                                  () => a.saveOrder({
                                    ...order,
                                    'status': 'cancelled',
                                  }),
                                );
                              }
                            },
                            child: const Text('Remove order'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> orderDialog(BuildContext c, AppStore a, {Json? existing}) async {
  final id = existing?['id'] ?? const Uuid().v4();
  String company = existing?['party'] ?? '',
      date = existing?['date'] ?? today();
  final amount = TextEditingController(
        text: existing == null ? '' : '${existing['amount'] / 100}',
      ),
      notes = TextEditingController(text: existing?['notes'] ?? ''),
      staffName = TextEditingController(text: existing?['staffName'] ?? '');
  bool saving = false;
  String? error;
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(existing == null ? 'New company order' : 'Edit order'),
        content: SizedBox(
          width: 370,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: company.isEmpty ? null : company,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Company *'),
                  items: [
                    for (final p in a.people('suppliers'))
                      DropdownMenuItem(value: p['id'], child: Text(p['name'])),
                  ],
                  onChanged: (v) => company = v!,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('order-person'),
                  controller: staffName,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Order dene wale ka naam *',
                    hintText: 'Umar',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('order-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Order amount (Rs) *',
                    hintText: 'Misal: 8000',
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(dateLabel(date)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.parse(date),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.parse(today()),
                    );
                    if (d != null) {
                      set(() => date = d.toIso8601String().substring(0, 10));
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Medicines / notes (optional)',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
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
                    try {
                      final value = paisa(amount.text);
                      final personName = staffName.text.trim();
                      if (company.isEmpty || personName.isEmpty || value <= 0) {
                        throw StateError(
                          'Company, naam aur amount enter karein',
                        );
                      }
                      set(() => saving = true);
                      await a.saveOrder({
                        ...existing ?? {},
                        'id': id,
                        'party': company,
                        'companyName': a.name(company),
                        'staffId': personName == existing?['staffName']
                            ? existing!['staffId']
                            : a
                                      .people('salary')
                                      .where(
                                        (p) =>
                                            (p['name'] as String)
                                                .toLowerCase() ==
                                            personName.toLowerCase(),
                                      )
                                      .firstOrNull?['id'] ??
                                  'person-${const Uuid().v4()}',
                        'staffName': personName,
                        'date': date,
                        'amount': value,
                        'notes': notes.text.trim(),
                        'status': 'open',
                        'billId': '',
                        'billAmount': 0,
                      });
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
            child: Text(saving ? 'Saving...' : 'Save order'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  notes.dispose();
  staffName.dispose();
}
