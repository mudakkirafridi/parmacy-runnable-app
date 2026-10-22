part of '../../ui/screens.dart';

Future<void> simpleProfileDialog(
  BuildContext c,
  AppStore a,
  String module, {
  Json? existing,
}) async {
  final id = existing?['id'] ?? const Uuid().v4();
  final name = TextEditingController(text: existing?['name'] ?? ''),
      phone = TextEditingController(text: existing?['phone'] ?? ''),
      notes = TextEditingController(text: existing?['notes'] ?? ''),
      salary = TextEditingController(text: existing?['rate'] ?? ''),
      due = TextEditingController(text: existing?['rate'] ?? '');
  final total = TextEditingController(
        text: existing?['totalAmount'] == null
            ? ''
            : '${existing!['totalAmount'] / 100}',
      ),
      qist = TextEditingController(
        text: existing?['installmentAmount'] == null
            ? ''
            : '${existing!['installmentAmount'] / 100}',
      );
  String frequency = existing?['frequency'] ?? 'Monthly',
      startDate = existing?['startDate'] ?? today();
  bool customDue = false;
  String month = today().substring(0, 7);
  bool recordSalary = existing == null && module == 'salary', saving = false;
  String? error;
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(
          module.isEmpty
              ? a.tr('Add profile')
              : module == 'salary'
              ? a.tr('Staff profile')
              : a.tr(profileCategories[module] ?? 'Profiles'),
        ),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existing == null) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('profile-category-$module'),
                    initialValue: module.isEmpty ? null : module,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: a.tr('Profile type'),
                    ),
                    items: [
                      for (final cat in profileCategories.entries.where(
                        (e) => a.canPost(e.key),
                      ))
                        DropdownMenuItem(
                          value: cat.key,
                          child: Text(a.tr(cat.value)),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => set(() {
                            module = v!;
                            recordSalary = module == 'salary';
                          }),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: name,
                  decoration: InputDecoration(
                    labelText: a.tr('Name *'),
                    hintText: 'Misal: Ali Khan',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: a.tr('Phone (optional)'),
                  ),
                ),
                if (module == 'committee') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: total,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: a.tr('Total amount (Rs)'),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qist,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: a.tr('Installment amount (Rs)'),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: frequency,
                    decoration: InputDecoration(labelText: a.tr('Schedule')),
                    items: [
                      for (final f in ['Daily', 'Weekly', 'Monthly'])
                        DropdownMenuItem(value: f, child: Text(a.tr(f))),
                    ],
                    onChanged: (v) => set(() => frequency = v!),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.parse(startDate),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) {
                        set(
                          () =>
                              startDate = d.toIso8601String().substring(0, 10),
                        );
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('Start: ${dateLabel(startDate)}'),
                  ),
                ],
                if (module == 'salary') ...[
                  const SizedBox(height: 12),
                  TextField(
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    controller: salary,
                    onChanged: (v) {
                      if (!customDue) due.text = v;
                    },
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: a.tr('Monthly salary (Rs)'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('Record salary due for a month'),
                    value: recordSalary,
                    onChanged: saving
                        ? null
                        : (v) => set(() => recordSalary = v),
                  ),
                  if (recordSalary)
                    TextField(
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      controller: due,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => customDue = true,
                      decoration: InputDecoration(
                        labelText: a.tr('Salary due this month (Rs)'),
                      ),
                    ),
                  if (recordSalary)
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: Text('Salary month: $month'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.parse('$month-01'),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.parse(today()),
                        );
                        if (d != null) {
                          set(
                            () => month = d.toIso8601String().substring(0, 7),
                          );
                        }
                      },
                    ),
                ],
                const SizedBox(height: 12),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: notes,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: a.tr('Notes (optional)'),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
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
                    if (module.isEmpty) {
                      set(() => error = 'Select profile type');
                      return;
                    }
                    if (name.text.trim().isEmpty) {
                      set(() => error = 'Enter a name');
                      return;
                    }
                    int? amount;
                    try {
                      if (module == 'committee' &&
                          (paisa(total.text) <= 0 ||
                              paisa(qist.text) <= 0 ||
                              paisa(qist.text) > paisa(total.text))) {
                        throw StateError(
                          'Enter a valid total and installment amount',
                        );
                      }
                      if (module == 'salary') {
                        if (salary.text.trim().isNotEmpty) paisa(salary.text);
                        amount = recordSalary ? paisa(due.text) : 0;
                        if (recordSalary && amount <= 0) {
                          throw StateError('Enter a positive monthly salary');
                        }
                      }
                    } catch (e) {
                      set(
                        () => error = e.toString().replaceFirst(
                          'Bad state: ',
                          '',
                        ),
                      );
                      return;
                    }
                    set(() => saving = true);
                    final profile = <String, dynamic>{
                      ...existing ?? {},
                      'id': id,
                      'module': module,
                      if (module == 'committee') ...{
                        'totalAmount': paisa(total.text),
                        'installmentAmount': paisa(qist.text),
                        'frequency': frequency,
                        'startDate': startDate,
                      },
                      'active': true,
                      'deleted': false,
                      'name': name.text.trim(),
                      'phone': phone.text.trim(),
                      'notes': notes.text.trim(),
                      if (module == 'salary') 'rate': salary.text,
                      if (module == 'salary') 'basis': 'Monthly',
                      if (module == 'salary')
                        'rateHistory': [
                          ...existing?['rateHistory'] ?? [],
                          if (existing?['rate'] != salary.text)
                            {'rate': salary.text, 'effectiveDate': today()},
                        ],
                    };
                    try {
                      if (module == 'salary') {
                        await a.saveStaffProfile(
                          profile,
                          salaryPeriod: recordSalary ? month : null,
                          salaryAmount: amount,
                        );
                      } else {
                        await a.saveProfile(profile);
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
            child: Text(saving ? a.tr('Saving...') : a.tr('Save profile')),
          ),
        ],
      ),
    ),
  );
  for (final controller in [name, phone, notes, salary, due, total, qist]) {
    controller.dispose();
  }
}
