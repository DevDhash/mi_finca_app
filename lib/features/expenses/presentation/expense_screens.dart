import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/domain/constants/expense_categories.dart';
import 'package:mi_finca_app/features/expenses/domain/validators/expense_amount.dart';
import 'package:mi_finca_app/features/expenses/presentation/formatters/expense_amount_input_formatter.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:uuid/uuid.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  DateTime _selectedMonth = _monthOf(DateTime.now());
  late final Future<void> _localeReady = initializeDateFormatting('es');

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expenseViewModelProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gastos de la finca',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ExpenseInfoCard(),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onPressed: () => openExpenseForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Registrar gasto'),
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<void>(
        future: _localeReady,
        builder: (context, locale) {
          if (locale.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return expenses.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('No se pudieron cargar los gastos.')),
            data: (items) {
              final months = _availableMonths(items);
              final selected = months.contains(_selectedMonth)
                  ? _selectedMonth
                  : _monthOf(DateTime.now());
              final visible =
                  items.where((e) => _monthOf(e.date) == selected).toList()
                    ..sort((a, b) => b.date.compareTo(a.date));
              final total = visible.fold<double>(0, (sum, e) => sum + e.amount);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _MonthSelector(
                    months: months,
                    selected: selected,
                    onChanged: (month) =>
                        setState(() => _selectedMonth = month),
                  ),
                  const SizedBox(height: 16),
                  _ExpenseMonthSummary(total: total, count: visible.length),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Gastos registrados',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${visible.length}',
                        key: const Key('expense-month-count'),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    _EmptyExpensesMonth(month: selected)
                  else
                    ...visible.map(
                      (expense) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ExpenseCard(expense: expense),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

List<DateTime> _availableMonths(List<Expense> expenses) => {
  _monthOf(DateTime.now()),
  ...expenses.map((expense) => _monthOf(expense.date)),
}.toList()..sort((a, b) => b.compareTo(a));

String _monthLabel(DateTime month) {
  final label = DateFormat('MMMM yyyy', 'es').format(month);
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

String _formatSoles(double amount) {
  final hasDecimals = amount % 1 != 0;

  final formatter = NumberFormat(hasDecimals ? '#,##0.00' : '#,##0', 'es');

  return 'S/ ${formatter.format(amount)}';
}

IconData _expenseIcon(String category) => switch (category) {
  'Alimento' => Icons.grass,
  'Medicina' => Icons.medication,
  'Mano de obra' => Icons.engineering,
  'Mantenimiento' => Icons.build,
  _ => Icons.receipt,
};

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.months,
    required this.selected,
    required this.onChanged,
  });
  final List<DateTime> months;
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<DateTime>(
    value: selected,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Mes',
      prefixIcon: Icon(Icons.calendar_month, color: AppColors.primaryDark),
    ),
    items: months
        .map(
          (month) =>
              DropdownMenuItem(value: month, child: Text(_monthLabel(month))),
        )
        .toList(),
    onChanged: (month) {
      if (month != null) onChanged(month);
    },
  );
}

class _ExpenseMonthSummary extends StatelessWidget {
  const _ExpenseMonthSummary({required this.total, required this.count});
  final double total;
  final int count;

  @override
  Widget build(BuildContext context) => _ExpensePanel(
    color: AppColors.primaryLight,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Total de gastos',
          style: TextStyle(color: AppColors.primaryDark),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatSoles(total),
                  key: const Key('expense-month-total'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.receipt_long,
              size: 20,
              color: AppColors.primaryDark,
            ),
            const SizedBox(width: 6),
            Text(
              '$count ${count == 1 ? 'gasto' : 'gastos'}',
              style: const TextStyle(color: AppColors.primaryDark),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ExpensePanel extends StatelessWidget {
  const _ExpensePanel({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});
  final Expense expense;
  @override
  Widget build(BuildContext context) => _ExpensePanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFEFE0CC),
          child: Icon(_expenseIcon(expense.category), color: AppColors.earth),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    expense.category,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formatSoles(expense.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${expense.date.day}/${expense.date.month}/${expense.date.year}${expense.note.isEmpty ? '' : ' · ${expense.note}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyExpensesMonth extends StatelessWidget {
  const _EmptyExpensesMonth({required this.month});
  final DateTime month;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const Icon(Icons.receipt_long, size: 44, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(
          'Sin gastos en ${_monthLabel(month)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cuando registres un gasto aparecerá aquí.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _ExpenseInfoCard extends StatelessWidget {
  const _ExpenseInfoCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F6EC),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(Icons.lightbulb_outline, color: AppColors.primaryDark),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registra todos los gastos de tu finca',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Lleva un mejor control de alimentación, medicina, mantenimiento y otros gastos.',
                style: TextStyle(color: AppColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> openExpenseForm(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
);

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});
  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final amount = TextEditingController();
  final note = TextEditingController();
  String category = expenseCategories.first;
  DateTime date = DateUtils.dateOnly(DateTime.now());
  bool _isSaving = false;
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: const Text(
        'Registrar gasto',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: expenseCategories
              .map(
                (v) => ChoiceChip(
                  label: Text(v),
                  selected: category == v,
                  onSelected: (_) => setState(() => category = v),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [ExpenseAmountInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Monto',
            prefixText: 'S/ ',
          ),
        ),
        const SizedBox(height: 14),
        ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Fecha'),
          subtitle: Text('${date.day}/${date.month}/${date.year}'),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              initialDate: date,
            );
            if (d != null && mounted) {
              setState(() => date = DateUtils.dateOnly(d));
            }
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nota opcional'),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          onPressed: _isSaving ? null : save,
          icon: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Guardando...' : 'Guardar gasto'),
        ),
      ],
    ),
  );
  Future<void> save() async {
    if (_isSaving) return;
    final value = parseExpenseAmount(amount.text);
    if (value == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ingresa un monto válido')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      await ref
          .read(expenseViewModelProvider.notifier)
          .save(
            Expense(
              id: const Uuid().v4(),
              category: category,
              amount: value,
              date: date,
              note: note.text.trim(),
              updatedAt: now,
            ),
          );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('✓ Gasto registrado')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo guardar el gasto: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el gasto. Inténtalo de nuevo.'),
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }
}
