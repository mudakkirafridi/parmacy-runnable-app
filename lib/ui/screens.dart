import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/ledger.dart';
import 'app_back_scope.dart';
import 'credential_editing.dart';
import '../core/ownership.dart';
import '../features/security/app_lock.dart';
import '../data/app_store.dart';
import '../features/reports/export.dart';

part '../features/registers/simple_forms.dart';
part '../features/profiles/profiles_screen.dart';
part '../features/home/simple_home.dart';
part '../features/reports/simple_reports.dart';
part '../features/orders/orders_screen.dart';
part '../features/profiles/staff_form.dart';

const expenseCategories = [
  'Expense',
  'Rent',
  'Dinner',
  'Lunch',
  'Tea',
  'Other',
  'Electricity',
  'Gas',
  'Water',
  'Internet / phone',
  'Transport',
  'Repairs',
  'Cleaning',
  'Stationery',
  'Miscellaneous',
];

const navy = Color(0xff071943),
    blue = Color(0xff005bea),
    green = Color(0xff00b78b),
    orange = Color(0xffff741b),
    pale = Color(0xffedf4fd);
const modules = {
  'orders': 'Orders',
  'suppliers': 'Companies',
  'profiles': 'Profiles',
  'salary': 'Salary',
  'loans': 'Loans',
  'zakat': 'Zakat',
  'sales': 'Daily sales',
  'expenses': 'Expenses',
  'cashbook': 'Cashbook',
  'owner': 'Owner',
};
const icons = {
  'orders': Icons.shopping_bag_outlined,
  'suppliers': Icons.local_shipping_rounded,
  'profiles': Icons.groups_rounded,
  'people': Icons.person_outline,
  'zakat_companies': Icons.business,
  'salary': Icons.badge_rounded,
  'rent': Icons.storefront_rounded,
  'loans': Icons.handshake_rounded,
  'zakat': Icons.volunteer_activism_rounded,
  'sales': Icons.point_of_sale_rounded,
  'expenses': Icons.description_outlined,
  'cashbook': Icons.account_balance_wallet_rounded,
  'owner': Icons.person_rounded,
};
String dateLabel(String date) =>
    DateFormat('dd MMM yyyy').format(DateTime.parse(date));
void toast(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));
Future<void> perform(BuildContext c, Future<void> Function() action) async {
  try {
    await action();
    if (c.mounted) {
      toast(
        c,
        ProviderScope.containerOf(c).read(appProvider).tr('Saved successfully'),
      );
    }
  } catch (e) {
    if (c.mounted) toast(c, e.toString().replaceFirst('Bad state: ', ''));
  }
}

Widget big(String s, {double size = 28, Color? color}) => Text(
  s,
  style: TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    color: color,
    letterSpacing: -.7,
  ),
);
Widget pair(String label, String value, {Color? color, bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 21 : 17,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );

class Tile extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const Tile({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(17),
    this.onTap,
  });
  @override
  Widget build(BuildContext c) => Container(
    decoration: BoxDecoration(
      color: color ?? Theme.of(c).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: color == null
          ? Border.all(color: Theme.of(c).dividerColor.withValues(alpha: .18))
          : null,
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class Frame extends ConsumerWidget {
  final String title;
  final Widget body;
  final int? tab;
  final Widget? bottom;
  final VoidCallback? onBack;
  final List<Widget> actions;
  const Frame({
    super.key,
    required this.title,
    required this.body,
    this.tab,
    this.bottom,
    this.onBack,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final a = ref.watch(appProvider);
    final headingStyle =
        (Theme.of(c).appBarTheme.titleTextStyle ?? const TextStyle()).copyWith(
          fontSize: 24,
        );
    final available = max(
      90.0,
      min(480.0, MediaQuery.sizeOf(c).width) -
          (tab == null ? 56 : 0) -
          actions.length * 48 -
          90 -
          32,
    );
    final heading = TextPainter(
      text: TextSpan(text: a.tr(title), style: headingStyle),
      textDirection: Directionality.of(c),
      textScaler: MediaQuery.textScalerOf(c),
    )..layout(maxWidth: available);
    final headingHeight = max(58.0, heading.height + 20);
    final navigation = GoRouter.maybeOf(c);
    return AppBackScope(
      goHome:
          onBack ??
          (navigation == null
              ? null
              : navigation.canPop()
              ? () => navigation.pop()
              : navigation.routerDelegate.currentConfiguration.uri.path == '/'
              ? null
              : () => navigation.go('/')),
      child: ColoredBox(
        color: a.dark ? const Color(0xff091020) : const Color(0xffeef2f8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: tab == null
                    ? IconButton(
                        onPressed:
                            onBack ?? () => c.canPop() ? c.pop() : c.go('/'),
                        icon: const Icon(Icons.arrow_back),
                      )
                    : null,
                toolbarHeight: headingHeight,
                title: Text(
                  a.tr(title),
                  style: headingStyle,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
                actions: [
                  ...actions,
                  SizedBox(
                    width: 90,
                    child: TextButton(
                      onPressed: a.toggleLanguage,
                      child: Text(
                        a.ur ? 'اردو  |  EN' : 'EN  |  اردو',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (a.live && (a.cached || a.error != null))
                    MaterialBanner(
                      content: Text(
                        [
                          if (a.cached) a.tr('Read cached data'),
                          if (a.error != null) a.error!,
                        ].join('\n'),
                      ),
                      actions: [
                        if (a.uploadIssues.isNotEmpty)
                          TextButton(
                            onPressed: () => uploadIssuesDialog(c, a),
                            child: const Text('Review'),
                          ),
                        TextButton(
                          onPressed: a.syncing
                              ? null
                              : () async {
                                  await a.retryUploads();
                                  await a.refresh();
                                },
                          child: Text(a.tr('Retry')),
                        ),
                      ],
                    ),
                  if (a.busy || a.syncing)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(child: body),
                ],
              ),
              bottomNavigationBar:
                  bottom ??
                  (tab != null
                      ? BottomNavigationBar(
                          currentIndex: tab!,
                          type: BottomNavigationBarType.fixed,
                          selectedItemColor: blue,
                          unselectedItemColor: const Color(0xff60718f),
                          selectedFontSize: 11,
                          unselectedFontSize: 11,
                          onTap: (i) =>
                              c.go(['/', '/registers', '/reports', '/more'][i]),
                          items: [
                            for (final pair in [
                              (Icons.home_rounded, 'Home'),
                              (Icons.description, 'Registers'),
                              (Icons.bar_chart_rounded, 'Reports'),
                              (Icons.more_horiz, 'More'),
                            ])
                              BottomNavigationBarItem(
                                icon: Icon(pair.$1, size: 27),
                                label: a.tr(pair.$2),
                              ),
                          ],
                        )
                      : null),
            ),
          ),
        ),
      ),
    );
  }
}

class RegistersScreen extends ConsumerWidget {
  const RegistersScreen({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final a = ref.watch(appProvider);
    return Frame(
      title: 'Registers',
      tab: 1,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          for (final m in modules.entries)
            if (a.can(m.key))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Tile(
                  onTap: () => c.push(
                    m.key == 'profiles' ? '/profiles' : '/register/${m.key}',
                  ),
                  child: Row(
                    children: [
                      Icon(icons[m.key], color: blue, size: 30),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          a.tr(m.value),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  final String module;
  const RegisterScreen({super.key, required this.module});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterState();
}

class _RegisterState extends ConsumerState<RegisterScreen> {
  String query = '', party = '';
  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider), module = widget.module;
    if (module == 'orders') return const OrdersScreen();
    if (module == 'profiles' || module == 'customers') {
      return const ProfilesScreen();
    }
    final people = a
        .people(module)
        .where(
          (p) => '${p['name']} ${p['phone']} ${p['notes']}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    final all =
        a.entries
            .where(
              (e) =>
                  (e['module'] == module ||
                      (module == 'cashbook' &&
                          (e['effects'] as Json).keys.any(
                            (k) => k.startsWith('money:'),
                          ))) &&
                  (party.isEmpty || party == e['party']) &&
                  '${a.name(e['party'])} ${e['reference']} ${e['notes']}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort(
            (x, y) => '${y['date']} ${y['createdAt'] ?? ''} ${y['id']}'
                .compareTo('${x['date']} ${x['createdAt'] ?? ''} ${x['id']}'),
          );
    final prefix = {
      'suppliers': 'supplier:',
      'customers': 'customer:',
      'salary': 'salary:',
      'rent': 'expense:rent',
      'loans': 'loanAsset:',
      'zakat': 'zakat',
      'zakat_companies': 'zakat:company',
      'cashbook': 'money:',
      'expenses': 'expense:',
      'owner': 'capital',
      'sales': 'sales',
    }[module]!;
    final entryChoices = a.ledger.types.entries
        .where(
          (e) =>
              e.value['module'] == module &&
              e.value['retired'] != true &&
              e.value['menuHidden'] != true &&
              (e.value['owner'] != true || a.owner),
        )
        .toList();
    final entryLabel = entryChoices.length == 1
        ? a.typeLabel(entryChoices.single.key)
        : a.tr('Add entry');
    final sign = ['suppliers', 'salary', 'sales', 'owner'].contains(module)
        ? -1
        : 1;
    return Frame(
      onBack: party.isEmpty ? null : () => setState(() => party = ''),
      title: modules[module] ?? module,
      bottom: a.canPost(module) && entryChoices.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('register-add-entry'),
                  onPressed: () => chooseType(c, a, module, party: party),
                  icon: const Icon(Icons.add),
                  label: Text(entryLabel),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          TextField(
            onChanged: (s) => setState(() => query = s),
            decoration: InputDecoration(
              hintText: a.tr('Search name or reference'),
              prefixIcon: const Icon(Icons.search),
              fillColor: a.dark ? null : pale,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 13),
          Tile(
            color: a.dark ? null : pale,
            child: Row(
              children: [
                Icon(icons[module], color: blue, size: 39),
                const SizedBox(width: 27),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.tr(
                          module == 'suppliers'
                              ? 'Total payable'
                              : module == 'sales'
                              ? 'Net daily sale'
                              : module == 'rent'
                              ? 'Rent paid'
                              : 'Balance',
                        ),
                      ),
                      big(
                        money(
                          (module == 'sales'
                                  ? a.netSalesTotal
                                  : module == 'loans'
                                  ? loanTotal(a.state['balances'])
                                  : a.total(prefix)) *
                              (module == 'sales' ? 1 : sign),
                        ),
                        size: 33,
                        color: const Color(0xff124ac4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (module == 'zakat')
            Tile(
              child: Column(
                children: [
                  pair(
                    a.tr('Annual zakat target'),
                    money(a.settings['zakatTarget'] ?? 0),
                  ),
                  pair(
                    a.tr('Remaining target'),
                    money(
                      max(
                        0,
                        (a.settings['zakatTarget'] as int? ?? 0) -
                            a.entries
                                .where(
                                  (e) => e['date'].toString().startsWith(
                                    today().substring(0, 4),
                                  ),
                                )
                                .fold<int>(
                                  0,
                                  (s, e) =>
                                      s +
                                      ((e['effects'] as Json)['zakat']
                                              as int? ??
                                          0),
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final p in people)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: module == 'suppliers'
                  ? supplierCard(c, a, p)
                  : Tile(
                      onTap: () => setState(
                        () => party = party == p['id'] ? '' : p['id'],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p['name'],
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    profileDialog(c, a, module, existing: p),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                            ],
                          ),
                          pair(
                            a.tr(
                              module == 'loans'
                                  ? ((a.balance('loanAsset:${p['id']}') +
                                                a.balance(
                                                  'loanDebt:${p['id']}',
                                                )) <
                                            0
                                        ? 'Jama'
                                        : 'Baqaya')
                                  : module == 'rent'
                                  ? 'Rent paid'
                                  : [
                                      'zakat',
                                      'zakat_companies',
                                    ].contains(module)
                                  ? 'Amount paid'
                                  : 'Outstanding',
                            ),
                            money(
                              [
                                    'rent',
                                    'zakat',
                                    'zakat_companies',
                                  ].contains(module)
                                  ? a.amountForPerson(module, p['id'])
                                  : module == 'loans'
                                  ? (a.balance('loanAsset:${p['id']}') +
                                            a.balance('loanDebt:${p['id']}'))
                                        .abs()
                                  : a.balance('$prefix${p['id']}') * sign,
                            ),
                          ),
                          if (module == 'salary')
                            pair(
                              a.tr('Advance / credit'),
                              money(a.balance('salaryAdvance:${p['id']}')),
                            ),
                        ],
                      ),
                    ),
            ),
          if ([
            'suppliers',
            'customers',
            'salary',
            'rent',
            'loans',
            'zakat',
            'zakat_companies',
          ].contains(module))
            TextButton.icon(
              onPressed: () => profileDialog(c, a, module),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(a.tr('Add person')),
            ),
          if (party.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => c.push('/reports?module=$module&party=$party'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Person / company report'),
            ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  a.tr(
                    module == 'suppliers'
                        ? 'Payment history'
                        : 'Account statement',
                  ),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (party.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => party = ''),
                  child: Text(a.tr('All')),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.all(25),
              child: Text(a.tr('No matching records')),
            ),
          for (final e in all) entryTile(c, a, e),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget supplierCard(BuildContext c, AppStore a, Json p) {
    final bills = a.bills('suppliers', p['id']);
    final amount = bills.fold<int>(0, (s, b) => s + (b['original'] as int));
    final related = a.entries.where(
      (e) => e['party'] == p['id'] && e['reversedBy'] == null,
    );
    final paid = related
        .where((e) => e['type'] == 'supplier_payment')
        .fold<int>(0, (s, e) => s + (e['amount'] as int));
    final returned = related
        .where((e) => e['type'] == 'supplier_return')
        .fold<int>(0, (s, e) => s + (e['amount'] as int));
    return Tile(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      onTap: () => setState(() => party = party == p['id'] ? '' : p['id']),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p['name'],
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => profileDialog(c, a, 'suppliers', existing: p),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          pair(
            '${a.tr('Bill')} ${bills.map((b) => b['reference']).join(', ')}',
            money(amount),
          ),
          pair(a.tr('Paid'), money(paid)),
          pair(a.tr('Confirmed return credit'), money(returned)),
          const Divider(height: 16),
          pair(
            a.tr('Outstanding'),
            money(-a.balance('supplier:${p['id']}')),
            color: Colors.deepOrange,
            bold: true,
          ),
        ],
      ),
    );
  }
}

Widget entryTile(BuildContext c, AppStore a, Json e) {
  final returned = e['type'].toString().contains('return');
  final out =
      (Json.from(e['effects'] ?? {}).entries
          .where((x) => x.key.startsWith('money:'))
          .fold<int>(0, (sum, x) => sum + (x.value as int))) <
      0;
  return Tile(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    onTap: () => entryDetails(c, a, e),
    child: Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: returned || out ? orange : green,
          child: Icon(
            returned
                ? Icons.undo
                : out
                ? Icons.arrow_downward
                : Icons.arrow_upward,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (a.entryName(e)).toString().isNotEmpty
                    ? (a.entryName(e))
                    : a.typeLabel(e['type']),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${a.typeLabel(e['type'])} | ${dateLabel(e['date'])}',
                style: const TextStyle(fontSize: 12, color: Color(0xff52698c)),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              money(e['amount']),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (e['syncStatus'] == 'Pending upload')
              const Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: Color(0xff60718f),
              ),
            if (returned)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xffc4fae0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  a.tr('Confirmed'),
                  style: const TextStyle(
                    color: Color(0xff005629),
                    fontSize: 11,
                  ),
                ),
              ),
            if (e['reversedBy'] != null)
              Text(
                a.tr('Reversed'),
                style: const TextStyle(color: orange, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, size: 21, color: Color(0xff60718f)),
      ],
    ),
  );
}

Future<void> chooseType(
  BuildContext c,
  AppStore a,
  String module, {
  String party = '',
}) async {
  final choices = a.ledger.types.entries
      .where(
        (e) =>
            e.value['module'] == module &&
            e.value['retired'] != true &&
            e.value['menuHidden'] != true &&
            (e.value['owner'] != true || a.owner),
      )
      .toList();
  if (choices.length == 1 || module == 'sales' || module == 'expenses') {
    final type = module == 'sales'
        ? 'daily_sales'
        : module == 'expenses'
        ? 'expense'
        : choices.single.key;
    c.push(
      '/entry/$type${party.isEmpty ? '' : '?party=${Uri.encodeComponent(party)}'}',
    );
    return;
  }
  final result = await showModalBottomSheet<String>(
    context: c,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Text(
              a.tr('Add entry'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            for (final t in a.ledger.types.entries.where(
              (e) =>
                  e.value['module'] == module &&
                  e.value['retired'] != true &&
                  e.value['menuHidden'] != true &&
                  (e.value['owner'] != true || a.owner),
            ))
              ListTile(
                title: Text(a.typeLabel(t.key)),
                leading: Icon(icons[module], color: blue),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, t.key),
              ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    ),
  );
  if (result != null && c.mounted) {
    c.push(
      '/entry/$result${party.isEmpty ? '' : '?party=${Uri.encodeComponent(party)}'}',
    );
  }
}

Future<void> uploadIssuesDialog(BuildContext c, AppStore a) async {
  await showSafeDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Entries to review'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final issue in a.uploadIssues)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${issue['operation'] == 'correctExpense'
                          ? issue['value']['entry']['amount'] == null
                                ? ''
                                : money(issue['value']['entry']['amount'])
                          : issue['key'] == 'entry'
                          ? money(issue['value']['amount'])
                          : issue['value']['name'] ?? 'Entry'}',
                    ),
                    subtitle: Text(issue['failure'] ?? 'Change rejected'),
                    trailing: IconButton(
                      tooltip: 'Discard rejected change',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            title: const Text('Discard rejected change?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && ctx.mounted) {
                          try {
                            await a.discardFailedUpload(issue['id']);
                            if (ctx.mounted) set(() {});
                          } catch (e) {
                            if (ctx.mounted) toast(ctx, e.toString());
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              await a.retryUploads();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

Future<void> entryDetails(BuildContext c, AppStore a, Json e) async {
  await showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              big(a.typeLabel(e['type']), size: 24),
              const SizedBox(height: 12),
              big(money(e['amount']), color: blue),
              pair(a.tr('Date'), dateLabel(e['date'])),
              pair(a.tr('Reference'), e['reference'] ?? ''),
              Text(a.entryName(e)),
              Text(e['notes'] ?? e['reason'] ?? ''),
              const Divider(),
              Text(
                '${a.tr('Audit history')}: ${e['createdBy']}\n${e['createdAt']}\nID: ${e['id']}',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => exportReport(
                  a,
                  [e],
                  e['date'],
                  e['date'],
                  'Receipt',
                  pdf: true,
                ),
                icon: const Icon(Icons.ios_share),
                label: Text(a.tr('Receipt')),
              ),
              if (a.owner && e['type'] == 'expense' && e['reversedBy'] == null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    editExpenseDialog(c, a, e);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(a.tr('Edit expense')),
                ),
              if (a.owner && e['reversedBy'] == null && e['type'] != 'reversal')
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await reverseDialog(c, a, e);
                  },
                  icon: const Icon(Icons.undo, color: orange),
                  label: Text(
                    a.tr(
                      e['type'] == 'expense'
                          ? 'Remove expense'
                          : 'Remove / reverse entry',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<T?> showSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  // showDialog's result completes at pop, before its exit animation removes
  // TextFields. Keep their controllers alive until the overlay is gone.
  await route.completed;
  return result;
}

Future<String?> inputDialog(
  BuildContext c,
  String label, {
  String value = '',
}) async {
  final controller = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(label),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return result;
}

Future<void> profileDialog(
  BuildContext c,
  AppStore a,
  String module, {
  Json? existing,
}) => simpleProfileDialog(c, a, module, existing: existing);

class EntryScreen extends ConsumerStatefulWidget {
  final String type;
  final String? party;
  final Json? draft;
  const EntryScreen({super.key, required this.type, this.party, this.draft});
  @override
  ConsumerState<EntryScreen> createState() => _EntryState();
}

class _EntryState extends ConsumerState<EntryScreen> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late String id, date, party;
  String account = 'cash',
      target = 'bank',
      category = 'Expense',
      basis = 'Monthly',
      proration = 'Calendar days';
  bool advance = false;
  String returnStatus = 'Confirmed';
  final allocations = <String, TextEditingController>{};
  final List<Json> creditRows = [];
  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    id = d?['id'] ?? const Uuid().v4();
    date = d?['date'] ?? today();
    party = d?['party'] ?? widget.party ?? '';
    account = d?['account'] ?? 'cash';
    target = d?['target'] ?? 'bank';
    category = d?['category'] ?? 'Expense';
    advance = d?['allowAdvance'] ?? false;
    for (final key in [
      'amount',
      'reference',
      'notes',
      'due',
      'cash',
      'bank',
      'credit',
      'returns',
      'refundCash',
      'refundBank',
      'reduction',
      'retained',
      'rate',
      'days',
      'allowance',
      'deduction',
      'deductionReason',
      'installment',
    ]) {
      final v = d?[key];
      fields[key] = TextEditingController(
        text: v == null
            ? ''
            : v is int
            ? (v / 100).toString()
            : v.toString(),
      );
    }
    if (widget.type == 'supplier_bill' &&
        fields['reference']!.text.trim().isEmpty) {
      final a = ref.read(appProvider);
      if (party.isEmpty && a.people('suppliers').isNotEmpty) {
        party = a.people('suppliers').first['id'];
      }
      fields['reference']!.text = a.nextBillNumber(party);
    }
    if (d != null) {
      for (final row in (d['credits'] as List? ?? []).skip(1)) {
        creditRows.add({
          'party': row['party'],
          'text': (row['amount'] / 100).toString(),
        });
      }
      for (final al in d['allocations'] ?? []) {
        allocations[al['id']] = TextEditingController(
          text: (al['amount'] / 100).toString(),
        );
      }
      if ((d['credits'] as List? ?? []).isNotEmpty) {
        party = d['credits'][0]['party'];
        fields['credit']!.text = (d['credits'][0]['amount'] / 100).toString();
      }
      if ((d['reductions'] as List? ?? []).isNotEmpty) {
        party = d['reductions'][0]['party'];
        fields['reduction']!.text = (d['reductions'][0]['amount'] / 100)
            .toString();
      }
    }
  }

  @override
  void dispose() {
    for (final x in [...fields.values, ...allocations.values]) {
      x.dispose();
    }
    super.dispose();
  }

  int val(String k) =>
      fields[k]!.text.trim().isEmpty ? 0 : paisa(fields[k]!.text);
  Widget field(
    AppStore a,
    String key,
    String label, {
    bool amount = false,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.tr(label), style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 7),
        TextFormField(
          key: ValueKey('entry-$key'),
          controller: fields[key],
          keyboardType: amount
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(
            fontSize: key == 'amount' ? 26 : 16,
            fontWeight: key == 'amount' ? FontWeight.w800 : FontWeight.w400,
          ),
          onChanged: (_) => setState(() {}),
          validator: (s) {
            if (required && (s ?? '').trim().isEmpty) return a.tr('Amount');
            if (amount && (s ?? '').isNotEmpty) {
              try {
                paisa(s!);
              } catch (e) {
                return e.toString();
              }
            }
            return null;
          },
          decoration: InputDecoration(
            prefixText: key == 'amount' ? 'Rs ' : null,
            hintText: key == 'notes'
                ? (a.ur
                      ? 'حوالہ یا کوئی نوٹ'
                      : 'e.g. Cheque no. 123, or any note...')
                : null,
          ),
        ),
      ],
    ),
  );
  Widget select(
    AppStore a,
    String label,
    String value,
    List<(String, String)> items,
    void Function(String) change, {
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.tr(label), style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: items.any((x) => x.$1 == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: icon == null
                ? null
                : Icon(icon, color: const Color(0xff52698c)),
          ),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item.$1,
                child: Text(a.tr(item.$2), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => change(v));
          },
        ),
      ],
    ),
  );
  int previewAmount() {
    try {
      return val('amount');
    } catch (_) {
      return 0;
    }
  }

  Json buildEntry(AppStore a) {
    final type = a.ledger.types[widget.type] as Json;
    if (widget.type == 'supplier_payment' &&
        !advance &&
        val('amount') > max(0, -a.balance('supplier:$party'))) {
      throw StateError('Amount exceeds remaining balance');
    }
    if (type['allocate'] == true) {
      final rows = widget.type == 'salary_payment' && advance
          ? <Json>[]
          : a.allocateOldest(
              type['module'],
              party,
              val('amount'),
              allowExcess: advance || type['creditReturn'] == true,
            );
      for (final c in allocations.values) {
        c.dispose();
      }
      allocations.clear();
      for (final row in rows) {
        allocations[row['id']] = TextEditingController(
          text: '${row['amount'] / 100}',
        );
      }
    }
    final x = <String, dynamic>{
      'id': id,
      if (widget.draft?['orderId'] != null) 'orderId': widget.draft!['orderId'],
      'type': widget.type == 'salary_payment' && advance
          ? 'salary_advance'
          : widget.type,
      'date': date,
      'party': party,
      'account': account,
      'target': target,
      'category': category,
      'amount': val('amount'),
      'reference': fields['reference']!.text.trim(),
      'notes': fields['notes']!.text.trim(),
      'allowAdvance': advance,
      'allocations': [
        for (final e
            in (widget.type == 'salary_payment' && advance
                    ? <String, TextEditingController>{}
                    : allocations)
                .entries)
          if (e.value.text.isNotEmpty && paisa(e.value.text) > 0)
            {'id': e.key, 'amount': paisa(e.value.text)},
      ],
    };
    if (widget.type != 'supplier_bill' && fields['due']!.text.isNotEmpty) {
      final d = DateTime.parse(fields['due']!.text);
      x['due'] = d.toIso8601String().substring(0, 10);
    }
    if (widget.type == 'supplier_bill') {
      x['scheduleAmount'] = val('installment');
      x['frequency'] = basis;
    }
    if (widget.type == 'salary_accrual') {
      final rate = val('rate'), days = int.tryParse(fields['days']!.text) ?? 0;
      final divisor = basis == 'Monthly'
          ? (proration == 'Fixed 30 days'
                ? 30
                : DateTime(
                    DateTime.parse(date).year,
                    DateTime.parse(date).month + 1,
                    0,
                  ).day)
          : basis == 'Weekly'
          ? 7
          : 1;
      if (days <= 0) throw StateError('Enter explicit payable days');
      if (val('deduction') > 0 &&
          fields['deductionReason']!.text.trim().isEmpty) {
        throw StateError('Deduction reason required');
      }
      x['amount'] =
          (rate * days + divisor ~/ 2) ~/ divisor +
          val('allowance') -
          val('deduction');
      x['salaryCalculation'] = {
        'rate': rate,
        'days': days,
        'basis': basis,
        'proration': proration,
        'allowance': val('allowance'),
        'deduction': val('deduction'),
        'deductionReason': fields['deductionReason']!.text,
      };
    }
    if (widget.type == 'daily_sales') {
      for (final k in [
        'cash',
        'bank',
        'returns',
        'refundCash',
        'refundBank',
        'retained',
      ]) {
        x[k] = val(k);
      }
      x['credits'] = [
        if (val('credit') > 0) {'party': party, 'amount': val('credit')},
      ];
      x['credits'].addAll(
        creditRows.map(
          (row) => {'party': row['party'], 'amount': paisa(row['text'])},
        ),
      );
      x['reductions'] = [
        if (val('reduction') > 0) {'party': party, 'amount': val('reduction')},
      ];
    }
    return x;
  }

  Future<void> review(AppStore a) async {
    if (!form.currentState!.validate()) return;
    try {
      final x = buildEntry(a);
      if (widget.type == 'supplier_return' && returnStatus != 'Confirmed') {
        await a.saveDraft({
          ...x,
          'returnStatus': returnStatus,
        }, status: returnStatus);
        if (mounted) toast(context, a.tr('Draft saved locally'));
        return;
      }
      final preview = a.ledger.post(a.state, x)['entry'] as Json;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(a.tr('Review entry')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.typeLabel(widget.type)),
                const SizedBox(height: 12),
                big(money(preview['amount']), color: blue),
                Text(a.name(party)),
                Text(dateLabel(date)),
                const SizedBox(height: 12),
                for (final e in (preview['effects'] as Json).entries.where(
                  (e) => e.key.startsWith('money:'),
                ))
                  pair(e.key.replaceFirst('money:', ''), money(e.value)),
                if (!(preview['effects'] as Json).keys.any(
                  (k) => k.startsWith('money:'),
                ))
                  Text(a.tr('No cash movement')),
                if (widget.type == 'salary_accrual')
                  Text(
                    '${a.tr('Payable days')}: ${fields['days']!.text}\n${a.tr('Rate')}: ${fields['rate']!.text}\n${a.tr(proration)}',
                  ),
                if (advance) Text(a.tr('Unallocated advance')),
                if (a.live) Text(a.tr('Pending submission')),
              ],
            ),
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
      if (ok == true) {
        await a.submit(x);
        if (mounted) {
          toast(context, a.tr('Saved successfully'));
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/register/${a.ledger.types[widget.type]['module']}');
          }
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider),
        t = a.ledger.types[widget.type] as Json,
        module = t['module'] as String;
    final isPay = widget.type == 'supplier_payment';
    final people = a.people(
      widget.type == 'daily_sales' ? 'customers' : module,
    );
    if (party.isEmpty && people.isNotEmpty) party = people.first['id'];
    final requiresParty =
        ('${t['debit']}${t['credit']}'.contains('{party}') ||
            t['partyRequired'] == true) ||
        ['daily_sales', 'zakat'].contains(widget.type);
    final hasCash =
        '${t['debit']}${t['credit']}'.contains('money:') ||
        widget.type == 'daily_sales';
    return Frame(
      title: isPay ? 'Pay company / Ograi' : a.typeLabel(widget.type),
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 8, 17, 14),
          child: FilledButton.icon(
            onPressed: a.busy ? null : () => review(a),
            icon: const Icon(Icons.check_circle, color: Colors.white, size: 26),
            label: Text(a.tr(isPay ? 'Review payment' : 'Review entry')),
          ),
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(17),
          children: [
            if (isPay && party.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 17),
                child: Tile(
                  color: a.dark ? null : pale,
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping, color: blue, size: 36),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          a.name(party),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (requiresParty && (!isPay || people.length != 1))
              select(
                a,
                'Select person',
                party,
                [
                  for (final p in people)
                    (p['id'] as String, p['name'] as String),
                ],
                (v) {
                  party = v;
                  for (final controller in allocations.values) {
                    controller.dispose();
                  }
                  allocations.clear();
                  if (widget.type == 'supplier_bill') {
                    fields['reference']!.text = a.nextBillNumber(party);
                  }
                },
                icon: icons[module],
              ),
            if (requiresParty && people.isEmpty)
              TextButton.icon(
                onPressed: () => profileDialog(
                  c,
                  a,
                  widget.type == 'daily_sales' ? 'customers' : module,
                ),
                icon: const Icon(Icons.person_add),
                label: Text(a.tr('Add person')),
              ),
            if (isPay && party.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Tile(
                  color: a.dark ? null : pale,
                  child: pair(
                    'Total remaining balance',
                    money(-a.balance('supplier:$party')),
                    bold: true,
                  ),
                ),
              ),
            if (widget.type == 'loan_collect' && party.isNotEmpty)
              Tile(
                color: a.dark ? null : pale,
                child: pair(
                  'Qarz baqaya',
                  money(
                    a.balance('loanAsset:$party') +
                        a.balance('loanDebt:$party'),
                  ),
                  bold: true,
                ),
              ),
            if (widget.type == 'salary_payment') ...[
              Tile(
                color: a.dark ? null : pale,
                child: Column(
                  children: [
                    pair(
                      'Remaining salary',
                      money(-a.balance('salary:$party')),
                      bold: true,
                    ),
                    pair('Advance', money(a.balance('salaryAdvance:$party'))),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pay advance'),
                value: advance,
                onChanged: (v) => setState(() => advance = v),
              ),
            ],
            if (!['daily_sales', 'salary_accrual'].contains(widget.type))
              field(a, 'amount', 'Amount', amount: true, required: true),
            Text(a.tr('Date')),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: InkWell(
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
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(
                      Icons.calendar_month,
                      color: Color(0xff52698c),
                    ),
                    suffixIcon: Icon(Icons.expand_more),
                  ),
                  child: Text(dateLabel(date)),
                ),
              ),
            ),
            if (hasCash)
              select(
                a,
                'Payment account',
                account,
                [
                  for (final acc in a.state['accounts'] ?? ['cash', 'bank'])
                    (
                      acc as String,
                      acc == 'cash'
                          ? 'Cash drawer'
                          : acc == 'bank'
                          ? 'Bank / digital'
                          : acc,
                    ),
                ],
                (v) => account = v,
                icon: Icons.account_balance_wallet,
              ),
            if (['transfer', 'daily_sales'].contains(widget.type))
              select(a, 'Target account', target, [
                for (final acc in a.state['accounts'] ?? ['cash', 'bank'])
                  (
                    acc as String,
                    acc == 'cash'
                        ? 'Cash drawer'
                        : acc == 'bank'
                        ? 'Bank / digital'
                        : acc,
                  ),
              ], (v) => target = v),
            if (isPay) ...[
              Tile(
                color: a.dark ? null : pale,
                child: pair(
                  'Remaining after payment',
                  money(-a.balance('supplier:$party') - previewAmount()),
                  color: blue,
                  bold: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pay advance / extra'),
                value: advance,
                onChanged: (v) => setState(() => advance = v),
              ),
            ],
            if (widget.type == 'customer_collection')
              SwitchListTile(
                value: advance,
                onChanged: (v) => setState(() => advance = v),
                title: Text(a.tr('Allow intentional advance / excess')),
              ),
            if (t['obligation'] == true || t['period'] == true)
              field(
                a,
                'reference',
                widget.type == 'supplier_bill'
                    ? 'Bill number'
                    : t['period'] == true
                    ? 'Shift / period reference'
                    : 'Reference',
                required: true,
              ),
            if (t['obligation'] == true && widget.type != 'supplier_bill')
              field(a, 'due', 'Due date'),
            if (widget.type == 'supplier_bill') ...[
              field(a, 'installment', 'Installment amount', amount: true),
              select(a, 'Payment frequency', basis, [
                ('Daily', 'Daily'),
                ('Weekly', 'Weekly'),
                ('Monthly', 'Monthly'),
                ('Irregular', 'Irregular'),
              ], (v) => basis = v),
            ],
            if (widget.type == 'supplier_return') ...[
              select(a, 'Return credit', returnStatus, [
                ('Confirmed', 'Confirmed'),
                ('Draft / requested return', 'Draft / requested return'),
                ('Rejected return', 'Rejected return'),
              ], (v) => returnStatus = v),
              const SizedBox(height: 15),
            ],
            if (widget.type == 'salary_accrual') ...[
              select(a, 'Salary basis', basis, [
                ('Daily', 'Daily'),
                ('Weekly', 'Weekly'),
                ('Monthly', 'Monthly'),
              ], (v) => basis = v),
              field(a, 'rate', 'Rate', amount: true, required: true),
              field(a, 'days', 'Payable days', required: true),
              if (basis == 'Monthly')
                select(a, 'Monthly proration', proration, [
                  ('Calendar days', 'Calendar days'),
                  ('Fixed 30 days', 'Fixed 30 days'),
                ], (v) => proration = v),
              field(a, 'allowance', 'Allowances / bonus', amount: true),
              field(a, 'deduction', 'Deductions', amount: true),
              field(a, 'deductionReason', 'Deduction reason'),
            ],
            if (widget.type == 'daily_sales') ...[
              for (final item in [
                ('cash', 'Cash sales'),
                ('bank', 'Bank sales'),
                ('credit', 'Named customer credit'),
                ('returns', 'Customer returns'),
                ('refundCash', 'Cash refund now'),
                ('refundBank', 'Bank refund now'),
                ('reduction', 'Customer debt reduction'),
                ('retained', 'Retained customer credit'),
              ])
                field(a, item.$1, item.$2, amount: true),
            ],
            if (widget.type == 'daily_sales') ...[
              for (final row in creditRows)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: row['party'],
                        isExpanded: true,
                        items: [
                          for (final person in people)
                            DropdownMenuItem(
                              value: person['id'] as String,
                              child: Text(person['name']),
                            ),
                        ],
                        onChanged: (v) => row['party'] = v,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        initialValue: row['text'],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(prefixText: 'Rs '),
                        onChanged: (v) => row['text'] = v,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => creditRows.remove(row)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              TextButton.icon(
                onPressed: people.isEmpty
                    ? null
                    : () => setState(
                        () => creditRows.add({
                          'party': people.first['id'],
                          'text': '',
                        }),
                      ),
                icon: const Icon(Icons.add),
                label: Text(a.tr('Named customer credit')),
              ),
            ],
            if (widget.type == 'expense')
              select(a, 'Category', category, [
                for (final s in expenseCategories) (s, s),
              ], (v) => category = v),
            const SizedBox(height: 14),
            field(a, 'notes', 'Reference / notes (optional)'),
            TextButton.icon(
              onPressed: () async {
                try {
                  await a.saveDraft(buildEntry(a));
                  if (c.mounted) toast(c, a.tr('Draft saved locally'));
                } catch (e) {
                  if (c.mounted) toast(c, e.toString());
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: Text(a.tr('Save local draft')),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final a = ref.watch(appProvider);
    return Frame(
      title: 'Offline drafts',
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          const SizedBox(height: 15),
          if (a.drafts.isEmpty) Text(a.tr('No entries yet')),
          for (final d in a.drafts)
            Card(
              child: ListTile(
                title: Text(a.typeLabel(d['type'])),
                subtitle: Text(
                  '${a.tr(d['syncStatus'] ?? 'Draft saved locally')}\n${d['rejection'] ?? ''}',
                ),
                onTap: () => c.push('/entry/${d['type']}', extra: d),
                trailing: IconButton(
                  tooltip: a.tr('Delete draft'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => a.discardDraft(d['id']),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CloseScreen extends ConsumerStatefulWidget {
  const CloseScreen({super.key});
  @override
  ConsumerState<CloseScreen> createState() => _CloseState();
}

class _CloseState extends ConsumerState<CloseScreen> {
  final counted = TextEditingController(), reason = TextEditingController();
  @override
  void dispose() {
    counted.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider);
    return Frame(
      title: 'Daily close',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(dateLabel(today())),
          pair(
            a.tr('Expected cash'),
            money(a.balance('money:cash')),
            bold: true,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: counted,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: a.tr('Counted cash')),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: reason,
            decoration: InputDecoration(
              labelText: a.tr('Difference explanation'),
            ),
          ),
          const SizedBox(height: 25),
          FilledButton(
            onPressed: () => perform(
              c,
              () => a.closeDay(today(), paisa(counted.text), reason.text),
            ),
            child: Text(a.tr('Close day')),
          ),
          for (final day in (a.state['closed'] as Json).entries)
            ListTile(
              title: Text(day.key),
              subtitle: Text(
                '${a.tr('Counted cash')}: ${money(day.value['counted'])}\n${day.value['reason']}',
              ),
            ),
        ],
      ),
    );
  }
}

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final a = ref.watch(appProvider);
    return Frame(
      title: 'More',
      tab: 3,
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          Tile(
            color: a.dark ? null : pale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                big(a.settings['name'] ?? '', size: 23),
                Text(
                  a.live
                      ? '${a.storeId} · ${a.member['role']}'
                      : '${a.tr('Demo mode')} · ${a.tr('Local synthetic data')}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            title: Text(a.tr('Dark mode')),
            value: a.dark,
            onChanged: (_) => a.toggleDark(),
          ),
          SwitchListTile(
            title: Text(a.tr('Language')),
            subtitle: const Text('English / اردو'),
            value: a.ur,
            onChanged: (_) => a.toggleLanguage(),
          ),
          if (a.owner)
            ListTile(
              leading: const Icon(Icons.storefront),
              title: Text(a.tr('Pharmacy name')),
              subtitle: Text(a.settings['name'] ?? ''),
              onTap: () async {
                final s = await inputDialog(
                  c,
                  a.tr('Pharmacy name'),
                  value: a.settings['name'],
                );
                if (s != null && s.isNotEmpty && c.mounted) {
                  await perform(
                    c,
                    () => a.saveSettings({...a.settings, 'name': s}),
                  );
                }
              },
            ),
          if (a.owner)
            ListTile(
              leading: const Icon(Icons.volunteer_activism),
              title: Text(a.tr('Annual zakat target')),
              onTap: () async {
                final s = await inputDialog(c, a.tr('Annual zakat target'));
                if (s != null && c.mounted) {
                  await perform(
                    c,
                    () => a.saveSettings({
                      ...a.settings,
                      'zakatTarget': paisa(s),
                    }),
                  );
                }
              },
            ),
          if (a.owner)
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text(a.tr('Payment account')),
              subtitle: Text((a.state['accounts'] as List).join(', ')),
              onTap: () async {
                final s = await inputDialog(c, a.tr('Payment account'));
                if (s != null &&
                    RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s) &&
                    c.mounted) {
                  await perform(
                    c,
                    () => a.saveSettings({
                      ...a.settings,
                      'accounts': <String>{
                        ...List<String>.from(a.state['accounts']),
                        s,
                      }.toList(),
                    }),
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.recycling),
            title: Text(a.tr('Recycle bin')),
            onTap: () => c.push('/recycle-bin'),
          ),
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: Text(a.tr('Offline drafts')),
            trailing: Text('${a.drafts.length}'),
            onTap: () => c.push('/drafts'),
          ),
          if (a.canPost('cashbook'))
            ListTile(
              leading: const Icon(Icons.lock_clock),
              title: Text(a.tr('Daily close')),
              onTap: () => c.push('/close'),
            ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(a.tr('Audit history')),
            onTap: () => c.go('/reports'),
          ),
          if (a.live && a.owner)
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: Text(a.tr('User access')),
              onTap: () => memberDialog(c, a),
            ),
          const Divider(),
          if (a.owner)
            ListTile(
              leading: const Icon(Icons.pie_chart),
              title: Text(a.tr('Owners & shares')),
              onTap: () => c.push('/owners'),
            ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: Text(a.tr('PIN & fingerprint')),
            onTap: () async {
              final lock = ref.read(appLockProvider);
              if (!lock.enabled) {
                if (!a.live) await a.prefs.setBool('demo-lock-enabled', true);
                await lock.bind(
                  a.live ? FirebaseAuth.instance.currentUser!.uid : 'demo',
                );
              } else if (c.mounted) {
                c.push('/security');
              }
            },
          ),
          if (ref.watch(appLockProvider).enabled)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(a.tr('Lock app')),
              onTap: () => ref.read(appLockProvider).lock(),
            ),
          if (a.live)
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(a.tr('Sign out')),
              onTap: () async {
                ref.read(appLockProvider).clearSession();
                await a.signOut();
              },
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

Future<void> memberDialog(BuildContext c, AppStore a) async {
  final uid = TextEditingController(), permissions = TextEditingController();
  String role = 'staff';
  bool active = true;
  await showDialog(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(a.tr('User access')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: uid,
                decoration: InputDecoration(labelText: a.tr('User UID')),
              ),
              DropdownButton<String>(
                value: role,
                isExpanded: true,
                items: [
                  for (final s in ['staff', 'manager', 'owner'])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (s) => set(() => role = s!),
              ),
              TextField(
                controller: permissions,
                decoration: InputDecoration(
                  labelText: a.tr('Permissions'),
                  hintText: 'suppliers:read,suppliers:post,cashbook:read',
                ),
              ),
              SwitchListTile(
                title: Text(a.tr('Active')),
                value: active,
                onChanged: (v) => set(() => active = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(a.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => perform(c, () async {
              await a.call('setMember', {
                'uid': uid.text.trim(),
                'role': role,
                'active': active,
                'permissions': permissions.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
            }),
            child: Text(a.tr('Save')),
          ),
        ],
      ),
    ),
  );
}

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onSignedIn;
  final Future<String> Function(String email, String password)? authenticate;
  const LoginScreen({super.key, this.onSignedIn, this.authenticate});
  @override
  ConsumerState<LoginScreen> createState() => _LoginState();
}

class _LoginState extends ConsumerState<LoginScreen> {
  final email = TextEditingController(text: 'mudakkirafridi@gmail.com'),
      password = TextEditingController();
  bool loading = false, showPassword = false;
  int inputSession = 0;
  final emailEditing = CredentialEditingFormatter(),
      passwordEditing = CredentialEditingFormatter();
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (loading) return;
    // The lock notification can replace this page while authentication finishes.
    // Capture dependencies/navigation before awaiting; never read a disposed ref.
    final a = ref.read(appProvider), lock = ref.read(appLockProvider);
    final route = GoRouter.maybeOf(context);
    final goHome = widget.onSignedIn ?? () => route?.go('/');
    final authenticate = widget.authenticate;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uid = authenticate != null
          ? await authenticate(email.text.trim(), password.text)
          : (await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: email.text.trim(),
              password: password.text,
            )).user!.uid;
      if (mounted) password.clear();
      await lock.resetAfterPasswordLogin(uid);
      await a.connect(
        a.prefs.getString('last-store-$uid') ??
            const String.fromEnvironment(
              'STORE_ID',
              defaultValue: 'family-pharmacy',
            ),
        refreshNow: false,
      );
      unawaited(a.refresh());
      goHome();
    } catch (e) {
      // Data/secure-storage/network errors are not an explicit sign-out.
      if (mounted) {
        password.value = TextEditingValue.empty;
        email.value = email.value.copyWith(
          composing: TextRange.empty,
          selection: TextSelection.collapsed(offset: email.text.length),
        );
        TextInput.finishAutofillContext(shouldSave: false);
        setState(() {
          inputSession++;
          error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = ref.watch(appProvider),
        configured = widget.authenticate != null || Firebase.apps.isNotEmpty;
    return AppBackScope(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(25),
                children: [
                  const Icon(Icons.local_pharmacy, color: blue, size: 65),
                  const SizedBox(height: 18),
                  Text(
                    a.tr('Pharmacy Hisab'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 18),
                  KeyedSubtree(
                    key: ValueKey('login-inputs-$inputSession'),
                    child: Column(
                      children: [
                        TextField(
                          key: const Key('login-email'),
                          inputFormatters: [emailEditing],
                          controller: email,
                          readOnly: loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: null,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          textCapitalization: TextCapitalization.none,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          decoration: InputDecoration(labelText: a.tr('Email')),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const Key('login-password'),
                          inputFormatters: [passwordEditing],
                          controller: password,
                          readOnly: loading,
                          obscureText: !showPassword,
                          autofillHints: null,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          onSubmitted: (_) {
                            if (configured && !loading) signIn();
                          },
                          decoration: InputDecoration(
                            labelText: a.tr('Password'),
                            suffixIcon: IconButton(
                              tooltip: showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: loading
                                  ? null
                                  : () => setState(
                                      () => showPassword = !showPassword,
                                    ),
                              icon: Icon(
                                showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        error!,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 25),
                  FilledButton(
                    onPressed: configured && !loading ? signIn : null,
                    child: Text(loading ? 'Please wait...' : a.tr('Sign in')),
                  ),
                  const SizedBox(height: 18),
                  if (!configured)
                    TextButton(
                      onPressed: () => c.go('/'),
                      child: Text(a.tr('Demo mode')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Map<String, int> aging(AppStore a, String asOf, String module) {
  final result = {'Current': 0, '1–30': 0, '31–60': 0, '61–90': 0, '90+': 0};
  final obligations = <String, Json>{};
  final customerLots = <String, List<Json>>{};
  final credits = <String, int>{};
  final history =
      a.entries
          .where((e) => (e['date'] as String).compareTo(asOf) <= 0)
          .toList()
        ..sort((x, y) {
          final d = (x['date'] as String).compareTo(y['date']);
          return d != 0
              ? d
              : a.entries.indexOf(y).compareTo(a.entries.indexOf(x));
        });
  for (final e in history) {
    final t = a.ledger.types[e['type']];
    if (t?['obligation'] == true) {
      obligations[e['id']] = {
        'remaining': e['amount'],
        'module': e['module'],
        'due': e['due'] ?? e['date'],
      };
    }
    for (final al in e['allocations'] ?? []) {
      if (obligations[al['id']] != null) {
        obligations[al['id']]!['remaining'] -= al['amount'];
      }
    }
    if (e['type'] == 'reversal') {
      final original = a.entries
          .where((x) => x['id'] == e['reference'])
          .firstOrNull;
      if (original != null) {
        obligations.remove(original['id']);
        for (final al in original['allocations'] ?? []) {
          if (obligations[al['id']] != null) {
            obligations[al['id']]!['remaining'] += al['amount'];
          }
        }
      }
    }
    for (final effect in (e['effects'] as Json).entries.where(
      (x) => x.key.startsWith('customer:'),
    )) {
      var amount = effect.value as int;
      final lots = customerLots.putIfAbsent(effect.key, () => []);
      if (amount > 0) {
        final available = credits[effect.key] ?? 0;
        final use = min(amount, available);
        amount -= use;
        credits[effect.key] = available - use;
        if (amount > 0) {
          lots.add({
            'remaining': amount,
            'module': 'customers',
            'due': e['due'] ?? e['date'],
          });
        }
      } else {
        var remaining = -amount;
        for (final lot in lots) {
          final use = min(remaining, lot['remaining'] as int);
          lot['remaining'] -= use;
          remaining -= use;
        }
        credits[effect.key] = (credits[effect.key] ?? 0) + remaining;
      }
    }
  }
  for (final b in [
    ...obligations.values,
    ...customerLots.values.expand((x) => x),
  ]) {
    if (module != 'all' && b['module'] != module) continue;
    if (b['remaining'] <= 0) continue;
    final days = DateTime.parse(
      asOf,
    ).difference(DateTime.parse(b['due'])).inDays;
    final key = days <= 0
        ? 'Current'
        : days <= 30
        ? '1–30'
        : days <= 60
        ? '31–60'
        : days <= 90
        ? '61–90'
        : '90+';
    result[key] = result[key]! + (b['remaining'] as int);
  }
  return result;
}
