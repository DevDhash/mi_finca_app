# Mi Finca

MVP móvil offline-first para administrar animales, potreros, movimientos y gastos de una finca ganadera.

La app permite trabajar sin conexión, guardar datos localmente y sincronizarlos con Supabase cuando hay conectividad disponible.

## Funcionalidad principal

- Registro e inicio de sesión con Supabase Auth.
- Configuración inicial de finca.
- Dashboard con resumen de animales, potreros, gastos mensuales y cambios pendientes.
- Registro de animales en tres pasos.
- Foto persistente por animal en almacenamiento local del dispositivo.
- Detalle de animal.
- Movimiento de animales entre potreros.
- Historial de movimientos.
- Registro y estado de potreros.
- Rotación manual sugerida según días de descanso.
- Registro de gastos por categoría, monto, fecha y nota.
- Indicadores básicos de la finca.
- Pantalla de sincronización con:
  - cambios pendientes,
  - última sincronización,
  - estado de conexión,
  - modo offline manual para pruebas,
  - sincronización manual.

## Offline-first

La app está diseñada para funcionar en campo, incluso cuando no hay internet.

Cada operación importante se guarda primero en SQLite local mediante Drift. Luego la app intenta sincronizar el cambio con Supabase.

Flujo general:

```text
Usuario registra un dato
        ↓
SQLite local / Drift
        ↓
Se intenta subir a Supabase
        ↓
Si Supabase responde OK:
    pending = 0
Si falla internet o backend:
    pending = 1
        ↓
El cambio queda pendiente para reintento posterior