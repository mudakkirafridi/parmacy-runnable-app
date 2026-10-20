import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pages return to the previous route; only two consecutive Home backs exit Android.
class AppBackScope extends StatefulWidget {
  final Widget child;
  final VoidCallback? goHome;
  const AppBackScope({super.key, required this.child, this.goHome});

  @override
  State<AppBackScope> createState() => _AppBackScopeState();
}

class _AppBackScopeState extends State<AppBackScope> {
  DateTime? lastBack;

  void back() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.goHome != null) {
      lastBack = null;
      widget.goHome!();
      return;
    }
    final now = DateTime.now();
    if (lastBack != null &&
        now.difference(lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    lastBack = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Dobara Back dabayein to close'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: widget.child,
  );
}
