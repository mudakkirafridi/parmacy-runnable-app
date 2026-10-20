import 'package:flutter/services.dart';

/// Keep the IME composing range intact. Rewriting it during typing causes
/// Samsung/Gboard to restore an older buffer after backspace.
class CredentialEditingFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue;
}
