import 'package:flutter/material.dart';

typedef AppInitializer = Future<void> Function();

class AppInitializationScreen extends StatefulWidget {
  const AppInitializationScreen({
    super.key,
    required this.onInitializationCompleted,
    this.initialize,
    this.minimumDisplayDuration = const Duration(seconds: 3),
  });

  /// Proceso opcional para inicializar servicios:
  /// Firebase, Remote Config, notificaciones, permisos, etc.
  final AppInitializer? initialize;

  /// Acción que se ejecutará cuando la inicialización termine.
  final VoidCallback onInitializationCompleted;

  /// Tiempo mínimo durante el cual se mostrará esta pantalla.
  final Duration minimumDisplayDuration;

  @override
  State<AppInitializationScreen> createState() =>
      _AppInitializationScreenState();
}

class _AppInitializationScreenState extends State<AppInitializationScreen> {
  Object? _initializationError;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (!_isInitializing) {
      setState(() {
        _isInitializing = true;
        _initializationError = null;
      });
    }

    try {
      final minimumDuration = Future<void>.delayed(
        widget.minimumDisplayDuration,
      );

      final initialization = widget.initialize?.call() ?? Future<void>.value();

      await Future.wait<void>([minimumDuration, initialization]);

      if (!mounted) return;

      widget.onInitializationCompleted();
    } catch (error, stackTrace) {
      debugPrint('Error inicializando la aplicación: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _initializationError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F0),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash_full_mi_finca.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(color: Color(0xFFFBF8F0));
            },
          ),
          if (!_isInitializing && _initializationError != null)
            _InitializationError(onRetry: _initializeApp),
        ],
      ),
    );
  }
}

class _InitializationError extends StatelessWidget {
  const _InitializationError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCCFBF8F0),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 56,
                      color: Color(0xFF2F6B3A),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No pudimos iniciar la aplicación',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Revisa tu conexión e inténtalo nuevamente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
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
