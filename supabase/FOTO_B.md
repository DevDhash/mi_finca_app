# FOTO B — subida durable

Implementa exclusivamente la subida y publicación de la referencia. Requiere la
migración FOTO A ya aplicada. No hay SQL nuevo ni cambios de policies.

## Flujo

1. El picker copia la foto a la carpeta privada existente.
2. AnimalLocalDataSource guarda el animal y un intent local `_photoUpload` en
   una sola transacción SQLite. Incluye propietario, UUID de versión y archivo.
3. El flujo existente de guardado inicia sync. También se puede utilizar
   «Sincronizar ahora». Dos solicitudes simultáneas comparten un solo worker.
4. Antes de subir se persisten destino, SHA-256 y MIME. Se admiten imágenes de
   hasta 6 MiB; una imagen mayor permanece pendiente, sin borrarse.
5. Se llama al SDK con sesión autenticada y `upsert: false`.
6. Se guarda `remotePhotoPath` y el estado `uploaded` en SQLite.
7. Se publica el animal en Supabase. Solo entonces se marca `published` y
   `pending = 0`, si el snapshot local no ha cambiado.

La ruta es `<user_id>/<animal_id>/<uuid>.<extensión>`.
Un reemplazo crea un UUID diferente. No se elimina el objeto anterior.

## Durabilidad y límites

- Si falla Storage, el archivo y destino siguen pendientes. Si falla el upsert de
  animals después del upload, solo se reintenta la publicación.
- Si se pierde la respuesta de Storage, un reintento usa el mismo destino. Solo
  un error explícito de duplicado inicia una consulta de metadatos; se exige que
  coincidan SHA-256 y tamaño. No se descarga la imagen para comprobarla.
- El hash se almacena como metadata del objeto, nunca la ruta del dispositivo.
- Se compara el snapshot completo en SQLite al aplicar respuestas y confirmar:
  una edición o reemplazo concurrente no queda confirmado por una respuesta vieja.
- El guardado local conserva el checkpoint aunque el formulario aún tenga una
  instancia antigua del animal.
- Se comprueba el propietario local y la sesión activa antes de subir/publicar.
- Fotos antiguas de FOTO A con archivo local y sin referencia remota se incorporan
  al pendiente, incluso cuando el animal ya estaba sincronizado. Archivos ausentes
  permanecen con error `missing_file`; no se inventan referencias remotas.
- Errores locales quedan en `_photoUpload.lastError`; el contador de pendientes
  existente sigue visible. No hay nueva pantalla de diagnóstico en esta fase.
- Reabrir la app conserva los checkpoints; continuar requiere guardar o pulsar
  sincronización. Reconexión automática, backoff y trabajo en segundo plano son
  FOTO D.
- El logout conserva su comportamiento anterior: tras advertir, puede eliminar
  los datos locales pendientes. Para esta prueba no cerrar sesión con pendientes.
  La protección/segregación del logout sigue pendiente para FOTO D.
- No se resuelven conflictos entre dos dispositivos ni se descarga su estado.
  La visualización remota y signed URLs corresponden a FOTO C.
- No hay limpieza de archivos/objetos (FOTO E), borrados de entidades o tombstones.

## Prueba manual en un teléfono

1. Mantener la sesión de una cuenta de prueba; crear un animal con foto.
2. Confirmar guardado local y desaparición del pendiente tras sincronizar.
3. En Supabase, comprobar el objeto privado bajo usuario/animal y la columna
   animals.remote_photo_path apuntando a ese objeto, sin URL ni ruta local.
4. Activar modo offline manual, guardar otra foto y cerrar/reabrir la app.
   Reintentar con «Sincronizar ahora» al tener conexión; verificar el mismo destino.
5. Provocar fallo de red durante upload y repetir. No debe perder el archivo ni
   publicar una referencia antes de confirmar la subida.
6. Reemplazar la foto: debe aparecer otro objeto, conservando el anterior.
7. No esperar que otro teléfono muestre la imagen todavía: eso es FOTO C.

Las pruebas de Storage del repositorio usan el SDK real con HTTP simulado; no
sustituyen esta comprobación con el proyecto Supabase y su RLS desplegado.
