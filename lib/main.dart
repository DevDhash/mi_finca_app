import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MiFincaApp(),
    ),
  );
}

class MiFincaApp extends StatelessWidget {
  const MiFincaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Finca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final options = [
      HomeOption(
        title: 'Ganado',
        subtitle: 'Registro de animales con foto',
        icon: Icons.pets,
        color: Colors.brown,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AnimalsScreen(),
            ),
          );
        },
      ),
      HomeOption(
        title: 'Potreros',
        subtitle: 'Pastizales, áreas y estado',
        icon: Icons.grass,
        color: Colors.green,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PaddocksScreen(),
            ),
          );
        },
      ),
      HomeOption(
        title: 'Rotación',
        subtitle: 'Control básico de ocupación y descanso',
        icon: Icons.sync_alt,
        color: Colors.blueGrey,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const GrazingScreen(),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Finca'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Panel principal',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gestiona tu ganado, potreros y rotación de pastizales.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ...options.map((option) => HomeOptionCard(option: option)),
        ],
      ),
    );
  }
}

class HomeOption {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  HomeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class HomeOptionCard extends StatelessWidget {
  final HomeOption option;

  const HomeOptionCard({
    super.key,
    required this.option,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: option.color.withValues(alpha: 0.15),
          child: Icon(
            option.icon,
            color: option.color,
          ),
        ),
        title: Text(
          option.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(option.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: option.onTap,
      ),
    );
  }
}

class AnimalsScreen extends StatelessWidget {
  const AnimalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Ganado',
      message: 'Aquí registraremos animales con foto, arete, raza y categoría.',
      icon: Icons.pets,
    );
  }
}

class PaddocksScreen extends StatelessWidget {
  const PaddocksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Potreros',
      message: 'Aquí registraremos potreros, área, tipo de pasto y estado.',
      icon: Icons.grass,
    );
  }
}

class GrazingScreen extends StatelessWidget {
  const GrazingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Rotación',
      message: 'Aquí controlaremos ingreso, salida y días de descanso del potrero.',
      icon: Icons.sync_alt,
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}