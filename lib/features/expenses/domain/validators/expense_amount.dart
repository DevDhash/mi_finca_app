/// Parses a positive amount without currency symbols or thousands separators.
double? parseExpenseAmount(String input) {
  if (!RegExp(r'^[0-9]+([.,][0-9]{1,2})?$').hasMatch(input)) return null;
  final value = double.tryParse(input.replaceAll(',', '.'));
  return value != null && value.isFinite && value > 0 ? value : null;
}
