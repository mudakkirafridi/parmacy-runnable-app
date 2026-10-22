part of '../../ui/screens.dart';

final notebookTypes = {
  for (final e in entryNames.entries)
    if (!['daily_sales', 'salary_advance'].contains(e.key)) e.key: e.value,
};

class NotebookEntryScreen extends ConsumerStatefulWidget {
  final String? initialType, initialParty;
  final Json? initialDraft;
  const NotebookEntryScreen({
    super.key,
    this.initialType,
    this.initialParty,
    this.initialDraft,
  });
  @override
  ConsumerState<NotebookEntryScreen> createState() => _NotebookEntryState();
}

class _NotebookEntryState extends ConsumerState<NotebookEntryScreen> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(),
      reference = TextEditingController(),
      notes = TextEditingController(),
      staff = TextEditingController();
  late String type, party;
  String date = today(), account = 'cash', category = 'Expense';
  String id = const Uuid().v4();
  bool saving = false, allowAdvance = false;
  @override
  void initState() {
    super.initState();
    type = widget.initialType == 'daily_sales'
        ? 'daily_sale_cash'
        : widget.initialType ?? '';
    final draft = widget.initialDraft;
    party = draft?['party'] ?? widget.initialParty ?? '';
    if (draft != null) {
      id = draft['id'] ?? id;
      date = draft['date'] ?? date;
      amount.text = draft['amount'] == null ? '' : '${draft['amount'] / 100}';
      reference.text = draft['reference'] ?? '';
      notes.text = draft['notes'] ?? '';
      account = draft['account'] ?? 'cash';
    }

    if (type.startsWith('committee_') &&
        party.isNotEmpty &&
        amount.text.isEmpty) {
      final p = ref
          .read(appProvider)
          .profiles
          .where((p) => p['id'] == party)
          .firstOrNull;
      final value = type == 'committee_pay'
          ? (p?['installmentAmount'])
          : (p?['totalAmount']);
      if (value is int) {
        amount.text = (value / 100).toStringAsFixed(value % 100 == 0 ? 0 : 2);
      }
    }
    if (type == 'supplier_bill' && reference.text.isEmpty) {
      reference.text = ref.read(appProvider).nextBillNumber(party);
    }
  }

  @override
  void dispose() {
    for (final c in [amount, reference, notes, staff]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget input(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    bool required = false,
    String? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: key == null ? null : Key(key),
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontSize: numeric ? 25 : 16,
        fontWeight: numeric ? FontWeight.w800 : FontWeight.w400,
      ),
      decoration: InputDecoration(
        labelText: ref.read(appProvider).tr(label),
        prefixText: numeric ? 'Rs ' : null,
      ),
      validator: (v) {
        if (required && (v ?? '').trim().isEmpty) return 'Required';
        if (numeric && (v ?? '').isNotEmpty) {
          try {
            paisa(v!);
          } catch (_) {
            return 'Enter a valid amount';
          }
        }
        return null;
      },
    ),
  );
  Future<void> save(AppStore a) async {
    if (saving || !form.currentState!.validate()) return;
    final definition = a.ledger.types[type] as Json?;
    final module = type == 'order' ? 'suppliers' : definition?['module'];
    final requiresParty =
        type == 'order' ||
        definition?['partyRequired'] == true ||
        '${definition?['debit']}${definition?['credit']}'.contains('{party}');
    try {
      if (type.isEmpty) throw StateError('Select entry type');
      if (requiresParty && party.isEmpty) throw StateError('Select a name');
      if (!a.canPost(
        module == 'suppliers' && type == 'order' ? 'orders' : module,
      )) {
        throw StateError('Entry permission required');
      }
      final n = paisa(amount.text);
      final entry = <String, dynamic>{
        'id': id,
        if (type == 'supplier_bill' && widget.initialDraft?['orderId'] != null)
          'orderId': widget.initialDraft!['orderId'],
        'type': type,
        'party': party,
        'amount': n,
        'date': date,
        'account': account,
        'notes': notes.text.trim(),
        'reference': reference.text.trim(),
        if (type == 'expense') 'category': category,
        'allocations': <Json>[],
      };
      if (type == 'supplier_bill' && reference.text.trim().isEmpty) {
        throw StateError('Enter bill number');
      }
      if (type == 'order' && (n <= 0 || staff.text.trim().isEmpty)) {
        throw StateError('Enter order amount and staff name');
      }
      if (['supplier_payment', 'supplier_return'].contains(type)) {
        final credit = type == 'supplier_return';
        if (!credit &&
            !allowAdvance &&
            n > max(0, -a.balance('supplier:$party'))) {
          throw StateError('Amount exceeds remaining balance');
        }
        entry['allocations'] = a.allocateOldest(
          'suppliers',
          party,
          n,
          allowExcess: credit || allowAdvance,
        );
        entry['allowAdvance'] = credit || allowAdvance;
      }
      if (type != 'order') a.previewEntry(entry);
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(a.tr(notebookTypes[type]!)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (party.isNotEmpty) Text(a.name(party)),
              big(money(n), color: blue),
              Text(dateLabel(date)),
              if (type != 'order' &&
                  '${definition?['debit']}${definition?['credit']}'.contains(
                    'money:',
                  ))
                Text(account == 'cash' ? 'Cash' : 'Bank'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const LocalizedText('Save'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      setState(() => saving = true);
      if (type == 'order') {
        await a.saveOrder({
          'id': id,
          'party': party,
          'companyName': a.name(party),
          'staffName': staff.text.trim(),
          'staffId': 'manual-$id',
          'amount': n,
          'date': date,
          'notes': notes.text.trim(),
          'status': 'open',
        });
      } else {
        await a.submit(entry);
      }
      if (mounted) {
        toast(context, 'Saved successfully');
        context.canPop() ? context.pop() : context.go('/');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider),
        definition = a.ledger.types[type] as Json?;
    final module = type == 'order'
        ? 'suppliers'
        : definition?['module'] as String? ?? '';
    final needsPerson =
        type == 'order' ||
        definition?['partyRequired'] == true ||
        '${definition?['debit']}${definition?['credit']}'.contains('{party}');
    final hasAccount = '${definition?['debit']}${definition?['credit']}'
        .contains('money:');
    final choices = notebookTypes.entries.where(
      (e) =>
          a.canPost(
            e.key == 'order' ? 'orders' : a.ledger.types[e.key]['module'],
          ) &&
          (a.ledger.types[e.key]?['owner'] != true || a.owner),
    );
    final progress = module == 'committee' && party.isNotEmpty
        ? CommitteeProgress.from(
            a.profiles.firstWhere((p) => p['id'] == party),
            a.entries,
          )
        : null;
    int entered = 0;
    try {
      if (amount.text.isNotEmpty) entered = paisa(amount.text);
    } catch (_) {}
    final tone = switch (module) {
      'expenses' => const Color(0xffc65318),
      'loans' => const Color(0xff7545bf),
      'committee' => const Color(0xff008c80),
      'salary' => const Color(0xff4158b3),
      'owner' => const Color(0xff137c59),
      _ => blue,
    };
    final entryIcon = switch (type) {
      'daily_sale_cash' => Icons.point_of_sale_rounded,
      'supplier_bill' => Icons.receipt_long_rounded,
      'supplier_payment' => Icons.payments_rounded,
      'supplier_return' => Icons.assignment_return_rounded,
      'loan_lend' => Icons.north_east_rounded,
      'loan_collect' => Icons.south_west_rounded,
      'committee_pay' => Icons.event_repeat_rounded,
      'committee_receive' => Icons.savings_rounded,
      'salary_payment' => Icons.badge_rounded,
      'expense' => Icons.receipt_rounded,
      'order' => Icons.shopping_bag_rounded,
      _ => Icons.edit_note_rounded,
    };
    return Frame(
      title: 'New entry',
      bottom: type.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('notebook-save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tone,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: saving ? null : () => save(a),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    saving
                        ? a.tr('Saving...')
                        : type == 'order'
                        ? a.tr('Save order')
                        : a.tr('Save entry'),
                  ),
                ),
              ),
            ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: a.dark ? .18 : .07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: tone.withValues(alpha: .25)),
              ),
              child: DropdownButtonFormField<String>(
                key: ValueKey('notebook-type-$type'),
                initialValue: type.isEmpty ? null : type,
                isExpanded: true,
                itemHeight: 72,
                decoration: InputDecoration(
                  labelText: a.tr('Entry type'),
                  prefixIcon: Icon(entryIcon, color: tone),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                hint: const LocalizedText('Select entry'),
                items: [
                  for (final e in choices)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        a.tr(e.value),
                        maxLines: 2,
                        softWrap: true,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (v) => setState(() {
                        type = v!;
                        party = '';
                        amount.clear();
                        notes.clear();
                        reference.clear();
                        staff.clear();
                        allowAdvance = false;
                        id = const Uuid().v4();
                        if (type == 'supplier_bill') {
                          reference.text = a.nextBillNumber('');
                        }
                      }),
              ),
            ),
            const SizedBox(height: 20),
            if (type.isNotEmpty) ...[
              if (needsPerson) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('notebook-party-$type-$party'),
                  initialValue: party.isEmpty ? null : party,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      icons[module] ?? Icons.person_outline,
                      color: tone,
                    ),
                    labelText: module == 'suppliers'
                        ? a.tr('Select company')
                        : module == 'salary'
                        ? a.tr('Select staff')
                        : module == 'committee'
                        ? a.tr('Select installment')
                        : module == 'owner'
                        ? a.tr('Select owner')
                        : a.tr('Select person'),
                  ),
                  items: [
                    for (final p in a.people(module))
                      DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text(p['name']),
                      ),
                  ],
                  validator: (v) => v == null ? 'Select a name' : null,
                  onChanged: saving
                      ? null
                      : (v) => setState(() {
                          party = v!;
                          if (type == 'supplier_bill') {
                            reference.text = a.nextBillNumber(party);
                          }
                          if (module == 'committee' && amount.text.isEmpty) {
                            final p = a.profiles.firstWhere(
                              (p) => p['id'] == party,
                            );
                            amount.text =
                                '${(type == 'committee_pay' ? p['installmentAmount'] : p['totalAmount']) / 100}';
                          }
                        }),
                ),
                if (module != 'owner')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => profileDialog(c, a, module),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const LocalizedText('Add profile'),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (party.isNotEmpty &&
                  ['supplier_payment', 'supplier_return'].contains(type))
                Tile(
                  color: a.dark ? null : pale,
                  child: pair(
                    'Remaining company balance',
                    money(max(0, -a.balance('supplier:$party'))),
                  ),
                ),
              if (party.isNotEmpty && type == 'loan_collect')
                Tile(
                  color: a.dark ? null : pale,
                  child: pair(
                    'Qarz baqaya',
                    money(
                      max(
                        0,
                        a.balance('loanAsset:$party') +
                            a.balance('loanDebt:$party'),
                      ),
                    ),
                  ),
                ),
              if (party.isNotEmpty && type == 'salary_payment')
                Tile(
                  color: a.dark ? null : pale,
                  child: Column(
                    children: [
                      pair('Remaining salary', money(a.salaryDue(party))),
                      pair('Advance', money(a.salaryCredit(party))),
                      if (entered > 0) ...[
                        pair(
                          'Salary after payment',
                          money(max(0, a.salaryNet(party) - entered)),
                        ),
                        pair(
                          'Advance after payment',
                          money(max(0, entered - a.salaryNet(party))),
                        ),
                      ],
                    ],
                  ),
                ),
              if (progress != null)
                Tile(
                  color: a.dark ? null : pale,
                  child: Column(
                    children: [
                      pair('Qistain baqi', money(progress.remaining)),
                      pair('Qist di', money(progress.paid)),
                      pair('Committee mili', money(progress.received)),
                      if (progress.nextDate != null)
                        pair('Next qist', dateLabel(progress.nextDate!)),
                    ],
                  ),
                ),
              if (party.isNotEmpty) const SizedBox(height: 16),
              if (type == 'order')
                input(staff, 'Order by', required: true, key: 'order-person'),
              input(
                amount,
                type == 'daily_sale_cash' ? 'Net daily sale' : 'Amount',
                numeric: true,
                required: true,
                key: type == 'order' ? 'order-amount' : 'notebook-amount',
              ),
              if (type == 'expense') ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: a.tr('Expense category'),
                  ),
                  items: [
                    for (final s in expenseCategories)
                      DropdownMenuItem(value: s, child: Text(a.tr(s))),
                  ],
                  onChanged: (v) => setState(() => category = v!),
                ),
                const SizedBox(height: 16),
              ],
              if (hasAccount) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: account,
                  decoration: InputDecoration(labelText: a.tr('Cash / Bank')),
                  items: [
                    for (final s in a.state['accounts'])
                      DropdownMenuItem(
                        value: s as String,
                        child: Text(
                          a.tr(
                            s == 'cash'
                                ? 'Cash'
                                : s == 'bank'
                                ? 'Bank'
                                : s,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => account = v!),
                ),
                const SizedBox(height: 16),
              ],
              Tile(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: c,
                    initialDate: DateTime.parse(date),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.parse(today()),
                  );
                  if (picked != null) {
                    setState(
                      () => date = picked.toIso8601String().substring(0, 10),
                    );
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
              if (type == 'supplier_bill') ...[
                const SizedBox(height: 16),
                input(
                  reference,
                  'Bill number',
                  required: true,
                  key: 'entry-reference',
                ),
              ],
              if (type == 'supplier_payment')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('Extra company advance'),
                  value: allowAdvance,
                  onChanged: (v) => setState(() => allowAdvance = v),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const LocalizedText('Notes'),
                children: [input(notes, 'Notes (optional)')],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
