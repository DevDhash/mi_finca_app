# DELETE E1C — contrato materializado, validación local

Estado: validado en PostgreSQL 17 desechable; NO aplicado a Supabase remoto.
Checkpoint inicial: `8f93b15e810ff32808e8e3776b0f122dd20acff9`, rama
`feature/estructura-app-mvp`, árbol limpio. No cambios Flutter, commit ni push.

## Alcance

La única migración nueva es
`migrations/20260924000300_animal_photo_cleanup_contract.sql`: timestamp siguiente
a FOTO A (`...00100`) y DELETE A (`...00200`). Crea una tabla, cinco funciones,
tres índices parciales además de PK/UNIQUE, un trigger sobre jobs y una policy de
jobs. Refuerza exclusivamente `animal_photos_insert_guard`. No contiene worker,
cron, Storage API, eliminación física ni trigger sobre sync_deletions.

La fuente durable es sync_deletions; cada animal tiene un job. FK a sequence,
sin cascada y sin FK a animals. Las referencias históricas y movimientos no se
modifican. No usa records.pending. Las funciones permanecen SECURITY INVOKER con
search_path vacío. El rol servidor confiable usa discovery/claim/finish; sus
privilegios administrativos no constituyen una frontera contra un servidor
malicioso. Clientes no tienen acceso a jobs ni EXECUTE de esas funciones.

La evidencia remota REPORTADA por el usuario es cuatro tombstones consistentes y
cinco objetos, distribuidos 3/0/1/1. E1 no procesa esos jobs ni toca esos objetos.
El harness reproduce esa cardinalidad con UUIDs sintéticos, no con datos reales.

## Revisión/correcciones respecto de E1B

- internal_error, permission_denied y no_progress se reportan como retry. Dos
  fallos consecutivos inciertos reprograman; el tercero pone en quarantined.
  Se agregó uncertain_failure_count, acotado a 0..3. Puede mezclar esos tres
  códigos: son una misma clase incierta. Claim/crash no lo reinicia. Un resultado
  exitoso o claramente transitorio lo reinicia. No se permite solicitar
  cuarentena inmediata usando uno de esos códigos.
- storage_unavailable, rate_limited y timeout siempre reintentan, con backoff
  hasta cinco minutos. No se abandona por cantidad de timeouts. El backoff usa
  attempt_count acumulado (incluye verificaciones), por lo que un job antiguo
  puede usar directamente el máximo de cinco minutos.
- terminal_mismatch, invalid_namespace y legacy_conflict admiten cuarentena
  explícita tras diagnóstico del futuro worker. No se guardan mensajes libres.
- REVIEW: se sustituyó la igualdad textual de no_update/no_delete por una
  gramática acotada y anclada de `bucket_id <> 'animal-photos'`. Tolera espacios,
  paréntesis, identificador entre comillas y cast text del literal; nunca elimina
  espacios dentro del literal ni acepta OR/AND. No pretende probar equivalencia
  de SQL arbitrario. PUBLIC es un único elemento: no hay orden de array ambiguo.
  Los nombres de comando/permisividad son valores normalizados de pg_policies.
  Se prueba el DO real extraído de la migración, incluyendo drift rechazado.
- Claim/finish rechazan aislamiento distinto de READ COMMITTED con SQLSTATE 0A000.
- E1 sigue siendo instalación única. Un rerun aborta sin sobrescribir jobs;
  discovery/backfill sí es idempotente y reconstruye filas faltantes.
- No se encontró error de compilación en las funciones propuestas de E1B bajo
  PostgreSQL 17. Durante el desarrollo se corrigió una aserción CASE del harness
  y una carrera del runner con el servidor temporal de inicialización de Docker.
  El resultado final se obtuvo repitiendo desde un contenedor vacío.

La validación de path usa IF antes del cast; no confía en orden de AND. Admite
las extensiones alfanuméricas de Flutter, no una whitelist JPG/PNG. Owner y animal
son carpetas UUID canónicas; filename UUID/extensión. Permite subir antes de que
exista animals si no hay tombstone propio. No consulta animales ajenos.

Un snapshot de autorización previo al tombstone todavía puede admitir un upload
en vuelo. E1 no revoca HTTP ni cancela esa operación. Observed_empty programa una
revisión posterior: un minuto inicialmente y luego intervalos según antigüedad
del tombstone hasta semanal. E2 debe implementar esa reconciliación; aún no existe
scheduler. Fencing SQL no impide que un worker viejo termine una llamada externa.

## Ejecutar localmente

Requisitos: Docker disponible y la imagen `postgres:17-alpine`.

```sh
bash supabase/tests/run_delete_e1_local.sh
```

El runner crea un contenedor propio con `--network none`, sin puertos y con el
árbol supabase montado read-only. Usa un cluster vacío y una base cuyo nombre se
verifica. Nunca utiliza URL, claves, configuración de enlace ni CLI Supabase.
Detiene/elimina su contenedor al finalizar y conserva logs temporales cuya ruta
imprime. La contraseña trust es solo para este contenedor aislado.

El esquema original de dominio no está versionado íntegramente. El harness
explicita una base mínima de auth, las cinco tablas y storage, concede una policy
Storage deliberadamente amplia, y aplica TODAS las migraciones versionadas en
orden: FOTO A, DELETE A y E1. También prueba rollback de E1 previo a actividad y
reaplica E1. No es una reconstrucción integral de Supabase desplegado.

No hay Supabase CLI ni config.toml local en el proyecto. No se ejecutó
`supabase db reset`. La validación equivalente es PostgreSQL + fixture explícito,
NO el servidor HTTP Storage, backend S3, JWT verificado por gateway ni trigger
nativo protect_delete. Se omite ese trigger en el fixture para demostrar que las
policies por sí mismas bloquean DELETE, sin que el trigger enmascare una regresión.
La policy INSERT se prueba con INSERT real en storage.objects bajo authenticated,
no solo llamando al helper. El servidor remoto no fue contactado.

## Resultado final

57 comprobaciones aprobadas; runner salida 0 en un cluster nuevo.

| IDs | Cobertura |
|---|---|
| 1–9 | INSERT real + helper: nuevo, activo, terminal, referencia NULL/stale, owner, UUID y paths |
| 10–11 | UPDATE/DELETE bloqueados incluso con grants/policy permisiva amplia |
| 12–15 | Cuatro jobs, idempotencia completa, cero y múltiples objetos |
| 16–20 | Clientes sin escritura/lectura jobs; anon sin upload/RPC |
| 21–25 | Retry DELETE A, anti-resurrección, movimientos, payload/foto y cinco objetos intactos |
| 26 | Dos sesiones simultáneas: segundo claim salta la fila bloqueada |
| 27–30 | Expiración, token/generation antiguos, reconstrucción, nueva verificación |
| 31–34 | INVOKER ve ledger propio, no revela ajeno, malformed sin cast, upload antes del UPSERT |
| 35–37 | Funciones/triggers previos intactos, doble claim secuencial, ACK expirado |
| 38–39 | Tres códigos inciertos: retry/retry/quarantine; timeout reinicia incertidumbre |
| 40–41 | Dos discovery concurrentes: uno inserta, el otro no duplica |
| 42 | Todos los 34 casos obligatorios tienen resultado |
| 43 | Rollback operativo y rerun rechazados; checksum jobs intacto |
| 44–46 | Extensiones, RPC vedadas al cliente, límites de discovery |
| 47–50 | Owner inmutable, no cuarentena inmediata incierta, reset tras éxito, aislamiento rechazado |
| 51–52 | Rollback intermedio: objetos E1 ausentes e INSERT terminal real con guard FOTO A, revertido |
| 53–54 | Preflight real: baseline/cosmética aceptados; OR true, literal distinto y operador distinto rechazados |
| 55–57 | Ledger y otras policies intactos; cinco funciones INVOKER con search_path vacío |

Las dos sesiones concurrentes usan un punto de espera observable en
pg_stat_activity; no se confunde doble llamada secuencial con concurrencia.

## Rollback

`tests/delete_e1_rollback_local.sql` es SOLO un harness local con comprobación de
nombre de base. Restaura la policy INSERT FOTO A y retira exclusivamente objetos
E1 si los jobs son backfill sin actividad. No usa CASCADE. Elimina únicamente jobs
reconstruibles del fixture, nunca objetos Storage. Tras intentos/leases/verificación
aborta y conserva los jobs. Para rollback remoto se necesita revisión y autorización
separada; no ejecutar el harness en SQL Editor. Restaurar el guard antiguo vuelve a
permitir uploads terminales: detener el futuro worker antes de cualquier rollback.

## Antes de autorizar aplicación remota

- Revisar diff y contrato de tres fallos inciertos; E2 aún debe clasificar errores.
- Validar la configuración completa Supabase/Storage API en entorno no productivo,
  incluidos signed URLs, duplicate recovery, trigger nativo y errores HTTP reales.
- Confirmar nuevamente precondiciones/versiones/grants del servidor si cambian.
- Conservar los cinco objetos reales para E2: esta fase NO los elimina.
- Sin cron/worker aún no hay progreso automático de cleanup; solo el contrato.

No se ejecutaron format/analyze/test/build Flutter: no se modificó Dart y el alcance
solicitado es SQL. Compatibilidad revisada estáticamente con AnimalPhotoUpload,
AnimalRemotePayload y SupabaseAnimalPhotoStorage.

## Cierre E1C-REVIEW

Se leyó la migración completa, no el borrador E1B. Se corrigieron dos carencias:
comparación textual frágil y ausencia de comprobación intermedia del rollback.
El test 12 ahora valida también el estado inicial pending y contadores/leases.
Los 50 resultados originales contienen escenarios reales sobre las migraciones;
42 es una comprobación de cobertura, no un escenario independiente. 44 verifica
el helper, no HTTP. El fixture mínimo y las funciones auth siguen siendo simulados.
La evidencia Q1–Q15 fue aportada por el usuario; no se volvió a consultar remoto.

Veredicto: READY FOR CONTROLLED REMOTE APPLY, condicionado a que siga vigente esa
configuración y a aplicación con rol administrativo propietario autorizado.
No significa E2 implementado ni validación del servicio HTTP de Storage.
El preflight no es una reconstrucción exhaustiva de Q1–Q15: no comprueba las
versiones HTTP, todos los grants de esquema ni las definiciones completas de las
policies SELECT/insert_own. Las conserva; incompatibilidades SQL abortan la
transacción. Nombres E1 preexistentes también abortan, nunca se reemplazan.
Los cuatro jobs previstos son todos pending, incluido el de cero objetos.
No hay lectura de storage.objects en la migración: el backfill usa solo ledger.
La FK RESTRICT nueva impide borrar/modificar sequences del ledger referenciadas,
un efecto intencionado sobre futuras operaciones administrativas.
No se añadió identity sequence. El índice PK y el UNIQUE se crean junto con la tabla.
No se aplicó SQL remoto, ni se modificó Flutter, ni se hizo commit/push.
