import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_finca_app/features/expenses/domain/validators/expense_amount.dart';
import 'package:mi_finca_app/features/expenses/presentation/formatters/expense_amount_input_formatter.dart';

void main() {
  for (final entry in {
    '12': 12.0,
    '12.5': 12.5,
    '12.50': 12.5,
    '12,5': 12.5,
    '12,50': 12.5,
    '0.01': 0.01,
    '999.99': 999.99,
  }.entries) {
    test('accepts ${entry.key}', () {
      expect(parseExpenseAmount(entry.key), entry.value);
    });
  }
  for (final input in [
    '',
    '0',
    '0.00',
    '-1',
    'abc',
    'NaN',
    'Infinity',
    '12.999',
    '1,234.56',
    '1.234,56',
    '1,234',
    '1.234',
    'S/ 12',
    '1e2',
    '12.',
    ' 12 ',
    '9' * 400,
  ]) {
    test('rejects "$input"', () {
      expect(parseExpenseAmount(input), isNull);
    });
  }
  test('formatter preserves invalid edits without sanitizing pasted money', () {
    final formatter = ExpenseAmountInputFormatter();
    const oldValue = TextEditingValue(
      text: '12',
      selection: TextSelection.collapsed(offset: 2),
    );
    for (final text in ['1,234.56', '12.999', 'S/ 12', '-1', '12,3.4']) {
      expect(
        formatter.formatEditUpdate(oldValue, TextEditingValue(text: text)),
        oldValue,
      );
    }
    for (final text in ['', '12.', '12,', '12,50', '0.01']) {
      final edit = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      expect(formatter.formatEditUpdate(oldValue, edit), edit);
    }
  });
}
