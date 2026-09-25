# DELETE C1 — presencia remota y dependencias

Base: dae3e18. Infraestructura únicamente; no deleteAnimal, UI de eliminación,
cancelación local, borrado de movimientos/fotos ni cambios SQL.

## Presencia durable

`_sync.remotePresence` pertenece al protocolo, no a Animal:

- Ausente / valor desconocido: `unknown` (legacy conservador).
- Nueva fila local con owner persistido y pending: `local_only`.
- `beginRemotePublish`: transacción que compara operación y timestamp, comprueba
  pending/sesión/terminalidad y persiste `unknown` antes del primer efecto remoto.
- UPSERT autenticado satisfactorio o lectura positiva de fila: `confirmed`.
- Una edición conserva la presencia; Storage, URLs y ledger no la confirman.
- `markDeleted` conserva la presencia; un padre confirmado y luego eliminado
  sigue siendo una fila física acreditada. No se modifica la semántica RPC.

Las creaciones pasan por putRecord: AnimalLocalDataSource.save,
AnimalLocalDataSource.saveMovement y PaddockLocalDataSource.save. Una fila previa
sin evidencia nunca se reclasifica como local_only. No hay migración de datos.

## Evidencia no es ACK

`markRemoteConfirmed` hace merge transaccional por colección/ID/owner, manteniendo
payload, pending, revisión, operación y tombstone actuales. Puede incorporar una
respuesta positiva anterior sin confirmar una edición posterior.

Los checkpoints/ACK comparan todo el snapshot de operación y timestamp salvo
remotePresence, la única evidencia independiente. Siempre preservan la presencia
actual. Cambios en owner, operationId, revisión, payload o tombstone impiden ACK.
No se considera synced ni published una revisión nueva por una respuesta vieja.

El merge de Animals incorpora evidencia antes de descartar contenido por pending.
verifiedRemoteOwner permite lo mismo a los demás lectores autenticados. Verificar
ownership con metadata local de foto no establece confirmed; una lectura positiva
real de verifyLegacyOwner sí puede hacerlo.

## Publicación y fotos

AnimalPhotoSync reclama la operación antes de Storage o publicación sin foto.
Un upload no confirma la fila: se mantiene unknown hasta publicar animals.
Conserva target, versión, hash, rutas y checkpoints. Un refresh concurrente puede
confirmar presencia sin invalidar un checkpoint de foto de la misma operación.
La configuración productiva publica con SupabaseSyncRemoteDataSource, que valida
sesión/owner. Los métodos de UPSERT directo del datasource Animals no se utilizan
por el flujo de repositorio/outbox y no deben introducirse como bypass de la barrera.

## Dependencias concretas

Para cada UPSERT movements se comprueban from/to paddock no nulos y animal:

- Confirmed del owner: admite el hijo, incluso con edición pendiente o tombstone.
- Unknown/ausente: consulta autenticada de la fila física, incluyendo soft-deleted
  si las policies permiten verla. Una respuesta vacía no es prueba de inexistencia.
- Padre pendiente activo no confirmado: intenta su publicación, una vez por pasada.
- Fallo/sin evidencia: difiere el hijo y mantiene pending; otros registros avanzan.
- No vuelve a publicar un padre terminal para satisfacer al hijo.

La fecha es solo orden base. No hay DAG, segunda outbox, busy-loop ni dependencia
farm inventada. Las consultas fallidas y los intentos se acotan por pasada; el
siguiente sync empieza de nuevo. Un padre acreditado remoto sin copia local permite
el hijo durante esa pasada sin fabricar un payload de dominio parcial en SQLite.

## Límites

- UNKNOWN puede requerir conexión/reconciliación. No autoriza cancelación local.
- No se garantiza padre-before-child para todos los dominios. Las reglas nuevas
  son las solicitadas para movements. Por ejemplo, un animal con un potrero nuevo
  puede necesitar retry si su propio UPSERT se procesa antes que ese potrero.
- El SQL DELETE A versionado no prohíbe historial sobre un animal soft-deleted;
  las policies adicionales de producción no están versionadas aquí. Requieren
  validación física; los tests usan transportes simulados y SQLite real.
- Confirmed prueba existencia histórica, no protege contra hard deletes
  administrativos fuera del contrato normal de clientes.
- El claim hace conservador un crash previo a HTTP: queda unknown aunque nunca
  haya salido la petición. No hay downgrade posterior a local_only.
- La futura cancelación debe competir transaccionalmente con beginRemotePublish;
  no está implementada. DELETE C también debe resolver UI, selección, historial y
  los casos UNKNOWN con dependencias, sin asumir ausencia por un GET vacío.

## Pruebas

remote_presence_sync_test.dart: 56 casos con SQLite en archivo, restart, evidencia,
ACK tardío, ownership, refresh, Storage, dependencias, padre fallido, tiempos adversos,
varios movimientos reales de MoveAnimal y sync concurrente.

Se actualizan dos fixtures/assertions de fotos para el contrato de evidencia;
los cinco fallos históricos de gastos no se modifican.

## Revisión previa al commit

Se añadieron 17 casos. Dos reprodujeron defectos antes de corregirlos:

- `sameOperation` dependía del orden de inserción de los Map. Ahora compara
  estructuralmente Map y listas (estas conservan su orden), omitiendo únicamente
  remotePresence, sin ignorar otros campos de _sync.
- Un false en checkedParents podía ocultar una confirmación posterior en la misma
  pasada. parentReady consulta primero la evidencia durable actual, validando
  sesión/owner, antes de reutilizar el resultado cacheado.

La transacción anidada era segura con Drift 2.31.0 y NativeDatabase: usa savepoints
y depende del commit exterior. Se extrajo _markRemoteConfirmedInTransaction para
que putRecord reutilice su propia transacción sin llamar al wrapper público.
Los casos inexistente/UNKNOWN/pending/CONFIRMED y rollback real verifican atomicidad.

Los siblings comparten publicación y evidencia; ante fallo o respuesta ambigua el
padre se intenta una sola vez por pasada, manteniendo hijos pending y permitiendo
avanzar registros independientes. La recursión termina en animals/paddocks, cuyas
dependencias no llaman a process; attempted evita reprocesar la misma identidad.

markDeleted conserva los tres valores de presencia. LOCAL_ONLY genera DELETE
pending y sigue LOCAL_ONLY: no hay cancelación local. Respuestas antiguas no
alteran la revisión/operación/payload actuales ni retiran tombstones. Los cambios
de cuenta rechazan evidencia antigua, incluso con una fila del mismo ID de B.

## Validación final

- dart format lib test: 105 archivos procesados, 1 formateado en la última ejecución.
- flutter analyze: sin incidencias (salida 0).
- flutter test: 254 aprobados, 5 fallos históricos de gastos (259 en total; salida 1).
- Los 56 tests de C1 pasan. Sin fallos nuevos.
- flutter build apk --debug: correcto (salida 0).
- git diff --check: correcto.
- Migración DELETE A sin cambios; ningún SQL manual/remoto ejecutado.
- Sin commit/push. DELETE C de animales sigue pendiente de autorización.
