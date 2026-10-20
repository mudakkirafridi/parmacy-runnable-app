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
  bool customDue = false;
  String month = today().substring(0, 7);
  bool recordSalary = existing == null && module == 'salary', saving = false;
  String? error;
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(
          module == 'salary'
              ? 'Staff profile'
              : profileCategories[module] ?? 'Profile',
        ),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'Misal: Ali Khan',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                  ),
                ),
                if (module == 'salary') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: salary,
                    onChanged: (v) {
                      if (!customDue) due.text = v;
                    },
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monthly salary (Rs)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Record salary due for a month'),
                    value: recordSalary,
                    onChanged: saving
                        ? null
                        : (v) => set(() => recordSalary = v),
                  ),
                  if (recordSalary)
                    TextField(
                      controller: due,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => customDue = true,
                      decoration: const InputDecoration(
                        labelText: 'Salary due this month (Rs)',
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
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (name.text.trim().isEmpty) {
                      set(() => error = 'Enter a name');
                      return;
                    }
                    int? amount;
                    try {
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
            child: Text(saving ? 'Saving...' : 'Save profile'),
          ),
        ],
      ),
    ),
  );
  for (final controller in [name, phone, notes, salary, due]) {
    controller.dispose();
  }
}
