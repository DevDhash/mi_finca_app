import 'package:flutter/services.dart';

/// Allows incomplete decimals while editing; rejects invalid edits as a whole.
class ExpenseAmountInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^[0-9]*([.,][0-9]{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}
