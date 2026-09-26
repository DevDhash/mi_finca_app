# DELETE E2B — adaptadores locales del worker

## Checkpoint y alcance

Rama `feature/estructura-app-mvp`, HEAD y referencia local origin
`f03464df17f4bb71cf8b14fe478e13c8aaa81f04`, working tree inicialmente limpio.
Se leyó el contrato E1 y sus pruebas de claim, fencing, retry y autorización.
No se ejecutó SQL. E1, Flutter y la semántica E2A permanecen intactos.

E2B contiene adaptadores y pruebas con fetch inyectado; no tiene endpoint,
orchestrator productivo, lectura de variables de entorno, credenciales reales,
SDK inicializado, discovery automático ni llamada automática al cargar módulos.
Los tests jamás utilizan fetch global. El dominio fixture.invalid y sus headers
son sintéticos; no se abre ninguna conexión.

## SDK frente a fetch

Se eligió fetch HTTP directo para producción, aislado en adapters. El SDK oficial
simplifica RPC/Storage, tipado y mantenimiento habitual, pero aquí necesitamos
preservar bigint antes de la deserialización y controlar AbortSignal hasta acabar
el cuerpo HTTP. Su deserialización JSON habitual no constituye esa garantía.
Fetch permite controlar esos dos puntos sin una dependencia externa adicional.
Coste: mantener y validar nuestro contrato HTTP, schemas y clasificador.

Se contrastó el protocolo Storage con el cliente oficial instalado localmente
`storage_client` 2.5.9: list POST /object/list/{bucket}, remove DELETE /object/{bucket}
con prefixes. No se descargaron documentación ni paquetes ni se consultó remoto.
No se agregó ninguna dependencia; no hay versiones flotantes. Se usan APIs Web
(fetch inyectado, Response, AbortController, URL, timers). La compatibilidad Deno
no está certificada hasta ejecutar sus herramientas.

## Componentes

- adapters/http.ts: transporte sin retries, deadline, JSON exacto, errores sanitizados
  y señal de fallo administrativo de toda la invocación.
- adapters/jobs_adapter.ts: discover, claim, terminal evidence, mapping y finish.
- adapters/storage_adapter.ts: bucket fijo y namespace del claim, list/remove.
- adapters/timeout.ts: aborto real y helpers lease/deadline/presupuesto.
- tests/adapter_fakes.ts y cuatro nuevos archivos *_test.ts: respuestas sintéticas,
  integración del núcleo E2A y pruebas de aborto.

Los constructores son interfaces internas de servidor, no contratos HTTP públicos.
E2C debe construir StorageAdapter exclusivamente desde el claim validado por
JobsAdapter. JobsAdapter además registra sus claims congelados en WeakSet y no
acepta jobs fabricados/copias para consultar evidencia o finalizar intentos.
El servidor es confiable: esto no es una frontera contra código servidor malicioso.

## RPC y ledger

| Método | Contrato E1 / HTTP | Validación |
| --- | --- | --- |
| discover(limit) | POST discover_animal_photo_cleanup_jobs, p_limit | 1..5000; respuesta entera 0..limit; error nunca es cero |
| claim() | POST claim_animal_photo_cleanup_job, {} | 0 filas = sin job; 1 = validar; más de 1 = error |
| getTerminalEvidence(job) | GET sync_deletions | collection=animals, entity_id y user_id del claim, limit=2 |
| finish(job,result) | POST finish_animal_photo_cleanup_attempt | p_animal_id, p_lease_token, p_generation, p_outcome, p_error_code |

Claim lee los nombres reales tombstone_sequence, tombstone_operation_id y
tombstone_deleted_at; exige status leased, UUID canónicos, generation/sequence
positivos en rango PostgreSQL, lease_token y timestamps válidos sin truncarlos.
Una respuesta de claim perdida/malformada no se reintenta automáticamente: puede
haber dejado un lease real que deberá expirar.

JSON exacto valida sintaxis y transforma los tokens enteros a strings antes del
parse utilizado por los adaptadores. Ningún valor de la primera validación de
sintaxis se usa: sequence/generation se construyen desde el token decimal original
mediante BigInt, nunca desde Number. Los strings JSON y escapes se conservan.
La firma finish recibe p_generation como string decimal compatible con bigint en
PostgREST. El conteo SQL integer de discovery sí se convierte a Number acotado.

Ledger: cero filas produce terminalMismatch; más de una o schema malformado,
internal_error. Con una fila se usa compareTerminal de E2A para comparar toda la
identidad y microsegundos. Nunca se consulta animals, ausencia de animals ni
remote_photo_path. La ausencia/mismatch debe detener cleanup; E2C decidirá cómo
reportar el diagnóstico, sabiendo que el guard E1 puede rechazar finish si el
ledger dejó de ser consistente. No se repara ni se omite ese guard.

## Storage

Bucket animal-photos constante, no seleccionable por job/HTTP.
List exige folder exacto owner/animal del claim, limit 100, offset 0 y name asc.
No admite search, no recorre folders ni filtra entradas sospechosas. Una entrada
con id y metadata de archivo se normaliza a file; null/null a folder; las demás
a unexpected. El núcleo valida la página completa y rechaza namespaces inválidos.
Un fallo HTTP/JSON nunca se convierte en una lista vacía.

Remove exige 1..100 paths únicos del namespace enlazado y los revalida con
pagePaths E2A. Rechaza wildcard, folder-only, traversal y namespaces ajenos.
Solo usa Storage API, nunca SQL ni storage.objects. La respuesta debe ser un
array pero su inventario no demuestra eliminación: E2A siempre vuelve a listar.
No existen retries automáticos.

## Timeouts y lease

withDeadline usa AbortController, timer y una carrera para resolver incluso si un
mock ignora el aborto. No depende únicamente de Promise.race: transmite signal a
fetch y llama abort al vencer. El plazo incluye response.text(). Un plazo vencido
no inicia petición. Errores normalizados no contienen mensajes libres.
Abort local no demuestra cancelación del servidor; una eliminación o ACK puede
completar remotamente tras cortar la conexión.

leaseBudget toma min(leaseExpiresAt, invocationDeadline), resta margen por skew,
reserva tiempo para finish y no permite comenzar list/remove sin el presupuesto
completo por operación. Usa milisegundos conservadores solo para scheduling; no
modifica timestamps ni la comparación terminal exacta. Reloj inyectable, que E2C
debe mantener sin retrocesos; debe fijar una tolerancia de reloj razonable.
Defaults de helpers: request 5s, reserva finish 5s, skew 2s; no son configuración
remota validada. E2C debe enlazar storageDeadline a StorageAdapter, finishDeadline
a finish y el budget al core; discovery/claim usarán deadline de invocación.
No hay renovación de lease.

## Errores y fallos globales

Se conservan solo kind/status y códigos de una lista cerrada. 429 y SlowDown
son rate_limited; timeout/abort es timeout; network es storage_unavailable;
InternalError es internal_error; JSON/schema inesperado es internal_error.
401/403 administrativos activan fatalWorkerError incluso antes de consumir el
cuerpo. AccessDenied/InvalidJWT/errores de firma reconocidos también lo activan.
La señal es persistente por instancia compartida de HttpTransport y bloquea nuevas
peticiones. finish se niega a enviar reportes de un job después del fallo global.

E2C debe compartir ese transporte en la invocación, comprobar la señal después de
cada operación y detenerse inmediatamente, sin reclamar más jobs ni llevarlos a
quarantine. Los leases pendientes expiran. La clasificación conservadora no puede
probar si un 403 fue aislado; no se intenta resolverlo modificando jobs. Un fallo
operacional permission_denied que haya sido diagnosticado como aislado tiene
mapping E1 retry, pero no neutraliza el latch administrativo de este transporte.

## Finish y mapping

- observed_empty -> observed_empty / error null.
- storage_unavailable, rate_limited, timeout -> retry transitorio E1.
- internal_error, permission_denied, no_progress -> retry incierto E1; E1 cuenta
  tres fallos consecutivos antes de quarantine.
- terminal_mismatch, invalid_namespace, legacy_conflict -> quarantined estructural.
- budget_exhausted -> expire_lease (sin llamada finish).

Finish true = accepted; false = rejected por fencing/estado/expiración; error,
timeout o respuesta malformada = uncertain. No se reintenta automáticamente porque
el ACK puede haberse aplicado. not_sent distingue rechazo local/global y
lease_expiry la decisión explícita para presupuesto agotado. E2C debe reconciliar
un ACK incierto mediante el estado durable/futuras ejecuciones, no repetirlo a ciegas.

## Decisión budget_exhausted

Se recomienda y codifica opción B: dejar expirar lease, sin RPC ni cambio E1.
A (timeout) sería posible técnicamente pero inventaría un timeout y alteraría el
contador de incertidumbre. C (release/retry) y D (ampliar E1) necesitan contrato SQL
nuevo y revisión separada. Expirar conserva semántica y progreso ya realizado;
cuesta esperar hasta el fin del lease de 120s y no reinicia uncertain_failure_count.
E2C debe parar ese intento al recibir lease_expiry; no seguir eliminando con el
mismo lease ni afirmar ACK. Reclaim/re-list retoma el trabajo idempotentemente.

## Versioning y fases

Primera versión E2 soporta únicamente el bucket no versionado previamente validado.
List v1 no demuestra que no existan versiones históricas, delete markers o archivos
archivados. No se interpreta una propiedad genérica version como prueba de versioning;
no se intenta eliminar versiones históricas. legacy_conflict tiene mapping estructural,
pero no se inventa detección de una condición que este protocolo no puede certificar.
E2C/E2D deben validar esa precondición antes de ejecución real.

E2A motor puro; E2B adapters locales; E2C endpoint autenticado/ensamblaje;
E2D primera eliminación real autorizada; E2E scheduler.
Los cinco objetos reservados permanecen intactos respecto a esta intervención.
La cardinalidad procede de la evidencia del usuario, sin nueva consulta remota.

## Validación

Ejecutar Node local: node --test supabase/functions/animal-photo-cleanup/tests/*_test.ts
Resultado local: 273 tests, 273 pass, 0 fail (140 E2A + 133 E2B).
Además node --check en todos los TS nuevos y whitespace contra /dev/null para cada
archivo nuevo. No se ejecutaron pruebas Flutter ni SQL.

Deno validation: PENDING. command -v deno no encontró Deno; no se instaló ni se
modificó PATH. tsc tampoco está disponible. Node prueba ejecución/sintaxis, no
verifica tipos estáticos ni certifica compatibilidad o formato Deno. Antes de E2C
se requieren deno check, deno test y deno fmt --check, revisión del contrato HTTP
real en entorno autorizado y ensamblaje de plazos/fallo global/autenticación.

No deployment, secretos reales, service role real, jobs reclamados, discovery,
finish remoto, eliminación física, scheduler, commit ni push.
