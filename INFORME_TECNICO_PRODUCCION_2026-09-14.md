# Informe técnico de preparación para producción — Mi Finca

Fecha: 14 de septiembre de 2026  
Resultado: **NO-GO para publicación pública; apta para piloto interno controlado**.

## Resumen ejecutivo

Mi Finca tiene una base funcional y arquitectónica suficientemente buena para continuar un piloto: Flutter/Riverpod, separación por funcionalidades, persistencia offline, outbox central, autenticación Supabase y transacción local para movimientos de animales y potreros. El análisis estático pasa y Android genera un APK release.

Todavía no debe publicarse como producto estable. La evaluación actual es **6/10 en preparación productiva**. Los bloqueadores principales son la configuración de distribución, la suite de pruebas en rojo, la sincronización incompleta, la falta de infraestructura versionada de Supabase/RLS y la ausencia de observabilidad operativa.

## Evidencia ejecutada

- `flutter analyze`: aprobado, sin incidencias.
- `flutter build apk --release`: aprobado; APK generado de 58.8 MB.
- `flutter test`: falló; 5 pruebas de widgets de gastos no pasan.
- Código Dart en `lib`: aproximadamente 9,317 líneas.
- Pruebas: aproximadamente 1,165 líneas.
- Estado del repositorio al auditar: cambios locales sin confirmar en pantallas de gastos/inicio y un test nuevo de gastos. No se alteraron esos cambios durante esta auditoría.

## Bloqueadores P0

### 1. Build release firmado con credenciales de debug

Android usa todavía:

- `applicationId = com.example.mi_finca_app`.
- `signingConfig = signingConfigs.getByName("debug")` para release.

iOS conserva `com.example.miFincaApp`. Aunque el APK compila, **no es un artefacto de producción válido**. Antes de publicar se deben definir identificadores definitivos, keystore de producción protegido, configuración de firma iOS y custodia/backup de credenciales.

### 2. Suite automatizada en rojo

Fallan cinco pruebas:

- Dos escenarios de `expense_form_test.dart` no encuentran el control esperado al abrir el formulario.
- Tres escenarios de `expense_list_test.dart` no encuentran totales con el formato monetario esperado.

Los fallos se reproducen ejecutando únicamente los tests de gastos, por lo que no son interferencia de la compilación paralela. Los cambios locales actuales de la pantalla de gastos y las expectativas de pruebas no están alineados. Debe determinarse si son regresiones o expectativas obsoletas, y dejar toda la suite verde antes de crear una versión candidata.

### 3. Seguridad backend no auditable/versionada

El repositorio no contiene migraciones SQL, constraints, políticas RLS ni pruebas de aislamiento de Supabase. El cliente filtra por `user_id`, pero eso no protege datos si RLS está ausente o mal configurado.

Antes de producción:

- Versionar esquema, migraciones, RLS, Storage policies e índices.
- Probar lectura/escritura cruzada entre dos usuarios.
- Separar proyectos/credenciales de desarrollo, staging y producción.
- Revisar eliminación de cuenta, exportación y retención de datos.

### 4. Sincronización todavía no garantiza consistencia multidispositivo

La outbox sube registros pendientes uno por uno y captura errores sin registrar causa. Los repositorios descargan datos remotos principalmente cuando la colección local está vacía; no existe pull incremental continuo, resolución de conflictos ni tombstones completos verificables.

Riesgos:

- Cambios de otro teléfono pueden no llegar a un dispositivo con datos locales.
- Una sincronización parcialmente exitosa puede actualizar `lastSync`.
- No hay diagnóstico por registro, intentos, backoff ni estado de conflicto.
- La transacción de movimiento es atómica localmente, pero sus registros se suben separadamente a Supabase.

Se necesita sincronización bidireccional incremental, política de conflictos, reintentos observables e idempotencia antes de admitir uso serio en varios dispositivos.

## Riesgos P1

### Base de datos y migraciones

La base local continúa en `schemaVersion = 1`, con tabla genérica JSON `records`, sin tablas Drift declarativas, relaciones ni una estrategia de upgrade probada. Esto funciona para piloto, pero aumenta el riesgo al cambiar modelos después de publicar. Una actualización de app nunca debe perder datos existentes.

### Observabilidad

No se encontraron crash reporting, logs estructurados, métricas de sincronización, analítica operativa ni alertas. En producción no habría forma suficiente de conocer:

- Cuántos usuarios sufren fallos.
- Qué registros quedan pendientes.
- Qué versión introdujo una regresión.
- Cuánto tarda la app en iniciar o sincronizar.

### Fotografías

Los animales guardan una ruta local de fotografía. Esa ruta no es portable a otro teléfono y no constituye backup. Se requiere compresión, subida a Supabase Storage, políticas de acceso y caché local.

### Arranque y resiliencia

La app mantiene un splash fijo de cinco segundos y un fallo de carga de cualquier módulo puede bloquear el acceso general. Para campo, animales/potreros deberían seguir disponibles localmente aunque gastos o sincronización fallen.

### Configuración y metadata

`pubspec.yaml`, web manifest y títulos conservan descripciones de plantilla. Falta completar metadata de tiendas, versión real, política de privacidad, canal de soporte, screenshots, clasificación y textos legales.

### CI/CD y calidad

No se encontró pipeline versionado para ejecutar análisis, pruebas y builds por pull request. Tampoco hay pruebas de integración end-to-end, actualización de base instalada, sesión expirada, dos dispositivos, restauración, rendimiento en Android de gama baja o pérdida de conectividad durante una operación.

## Mejoras confirmadas desde la auditoría anterior

- La finca participa ahora en la outbox central.
- El movimiento de animales actualiza origen y destino.
- El movimiento local agrupa historial, animales y potreros en una transacción SQLite.
- Se fortalecieron reglas operativas de descanso/ disponibilidad de potreros.
- La suite creció de 17 a más de 50 casos ejecutados, aunque actualmente cinco fallan.
- Perfil y cierre de sesión tienen un flujo más completo.

## Matriz de decisión

| Área | Estado | Decisión |
|---|---|---|
| Análisis estático | Verde | Aprobado |
| Build Android | Amarillo | Compila, pero firma/ID no son productivos |
| Pruebas | Rojo | 5 fallos reproducibles |
| Persistencia offline | Amarillo | Funcional, migraciones insuficientes |
| Movimiento de ganado | Amarillo/verde | Consistente localmente; sync remoto no atómico |
| Seguridad Supabase | Rojo/no verificable | Faltan RLS/esquema versionados y pruebas |
| Sincronización multidispositivo | Rojo | Falta pull/conflictos/diagnóstico |
| Observabilidad | Rojo | Sin monitoreo de producción |
| Distribución y legal | Rojo | Firma, IDs, metadata y políticas pendientes |

## Plan mínimo para obtener un GO

### Semana 1: estabilización de release

1. Resolver los cinco tests de gastos y congelar cambios de UI para la candidata.
2. Configurar IDs definitivos, firma Android/iOS y secretos por entorno.
3. Añadir CI obligatorio: format, analyze, tests y build release.
4. Completar metadata, privacidad, soporte y eliminación de cuenta.

### Semanas 2–3: datos y seguridad

1. Versionar Supabase y probar RLS/Storage.
2. Implementar pull incremental, errores visibles y política de conflictos.
3. Diseñar y probar migración de base local.
4. Mover fotografías a Storage con caché offline.

### Semana 4: operación y piloto

1. Instalar crash reporting y métricas de sync/arranque.
2. Probar en dispositivos físicos de gama baja y conectividad intermitente.
3. Ejecutar piloto con 10–20 fincas, despliegue gradual y rollback ensayado.
4. Publicar solo si no hay pérdida de datos ni bloqueadores durante el piloto.

## Criterios obligatorios de salida

Dar **GO a producción pública** únicamente cuando:

- El 100% de pruebas pase de forma repetible en CI.
- Android/iOS estén firmados con credenciales productivas y IDs definitivos.
- RLS impida acceso entre usuarios y esté cubierta por pruebas.
- Reinstalación, actualización y segundo dispositivo no causen pérdida o divergencia silenciosa.
- Cada fallo de sincronización sea visible y recuperable.
- Existan crash reporting, métricas, soporte y procedimiento de rollback.
- La versión candidata complete un piloto controlado sin incidentes críticos.

## Conclusión

**Mi Finca aún no está lista para salir a producción pública.** Sí está suficientemente avanzada para una beta interna o piloto controlado, siempre que los participantes sepan que la sincronización multidispositivo y la recuperación operativa todavía están en estabilización. El próximo esfuerzo no debería centrarse en agregar funciones, sino en cerrar pruebas, seguridad, sincronización, migraciones y distribución.
