# DELETE E2C — handler seguro y orchestration local

## Checkpoint y alcance

Rama feature/estructura-app-mvp, HEAD y referencia origin iniciales
038baa4451893d993352d6a400d874b3825c45e5; árbol limpio. E1, E2A, E2B y Flutter
permanecen intactos. No deployment, secretos configurados, SQL ni servicios remotos.
No se instalaron herramientas. Los tests HTTP inyectan fetch y no abren sockets.

## Documentación oficial consultada (2026-09-26)

- https://supabase.com/docs/guides/functions/auth
- https://supabase.com/docs/guides/functions/auth-headers
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys
- https://supabase.com/docs/guides/functions/function-configuration
- https://supabase.com/docs/guides/functions/quickstart

Se consultó únicamente documentación pública, nunca el proyecto del usuario.
La guía auth recomienda @supabase/server con auth secret o secret:<name> para
server-to-server. Las claves publishable son de cliente; un JWT válido identifica
un usuario y no lo autoriza a ejecutar este worker. Las claves secretas son de
servidor, dan privilegios administrativos y no deben distribuirse a Flutter.

Las páginas presentan una diferencia sobre la compatibilidad histórica de
verify_jwt con claves nuevas. Ambas coinciden en la decisión relevante para este
worker: autenticar la clave en código y usar verify_jwt=false en service-to-service.
No se usa esa comprobación del gateway como autorización administrativa.

## Autenticación y modelo de secretos

Se mantiene fetch E2B. No se añade @supabase/server solo para crear clientes SDK
que aquí no utilizamos. Se adopta el modelo actual de clave secreta nombrada en
SUPABASE_SECRET_KEYS (JSON), seleccionada por ANIMAL_PHOTO_CLEANUP_KEY_NAME; nombre
default animal-photo-cleanup. Se exige que esa entrada exista; no hay fallback a
otra clave, publishable, JWT, SUPABASE_SERVICE_ROLE_KEY ni formato legacy.

El caller servidor debe enviar la clave nombrada en apikey. auth.ts verifica
igualdad mediante HMAC-SHA256 con WebCrypto: firma un mensaje fijo con la clave
esperada y verifica con la presentada, sin comparación de strings con salida
anticipada. No es un protocolo de firma de requests ni agrega protección contra
replay; es autenticación bearer por posesión sobre TLS. No registra credenciales.
Solo sintaxis/tamaño se validan localmente; la validez de la clave ante Supabase
será comprobada por su gateway al realizar operaciones en una fase autorizada.

La misma clave nombrada se envía al backend en apikey, sin reenviar Authorization
ni headers del request. Ante revocación/error administrativo, E2B activa el latch
global y el worker se detiene. Rotación/configuración de claves y revisión de su
propagación al runtime son actividades futuras; esta fase no las ejecuta.

Decisión para configuración futura, NO aplicada ni desplegada:

```toml
[functions.animal-photo-cleanup]
verify_jwt = false
```

No se crea config.toml completo ni se inicializa/enlaza un proyecto local para
simular validación. El handler conserva su propia autenticación obligatoria.
Se revisó .gitignore: no contiene regla .env específica. No se creó ningún .env
ni .env.example y no se modificó .gitignore; antes de crear un archivo de secretos
local futuro, habrá que excluirlo de Git.

## Arquitectura y endpoint

index.ts exporta fetch como entrypoint mínimo, sin peticiones al importar módulos.
handler.ts valida método/config/auth/input; worker.ts ensambla discovery, claim,
evidencia, cleanup E2A, Storage E2B y finish. auth.ts y config.ts son independientes.
Dependencias de worker: fetch, reloj y logger inyectables. Sin mutex global.

POST sin body y sin query parameters. Se rechazan incluso {} y selecciones de
animal/user/bucket/path/object/job. El body no se consume, evitando una lectura
sin límite. GET y demás métodos: 405 + Allow POST. Config inválida: 503; auth
inválida/ausente: 401; input extra: 400. No hay CORS para clientes Flutter.
Responses JSON con Cache-Control no-store. El entrypoint usa reloj monotónico
performance.now anclado a Date.now, conservando la escala epoch para leases.

## Configuración fail closed

SUPABASE_URL debe ser un origen HTTPS sin credenciales, path, query ni fragmento.
SUPABASE_SECRET_KEYS debe ser objeto JSON acotado y contener una clave secreta
nombrada válida en forma. Los errores no incluyen valores recibidos.

| Variable ANIMAL_PHOTO_CLEANUP_… | Default | Rango |
| --- | --- | --- |
| KEY_NAME | animal-photo-cleanup | Entrada propia existente en el JSON |
| MAX_JOBS | 4 | 1..4 |
| DISCOVERY_LIMIT | 1000 | 1..5000 |
| INVOCATION_MS | 90000 | 15000..90000 |
| REQUEST_MS | 5000 | 100..10000 |
| FINISH_MS | 5000 | 100..10000 |
| SKEW_MS | 2000 | 100..10000 |
| MAX_BATCHES | 20 | 1..20 |

Se rechaza una combinación de plazos que no deje espacio para trabajo y ACK.
Ningún parámetro es controlable desde el request HTTP.

## Orchestration y deadlines

Discovery se ejecuta una sola vez; cualquier error detiene la invocación.
Claim secuencial hasta cuatro veces; none termina normalmente. Cada claim está
validado por E2B y queda ligado al mismo JobsAdapter para evidencia/finish.
Un conjunto de identidades procesadas impide repetir cleanup si claim devuelve
el mismo animal otra vez; el nuevo lease se deja expirar.

Antes de cualquier Storage I/O se lee sync_deletions. Mismatch produce diagnóstico
terminal_mismatch y un único intento estructural de finish mientras haya margen.
Si el guard E1 impide el ACK, o no hay margen, se marca interventionRequired;
no se escribe ni repara el ledger y no se borra Storage. Un ACK incierto no permite
afirmar la causa SQL exacta: la señal de intervención es conservadora.

Se usan exclusivamente core y adapters existentes. List permanece en offset 0,
limit 100/name asc, validación de página completa, paths exactos, double-empty y
máximo 100/remove. Sin inventario animals/remote_photo_path ni SQL Storage.

Deadline lógico de 90s desde el inicio del worker, después de auth/config. No es
una promesa sobre la vida del runtime. E2B limita las peticiones y aborta; su helper
combina lease/invocación, reserva finish y aplica margen de reloj. Evidencia usa
storageDeadline; finish usa finishDeadline. Sin margen, no se inicia Storage ni
ACK. No se renueva lease. Abort no prueba cancelación del servidor.

budget_exhausted: NO finish, NO cambio de código de error, lease_expiry y detener
la invocación. El progreso permanece y una ejecución posterior podrá retomarlo.

## ACKs, errores administrativos y resumen

accepted confirma la clase de resultado reportada; rejected no confirma éxito;
uncertain detiene la invocación sin retry ni nuevo claim. Un fallo global en
cualquier etapa (incluso finish) detiene toda la invocación, sin reportar
permission_denied para cada job ni producir cuarentena masiva.

Resumen bounded: discovered, claimed, processed, observedEmpty, retry,
quarantined, leaseExpiry, ackRejected, ackUncertain, fatal, interventionRequired,
stopped. observedEmpty/retry/quarantined cuentan ACKs aceptados por clase enviada.
Un retry incierto puede llevar a cuarentena dentro de E1; el boolean de finish no
expone ese estado final, por lo que el resumen no pretende conocerlo.
Processed cuenta resultados locales, no ACKs. 200 indica invocación manejada,
incluso stale/uncertain/deadline; no garantiza eliminación durable. 503 para fallo
global/discovery/claim o intervención requerida. Siempre inspeccionar el resumen.

Logs se construyen campo a campo desde categorías internas: invocationId generado,
sequence/generation decimal, outcome, ACK, código normalizado, contadores y duración.
Nunca se serializan jobs completos, bodies administrativos, excepciones, paths,
URL, headers o secrets. Un logger que falla no altera los ACKs.

## Concurrencia y late uploads

E1 sigue siendo autoridad: SKIP LOCKED, lease_token, generation y fencing.
Los tests simulan dos workers simultáneos y un reclaim con generación nueva;
un ACK viejo es rechazado. Son tests del ensamblaje, no prueba nueva de PostgreSQL.
E1 ya tiene harness SQL separado; no se ejecuta ni se modifica aquí.

El guard INSERT E1 rechaza nuevos uploads después de observar el tombstone.
Uploads ya en vuelo pueden terminar tarde: double-empty no es garantía permanente.
E1 programa reconciliación tras observed_empty. Se prueba un upload entre lecturas
vacías sin agregar sleeps. E2C no crea el scheduler que disparará reconciliaciones.

## Preflight obligatorio E2D — NO ejecutado

Antes de autorizar cualquier borrado real:

1. Completar Deno check/lint/fmt/test y validar entrypoint/auth en Edge Runtime
   local aislado con transporte fake, sin credenciales ni conexión productivas.
2. Revisar configuración de clave nombrada y verify_jwt, límites, reloj y permisos
   administrativos en un entorno autorizado; no presumir que existen por el código.
3. Reconfirmar bucket privado no versionado, versioned_objects=0, delete_markers=0
   y archived_objects=0, y ausencia de cambios de backend/configuración.
4. Reconfirmar los cinco objetos reservados, jobs/ledger consistentes y guards E1.
5. Revisar rollout y autorizar explícitamente despliegue/primera ejecución limitada.

Si versioning/archivado no puede descartarse, no ejecutar este worker ni improvisar
borrado de versiones históricas. List v1 no certifica esa precondición.

## Validación local de E2C

337 tests Node: 337 pass, 0 fail (273 previos + 64 nuevos). Incluyen auth/config,
input prohibido, flujos completos con y sin objetos, deadline, budget_exhausted,
terminal mismatch, fatal 401/403 por etapa, ACK incierto, logs/responses y concurrencia.
Sintaxis con node --check y whitespace incluyendo todos los archivos untracked.
No se hicieron tests Flutter ni SQL.

command -v supabase y command -v deno no encontraron ejecutables. Por ello no hay
versiones CLI/Deno que reportar ni se ejecutó deno fmt/lint/check/test.
Docker CLI 29.4.0 está instalado; docker info falla por ausencia de socket/daemon.
No se arrancó Docker, stack ni Edge Runtime. No se instalaron herramientas.

Deno validation: PENDING. Edge Runtime validation: PENDING.
Node no valida tipos estáticos ni certifica runtime Deno. Supabase local usa
normalmente URLs HTTP internas; E2B conserva su restricción HTTPS. Un futuro
harness de Edge Runtime debe inyectar transporte fake sin alterar ese contrato;
probar contra un stack HTTP local exigiría una decisión separada. No se simula
compatibilidad local mediante una URL productiva.

Los cinco objetos reservados siguen intactos respecto a esta intervención. La
cardinalidad proviene de la evidencia del usuario, no de una nueva consulta.
Cero jobs reales reclamados, discovery/finish remotos, secretos reales, deploy,
scheduler, commit o push. E2D no comenzó.
