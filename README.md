# Mi Finca

MVP móvil offline-first para administrar animales, potreros, movimientos y gastos de una finca ganadera.

## Funcionalidad

- Acceso y creación de cuenta simulados, más un modo demostración.
- Configuración inicial de finca.
- Dashboard e indicadores básicos.
- Registro de animales en tres pasos, fotos persistentes, detalle y movimiento entre potreros.
- Registro y estado de potreros, con rotación manual sugerida.
- Gastos y resumen mensual.
- Persistencia SQLite local mediante Drift y cola de cambios pendientes.
- Sincronización simulada preparada para sustituirse por un backend.

## Integración futura con backend

La UI depende de `AppRepository` y `RemoteGateway`. Para integrar una API, implementa esos contratos y reemplaza sus providers en `lib/app/state/app_controller.dart`; las pantallas no necesitan cambios.

El login del MVP es local: acepta cualquier correo y una clave de al menos cuatro caracteres. `MockRemoteGateway` solo simula el envío de cambios.

## Ejecutar

```bash
flutter pub get
flutter run
```

Para cargar datos de ejemplo, usa **Entrar con datos de demostración** en la pantalla de acceso.
