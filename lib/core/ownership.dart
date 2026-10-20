import 'ledger.dart';

List<Json> defaultOwners() => [
  {'id': 'owner-1', 'name': 'Owner 1', 'shareBps': 4000},
  {'id': 'owner-2', 'name': 'Owner 2', 'shareBps': 4000},
  {'id': 'owner-3', 'name': 'Owner 3', 'shareBps': 2000},
];
void validateOwners(List<Json> owners) {
  if (owners.isEmpty || owners.length > 10) {
    throw StateError('Add at least one owner');
  }
  final ids = <String>{};
  var total = 0;
  for (final o in owners) {
    if ((o['name'] as String? ?? '').trim().isEmpty) {
      throw StateError('Owner name required');
    }
    if (!ids.add(o['id'] as String)) throw StateError('Duplicate owner');
    final share = o['shareBps'];
    if (share is! int || share <= 0 || share > 10000) {
      throw StateError(
        'Each share must be greater than 0 and no more than 100%',
      );
    }
    total += share;
  }
  if (total != 10000) throw StateError('Owner shares must total 100%');
}

int parseOwnerShare(String value) {
  final text = value.trim().replaceAll('%', '').trim();
  if (!RegExp(r'^\d+(?:\.\d{0,2})?$').hasMatch(text)) {
    throw const FormatException('Enter a share such as 45 or 45.0');
  }
  return paisa(text.endsWith('.') ? '${text}0' : text);
}
