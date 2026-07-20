import 'package:intl/intl.dart';

abstract final class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _decimalFormatter = NumberFormat.decimalPattern(
    'es_PE',
  );

  /// Muestra el monto completo hasta 9.999.
  /// Desde 10.000, lo abrevia en miles.
  ///
  /// Ejemplos:
  /// 950   -> S/ 950
  /// 1750  -> S/ 1.750
  /// 9999  -> S/ 9.999
  /// 10000 -> S/ 10 mil
  /// 10500 -> S/ 10,5 mil
  static String compactSoles(num amount) {
    if (amount.abs() < 10000) {
      return 'S/ ${_decimalFormatter.format(amount)}';
    }

    final amountInThousands = amount / 1000;

    final formattedThousands = amountInThousands % 1 == 0
        ? amountInThousands.toStringAsFixed(0)
        : amountInThousands.toStringAsFixed(1).replaceAll('.', ',');

    return 'S/ $formattedThousands mil';
  }

  /// Muestra siempre el monto completo.
  static String soles(num amount) {
    return 'S/ ${_decimalFormatter.format(amount)}';
  }
}
