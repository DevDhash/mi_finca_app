# Ejecutar Mi Finca en Chrome

```sh
flutter pub get
flutter run -d chrome --web-port 7357
```

El puerto fijo mantiene el origen entre ejecuciones. También funciona
`flutter run -d chrome`, pero otro puerto usa otro almacenamiento.
La persistencia depende del origen y perfil del navegador. Flutter usa un perfil
 temporal de depuración que puede desaparecer al terminar la sesión.

Drift Flutter 0.2.8 abre SQLite WASM y elige OPFS o IndexedDB según el navegador.
En el Chrome probado usa `sharedIndexedDb`, sin cabeceras de aislamiento.
Se conservan el nombre `mi_finca_mvp`, schemaVersion 1, tablas y migraciones.
Las plataformas nativas mantienen su apertura con sqlite3_flutter_libs.
Riverpod conserva su ciclo de vida.

## Recursos versionados

- `web/drift_worker.js`: recurso oficial de Drift 2.31.0:
  https://github.com/simolus3/drift/releases/download/drift-2.31.0/drift_worker.js
- `web/sqlite3.wasm`: recurso oficial de sqlite3 2.9.4, versión del lockfile:
  https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm

La release de Drift 2.31.0 solo incluye el worker; el WASM se obtiene de SQLite.
Ambos se incluyen al compilar web. Revisarlos al actualizar Drift o sqlite3.
No se necesita sql.js ni cambiar dependencias.

SHA-256:

```text
sqlite3.wasm 922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117
drift_worker.js f0a9b87085f732fd7b6ee7eb34d3858c556f05d221eb1febfc443649cd365752
```

## Comprobación aislada

```sh
flutter run -d chrome --web-port 7358 -t tool/check_web_database.dart
```

Usa `mi_finca_web_smoke`, sin Supabase ni registros de negocio. Comprueba lectura,
escritura y reapertura, e informa cuántas ejecuciones anteriores persistieron.
Recargar la pestaña permite comprobar persistencia entre cargas.

## Publicación y límites

```sh
flutter build web --release
```

Servir `build/web` mediante HTTPS (localhost sirve para desarrollo), con
`sqlite3.wasm` como `application/wasm` y el worker como JavaScript. Las rutas
respetan el base href. COOP/COEP son opcionales para implementaciones más rápidas;
evaluar compatibilidad con autenticación antes de activarlas.

El navegador aplica cuotas y puede eliminar almacenamiento. Borrar datos del sitio
o usar incógnito afecta la persistencia. La base web es independiente de SQLite
en dispositivos móviles; Supabase sigue siendo la vía de sincronización.

Las fotos elegidas en web se conservan como data URI en SQLite local (hasta 6 MB
por foto); el publicador existente sube sus bytes a Storage. Base64 aumenta
aproximadamente un tercio el tamaño. La caché nativa de fotos en disco no se usa
en web: las fotos remotas usan URLs firmadas y requieren red. La cámara depende
de las capacidades y permisos del navegador.

No se realizó rediseño responsive. Las dos pantallas de error permiten scroll;
inicio, animales y potreros se revisaron en Chrome sin overflow visible.

## Archivos de esta intervención

- `lib/core/database/app_database.dart`: DriftWebOptions.
- `web/sqlite3.wasm`, `web/drift_worker.js`: runtime web.
- `lib/app/app.dart`: error de apertura desplazable.
- `lib/features/splash/presentation/screens/app_initialization_screen.dart`: error de inicialización desplazable.
- `lib/features/animals/presentation/screens/animal_screens.dart`: selección de fotos web.
- `lib/features/animals/presentation/widgets/local_animal_photo_avatar.dart`: visualización de fotos web.
- `lib/features/animals/presentation/viewmodels/animal_photo_cache_provider.dart`: omitir caché nativa en web.
- `lib/features/animals/data/services/animal_photo_sync.dart`: publicación desde data URI.
- `lib/features/auth/presentation/viewmodels/auth_view_model.dart`: limpieza de sesión compatible con web.
- `test/animal_photo_upload_test.dart`: regresión de persistencia y publicación de foto web.
- `test/startup_error_layout_test.dart`: regresión de overflow y acceso a Reintentar.
- `tool/check_web_database.dart`: comprobación real con base aislada.
- `docs/FLUTTER_WEB.md`: esta guía.
