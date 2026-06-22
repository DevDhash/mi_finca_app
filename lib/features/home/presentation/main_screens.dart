import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/widgets/common_widgets.dart';
import 'package:mi_finca_app/features/animals/presentation/screens/animal_screens.dart';
import 'package:mi_finca_app/features/animals/presentation/viewmodels/animal_view_model.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/expenses/presentation/expense_screens.dart';
import 'package:mi_finca_app/features/expenses/presentation/viewmodels/expense_view_model.dart';
import 'package:mi_finca_app/features/farm/presentation/viewmodels/farm_view_model.dart';
import 'package:mi_finca_app/features/paddocks/presentation/screens/paddock_screens.dart';
import 'package:mi_finca_app/features/paddocks/presentation/viewmodels/paddock_view_model.dart';
import 'package:mi_finca_app/features/sync/presentation/viewmodels/sync_view_model.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncViewModelProvider).requireValue;
    const pages = [
      DashboardScreen(),
      AnimalListScreen(),
      PaddockListScreen(),
      MoreScreen(),
    ];
    return Scaffold(
      body: Column(
        children: [
          ConnectivityBanner(state: sync),
          Expanded(
            child: IndexedStack(index: index, children: pages),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _quickActions(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: 'Animales',
          ),
          NavigationDestination(
            icon: Icon(Icons.grass_outlined),
            selectedIcon: Icon(Icons.grass),
            label: 'Potreros',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Más'),
        ],
      ),
    );
  }

  void _quickActions(BuildContext context) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Acciones rápidas',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Registrar animal'),
              onTap: () {
                Navigator.pop(context);
                openAnimalForm(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Mover un animal'),
              subtitle: const Text('Elige el animal desde su lista'),
              onTap: () {
                Navigator.pop(context);
                setState(() => index = 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text('Agregar potrero'),
              onTap: () {
                Navigator.pop(context);
                openPaddockForm(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Registrar gasto'),
              onTap: () {
                Navigator.pop(context);
                openExpenseForm(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authViewModelProvider).requireValue;
    final farm = ref.watch(farmViewModelProvider).requireValue;
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final monthlyTotal = ref.watch(monthlyExpenseTotalProvider);
    final sync = ref.watch(syncViewModelProvider).requireValue;
    final suggested =
        (paddocks.where((p) => p.status != 'En uso').toList()
              ..sort((a, b) => b.restDays.compareTo(a.restDays)))
            .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(farm?.name ?? 'Mi Finca'),
            Text(
              'Hola, ${session?.name ?? ''}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Resumen de la finca',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.pets,
                  value: '${animals.length}',
                  label: 'Animales',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Metric(
                  icon: Icons.grass,
                  value:
                      '${paddocks.where((p) => p.status == 'Disponible').length}/${paddocks.length}',
                  label: 'Potreros libres',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.receipt_long,
                  value: NumberFormat.compactCurrency(
                    locale: 'es_PE',
                    symbol: 'S/',
                  ).format(monthlyTotal),
                  label: 'Gastos del mes',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Metric(
                  icon: Icons.cloud_upload_outlined,
                  value: '${sync.pendingChanges}',
                  label: 'Cambios pendientes',
                ),
              ),
            ],
          ),
          if (suggested != null) ...[
            const SizedBox(height: 18),
            Card(
              color: const Color(0xFFFBEBD0),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const Icon(
                  Icons.lightbulb_outline,
                  color: AppColors.warning,
                ),
                title: Text(
                  '${suggested.name} puede estar listo para uso',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Lleva ${suggested.restDays} días de descanso.'),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Registrados recientemente',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (animals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Registra tu primer animal desde el botón +.'),
              ),
            )
          else
            ...animals
                .take(3)
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimalListCard(
                      animal: a,
                      paddockName: paddocks
                          .where((p) => p.id == a.paddockId)
                          .firstOrNull
                          ?.name,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnimalDetailScreen(animalId: a.id),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value, label;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          Text(label, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );
}

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Más')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _item(
          context,
          Icons.receipt_long,
          'Costos y bodega',
          'Gastos y resumen mensual',
          const ExpenseListScreen(),
        ),
        _item(
          context,
          Icons.insights,
          'Indicadores',
          'Una vista simple de tu finca',
          const IndicatorsScreen(),
        ),
        _item(
          context,
          Icons.cloud_sync,
          'Sincronización',
          'Conexión y cambios pendientes',
          const SyncScreen(),
        ),
        _item(
          context,
          Icons.person_outline,
          'Perfil y ajustes',
          'Datos de finca y sesión',
          const ProfileScreen(),
        ),
      ],
    ),
  );
  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(icon, color: AppColors.primaryDark),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      ),
    ),
  );
}

class IndicatorsScreen extends ConsumerWidget {
  const IndicatorsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(animalViewModelProvider).requireValue.animals;
    final paddocks = ref.watch(paddockViewModelProvider).requireValue;
    final monthlyTotal = ref.watch(monthlyExpenseTotalProvider);
    final sync = ref.watch(syncViewModelProvider).requireValue;
    final avg = animals.where((a) => a.weight != null).toList();
    final average = avg.isEmpty
        ? 0
        : avg.fold<double>(0, (s, a) => s + a.weight!) / avg.length;
    final values = [
      ('Animales', '${animals.length}', Icons.pets),
      (
        'Costos del mes',
        NumberFormat.compactCurrency(
          locale: 'es_PE',
          symbol: 'S/',
        ).format(monthlyTotal),
        Icons.payments,
      ),
      (
        'Potreros libres',
        '${paddocks.where((p) => p.status == 'Disponible').length}',
        Icons.grass,
      ),
      (
        'Animales enfermos',
        '${animals.where((a) => a.status == 'Enfermo').length}',
        Icons.health_and_safety,
      ),
      (
        'Peso promedio',
        '${average.toStringAsFixed(0)} kg',
        Icons.monitor_weight,
      ),
      ('Cambios pendientes', '${sync.pendingChanges}', Icons.cloud_upload),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Indicadores')),
      body: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: values
            .map((v) => _Metric(icon: v.$3, value: v.$2, label: v.$1))
            .toList(),
      ),
    );
  }
}

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(syncViewModelProvider).requireValue;
    final icon = !d.isOnline
        ? Icons.cloud_off
        : d.isSyncing
        ? Icons.cloud_sync
        : d.pendingChanges > 0
        ? Icons.cloud_upload
        : Icons.cloud_done;
    final title = !d.isOnline
        ? 'Sin conexión'
        : d.isSyncing
        ? 'Sincronizando cambios…'
        : d.pendingChanges > 0
        ? '${d.pendingChanges} cambios pendientes'
        : 'Todo sincronizado';
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Icon(
              icon,
              size: 90,
              color: d.pendingChanges > 0
                  ? AppColors.warning
                  : AppColors.primary,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              d.lastSync == null
                  ? 'Todavía no se realizó una sincronización.'
                  : 'Última sincronización: ${d.lastSync!.day}/${d.lastSync!.month} ${d.lastSync!.hour}:${d.lastSync!.minute.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Simular conexión'),
              subtitle: const Text(
                'Se reemplaza por connectivity_plus al integrar el backend.',
              ),
              value: d.isOnline,
              onChanged: ref.read(syncViewModelProvider.notifier).setOnline,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: !d.isOnline || d.pendingChanges == 0 || d.isSyncing
                  ? null
                  : ref.read(syncViewModelProvider.notifier).syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authViewModelProvider).requireValue;
    final farm = ref.watch(farmViewModelProvider).requireValue;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil y ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
          const SizedBox(height: 14),
          Text(
            session?.name ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(session?.email ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.landscape),
              title: Text(farm?.name ?? ''),
              subtitle: Text(farm?.location ?? ''),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => ref.read(authViewModelProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
