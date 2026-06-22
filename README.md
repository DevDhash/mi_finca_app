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

Cada feature contiene su contrato de repositorio, fuente local, implementación y ViewModel. Para integrar una API, agrega una fuente remota dentro de la feature y cambia únicamente su implementación de repositorio; las pantallas y casos de uso permanecen iguales.

## Arquitectura

El proyecto usa Feature First + Clean Architecture + MVVM:

- `domain/entities`: reglas y entidades de la feature.
- `domain/repositories`: contratos independientes de Drift o HTTP.
- `domain/usecases`: operaciones que coordinan reglas de negocio.
- `data/datasources`: acceso local y mocks remotos.
- `data/repositories`: implementaciones de los contratos de dominio.
- `presentation/viewmodels`: estado y acciones de cada feature con Riverpod.
- `presentation/screens`: vistas sin acceso directo a base de datos.

No existe un controlador ni repositorio global. La raíz solo compone los estados de sesión y módulos para mostrar splash, onboarding o navegación principal. La cola de sincronización escucha cambios del almacenamiento local sin acoplar los ViewModels entre features.

El login del MVP es local: acepta cualquier correo y una clave de al menos cuatro caracteres. `MockRemoteGateway` solo simula el envío de cambios.

## Ejecutar

```bash
flutter pub get
flutter run
```

Para cargar datos de ejemplo, usa **Entrar con datos de demostración** en la pantalla de acceso.
