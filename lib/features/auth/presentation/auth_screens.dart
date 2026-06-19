import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/state/app_controller.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool create = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(appControllerProvider.notifier)
          .login(
            email: email.text,
            password: password.text,
            name: create ? name.text : null,
          );
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(
                    Icons.grass,
                    size: 42,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  create ? 'Crea tu cuenta' : 'Bienvenido a Mi Finca',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tus datos quedan guardados en este dispositivo, incluso sin señal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppColors.muted),
                ),
                const SizedBox(height: 28),
                if (create) ...[
                  TextField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Tu nombre'),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: password,
                  obscureText: true,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(labelText: 'Clave'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(create ? 'Crear cuenta' : 'Iniciar sesión'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          create = !create;
                          error = null;
                        }),
                  child: Text(
                    create ? 'Ya tengo una cuenta' : 'Crear una cuenta',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('o'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => ref
                            .read(appControllerProvider.notifier)
                            .enterDemo(),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Entrar con datos de demostración'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'MVP: el acceso es local y acepta cualquier correo con una clave de 4 caracteres. Sustituye MockRemoteGateway al integrar tu API.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class FarmSetupScreen extends ConsumerStatefulWidget {
  const FarmSetupScreen({super.key});
  @override
  ConsumerState<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

class _FarmSetupScreenState extends ConsumerState<FarmSetupScreen> {
  final name = TextEditingController();
  final location = TextEditingController();
  final paddock = TextEditingController();
  final key = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    location.dispose();
    paddock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Configura tu finca')),
    body: Form(
      key: key,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.landscape, size: 72, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Empecemos por lo esencial',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Podrás cambiar estos datos más adelante.',
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nombre de la finca'),
            validator: required,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: location,
            decoration: const InputDecoration(labelText: 'Ubicación'),
            validator: required,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: paddock,
            decoration: const InputDecoration(
              labelText: 'Nombre del primer potrero',
              hintText: 'Ejemplo: Potrero Norte',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              if (!key.currentState!.validate()) return;
              await ref
                  .read(appControllerProvider.notifier)
                  .configureFarm(name.text, location.text, paddock.text);
            },
            child: const Text('Guardar y comenzar'),
          ),
        ],
      ),
    ),
  );
  String? required(String? value) =>
      value == null || value.trim().isEmpty ? 'Este dato es necesario' : null;
}
