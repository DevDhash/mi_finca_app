# DELETE C — eliminación offline-first de animales

Estado: **IMPLEMENTADO Y VALIDADO EN DISPOSITIVO REAL**.

Storage cleanup NO forma parte de DELETE C y se implementará en DELETE E.

Base inicial: `feature/estructura-app-mvp`, HEAD
`8434e237ae275162a9897a81aac3468164a64e0a`, working tree limpio.
No requiere cambios de esquema SQLite ni cambios en Supabase.

## API y decisión durable

`AnimalRepository.deleteAnimal(id)` devuelve `AnimalDeletionResult`:
accepted, alreadyDeleted, notFound, needsVerification u ownershipFailure.
La UI entrega solo el ID; no decide presencia ni proporciona el owner.
El repository valida sesión local, sesión remota cuando existe y ownership
persistido, incluyendo el de la foto. Las transacciones vuelven a validar sesión.

- **CONFIRMED:** la primitiva local aplica el mismo protocolo de markDeleted,
  manteniendo payload y presencia, generando operación/revisión DELETE pending.
  La outbox existente llama sync_soft_delete y aplica su ACK por snapshot. No se
  espera la red para aceptar la acción en el detalle.
- **LOCAL_ONLY:** una transacción inspecciona todos los movements del animal,
  incluidos tombstones. Solo admite movimientos del mismo owner acreditados
  LOCAL_ONLY, con operación local consistente y sin ACK remoto. Un movimiento
  ya cancelado localmente es idempotente. Cualquier evidencia ambigua impide
  cancelar el conjunto. También se rechaza evidencia contradictoria de foto.
  Animal y movimientos cancelables quedan tombstoned, pending=false, operación
  `cancel`, `_sync.localCancellation=true`, y conservan payload/owner/fotos.
  No se inventan deletedAt ni remoteOperationId. operationId identifica una
  intención exclusivamente local; no es un ACK remoto.
- **UNKNOWN:** nunca se cancela por ausencia. Se consulta la fila física de
  animals mediante sesión autenticada y filtro id/user_id, incluyendo filas
  soft-deleted. Solo un resultado positivo aporta CONFIRMED. Vacío/error/offline
  conserva la fila y ofrece volver a intentar con conexión. Un cambio de cuenta
  rechaza la evidencia. Los errores inesperados de persistencia se propagan a la
  UI como fallo, sin convertirlos en un éxito o en una confirmación remota.

## Atomicidad y carreras

`deleteAnimalLocally` y `beginRemotePublish` compiten mediante transacciones
SQLite. Si la cancelación gana, el snapshot anterior ya no puede reclamar ni
publicar el animal o sus movements. Si gana la publicación, la presencia es
UNKNOWN y la cancelación LOCAL_ONLY deja de ser admisible.

La escritura de DELETE confirmado comparte una primitiva privada con
markDeleted para reutilizar la transacción sin anidar el wrapper público.
La cancelación verifica todos los dependientes antes de escribir cualquiera.
Los tests ejecutan ambas órdenes de carrera, snapshots anteriores, retries y
restart usando SQLite real en archivo.

El ViewModel comparte el Future de una eliminación simultánea del mismo ID.
El detalle bloquea diálogos/acciones duplicados y sale tras aceptar la intención
local. Los fallos posteriores del sync automático no convierten ese éxito local
en un error de eliminación: la outbox mantiene el retry.

## Movimientos y potreros

CONFIRMED conserva todos los movimientos, históricos y pendientes. C1 permite
publicar un movement legítimo con padre CONFIRMED soft-deleted físicamente
existente, según el contrato remoto previamente verificado.
LOCAL_ONLY cancela únicamente movimientos acreditados como locales en la misma
transacción. No hay borrado físico, movimiento artificial ni tombstone remoto.

MoveAnimal relee el animal y usa saveMove para validar animal activo, owner y
potrero origen antes de persistir animal/movement atómicamente. saveMovement
local pendiente también exige un padre activo propio. MoveMany intersecta IDs
seleccionados con SQLite dentro de su transacción y revalida cada escritura;
si no quedan animales, no escribe ni actualiza potreros.

Eliminar no restaura snapshots de potreros ni cambia status, grazingStartDate,
lastGrazingEndDate, plannedGrazingDays o rotationOrder. Los efectos previos de un
movimiento cancelado se conservan en potreros para no deshacer cambios de otros
animales. Quitar el último animal puede dejar el potrero En uso con cero animales.

## Fotos

Se reutilizan claim/CAS de FOTO A–D y C1. Un animal cancelado no aparece en la
outbox ni en el descubrimiento de fotos; un snapshot viejo no supera el claim.
Un tombstone confirmado conserva rutas y metadata de upload. Los checkpoints y
ACK de un upload/publicación antigua no pueden reemplazar el tombstone.
No se borran objetos Storage ni se fuerza limpieza de archivos/cache. Un objeto
huérfano de un trabajo que ya estaba en vuelo queda para DELETE E.

## Estado, refresh y navegación

El ViewModel relee SQLite después de save, delete, move y refresh. Las lecturas
locales usan un contador para descartar respuestas reemplazadas por otra lectura.
El delete no elimina el historial en AnimalState.movements. Los lectores normales
de SQLite ocultan los movements cancelados.

El finally de refresh relee animales locales aunque el pull de tombstones haya
sido seguido por un GET fallido. Un listado con solo tombstones cuenta como datos
locales existentes y abre offline sin volver a consultar animales remotos. Las
colecciones de movements cancelados reciben el mismo tratamiento, sin impedir
la descarga inicial de historial cuando aún no existe ningún movement local.
La ausencia de una fila en un listado remoto no se interpreta como eliminación.

Al finalizar el push, SyncViewModel relee Animals si ese provider existe: incluye
los conflictos terminales resueltos durante sync automático, sin polling ni un
nuevo stream y sin iniciar otro refresh remoto.

El menú overflow del detalle contiene Eliminar animal con confirmación Material,
identificación por nombre/código y estilo destructivo. No hay papelera en cards.
Los detalles y movimientos sin animal muestran estado no disponible y salen si
su propia ruta está activa; nunca hacen pop de un editor o diálogo superpuesto.
El formulario captura un guardado rechazado por tombstone. MoveMany depura la
selección y su contador; no usa firstWhere sobre IDs que desaparecieron.
Home, búsqueda/lista y contadores/detalle de potreros observan AnimalState y
reflejan la reducción sin escribir estados operativos de potreros.

## Corrección de automaticSyncProvider

Durante la validación física apareció la excepción Riverpod 3.3.2:
"Tried to modify a provider while the widget tree was building."
Los listeners llamaban update() y setConnectivity() sincrónicamente; la excepción
podía interrumpir update antes de worker.setEnabled. El microtask inicial no
protegía los listeners posteriores.

Ahora una única tarea cancelable con Timer(Duration.zero) separa esas señales
del ciclo síncrono de construcción. Agrupa red/auth/manual offline/lifecycle,
acumula resetBackoff sin perder solicitudes y relee valores actuales al ejecutar.
Comprueba ref.mounted y actualiza conectividad/habilitación en el mismo callback.
Dispose cancela el timer y el worker. No hay demora temporal arbitraria ni un
segundo scheduler de outbox. El worker existente recibe cambios de records y
reintenta; DELETE también solicita sync explícitamente tras aceptar localmente.

La reproducción literal automatizada usa auth durante build y alcanza el mismo
update/setConnectivity que el stack físico. Falló con el provider anterior y
pasa con el corregido. También se cubren red/recompute, resume, coalescencia,
dispose, reconnect, DELETE creado estando online y procesamiento único/ACK.
No se atribuye retrospectivamente el caso histórico de Toriski a esta excepción:
la evidencia disponible de aquella operación no permite reconstruirlo.

## Validación física del 25 de septiembre de 2026

Resultados reportados por el responsable de las pruebas en dispositivo real;
no se repitieron ni se modificaron datos reales durante este cierre.

- **Online:** soft delete remoto con deleted_at
  `2026-09-25 15:49:41.892565+00` y ledger sequence 4. Sus dos movimientos
  permanecieron con deleted_at NULL.
- **Offline + restart + reconnect:** animal previamente creado y confirmado
  online; eliminado en modo avión, desaparece de Animales y del conteo del
  potrero, con un cambio pendiente en Dashboard. Tras cerrar completamente la
  app y reabrir offline, continúa oculto. Antes de reconectar no existía ledger
  remoto y deleted_at seguía NULL. Al recuperar Internet, sin editar ni recrear,
  automatic sync aplicó el DELETE: deleted_at
  `2026-09-25 16:10:17.015854+00`, ledger sequence 5. Su movimiento permaneció
  con deleted_at NULL.

Estos casos validan eliminación online, intención durable offline, restart
sin conexión, reconexión automática, actualización de conteos e historial.

**Validación específica multi-dispositivo: PENDIENTE, NO BLOCKER.**
Debe repetirse cuando esté disponible el segundo teléfono. Hubo una prueba
anterior positiva de propagación, pero no se afirma que el escenario final
específico de DELETE C se haya repetido ahora.

## Cobertura y validación

`animal_deletion_test.dart` cubre persistencia, retry/restart/reconnect, cancelación
atómica, claims concurrentes, dependencias ambiguas, ownership/sesión, UNKNOWN,
fotos en vuelo, respuestas antiguas, refresh parcial, solo tombstones, historial,
state y movimientos individuales/lote. Los transportes remotos son simulados.
`animal_delete_ui_test.dart` cubre confirmación/cancelación/doble acción, mensajes,
navegación abierta, editor, selección por lote y contadores Home/potreros/lista.
La suite previa cubre FOTO A–D, DELETE A/B y las 56 pruebas de C1.

Validación final sobre el código terminado:

- `dart format lib test`: 108 archivos, 0 cambios en la última ejecución.
- `flutter analyze`: sin incidencias, salida 0.
- `flutter test`: 311 tests; 306 pasan y 5 fallan (salida 1).
- Los 52 casos de este avance pasan: 31 de persistencia/estado de DELETE C,
  12 de UI de DELETE C y 9 de integración de automaticSyncProvider.
- Se mantienen exclusivamente los dos fallos históricos de expense_form_test y
  los tres de expense_list_test. No se modificaron esos tests.
- `flutter build apk --debug`: correcto, APK generado.
- `git diff --check`: correcto.
- Archivos de Supabase sin diferencias respecto al HEAD inicial.
- No SQL manual, migraciones, hard delete de dominio, Storage delete ni credenciales añadidas.

## Límites y comprobación manual

- No se ejecutó ninguna migración ni SQL manual contra Supabase durante el cierre.
  La repetición multi-dispositivo específica sigue pendiente, no es blocker.
- SYNC_ENTITY_DELETED se reconcilia mediante el pull del ledger: al incorporar
  el tombstone remoto, el UPSERT pierde y deja de estar pending. Si la red o la
  lectura del ledger fallan, se conserva pending y se reintenta con backoff;
  no se infiere eliminación a partir de ausencia ni se descarta la operación.
- Una petición de foto ya iniciada puede terminar en la red, pero su checkpoint
  o ACK obsoleto no puede sustituir el tombstone. Un objeto huérfano eventual
  se conserva para DELETE E.
- UNKNOWN sin evidencia física positiva exige reconexión/verificación. Incluso
  si solo se subió Storage antes de un fallo, no se presume que sea LOCAL_ONLY.
- No hay suscripción realtime nueva: el segundo dispositivo incorpora tombstones
  mediante el refresh/sync existente. El push automático actualiza la UI cuando
  aplica un conflicto terminal local.
- Una eliminación administrativa física queda fuera del contrato CONFIRMED/C1.
- Los archivos/fotos cancelados pueden mantenerse hasta la limpieza local ya
  existente; no se añadió limpieza agresiva. DELETE E sigue pendiente.
- No se implementan DELETE D/E/F, eliminación de cuenta ni cascadas generales.
