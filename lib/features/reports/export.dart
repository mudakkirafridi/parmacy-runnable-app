import '../../data/app_store.dart';
import '../../core/ledger.dart';
import 'report_document.dart';
export 'report_document.dart';

Future<void> exportReport(
  AppStore a,
  List<Json> entries,
  String from,
  String to,
  String title, {
  bool pdf = true,
}) => shareReport(
  buildReportData(
    a,
    entries,
    from,
    to,
    title,
    module: entries.firstOrNull?['module'] ?? 'all',
    party: entries.firstOrNull?['party'] ?? '',
    historySource: entries,
  ),
);

String accountLabel(AppStore a, String key) {
  final parts = key.split(':');
  final group =
      {
        'supplier': 'Supplier payable',
        'customer': 'Customer dues',
        'salary': 'Salary outstanding',
        'salaryAdvance': 'Advance / credit',
        'rent': 'Rent outstanding',
        'deposit': 'Security deposit',
        'loanAsset': 'Loan receivables',
        'loanDebt': 'Loan payables',
        'money': 'Cashbook',
        'expense': 'Expenses',
        'sales': 'Net daily sale',
        'netSales': 'Net daily sale',
        'salesControl': 'Imported Abuzar summary',
        'returns': 'Returns',
        'zakat': 'Zakat',
        'capital': 'Owner',
        'drawings': 'Owner withdrawal',
        'opening': 'Opening',
        'purchases': 'Supplier bill',
      }[parts.first] ??
      parts.first;
  return '${a.tr(group)}${parts.length > 1 ? ' Â· ${a.name(parts.sublist(1).join(':'))}' : ''}';
}
