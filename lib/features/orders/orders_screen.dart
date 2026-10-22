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
                  onPressed: () => c.push('/entry?type=order'),
                  icon: const Icon(Icons.add),
                  label: const LocalizedText('New order'),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
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
              child: const LocalizedText('Add company'),
            ),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: LocalizedText('No orders yet'),
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
                        child: const LocalizedText('View bill / reverse'),
                      ),
                    ],
                    if (order['status'] == 'open' &&
                        a.canPost('suppliers')) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const LocalizedText('Bill received - add bill'),
                        onPressed: () => c.push(
                          '/entry?type=supplier_bill',
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
                            child: const LocalizedText('Edit order'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: c,
                                builder: (ctx) => AlertDialog(
                                  title: const LocalizedText(
                                    'Cancel duplicate / wrong order?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const LocalizedText('Keep order'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const LocalizedText(
                                        'Cancel order',
                                      ),
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
                            child: const LocalizedText('Remove order'),
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
                  decoration: InputDecoration(
                    labelText: a.tr('Select company'),
                  ),
                  items: [
                    for (final p in a.people('suppliers'))
                      DropdownMenuItem(value: p['id'], child: Text(p['name'])),
                  ],
                  onChanged: (v) => company = v!,
                ),
                const SizedBox(height: 12),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  key: const Key('order-person'),
                  controller: staffName,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: a.tr('Order dene wale ka naam *'),
                    hintText: 'Umar',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  key: const Key('order-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: a.tr('Order amount (Rs) *'),
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
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: notes,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: a.tr('Medicines / notes (optional)'),
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
            child: const LocalizedText('Cancel'),
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

Future<void> orderDetails(BuildContext c, AppStore a, Json order) async {
  final action = await showModalBottomSheet<String>(
    context: c,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            big(order['companyName'] ?? a.name(order['party']), size: 23),
            pair('Amount', money(order['amount'])),
            pair('Order by', order['staffName'] ?? ''),
            pair('Date', dateLabel(order['date'])),
            if (order['status'] == 'open' && a.canPost('orders')) ...[
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'bill'),
                icon: const Icon(Icons.receipt_long),
                label: const LocalizedText('Receive bill'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const LocalizedText('Edit order'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const LocalizedText('Cancel order'),
              ),
            ],
            if (order['status'] == 'received')
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'view'),
                child: const LocalizedText('View bill'),
              ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !c.mounted) return;
  if (action == 'bill') {
    c.push(
      '/entry?type=supplier_bill',
      extra: {
        'id': const Uuid().v4(),
        'orderId': order['id'],
        'party': order['party'],
        'amount': order['amount'],
        'date': today(),
        'notes': 'Order by ${order['staffName']}',
      },
    );
  }
  if (action == 'edit') await orderDialog(c, a, existing: order);
  if (action == 'view') {
    final bill = a.entries.where((e) => e['id'] == order['billId']).firstOrNull;
    if (bill != null && c.mounted) entryDetails(c, a, bill);
  }
  if (action == 'cancel' && c.mounted) {
    final yes = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const LocalizedText('Cancel order'),
        content: Text(order['companyName'] ?? a.name(order['party'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const LocalizedText('Confirm'),
          ),
        ],
      ),
    );
    if (yes == true && c.mounted) {
      await perform(c, () => a.saveOrder({...order, 'status': 'cancelled'}));
    }
  }
}
