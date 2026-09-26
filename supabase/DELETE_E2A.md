# DELETE E2A — núcleo puro de cleanup

## Alcance y checkpoint

Implementación local, sin adaptadores Supabase, sobre la rama
`feature/estructura-app-mvp`, HEAD inicial
`fc0e7b128358035b669c4ccb33cba1e0367eec41`, working tree inicialmente limpio.
E1 permanece intacto. Su validación remota posterior fue comunicada por el usuario;
las menciones históricas de E1C a «no aplicado» no describen ese estado posterior.

**NO remote Supabase. NO Storage real. NO service_role. NO cron.
NO physical deletion.** Los tests solo eliminan entradas de arrays en memoria.
No hay endpoint, SDK, secretos, SQL nuevo, migración, scheduler ni cambios Flutter.

## Componentes

En `functions/animal-photo-cleanup/`:

- `types.ts`: job, evidencia terminal, entradas, resultados y adapter abstracto.
- `namespace.ts`: UUIDs canónicos, namespace y validación completa de páginas.
- `terminal.ts`: comparación de identidad y timestamps exactos a microsegundos.
- `errors.ts`: clasificador de errores normalizados, sin texto sensible.
- `budget.ts`: interfaz inyectable; no reloj global ni valores de producción.
- `cleanup.ts`: algoritmo que solo utiliza esas interfaces.
- `tests/`: fakes deterministas y tests sin paquetes externos.

`PhotoStorage` está vinculado al bucket constante `animal-photos`; expone
`list(folder, options)` y `remove(paths)`. No recibe un bucket por petición.
`CleanupBudget` expone `canStartList`, `canStartRemove` y `canFinish`.
El resultado de remove es opaco: no determina cuántos objetos desaparecieron.

## Invariantes y algoritmo

1. Copiar la identidad del job antes del primer await.
2. Validar namespace, metadata del claim, máximo de batches y evidencia terminal.
3. Listar siempre con limit 100, offset 0 y name asc, sin search.
4. Validar la página completa antes de cualquier remove.
5. Si hay archivos, comprobar presupuesto y máximo de batches; eliminar paths
   exactos y volver a listar desde offset cero.
6. Comparar el conjunto anterior con el observado después del remove.
7. Exigir dos lecturas vacías consecutivas y margen de finalización para devolver
   `observed_empty`. Un objeto en la segunda lectura reinicia el proceso.

No se utiliza animals, remote_photo_path, estado local ni ausencia de fila.
La evidencia terminal exige collection=animals, entityId, userId, sequence,
operationId y deletedAt coincidentes. El núcleo no puede certificar la procedencia
ni frescura de un record inyectado: E2B deberá obtenerlo del ledger remoto.

## Namespace

Comparación con `20260924000300_animal_photo_cleanup_contract.sql` (E1 intacto):

| Regla | E1 | E2A después de revisión |
| --- | --- | --- |
| Owner | Igual a `auth.uid()::text`, UUID hexadecimal lowercase 8-4-4-4-12 | UUID lowercase 8-4-4-4-12 del job validado |
| Animal | UUID hexadecimal lowercase 8-4-4-4-12 | Igual |
| Filename UUID | Hexadecimal 8-4-4-4-12, admite mayúsculas y minúsculas | Igual, preservando case |
| Extensión | `[a-zA-Z0-9]+`, sin límite de longitud en el guard | Igual |
| Segmentos | Exactamente owner/animal/filename | Exactamente esos tres segmentos |

«Canónico» aquí describe formato y case; E1 no restringe versión/variant ni
excluye UUID nil. La extensión es ASCII, no una clase Unicode ni una decisión MIME.
Se retiraron las restricciones accidentales de filename lowercase y extensión
lowercase de máximo 16 caracteres. No se normaliza el nombre antes de remove.

La equivalencia es de gramática del path, no de autorización: E1 verifica sesión,
owner y ausencia de tombstone para INSERT; E2A recibe identidad del job y exige
la evidencia terminal para cleanup. E2B deberá verificar la procedencia del claim.

Se rechazan folders, duplicados, páginas de más de 100 entradas y nombres con
paths/escapes/traversal/espacios/newlines. No hay trim, decodeURIComponent ni
normalización de paths sospechosos. Un elemento inválido invalida toda la página,
incluso con 99 elementos válidos. No se atraviesan subcarpetas ni se borran
prefijos, carpetas o wildcards; los paths siempre pertenecen al namespace validado.

## Precisión terminal

Sequence y generation son bigint, con rango positivo de bigint PostgreSQL.
No se aceptan Number para estos campos. El futuro adapter debe preservar esa
precisión antes del parsing (convertir un Number ya redondeado no la recupera).

Timestamps: formatos ISO/SQL con T o espacio, zona Z o ±HH:MM y 0 a 6 dígitos
fraccionales. Se compara el instante exacto usando bigint de microsegundos.
Date solo valida el calendario y convierte segundos integrales; nunca recibe
la fracción. Offsets equivalentes comparan iguales. Se rechazan fechas inválidas,
precisión superior a microsegundos, zona ausente, infinity y leap seconds.

## Paginación, idempotencia y progreso

Nunca se incrementa offset. Al eliminar la primera página, la siguiente llamada
lee los elementos desplazados a esa misma posición. El máximo por remove es 100.

Una eliminación parcial se resuelve mediante re-list, aunque remove devuelva una
lista vacía. Desaparición concurrente, repetición de ejecución y reinicio después
de eliminar son seguros. Si una nueva foto aparece durante la segunda lectura
vacía, se elimina y se exige nuevamente doble vacío.

Si todos los paths anteriores siguen en la página observada después de remove,
se incrementa el contador de ciclos sin progreso. Si desaparece alguno se
reinicia, incluso si aparecen otros. Dos ciclos consecutivos producen
`retry/no_progress`. Mantener el mismo tamaño de página no significa estancamiento.
Esta métrica compara páginas observadas, no demuestra ausencia global de un path
que un upload concurrente pudo desplazar fuera de la primera página.

## Budget y resultados internos

El budget se consulta antes de list/remove y antes del resultado observado vacío.
Falta de margen produce `retry/timeout`, nunca éxito ni no_progress.
Los fakes prueban esos puntos determinísticamente, sin sleeps ni Date.now.

El máximo de batches es configurable, positivo y entero, default 20. Alcanzarlo
con elementos pendientes y progreso produce `retry/budget_exhausted`. Todavía se
permite verificar vacío después del último batch autorizado; completar exactamente
ese batch no implica error. No se inician más removes.

**budget_exhausted NO pertenece al contrato E1**. No existe mapping a finish en
E2A y no debe enviarse este resultado directamente a la RPC. E2B deberá decidir
cómo liberar/reintentar durablemente el job al alcanzar maxBatches con progreso,
mediante expiración segura u otra solución explícitamente aprobada. No se mapea
a no_progress ni se introduce una RPC nueva.

Los resultados internos no son ACKs SQL. Incluso `observed_empty` solo propone una
observación que E2B tendrá que persistir mediante el fencing de E1.

## Errores

El adapter abstracto devuelve un resultado discriminado con error normalizado
kind/status/code. El clasificador prioriza código específico sobre HTTP:
SlowDown+503 es rate_limited; InternalError+503 es internal_error.
401/403 son permission_denied; timeout es timeout; network es storage_unavailable.
Errores desconocidos o excepciones crudas se convierten en internal_error y no
se devuelven sus mensajes. Un 404 no significa namespace vacío.

La unión interna también contiene terminal_mismatch, invalid_namespace y
legacy_conflict. Los dos primeros son producidos por los validadores;
legacy_conflict queda reservado para diagnóstico posterior de infraestructura.
No se simula detección de versioning en esta fase.

## Validación local y tooling

Sin dependencias externas. Los tests usan los módulos incorporados `node:test` y
`node:assert/strict`; el núcleo no depende de APIs Node ni Deno.
Node 25.3.0, ya instalado, ejecuta TypeScript mediante type stripping:

```sh
node --test supabase/functions/animal-photo-cleanup/tests/*_test.ts
```

Resultado final: 140 tests, 140 pass, 0 fail, 0 skipped.
No se instalaron herramientas ni descargaron paquetes.

Deno no está instalado. Por tanto NO se ejecutaron `deno test`, `deno check` ni
`deno fmt --check`. Tampoco hay tsc/prettier en PATH. Node ejecuta los tests, pero
**no comprueba tipos estáticamente** ni certifica formato Deno. Esas validaciones
permanecen pendientes; no se presentan los resultados Node como resultados Deno.
**Deno validation: PENDING**. No bloquea el cierre lógico de E2A, pero es requisito
antes de desplegar E2C. Se comprobó únicamente `command -v deno`, sin instalarlo.
Cuando exista Deno, ejecutar test/check/fmt exclusivamente sobre E2A y resolver
cualquier diferencia de compatibilidad de sus módulos node integrados.

Se revisa sintaxis con `node --check` y whitespace con `git diff --check`, también
contra /dev/null para cada archivo untracked. No se ejecutan tests Flutter ni SQL.

## Cobertura

Escalas 0/1/3/100/101/1000/1001 y límite default con 2001; offset fijo y paths
exactos; páginas inválidas; doble-empty; late upload; parcial; desaparición;
crash conceptual; repetición; no_progress y reset; todos los puntos del budget;
max batches; errores de list/remove; mensajes no filtrados; ledger mismatch en
cada campo; precisión submilisegundo y bigint; UUIDs, extensiones y timestamps.
Todos los UUIDs son sintéticos. No se incluye el dataset de producción.

## Limitaciones y próximos pasos E2B

- No discovery, claim, finish, renovación, autorización HTTP ni scheduler.
- El caller/budget futuro debe usar una deadline conservadora ligada al lease;
  E2A valida su formato, no comprueba vigencia con un reloj externo.
- Un budget no cancela una Promise en vuelo. El adapter futuro debe implementar
  abort/timeouts; una cancelación cliente tampoco garantiza cancelación servidor.
- No consulta versioning, archivados, delete markers ni backend físico.
- Doble-empty no sustituye reconciliaciones; un upload puede terminar después.
- La comparación del ledger no evita cambios administrativos posteriores.
- Si E1 detecta ledger inconsistente, su trigger puede rechazar incluso finish
  de cuarentena. E2B no debe reparar el ledger ni saltarse ese guard.
- Falta mapping explícito de resultados internos a E1, manejo de ACK incierto y
  pruebas de integración real, siempre antes de autorización de borrado real.

No avanzar a E2B, desplegar ni activar cleanup como parte de esta fase.

## Separación de fases y estado remoto

- E2A: motor puro (esta fase).
- E2B: adapters.
- E2C: endpoint.
- E2D: primera eliminación real.
- E2E: scheduler.

Los 5 objetos reales siguen intactos respecto a esta intervención: no hubo acceso
ni operaciones remotas. La cantidad procede de la evidencia E1 del usuario, no de
una nueva consulta. Jobs reales reclamados por esta fase: 0.
