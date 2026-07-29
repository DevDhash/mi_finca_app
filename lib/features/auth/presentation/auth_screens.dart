import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_finca_app/app/theme/app_theme.dart';
import 'package:mi_finca_app/core/constants/app_images.dart';
import 'package:mi_finca_app/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:mi_finca_app/features/onboarding/presentation/viewmodels/onboarding_view_model.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();

  bool create = false;
  bool busy = false;
  bool obscurePassword = true;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final authNotifier = ref.read(authViewModelProvider.notifier);

      if (create) {
        await authNotifier.signUp(
          email: email.text.trim(),
          password: password.text,
          name: name.text.trim(),
        );
      } else {
        await authNotifier.login(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FormatException catch (exception) {
      if (!mounted) return;

      setState(() {
        error = exception.message;
      });

      _showError(exception.message);
    } catch (exception) {
      final message = _friendlyAuthMessage(exception);

      if (!mounted) return;

      setState(() {
        error = message;
      });

      _showError(message);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  void _toggleMode() {
    FocusScope.of(context).unfocus();

    _formKey.currentState?.reset();

    setState(() {
      create = !create;
      error = null;
      obscurePassword = true;
      password.clear();

      if (!create) {
        name.clear();
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _friendlyAuthMessage(Object? error) {
    final rawMessage = error.toString();
    final message = rawMessage.toLowerCase();

    if (message.contains('invalid login credentials') ||
        message.contains('invalid credentials') ||
        message.contains('correo o contraseña incorrectos')) {
      return 'Correo o contraseña incorrectos.';
    }

    if (message.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de iniciar sesión.';
    }

    if (message.contains('user already registered') ||
        message.contains('already registered')) {
      return 'Este correo ya está registrado. Inicia sesión.';
    }

    if (message.contains('socketexception') ||
        message.contains('clientexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection timed out') ||
        message.contains('connection refused')) {
      return 'No se pudo conectar con el servidor. Verifica tu internet e intenta nuevamente.';
    }

    if (message.contains('timeout')) {
      return 'El servidor tardó demasiado en responder. Intenta nuevamente.';
    }

    final cleanMessage = rawMessage
        .replaceFirst('Exception: ', '')
        .replaceFirst('AuthException(message: ', '')
        .replaceFirst(', statusCode: null, code: null)', '')
        .trim();

    if (cleanMessage.isEmpty) {
      return 'Ocurrió un error inesperado. Intenta nuevamente.';
    }

    return cleanMessage;
  }

  @override
  Widget build(BuildContext context) {
    final title = create ? 'Crea tu cuenta' : 'Bienvenido a Mi Finca';

    final subtitle = create
        ? 'Registra tu acceso para gestionar tu finca desde cualquier lugar.'
        : 'Ingresa con tu correo y contraseña para continuar.';

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.42, 0.72, 1.0],
              colors: [
                Colors.white,
                AppColors.primaryLight,
                AppColors.primary,
                AppColors.primaryDark,
              ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LogoHeader(title: title, subtitle: subtitle),
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: _AuthPanel(
                        create: create,
                        busy: busy,
                        error: error,
                        obscurePassword: obscurePassword,
                        name: name,
                        email: email,
                        password: password,
                        onSubmit: submit,
                        onTogglePassword: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: busy ? null : _toggleMode,
                      child: Text(
                        create
                            ? 'Ya tengo una cuenta'
                            : 'Crear una cuenta nueva',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Conecta · Protege · Gestiona',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoHeader extends StatelessWidget {
  const _LogoHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Transform.scale(
              scale: 2.8,
              child: Image.asset(
                AppImages.miFincaIcono,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.agriculture,
                  size: 52,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.primaryDark,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.primaryDark.withValues(alpha: 0.78),
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.create,
    required this.busy,
    required this.error,
    required this.obscurePassword,
    required this.name,
    required this.email,
    required this.password,
    required this.onSubmit,
    required this.onTogglePassword,
  });

  final bool create;
  final bool busy;
  final String? error;
  final bool obscurePassword;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController password;
  final VoidCallback onSubmit;
  final VoidCallback onTogglePassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          if (create) ...[
            TextFormField(
              key: const ValueKey('auth_name_field'),
              controller: name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: _inputDecoration(
                label: 'Nombre',
                icon: Icons.person_outline,
              ),
              validator: (value) {
                if (!create) return null;

                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa tu nombre.';
                }

                if (value.trim().length < 2) {
                  return 'Ingresa un nombre válido.';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            key: const ValueKey('auth_email_field'),
            controller: email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: _inputDecoration(
              label: 'Correo electrónico',
              icon: Icons.email_outlined,
            ),
            validator: (value) {
              final cleanValue = value?.trim() ?? '';

              if (cleanValue.isEmpty) {
                return 'Ingresa tu correo electrónico.';
              }

              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

              if (!emailRegex.hasMatch(cleanValue)) {
                return 'Ingresa un correo válido.';
              }

              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: ValueKey(
              create ? 'signup_password_field' : 'login_password_field',
            ),
            controller: password,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: create
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            onFieldSubmitted: (_) {
              if (!busy) {
                onSubmit();
              }
            },
            decoration:
                _inputDecoration(
                  label: 'Contraseña',
                  icon: Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    onPressed: busy ? null : onTogglePassword,
                    tooltip: obscurePassword
                        ? 'Mostrar contraseña'
                        : 'Ocultar contraseña',
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.primaryDark.withValues(alpha: 0.64),
                    ),
                  ),
                ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Ingresa tu contraseña.';
              }

              if (value.length < 6) {
                return 'La contraseña debe tener al menos 6 caracteres.';
              }

              return null;
            },
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.26),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.danger,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: busy ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primaryDark.withValues(
                  alpha: 0.55,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      create ? 'Crear cuenta' : 'Iniciar sesión',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.primaryLight.withValues(alpha: 0.34),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: TextStyle(
        color: AppColors.primaryDark.withValues(alpha: 0.72),
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.primaryDark.withValues(alpha: 0.72),
      errorStyle: const TextStyle(
        color: AppColors.danger,
        fontWeight: FontWeight.w600,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppColors.primaryDark.withValues(alpha: 0.18),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
    );
  }
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
  final restDays = TextEditingController(text: '30');
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    name.dispose();
    location.dispose();
    paddock.dispose();
    restDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  backgroundColor: const Color(0xFFFBF8F0),
  body: SafeArea(
    child: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Image.asset(
                AppImages.donFincaBanner,
                height: 150,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.agriculture,
                  size: 72,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '¡Configuremos tu finca!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
          
            const SizedBox(height: 24),
            TextFormField(
              controller: name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre de la finca',
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: location,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ubicación'),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: paddock,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre del primer potrero',
                hintText: 'Ejemplo: Potrero Norte',
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: restDays,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Descanso requerido del primer potrero',
                suffixText: 'días',
                helperText:
                    'Podrás cambiar este valor más adelante desde Potreros.',
                helperMaxLines: 2,
              ),
              validator: _positiveIntegerValidator,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  FocusScope.of(context).unfocus();

                  await ref
                      .read(onboardingViewModelProvider.notifier)
                      .configure(
                        name.text.trim(),
                        location.text.trim(),
                        paddock.text.trim(),
                        int.parse(restDays.text.trim()),
                      );
                },
                child: const Text(
                  'Guardar y comenzar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Este dato es necesario';
    }

    return null;
  }

  String? _positiveIntegerValidator(String? value) {
    final restDays = int.tryParse(value?.trim() ?? '');

    if (restDays == null || restDays <= 0) {
      return 'Ingresa un número entero mayor a cero';
    }

    return null;
  }
}