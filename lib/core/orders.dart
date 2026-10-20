import 'ledger.dart';

void validateOrder(Json order, {Json? previous}) {
  if ((order['party'] ?? '').isEmpty || (order['staffId'] ?? '').isEmpty) {
    throw StateError('Select company and enter name');
  }
  if ((order['staffName'] ?? '').trim().isEmpty ||
      (order['staffName'] ?? '').length > 120) {
    throw StateError('Enter a valid name');
  }
  final amount = order['amount'];
  if (amount is! int || amount <= 0 || amount > 900000000000) {
    throw StateError('Enter a positive order amount');
  }
  final date = DateTime.tryParse('${order['date']}');
  if (date == null ||
      date.toIso8601String().substring(0, 10) != order['date'] ||
      order['date'].compareTo(today()) > 0) {
    throw StateError('Choose a valid order date');
  }
  if ((order['notes'] ?? '').length > 2000) {
    throw StateError('Keep notes under 2000 characters');
  }
  if (previous != null && previous['status'] != 'open') {
    throw StateError(
      'Received/cancelled orders cannot be edited. Reverse the linked bill first.',
    );
  }
  if ((previous == null && order['status'] != 'open') ||
      !['open', 'cancelled'].contains(order['status'])) {
    throw StateError('Invalid order status');
  }
}

void validateOrderBill(Json? order, Json bill) {
  if (order == null ||
      order['status'] != 'open' ||
      order['party'] != bill['party'] ||
      bill['type'] != 'supplier_bill') {
    throw StateError(
      'Order is already received, cancelled or belongs to another company',
    );
  }
}
