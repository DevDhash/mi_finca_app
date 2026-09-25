# DELETE A — infraestructura offline-first

Base: `96bae02` (FOTO A–D). No botones de borrado, cascadas de dominio ni limpieza
remota/local de fotos añadidas en esta fase. No commit ni despliegue a Supabase.

## Decisión

Se conserva SQLite `records`, schemaVersion 1. El payload guarda `_sync` separado
de los modelos de dominio: ownerId, ownership, operation (`upsert`/`delete`),
operationId UUID, revision, requestedAt y tombstone. `records.pending` sigue siendo
la fuente de verdad del trabajo pendiente; `syncStatus` no decide eliminaciones.
`requestedAt` es informativo; `deletedAt` siempre procede del servidor.

`AppDatabase.markDeleted(collection, id, ownerId)` y el facade del repositorio de
sync conservan el payload y cambian la intención en una transacción. Incrementan
revisión, generan operationId y marcan pending. Repetir DELETE no crea otra operación,
ni siquiera tras confirmar. Una nueva entidad necesita otro ID.

Los lectores normales list/find excluyen tombstones. La infraestructura puede usar
`includeDeleted: true`; la outbox nunca los filtra. Los repositorios devuelven el
resultado de SQLite tras un refresh: devolver directamente la respuesta HTTP podía
mostrar una fila que SQLite ya había rechazado como eliminada. Una descarga activa
no reemplaza una edición pendiente, ni un tombstone pendiente o confirmado.

## Sync y merge

- Un vuelo de push compartido por instancia evita duplicar ejecuciones concurrentes.
- DELETE usa `sync_soft_delete`; UPSERT conserva los escritores existentes y sus
  listas explícitas de campos. `_sync` nunca se envía a las tablas de dominio.
- DELETE se comprueba antes de la ruta de fotos. Un upload en vuelo puede terminar
  creando un objeto huérfano, pero su checkpoint antiguo no puede sobrescribir el
  tombstone ni publicar después del conflicto. No se limpia Storage en DELETE A.
- CAS compara colección, ID, JSON COMPLETO y updated_at. Por ello incluye ownerId,
  revision y operationId; también protege cambios hechos en el mismo milisegundo.
- El ACK DELETE valida entidad, colección y propietario antes del CAS. Guarda el
  timestamp y operationId remoto. Este último puede ser diferente: otro dispositivo
  pudo haber eliminado primero el mismo ID. El primer DELETE aceptado es terminal.
- Antes/después de la red se comprueba la sesión. Un DELETE viejo nunca adopta la
  cuenta actual. Una respuesta tardía no confirma una operación local diferente.
- Remoto activo + DELETE local: se conserva DELETE. Remoto eliminado + local limpio:
  se guarda tombstone. Remoto eliminado + UPSERT pendiente: DELETE gana, se conserva
  el payload anterior y se registra `_sync.conflict = remote_delete_wins`.
- Remoto activo antiguo + tombstone confirmado: se ignora. Ausencia remota: no borra.
- `clearAll`, removeRecord y confirmaciones masivas/por ID protegen DELETE pendiente
  (removeRecord protege también tombstones confirmados). Logout conserva el guard
  de FOTO D para cualquier pending y para fotos aún no publicadas.

## Descargar tombstones

`sync_deletions` proporciona collection, entity_id, user_id, deleted_at y operation_id.
La descarga usa owner explícito y paginación por `sequence`, hasta recibir una página
vacía; una página corta puede ser un límite del servidor. No hay cursor persistido:
cada pull empieza desde cero para recoger commits tardíos con secuencias inferiores.
No se infiere eliminación por ausencias ni por listas incompletas.

Se puede invocar `pullRemoteTombstones()` incluso con cero pending. «Sincronizar»
lo hace y recarga viewmodels. Actualizar animales lo hace antes del merge de FOTO C.
Un UPSERT rechazado intenta descargar tombstones, pero solo una respuesta autenticada
puede resolverlo. No hay Realtime ni polling general añadido: un segundo dispositivo
necesita una sincronización/actualización explícita para enterarse.

Antes de aplicar SQL, una respuesta específica de tabla ausente (42P01/PGRST205)
no bloquea FOTO C. Otros errores se propagan o conservan los pendientes. Esto NO
habilita DELETE: la RPC requiere la migración; sin ella los DELETE quedan pendientes.

## Propietario y datos legacy

1. Las nuevas operaciones locales guardan el owner de la sesión al crearse.
2. Las descargas activas autenticadas conservan el owner verificado en SQLite.
3. Un owner persistido de `_photoUpload` de FOTO B–D es evidencia previa; se rechaza
   si no coincide. No se asigna propietario nuevo a una foto legacy al descubrirla.
4. Filas antiguas sin evidencia no se atribuyen por estar una cuenta abierta.
   Una edición conserva `ownerId: null` y `ownership: legacy_unverified`.
5. Para un UPSERT legacy pendiente, sync consulta su ID con user_id y sesión
   autenticada. Solo una fila remota del propietario permite adoptarlo por CAS.
   `verifyLegacyOwnership(collection,id,ownerId)` ofrece el mismo paso para filas
   limpias antes de un futuro DELETE; luego puede eliminarse offline.
6. Si nunca se subió y no existe evidencia persistida, no se transmite ni elimina
   automáticamente. El dato permanece visible/local y pendiente si ya lo estaba.
   Hace falta una futura recuperación/exportación con verificación explícita del
   usuario. Esto puede bloquear logout; no se resuelve perdiendo datos.

La verificación remota no sobrescribe el payload pendiente. Se revisa tanto el owner
local como el remoto. Los clientes internos que usan `verifiedRemoteOwner` deben
haber comprobado la respuesta autenticada: no es un parámetro de UI.

## SQL propuesto (no ejecutado)

Archivo: `migrations/20260924000200_delete_a_infrastructure.sql`.
Prerequisitos confirmados por DELETE 0: UUID id/user_id, deleted_at timestamptz,
RLS y policies de propietario en farms, paddocks, animals, animal_movements, expenses.

| Objeto | Contenido y propósito |
| --- | --- |
| `public.sync_deletions` | PK `(collection,entity_id)`, user_id, deleted_at del servidor, primer operation_id y sequence identity. Mantiene identidades terminales incluso si DELETE llegó antes del primer CREATE. Sin FK adicional ni CASCADE; el propietario se valida en la RPC. |
| `sync_deletions_owner_sequence` | Índice `(user_id,sequence)` para descargar todas las identidades de la cuenta por páginas. |
| `sync_deletions_read_own` | SELECT permisivo para authenticated propietario. |
| `sync_deletions_read_guard` | SELECT restrictivo: exige auth.uid no nulo e igual a user_id, incluso si existiera otra policy permisiva. |
| Grants del ledger | SELECT solo para authenticated. Sin INSERT/UPDATE/DELETE de clientes; sin acceso anon. |
| `sync_soft_delete(text,uuid,uuid,uuid)` | RPC SECURITY DEFINER. Lista cerrada de colecciones; valida auth.uid y propietario real, incluso si RLS ocultaría la fila. Serializa por identidad con advisory lock, registra primer DELETE y actualiza solo deleted_at. Devuelve el tombstone canónico. Reintentos conservan timestamp/operación aceptados. |
| `sync_guard_entity()` | Trigger function SECURITY DEFINER con search_path vacío y nombres cualificados. Fija id/user_id, rechaza writes a IDs terminales y registra soft deletes directos con hora del servidor. No ejecutable como RPC del cliente. |
| `sync_terminal_identity` (5 triggers) | BEFORE INSERT OR UPDATE en las cinco tablas. Cubre el UPSERT directo de versiones antiguas. No modifica FK ni elimina filas. |
| `sync_no_hard_delete` (5 policies) | DELETE restrictivo `false` para authenticated. Bloquea hard deletes normales pese a las policies permisivas existentes. No modifica sus policies SELECT/INSERT/UPDATE. |
| Backfill | Copia al ledger identidades que ya tienen deleted_at, preservando fecha y todas las filas del dominio. ON CONFLICT no cambia un tombstone existente. |

La migración es transaccional, bloquea escrituras brevemente durante instalación,
y puede reaplicarse al esquema esperado sin duplicar ni borrar información. No
cambia Storage, columnas del dominio ni relaciones; no añade CASCADE de dominio.
El rol que instala debe ser de confianza (SQL Editor administrativo habitual).

### Por qué impide resurrecciones

No depende de Flutter: el trigger se ejecuta también en INSERT ... ON CONFLICT
DO UPDATE. Un ID presente en el ledger rechaza nuevos INSERT/UPSERT activos, y una
fila con deleted_at no admite UPDATE. El ledger cubre además el caso en el que el
DELETE llega antes del CREATE offline retrasado. Una app antigua puede recibir un
error de escritura y conservar pending, pero no restablecer el ID.

Referencias: [PostgreSQL, triggers y ON CONFLICT](https://www.postgresql.org/docs/17/sql-createtrigger.html)
y [composición de policies restrictivas](https://www.postgresql.org/docs/17/sql-createpolicy.html).

## Validación y despliegue manual

Tests Dart: `delete_a_test.dart`, `delete_a_remote_test.dart` y casos añadidos a
`animal_photo_upload_test.dart`. Usan SQLite real en archivo (incluido reinicio),
dobles de servidor y el SDK Supabase real con HTTP simulado. Cubren los 18 casos
solicitados y ownership legacy/paginación; no sustituyen pruebas del SQL real.

`tests/delete_a_local.sql` es un harness para PostgreSQL >=15 en una base NUEVA,
desechable, llamada `mi_finca_delete_a_test`. Crea roles/esquema/fixtures mínimos,
aplica dos veces la migración y verifica RPC, terminalidad, hora del servidor,
RLS, hard-delete bloqueado y DELETE antes de CREATE. **No ejecutarlo en Supabase**:
no es una migración. No se ejecutó aquí: no hay PostgreSQL local ni daemon Docker.

Antes de usar DELETE B:

1. Revisar la migración y ejecutar el harness en PostgreSQL local/staging; verificar
   también concurrencia con dos conexiones y compatibilidad con triggers existentes.
2. Aplicar MANUALMENTE solo la migración en Supabase. No hace falta tocar Storage.
3. Ejecutar `tests/delete_a_verify.sql` para inspección read-only de objetos/grants.
4. Validar con dos cuentas (aislamiento) y dos dispositivos de una misma cuenta,
   incluidos UPSERT de app antigua, reintento tras pérdida de respuesta y reconexión.

## Límites pendientes

- SQL no ejecutado ni validado contra los triggers adicionales del proyecto real.
  La validación local usa un esquema mínimo, no una copia completa de producción.
- SELECT FOR UPDATE y los triggers pueden encontrar deadlocks bajo escrituras
  concurrentes: PostgreSQL aborta una transacción; debe reintentarse. Los IDs no se
  resucitan. Los tests Dart no demuestran todas las intercalaciones PostgreSQL.
- Un administrador/service_role puede saltarse RLS, truncar tablas o desactivar
  triggers. El contrato protege sincronización normal, no acciones administrativas.
- No cascadas funcionales. Borrar finca/animal en futuras fases necesitará reglas
  de hijos, movimientos y referencias; las FKs actuales se conservan intactas.
- El ledger conserva el UUID propietario sin FK: su retención tras una futura
  eliminación de cuenta debe definirse en esa fase; no se añade CASCADE.
- No resolución manual de legacy no verificable, purga del ledger, backups/export
  ni limpieza de fotos huérfanas. Los archivos se mantienen.
- La descarga completa de tombstones es deliberadamente simple para el MVP; si el
  volumen crece, se diseñará un cursor seguro frente al orden de commit.
- No botones nuevos ni borrado de gastos implementado aquí.

## DELETE B

Integrar gastos como piloto: confirmación UX, `markDeleted('expenses',id,ownerId)`,
recarga del listado/resumen, indicación de pending/conflicto, verificación de legacy
cuando sea necesaria, y pruebas físicas offline/reinicio/reintento/dos celulares.
La RPC, tombstones, merge y acknowledgements ya son compartidos; no duplicar lógica.

## Resultado de esta ejecución

- `dart format lib test`: correcto (102 archivos procesados en la última ejecución).
- `flutter analyze`: No issues found, código 0.
- `flutter test`: 172 aprobados, 5 fallidos, código 1. Los cinco corresponden a
  los fallos preexistentes de gastos: dos de expense_form_test y tres de
  expense_list_test. No se corrigieron en este trabajo. Los 32 casos nuevos pasan.
- `git diff --check`: sin salida, código 0.
- SQL y pruebas PostgreSQL: no ejecutados. Supabase remoto no fue contactado.
- HEAD sigue en 96bae02; no se creó ningún commit.

## Endurecimiento previo a producción (SQL NO ejecutado)

- El trigger distingue INSERT, activo→activo, activo→eliminado y eliminado→cualquier
  UPDATE. La única transición de borrado es `OLD.deleted_at IS NULL AND
  NEW.deleted_at IS NOT NULL`. Un no-op sobre una fila eliminada también se rechaza.
- Si RPC ya creó ledger, el trigger lo reutiliza sin INSERT, generación de UUID ni
  consumo de identity. El soft delete legacy genera operation_id solo si no existe.
  La RPC conserva la primera operación aunque un retry envíe otro operation_id.
- El backfill usa NOT EXISTS además de ON CONFLICT: rerun normal no consume identity
  para entradas existentes. Ni RPC, ni trigger, ni backfill resetean la secuencia.
  Las secuencias NO son contadores sin huecos: un rollback puede consumir valores.
- Se bloquea también sync_deletions durante instalación y se limita lock_timeout a
  10 s. Un timeout/deadlock aborta la migración: reintentar la transacción completa,
  nunca continuar instrucciones sueltas. El bloqueo evita cambios entre backfill y
  reemplazo de guards; no representa una ventana sin protección para otras sesiones.
- SECURITY DEFINER conserva search_path vacío, nombres cualificados y ACL limitadas.
  El trigger valida destino/operación. La RPC usa una whitelist de tablas, parámetros
  enlazados y comprueba dueño real antes de crear el ledger. No devuelve el payload
  ni el UUID del dueño de una fila ajena. Sus errores de autorización son genéricos.
- **Límite de privacidad:** dado un UUID conocido, éxito para inexistente frente a
  rechazo para ID ajeno permite inferir que ese ID no está disponible. No se puede
  garantizar ocultación absoluta de existencia manteniendo simultáneamente ambos
  resultados del contrato. No se exponen contenido, propietario ni fechas ajenas.
  A y B reciben el mismo SYNC_ENTITY_DELETED al insertar sobre una identidad terminal.
- Las policies permisivas anteriores se conservan. La policy restrictiva de DELETE
  solo se dirige a authenticated. Un administrador/BYPASSRLS con los grants adecuados
  puede hacer hard DELETE; el trigger de INSERT/UPDATE sigue protegiendo identidades
  incluso para service/admin. No hay privilegios ni service_role en Flutter.
- `updated_at` se excluye del control de payload para convivir con triggers existentes
  de timestamps; ningún otro campo de negocio puede cambiar durante soft delete.
  Los triggers adicionales del Supabase real requieren revisión por orden y efectos.

### Alcance real de rerun

CREATE TABLE/INDEX IF NOT EXISTS conserva objetos y la identity existentes; NO
repara esquemas divergentes ni valida que un objeto homónimo tenga la forma correcta.
CREATE OR REPLACE conserva la identidad de las funciones (misma firma/retorno),
reemplaza su cuerpo/configuración y reaplica ACL. Las policies y triggers con nombres
DELETE A se recrean transaccionalmente; las policies anteriores de dominio no se
eliminan. Backfill conserva primer ledger, fecha y sequence; no cambia filas de dominio.
Una tabla/función/índice preexistente incompatible, dueño no confiable, FORCE RLS o
grants/triggers adicionales necesita auditoría manual: IF NOT EXISTS no lo subsana.
No ejecutar concurrentemente dos instalaciones. No reducir ni reiniciar la identity.

### Harness ampliado

`tests/delete_a_local.sql` prepara assertions SQL reales (no comparaciones textuales):
UPSERT activo/eliminado, INSERT tardío propio/ajeno, RPC con mismo/diferente operationId,
sequence/fecha estable, backfill/rerun, A/B, soft delete legacy en animals, payload
combinado rechazado, hard DELETE authenticated bloqueado y service role permitido.
Requiere instancia local desechable y rol administrativo con permiso de crear roles
BYPASSRLS; no ejecutar contra un clúster compartido o Supabase. No fue ejecutado.

Concurrencia opcional: tras el harness, abrir dos conexiones psql a esa base local.
Ejecutar `tests/delete_a_concurrency_a.sql`; cuando anuncie «Locks held», ejecutar
`tests/delete_a_concurrency_b.sql`. B exige esperar realmente al menos un segundo,
verifica que prevalezca la operación A y rechaza INSERT tardío. Reiniciar el fixture
para repetir. No cubre exhaustivamente deadlocks de UPDATE directo contra RPC.

### Validación de este endurecimiento

Se revocó también el acceso de PUBLIC/anon/authenticated a la secuencia identity,
independientemente de los grants por defecto de Supabase. Un esquema sin secuencia
asociada falla explícitamente en vez de continuar parcialmente.

- `dart format lib test`: completado.
- `flutter analyze`: sin incidencias, código 0.
- `flutter test`: 172 pasan, 5 fallan (los mismos gastos preexistentes), código 1.
- `flutter build apk --debug`: correcto, código 0; APK en
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: correcto, código 0.
- SQL: NO ejecutado por instrucción expresa, ni migración ni harness.
- Supabase: migración NO aplicada por el agente. Sin commit y sin DELETE B.

Se exige READ COMMITTED en RPC y trigger. Los advisory locks por sí solos no
renuevan un snapshot REPEATABLE READ: podría no ver un ledger confirmado mientras
esperaba el lock. Para no depender de esa suposición silenciosa, otro aislamiento
falla con SYNC_REQUIRES_READ_COMMITTED (0A000), incluido SERIALIZABLE. PostgREST
normal usa READ COMMITTED; comprobar que el proyecto no lo personalizó. Operaciones
administrativas INSERT/UPDATE deben usar ese aislamiento; hard DELETE no usa estos
triggers. El harness incluye rechazo de snapshots fijos. Tampoco se ejecutó.
