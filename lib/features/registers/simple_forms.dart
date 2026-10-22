part of '../../ui/screens.dart';

class SimpleSaleScreen extends ConsumerStatefulWidget {
  final Json? draft;
  const SimpleSaleScreen({super.key, this.draft});
  @override
  ConsumerState<SimpleSaleScreen> createState() => _SimpleSaleState();
}

class _SimpleSaleState extends ConsumerState<SimpleSaleScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController amount;
  late final String id;
  late String date;
  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    amount = TextEditingController(
      text: d == null ? '' : ((d['amount'] as int) / 100).toString(),
    );
    id = d?['id'] ?? const Uuid().v4();
    date = d?['date'] ?? today();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Json entry() => {
    'id': id,
    'type': 'daily_sales',
    'date': date,
    'amount': paisa(amount.text),
  };
  Future<void> review(AppStore a) async {
    if (!form.currentState!.validate()) return;
    try {
      final x = entry();
      a.ledger.post(a.state, x);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(a.tr('Daily net sale')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              big(money(x['amount']), color: blue),
              const SizedBox(height: 10),
              Text(dateLabel(date)),
              const SizedBox(height: 12),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(a.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(a.tr('Confirm and post')),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await a.submit(x);
        if (mounted) {
          toast(context, a.tr('Saved successfully'));
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/register/sales');
          }
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    return Frame(
      title: 'Net daily sale',
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: FilledButton.icon(
            onPressed: a.busy ? null : () => review(a),
            icon: const Icon(Icons.check_circle),
            label: Text(a.tr('Review entry')),
          ),
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Tile(
              color: a.dark ? null : pale,
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: DateTime.parse(date),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) {
                  setState(() => date = d.toIso8601String().substring(0, 10));
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: blue),
                  const SizedBox(width: 14),
                  Expanded(child: Text(dateLabel(date))),
                  const Icon(Icons.expand_more),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Text(
              a.tr('Net daily sale'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextFormField(
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              key: const Key('net-daily-sale'),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                prefixText: 'Rs ',
                hintText: '53,000',
              ),
              validator: (v) {
                try {
                  paisa(v ?? '');
                  return null;
                } catch (_) {
                  return a.ur
                      ? 'درست رقم درج کریں'
                      : 'Enter the whole day net sale';
                }
              },
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () async {
                if (form.currentState!.validate()) {
                  await perform(c, () => a.saveDraft(entry()));
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: Text(a.tr('Save local draft')),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleRentScreen extends ConsumerStatefulWidget {
  final Json? draft;
  final String? party;
  const SimpleRentScreen({super.key, this.draft, this.party});
  @override
  ConsumerState<SimpleRentScreen> createState() => _SimpleRentState();
}

class _SimpleRentState extends ConsumerState<SimpleRentScreen> {
  final amount = TextEditingController(),
      period = TextEditingController(),
      notes = TextEditingController();
  late String id, date;
  String party = '', account = 'cash';
  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    id = d?['id'] ?? const Uuid().v4();
    date = d?['date'] ?? today();
    party = d?['party'] ?? widget.party ?? '';
    account = d?['account'] ?? 'cash';
    if (d != null) {
      amount.text = '${d['amount'] / 100}';
      period.text = d['reference'] ?? '';
      notes.text = d['notes'] ?? '';
    }
  }

  @override
  void dispose() {
    amount.dispose();
    period.dispose();
    notes.dispose();
    super.dispose();
  }

  Json entry() => {
    'id': id,
    'type': 'rent_payment',
    'amount': paisa(amount.text),
    'date': date,
    'party': party,
    'account': account,
    'reference': period.text,
    'notes': notes.text,
  };
  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider), people = a.people('rent');
    return Frame(
      title: 'Pay rent',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: people.any((p) => p['id'] == party) ? party : null,
            decoration: InputDecoration(labelText: a.tr('Select person')),
            items: [
              for (final p in people)
                DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(p['name']),
                ),
            ],
            onChanged: (v) => setState(() => party = v!),
          ),
          TextButton.icon(
            onPressed: () => profileDialog(c, a, 'rent'),
            icon: const Icon(Icons.add),
            label: Text(a.tr('Add person')),
          ),
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: a.tr('Amount'),
              prefixText: 'Rs ',
            ),
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month, color: blue),
            title: Text(dateLabel(date)),
            trailing: const Icon(Icons.expand_more),
            onTap: () async {
              final d = await showDatePicker(
                context: c,
                initialDate: DateTime.parse(date),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) {
                setState(() => date = d.toIso8601String().substring(0, 10));
              }
            },
          ),
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            controller: period,
            decoration: InputDecoration(
              labelText: a.tr('Bill / period'),
              hintText: '2026-10',
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: account,
            decoration: InputDecoration(labelText: a.tr('Payment account')),
            items: [
              for (final s in a.state['accounts'])
                DropdownMenuItem(
                  value: s as String,
                  child: Text(
                    a.tr(
                      s == 'cash'
                          ? 'Cash drawer'
                          : s == 'bank'
                          ? 'Bank / digital'
                          : s,
                    ),
                  ),
                ),
            ],
            onChanged: (v) => account = v!,
          ),
          const SizedBox(height: 18),
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            controller: notes,
            decoration: InputDecoration(labelText: a.tr('Notes')),
          ),
          const SizedBox(height: 25),
          FilledButton(
            onPressed: a.busy
                ? null
                : () async {
                    try {
                      final x = entry();
                      a.ledger.post(a.state, x);
                      final ok = await showDialog<bool>(
                        context: c,
                        builder: (ctx) => AlertDialog(
                          title: Text(a.tr('Review entry')),
                          content: Text(
                            '${a.name(party)}\n${money(x['amount'])}\n${dateLabel(date)}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(a.tr('Cancel')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(a.tr('Confirm and post')),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await a.submit(x);
                        if (c.mounted) c.go('/register/rent');
                      }
                    } catch (e) {
                      if (c.mounted) toast(c, e.toString());
                    }
                  },
            child: Text(a.tr('Review payment')),
          ),
          TextButton(
            onPressed: () async {
              try {
                await a.saveDraft(entry());
                if (c.mounted) toast(c, a.tr('Draft saved locally'));
              } catch (e) {
                if (c.mounted) toast(c, e.toString());
              }
            },
            child: Text(a.tr('Save local draft')),
          ),
        ],
      ),
    );
  }
}

Future<void> editExpenseDialog(
  BuildContext c,
  AppStore a,
  Json original,
) async {
  final amount = TextEditingController(text: '${original['amount'] / 100}'),
      notes = TextEditingController(text: original['notes'] ?? '');
  bool saving = false;
  String? error;
  String category = original['category'] ?? 'Other',
      account = original['account'] ?? 'cash';
  final replacementId = const Uuid().v4();
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(a.tr('Edit expense')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: a.tr('Amount'),
                    prefixText: 'Rs ',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: InputDecoration(labelText: a.tr('Category')),
                  items: [
                    for (final s in <String>{...expenseCategories, category})
                      DropdownMenuItem(value: s, child: Text(a.tr(s))),
                  ],
                  onChanged: (v) => category = v!,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: account,
                  decoration: InputDecoration(
                    labelText: a.tr('Payment account'),
                  ),
                  items: [
                    for (final s in a.state['accounts'])
                      DropdownMenuItem(
                        value: s as String,
                        child: Text(a.tr(s)),
                      ),
                  ],
                  onChanged: (v) => account = v!,
                ),
                const SizedBox(height: 14),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: notes,
                  decoration: InputDecoration(labelText: a.tr('Notes')),
                ),
                const SizedBox(height: 14),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(a.tr('Cancel')),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      final replacement = {
                        'id': replacementId,
                        'type': 'expense',
                        'date': today(),
                        'amount': paisa(amount.text),
                        'category': category,
                        'account': account,
                        'notes': notes.text,
                      };
                      await a.correctExpense(
                        original,
                        replacement,
                        'Entry edited',
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        toast(c, a.tr('Saved successfully'));
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        set(() {
                          saving = false;
                          error = e.toString().replaceFirst('Bad state: ', '');
                        });
                      }
                    }
                  },
            child: Text(a.tr('Save')),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  notes.dispose();
}
