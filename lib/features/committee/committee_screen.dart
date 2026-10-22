part of '../../ui/screens.dart';

class CommitteeScreen extends ConsumerWidget {
  const CommitteeScreen({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final a = ref.watch(appProvider);
    final progress = CommitteeProgress.all(
      a.profiles.where((p) => p['module'] == 'committee'),
      a.entries,
    );
    final records =
        a.entries
            .where((e) => e['module'] == 'committee' && a.entryVisible(e))
            .toList()
          ..sort(
            (a, b) => '${b['date']} ${b['createdAt']}'.compareTo(
              '${a['date']} ${a['createdAt']}',
            ),
          );
    return Frame(
      title: 'Committee / Qist',
      bottom: a.canPost('committee')
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('register-add-entry'),
                  onPressed: () => c.push('/entry?type=committee_pay'),
                  icon: const Icon(Icons.add),
                  label: const LocalizedText('New entry'),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          OutlinedButton.icon(
            onPressed: () => profileDialog(c, a, 'committee'),
            icon: const Icon(Icons.add),
            label: const LocalizedText('New profile'),
          ),
          const SizedBox(height: 16),
          for (final p in a.people('committee')) ...[
            Builder(
              builder: (c) {
                final s = progress[p['id']]!;
                return Tile(
                  onTap: () => c.push(
                    '/reports?module=committee&party=${Uri.encodeComponent(p['id'])}',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: big(p['name'], size: 20)),
                          IconButton(
                            onPressed: () =>
                                profileDialog(c, a, 'committee', existing: p),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      pair('Qist di', money(s.paid)),
                      pair('Raqam mili', money(s.received)),
                      pair('Qistain baqi', money(s.remaining), bold: true),
                      if (s.nextDate != null)
                        pair('Next qist', dateLabel(s.nextDate!)),
                      Text(
                        '${p['frequency']} • ${money(s.installment)}',
                        style: const TextStyle(color: blue),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          big('Entries', size: 22),
          const SizedBox(height: 10),
          for (final e in records) entryTile(c, a, e),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LocalizedText('No entries'),
            ),
        ],
      ),
    );
  }
}
