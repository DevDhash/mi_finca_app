# Informe técnico de productización — Mi Finca

Fecha de revisión: 24 de agosto de 2026  
Alcance: revisión estática del repositorio Flutter, arquitectura, datos, sincronización, pantallas, configuración de plataformas y pruebas automatizadas.

## Resumen ejecutivo

Mi Finca tiene una base funcional sólida para un MVP: arquitectura por funcionalidades, Riverpod, almacenamiento local con Drift, Supabase Auth, diseño offline-first y flujos de animales, potreros, movimientos y gastos. El analizador de Flutter no encontró problemas y las 17 pruebas actuales pasan.

No se recomienda publicar todavía como producto estable. Los principales bloqueos no están en la sintaxis, sino en confiabilidad de datos, seguridad verificable, observabilidad, distribución y mantenibilidad. La prioridad máxima es convertir la sincronización de una cola de subida tolerante a fallos en un sistema de datos consistente, auditable y recuperable.

**Diagnóstico global:** 5.5/10 para operación productiva.  
**Recomendación:** realizar una fase de estabilización de 6–10 semanas antes de una liberación comercial amplia.

## Fortalezas actuales

- Separación por `features` y capas `presentation/domain/data`.
- Funcionamiento local primero, apropiado para conectividad rural irregular.
- Estado centralizado con Riverpod y modelos de dominio separados.
- Flujos principales ya implementados: autenticación, finca, animales, movimientos, potreros, rotación y gastos.
- Navegación principal sencilla y acciones rápidas orientadas a tareas de campo.
- Validaciones de formularios y estados vacíos presentes en varios flujos.
- Configuración de permisos de cámara/fotos en Android e iOS.
- `flutter analyze`: sin incidencias.
- `flutter test`: 17/17 pruebas aprobadas.

## Hallazgos críticos (P0)

### 1. Sincronización incompleta y sin diagnóstico

La cola local solo conserva `pending` y descarta silenciosamente la excepción de cada registro. No guarda número de intentos, error, siguiente reintento ni estado terminal. Además, `lastSync` se actualiza si subió al menos un registro, aunque otros hayan fallado. El usuario puede interpretar una sincronización parcial como exitosa.

Los repositorios solo descargan del servidor cuando la colección local está vacía. Una vez que existe cualquier dato local, no vuelven a incorporar cambios remotos. Esto impide una experiencia correcta con dos dispositivos y deja datos remotos nuevos o modificados fuera del teléfono.

Acciones:

1. Diseñar sincronización bidireccional incremental con cursor/versionado por servidor.
2. Añadir a la outbox: `operation`, `attempt_count`, `last_error`, `next_retry_at`, `status` e idempotency key.
3. Implementar tombstones para eliminaciones y una política explícita de conflictos.
4. Ejecutar reintentos con backoff al recuperar conexión y mediante tareas de fondo compatibles con cada plataforma.
5. Mostrar resultado completo: subidos, descargados, fallidos y conflictos; nunca presentar una sincronización parcial como total.
6. Probar cambios concurrentes, reinstalación, cierre forzado, sesión expirada y dos dispositivos.

### 2. Modelo local sin esquema tipado ni estrategia de migración

La base Drift funciona como almacén genérico JSON: una tabla `records`, sin tablas declarativas, claves foráneas, índices de dominio ni migraciones posteriores a la versión 1. Esto acelera el MVP, pero dificulta consultas, integridad, evolución y recuperación. El nombre físico aún es `mi_finca_mvp`.

Acciones:

- Crear tablas Drift tipadas para fincas, animales, potreros, movimientos, gastos y outbox.
- Añadir claves foráneas e índices (`user/farm`, código del animal, potrero, fechas y estado de sync).
- Versionar y probar cada migración con copias de bases antiguas.
- Usar transacciones para operaciones compuestas, especialmente mover animales y cambiar estados de potreros.
- Definir exportación/backup y recuperación local.

### 3. Aislamiento y seguridad de datos no demostrables desde el repositorio

El cliente filtra por `user_id`, pero el repositorio no contiene migraciones SQL, políticas RLS, constraints ni pruebas de autorización de Supabase. El filtrado del cliente no sustituye RLS. Tampoco existe un modelo claro de finca/equipo/roles; los datos pertenecen al usuario, lo que limita colaboración entre trabajadores.

Acciones:

- Versionar el esquema Supabase y todas las políticas RLS en el repositorio.
- Probar que un usuario no puede leer, insertar, actualizar ni borrar datos de otro.
- Introducir `farm_id`/tenant en todas las entidades y roles como propietario, administrador y trabajador.
- Validar constraints en servidor, no solo en formularios.
- Incorporar política de privacidad, términos, eliminación de cuenta y retención de datos.

La publishable key de Supabase puede estar en el cliente por diseño; su seguridad depende de RLS correcto. Conviene inyectarla por entorno para separar desarrollo, staging y producción.

### 4. Build de producción no preparado

Android conserva `com.example.mi_finca_app` y firma la variante release con la llave de debug. La metadata de paquete y web conserva textos de plantilla. Esto bloquea una publicación profesional y puede impedir actualizaciones seguras futuras.

Acciones:

- Definir identificadores definitivos Android/iOS y firma release segura.
- Crear flavors `dev`, `staging`, `prod`, cada uno con proyecto Supabase separado.
- Completar nombre, descripción, iconos, splash, URLs legales y metadata de tiendas.
- Configurar builds reproducibles y distribución interna antes de producción.

## Hallazgos altos (P1)

### Arquitectura y mantenibilidad

- Tres archivos de pantallas concentran aproximadamente 3,900 líneas; `main_screens.dart` supera 1,500. Dividir por pantalla y extraer componentes/controladores reduce riesgo de regresión.
- `go_router` está declarado, pero la navegación principal se maneja con `Navigator` e índice local. Adoptar un router único permite deep links, restauración de estado y pruebas consistentes.
- Los módulos completos se bloquean durante el arranque: un fallo de gastos o sync reemplaza toda la app por un error global. Cada sección debe degradarse de manera independiente.
- El splash impone cinco segundos aun si la app está lista. El inicio debe durar lo necesario y medir tiempo real de arranque.
- Varias excepciones se capturan con `catch (_)`. Crear errores tipados y una política uniforme de presentación/reintento.

### Observabilidad y operación

No se encontró integración de crash reporting, logging estructurado, analítica de producto, rendimiento ni health checks.

Implementar:

- Crash reporting con símbolos de release y datos personales depurados.
- Logs estructurados para sync, base local, autenticación y operaciones críticas.
- Métricas: éxito de sync, registros atascados, tiempo de arranque, errores por versión y conversión de flujos.
- Alertas y tablero operativo; procedimiento de incidentes y rollback.
- Feature flags y despliegue gradual.

### Pruebas y entrega continua

Las pruebas actuales cubren lógica de rotación y parte de repositorios, pero no pantallas ni integración completa.

Pirámide mínima recomendada:

- Unitarias: validaciones, formatters, reglas de rotación, conflictos y serialización.
- Repositorio/base: migraciones, transacciones, outbox, tombstones e idempotencia.
- Widgets: login, formularios, estados vacío/error/offline y accesibilidad.
- Integración: alta de finca, animal, movimiento, gasto, logout/login y dos dispositivos simulados.
- Golden tests para pantallas críticas en tamaños pequeños y grandes.
- CI por pull request: format, analyze, test, cobertura, build Android/iOS y escaneo de secretos/dependencias.

Objetivo inicial razonable: 70% de cobertura en dominio/datos y pruebas de integración de todos los caminos críticos; la cobertura numérica no debe sustituir escenarios de riesgo.

## Evaluación de pantallas y UX

La jerarquía actual es entendible: Inicio, Animales, Potreros y Más, con menú flotante para acciones frecuentes. La identidad visual es coherente y la app usa lenguaje cercano al productor. Para productizar:

### Navegación y tareas

- Corregir “Mover lote”: hoy la acción rápida solo cambia a la pestaña Animales; debe abrir directamente la selección de lote o explicar el siguiente paso.
- Hacer Gastos una sección de primer nivel si es una tarea frecuente; actualmente queda detrás de “Más”. Validar esto con analítica y entrevistas.
- Preservar navegación, filtros y scroll al volver de formularios o al reiniciar el proceso.
- Añadir búsqueda, filtros combinables y orden por código, nombre, potrero, estado y fecha.

### Estados y confianza

- Diferenciar claramente: guardado local, sincronizando, sincronizado, error y conflicto.
- Permitir ver y reintentar cada cambio fallido, con explicación accionable.
- Añadir confirmación y opción de deshacer para acciones destructivas o movimientos masivos.
- Implementar edición/eliminación/archivo de gastos y animales con historial; hoy los flujos CRUD están incompletos.
- Mostrar fecha/hora de actualización y origen del dato cuando haya varios dispositivos.

### Uso en campo y accesibilidad

- Verificar contraste WCAG, escalado de texto al 200%, lectores de pantalla, orden de foco y áreas táctiles de al menos 48 dp.
- Evitar depender solo del color para estado de potrero/sync.
- Probar en sol directo, modo oscuro opcional, guantes/manos húmedas y teléfonos Android de gama baja.
- Diseñar formularios tolerantes a interrupciones: borrador automático y recuperación después de cierre forzado.
- Comprimir imágenes, quitar metadata sensible y subirlas a Storage; `photo_path` local no sirve en otro dispositivo.
- Definir orientación soportada de forma coherente; iOS admite paisaje mientras la web declara retrato.

### Funcionalidad que falta para un producto ganadero

Validar con usuarios antes de construir, pero los candidatos de mayor valor son:

- Eventos sanitarios: vacunas, tratamientos, enfermedades y recordatorios.
- Reproducción: servicios, gestación, partos y genealogía.
- Pesajes e historial productivo, no solo peso actual.
- Inventario de insumos y costos por animal/lote/potrero.
- Exportación PDF/Excel, respaldo y compartir reportes.
- Alertas y calendario operativo.
- Multiusuario por finca con permisos y bitácora de auditoría.

## Roadmap recomendado

### Fase 0 — Decisiones de producto (1 semana)

- Definir usuario objetivo, plataformas oficiales, modelo de finca/equipo y métricas de éxito.
- Identificar 5–8 flujos críticos con productores reales.
- Congelar temporalmente funcionalidades no esenciales.

### Fase 1 — Fundaciones P0 (2–4 semanas)

- Esquema Supabase versionado + RLS probado + entornos separados.
- Base local tipada y migraciones.
- Sync bidireccional con outbox robusta, conflictos y observabilidad.
- Firma/identificadores release, manejo central de errores y crash reporting.

### Fase 2 — Calidad y UX (2–3 semanas)

- Modularizar archivos grandes y unificar navegación.
- Completar CRUD, estados de sync, búsqueda/filtros y recuperación de formularios.
- Accesibilidad, rendimiento en gama baja y carga/compresión de fotos.
- Suite de widgets/integración y CI obligatoria.

### Fase 3 — Piloto controlado (2–3 semanas)

- 10–20 fincas piloto, despliegue gradual y soporte directo.
- Medir retención, tareas completadas, fallos y tiempo hasta sincronizar.
- Corregir bloqueadores y ensayar restauración/rollback antes de publicación general.

## Criterios de salida de MVP

Mi Finca puede considerarse lista para producto cuando:

- Ningún dato confirmado se pierde tras cierre, reinstalación o cambio de dispositivo.
- La sincronización funciona y resuelve conflictos en pruebas reales de dos dispositivos.
- RLS y separación entre fincas están cubiertas por pruebas automatizadas.
- Builds release están firmados, reproducibles y pasan CI.
- Los flujos críticos tienen pruebas de integración y no presentan bloqueadores conocidos.
- Crash-free users es ≥99.5% durante el piloto y los fallos de sync son visibles/recuperables.
- Existen privacidad, eliminación/exportación de datos, soporte y procedimiento de incidentes.
- La accesibilidad y el rendimiento fueron verificados en la matriz de dispositivos objetivo.

## Evidencia revisada

- 8,329 líneas Dart en `lib`; 646 líneas en pruebas.
- Archivos de UI más grandes: `main_screens.dart` (1,548), `paddock_screens.dart` (1,370), `animal_screens.dart` (1,005) y `auth_screens.dart` (723).
- `flutter analyze`: sin problemas.
- `flutter test`: 17 pruebas aprobadas.
- Repositorio limpio al iniciar la auditoría.

## Limitaciones de esta auditoría

Esta revisión no incluyó acceso al panel de Supabase, esquema/RLS remoto, métricas de usuarios, pruebas manuales en dispositivos físicos, perfiles de rendimiento, revisión de tiendas ni entrevistas con productores. Esos elementos deben auditarse antes de declarar la app lista para producción.
