# FOTO A — aplicación manual

La migración local NO está desplegada automáticamente.

Antes de usar esta versión de Flutter, abrir el SQL Editor del proyecto Supabase
correcto y ejecutar TODO el contenido de
`migrations/20260924000100_animal_photos_foto_a.sql`.
Se puede volver a ejecutar: conserva datos, añade la columna si falta y recrea
solo las políticas nombradas por esta migración.

Crea/configura el bucket privado animal-photos, añade animals.remote_photo_path
y permite SELECT/INSERT para authenticated únicamente bajo su auth.uid().
Las políticas restrictivas impiden que políticas permisivas preexistentes abran
este bucket y bloquean UPDATE/DELETE incluso si existían permisos amplios.
No cambian las reglas de otros buckets ni el RLS de otras tablas.
No utilizar service_role en Flutter. Verificar el RLS existente de animals por
separado: esta migración no lo redefine.

## Compatibilidad

- SQLite conserva el esquema records/payload, sin migración física.
- El lector local acepta photoPath antiguo solo como localPhotoPath candidato.
- localPhotoPath explícitamente null tiene prioridad sobre el legado.
- Al guardar se emiten localPhotoPath y remotePhotoPath, nunca photoPath.
- Ambos escritores remotos usan una whitelist común y validan que la referencia
  sea usuario/animal/UUID.extensión. Referencias inválidas fallan antes del envío.
- animals.photo_path queda intacta, pero el código nuevo no la lee ni escribe.
- No se copia photo_path a remote_photo_path.
- El formulario conserva remotePhotoPath al editar y solo muestra fotos locales.
- No hay upload, firma, descarga, borrado ni cambios a los reintentos/outbox.
- Un animal sincronizado en FOTO A NO significa que su foto tenga respaldo remoto.
  FOTO B deberá detectar también fotos locales de registros ya sincronizados.

## Verificación en Supabase

Después de aplicar, comprobar en Storage que animal-photos es privado y en
Database que remote_photo_path existe. Con sesiones de prueba de dos usuarios,
verificar SELECT/INSERT propios, rechazo cruzado y anónimo, y rechazo de
UPDATE/DELETE. Esas comprobaciones requieren Supabase y no las sustituyen los
tests locales de Flutter. Usar la nueva versión en ambos teléfonos.

FOTO B añadirá subida durable e idempotente y su coordinación con la outbox.
FOTO C añadirá visualización remota. Esta fase no envía bytes de imágenes.
