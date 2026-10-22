part of '../../ui/screens.dart';

const profileCategories = {
  'committee': 'Installment',
  'people': 'General profiles',
  'loans': 'Loan people',
  'salary': 'Staff profiles',
  'zakat': 'Zakat recipients',
  'suppliers': 'Companies',
};

class ProfilesScreen extends ConsumerStatefulWidget {
  final String? category;
  final bool recycleBin;
  const ProfilesScreen({super.key, this.category, this.recycleBin = false});
  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesState();
}

class _ProfilesState extends ConsumerState<ProfilesScreen> {
  String search = '', selectedCategory = '';
  Future<void> add(BuildContext c, AppStore a) async {
    await profileDialog(c, a, widget.category ?? '');
  }

  Future<void> remove(BuildContext c, AppStore a, Json record) async {
    final balances = a.profileBalances(record['id']);
    final purge = widget.recycleBin;
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(purge ? 'Delete permanently?' : 'Move to recycle bin?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record['name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final b in balances.entries)
              pair(b.key, money(b.value), color: orange),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const LocalizedText('Cancel'),
          ),
          if (!purge && balances.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                c.push('/register/${record['module']}');
              },
              child: const LocalizedText('Clear balance'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              purge
                  ? 'Delete permanently'
                  : balances.isEmpty
                  ? 'Move to bin'
                  : 'Force move to bin',
            ),
          ),
        ],
      ),
    );
    if (ok == true && c.mounted) {
      await perform(
        c,
        () => purge
            ? a.purgeProfile(record)
            : a.removeProfile(record, force: balances.isNotEmpty),
      );
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    final categories = profileCategories.entries
        .where((e) => a.can(e.key == 'people' ? 'profiles' : e.key))
        .toList();
    final records = a.profiles
        .where(
          (p) =>
              p['purged'] != true &&
              (widget.category == null || p['module'] == widget.category) &&
              (selectedCategory.isEmpty || p['module'] == selectedCategory) &&
              categories.any((e) => e.key == p['module']) &&
              (widget.recycleBin
                  ? !AppStore.profileVisible(p)
                  : AppStore.profileVisible(p)) &&
              '${p['name']} ${p['phone'] ?? ''}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Frame(
      title: widget.recycleBin
          ? 'Recycle bin'
          : widget.category == null
          ? 'Profiles'
          : profileCategories[widget.category]!,
      bottom:
          !widget.recycleBin &&
              (widget.category == null
                  ? categories.any((cat) => a.canPost(cat.key))
                  : a.canPost(widget.category!))
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('register-add-entry'),
                  onPressed: () => add(c, a),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(a.tr('Add profile')),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          if (!widget.recycleBin) ...[
            OutlinedButton.icon(
              onPressed: () => c.push('/recycle-bin'),
              icon: const Icon(Icons.recycling),
              label: Text(a.tr('Recycle bin')),
            ),
            const SizedBox(height: 16),
            if (widget.category == null)
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                isExpanded: true,
                decoration: InputDecoration(labelText: a.tr('Profile type')),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(a.tr('All profiles')),
                  ),
                  for (final cat in categories)
                    DropdownMenuItem(
                      value: cat.key,
                      child: Text(a.tr(cat.value)),
                    ),
                ],
                onChanged: (v) => setState(() => selectedCategory = v!),
              ),
            const SizedBox(height: 14),
          ],
          TextField(
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: a.tr('Search name or reference'),
            ),
          ),
          const SizedBox(height: 14),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(a.tr('No matching records')),
            ),
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Tile(
                onTap: widget.recycleBin
                    ? null
                    : () => profileDialog(
                        c,
                        a,
                        record['module'],
                        existing: record,
                      ),
                child: Row(
                  children: [
                    Icon(
                      icons[record['module']] ?? Icons.person_outline,
                      color: blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            a.tr(
                              profileCategories[record['module']] ?? 'Profile',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if ((record['phone'] ?? '').isNotEmpty)
                            Text(record['phone']),
                          for (final b
                              in a.profileBalances(record['id']).entries)
                            Text(
                              '${a.tr(b.key)}: ${money(b.value)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: orange,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (a.canPost(record['module'])) ...[
                      if (widget.recycleBin)
                        IconButton(
                          tooltip: 'Restore',
                          onPressed: () =>
                              perform(c, () => a.restoreProfile(record)),
                          icon: const Icon(Icons.restore, color: green),
                        ),
                      if (!widget.recycleBin || a.owner)
                        IconButton(
                          tooltip: widget.recycleBin
                              ? 'Delete permanently'
                              : 'Move to bin',
                          onPressed: () => remove(c, a, record),
                          icon: const Icon(Icons.delete_outline, color: orange),
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

class OwnersScreen extends ConsumerWidget {
  const OwnersScreen({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final a = ref.watch(appProvider);
    return Frame(
      title: 'Owners & shares',
      actions: [
        if (a.owner)
          IconButton(
            onPressed: () => editOwners(c, a),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Tile(
            color: a.dark ? null : pale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                big(a.settings['name'] ?? 'Pharmacy', size: 24),
                const SizedBox(height: 8),
                Text(a.tr('Owners & shares')),
                pair(a.tr('Total shares'), '100%', bold: true),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final o in a.owners)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Tile(
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: blue,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        o['name'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    big(
                      '${(o['shareBps'] / 100).toStringAsFixed(o['shareBps'] % 100 == 0 ? 0 : 2)}%',
                      color: blue,
                      size: 27,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (a.owner)
            FilledButton.icon(
              onPressed: () => editOwners(c, a),
              icon: const Icon(Icons.edit),
              label: Text(a.tr('Edit owners')),
            ),
        ],
      ),
    );
  }
}

Future<void> editOwners(BuildContext c, AppStore a) async {
  final rows = [
    for (final o in a.owners)
      {
        'id': o['id'],
        'editing': CredentialEditingFormatter(),
        'name': TextEditingController(text: o['name']),
        'share': TextEditingController(
          text: (o['shareBps'] / 100).toStringAsFixed(
            o['shareBps'] % 100 == 0 ? 0 : 2,
          ),
        ),
      },
  ];
  bool saving = false;
  String? error;
  final allControllers = <TextEditingController>[
    for (final row in rows) row['name'] as TextEditingController,
    for (final row in rows) row['share'] as TextEditingController,
  ];
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(a.tr('Edit owners')),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            controller: row['name'] as TextEditingController,
                            decoration: InputDecoration(
                              labelText: a.tr('Name'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            key: ValueKey('owner-share-${row['id']}'),
                            inputFormatters: [
                              row['editing'] as CredentialEditingFormatter,
                            ],
                            controller: row['share'] as TextEditingController,
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            onChanged: (_) => set(() => error = null),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(suffixText: '%'),
                          ),
                        ),
                        IconButton(
                          onPressed: saving
                              ? null
                              : () => set(() => rows.remove(row)),
                          icon: const Icon(Icons.delete_outline, color: orange),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () => set(() {
                          final name = TextEditingController(),
                              share = TextEditingController();
                          allControllers.addAll([name, share]);
                          rows.add({
                            'id': const Uuid().v4(),
                            'name': name,
                            'share': share,
                            'editing': CredentialEditingFormatter(),
                          });
                        }),
                  icon: const Icon(Icons.add),
                  label: Text(a.tr('Add owner')),
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
            child: Text(a.tr('Cancel')),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    try {
                      final owners = [
                        for (final row in rows)
                          {
                            'id': row['id'],
                            'name': (row['name'] as TextEditingController).text
                                .trim(),
                            'shareBps': parseOwnerShare(
                              (row['share'] as TextEditingController).text,
                            ),
                          },
                      ];
                      validateOwners(owners);
                      set(() => saving = true);
                      await a.saveSettings({...a.settings, 'owners': owners});
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        set(() {
                          saving = false;
                          error = e
                              .toString()
                              .replaceFirst('Bad state: ', '')
                              .replaceFirst('FormatException: ', '');
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
  for (final controller in allControllers) {
    controller.dispose();
  }
}
