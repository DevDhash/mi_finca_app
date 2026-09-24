# FOTO D: offline, reintentos y caché privada

No requiere SQL, bucket ni policies nuevas. Conserva la outbox de FOTO B y la
referencia privada `remote_photo_path` de FOTO A/C.

## Comportamiento

- La foto original elegida permanece en `ApplicationDocumentsDirectory/animal_photos`.
  El upload y la publicación mantienen sus checkpoints pendientes en SQLite.
- Con la app abierta y sesión Supabase disponible, la outbox se procesa al iniciar,
  guardar, recuperar conexión o volver al primer plano. La espera de una subida se limita a 60 s (un resultado tardío puede dejar el
  objeto creado y se comprueba en el siguiente intento). Si quedan pendientes,
  reintenta tras 5 s, 15 s, 30 s, 1 min y después cada 5 min. Solo un worker activo.
  El modo offline manual pausa nuevos intentos. No cancela solicitudes ya iniciadas.
- La disponibilidad de Wi-Fi/datos no garantiza acceso a Internet: los errores
  reales mantienen pendientes y activan las pausas. Una sesión ausente pausa el
  worker; una sesión caducada depende de la renovación del SDK y sus errores.
- No hay servicio en segundo plano del sistema operativo. Con la app cerrada se
  conservan los pendientes; al volver se reinician los intentos desde SQLite.
- Para mostrar una foto: original local válido → caché privada en disco → descarga
  autenticada del bucket privado. Si falla la caché, permanece el mecanismo de
  signed URLs temporales de FOTO C como alternativa online. No se guardan URLs.
- La caché vive en `ApplicationSupportDirectory/animal_photo_cache/<user_id>/`.
  Usa un hash de la ruta remota como nombre; cambiar de foto cambia la clave.
  Verifica propietario, contenido decodificable y un máximo de 6 MiB por descarga.
  Es una carpeta privada de la app, sin cifrado adicional implementado aquí.
- Escritura temporal y renombrado al completar; al iniciar el servicio se retiran
  temporales interrumpidos. Las descargas de una misma ruta se comparten.
  Límite de caché de 100 MiB por cuenta: se descartan descargas antiguas según uso.
  No se eliminan originales ni archivos pendientes para liberar caché.
- Sin conexión, solo pueden verse originales o fotos ya descargadas que continúen
  en caché. No se descargan anticipadamente todas las fotos. La caché no modifica
  animales, fechas ni outbox. Las descargas visibles fallidas tienen hasta cuatro
  reintentos (5/10/20/40 s), además del botón manual y la reconexión.
- Cerrar sesión se bloquea si existen cambios pendientes o una foto local sin
  publicar. Mientras se verifica/cierra se bloquean nuevas escrituras. Tras un
  logout correcto se limpia SQLite y se intenta limpiar caché de la cuenta,
  originales locales e imágenes en memoria. Si el sistema de archivos impide la
  limpieza, no se restaura la sesión; el acceso a caché sigue validando la cuenta.
- No se borra ningún objeto remoto. La limpieza de objetos reemplazados queda
  para FOTO E; no hay eliminación general de entidades ni cascadas.

## Prueba manual en dos celulares

1. Instalar la nueva compilación en ambos (incluye `connectivity_plus`).
2. En A, activar modo avión, crear/editar animal con foto y guardar. Comprobar foto
   local y pendientes. Intentar cerrar sesión: debe pedir sincronizar primero.
3. Cerrar la app completamente y abrirla aún sin conexión: foto y pendientes deben
   seguir presentes. Restaurar conexión y mantener la app abierta: sin pulsar
   sincronizar, los pendientes deben publicarse.
4. En B, pulsar «Actualizar animales» y abrir la foto con conexión. Activar modo
   avión, cerrar y abrir la app: esa foto descargada debe seguir visible.
5. En A, reemplazar la foto offline y reconectar. En B, reconectar y actualizar:
   debe aparecer la nueva foto; volver a probar su lectura offline.
6. Cortar Internet conservando Wi-Fi y restaurarlo después: comprobar que los
   pendientes se recuperan con los reintentos, sin perder la foto.
7. Con cero pendientes, cerrar sesión e iniciar con otra cuenta: no debe mostrar
   fotos de la cuenta anterior. Al volver a la primera, descargar otra vez online.

La actualización del listado remoto sigue siendo la de FOTO C: no se añade
Realtime ni un pull automático general. Pruebas de dispositivos pendientes de
validación por el usuario; los tests automatizados usan dobles de red y SQLite.
