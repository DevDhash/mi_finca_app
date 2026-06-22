import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/expenses/domain/entities/expense.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:uuid/uuid.dart';

class ExpenseListScreen extends ConsumerWidget {
  const ExpenseListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expenseViewModelProvider).requireValue;
    final monthlyTotal = ref.watch(monthlyExpenseTotalProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Costos y bodega'),
        actions: [
          IconButton(
            onPressed: () => openExpenseForm(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.primaryLight,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Este mes',
                    style: TextStyle(color: AppColors.primaryDark),
                  ),
                  Text(
                    NumberFormat.currency(
                      locale: 'es_PE',
                      symbol: 'S/ ',
                    ).format(monthlyTotal),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (expenses.isEmpty)
            SizedBox(
              height: 420,
              child: EmptyState(
                icon: Icons.receipt_long,
                message: 'Sin gastos registrados este mes.',
                actionLabel: 'Registrar gasto',
                onAction: () => openExpenseForm(context),
              ),
            )
          else
            ...expenses.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFEFE0CC),
                      child: Icon(_icon(e.category), color: AppColors.earth),
                    ),
                    title: Text(
                      e.category,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${e.date.day}/${e.date.month}/${e.date.year}${e.note.isEmpty ? '' : ' · ${e.note}'}',
                    ),
                    trailing: Text(
                      NumberFormat.currency(
                        locale: 'es_PE',
                        symbol: 'S/ ',
                      ).format(e.amount),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _icon(String c) => switch (c) {
    'Alimento' => Icons.grass,
    'Medicina' => Icons.medication,
    'Mano de obra' => Icons.engineering,
    'Mantenimiento' => Icons.build,
    _ => Icons.receipt,
  };
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
  String category = 'Alimento';
  DateTime date = DateTime.now();
  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Registrar gasto')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              ['Alimento', 'Medicina', 'Mano de obra', 'Mantenimiento', 'Otros']
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
            if (d != null) setState(() => date = d);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nota opcional'),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: save, child: const Text('Guardar gasto')),
      ],
    ),
  );
  Future<void> save() async {
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ingresa un monto válido')));
      return;
    }
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
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✓ Gasto registrado')));
    }
  }
}
