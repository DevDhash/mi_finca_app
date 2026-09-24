# FOTO C — visualización privada en otro dispositivo

No requiere migraciones SQL nuevas. Usa el bucket privado y SELECT de FOTO A,
además de las referencias publicadas por FOTO B.

## Probar en dos celulares

1. Instalar esta versión en ambos y entrar con la misma cuenta.
2. En A, guardar o reemplazar una foto y sincronizar hasta publicar la referencia.
3. En B, abrir Animales y tocar el icono de recarga («Actualizar animales»).
   Funciona aunque haya cero pendientes. No requiere salir de la cuenta.
4. La foto debe aparecer en lista, detalle, formulario y selección por lote.
5. Reemplazar la foto en A, sincronizar y repetir la actualización en B:
   debe aparecer el nuevo objeto, no la foto local antigua.
6. Editar algo offline en B y actualizar: el registro pendiente debe conservarse.
7. Quitar la conexión: las fotos locales siguen funcionando; las fotos que B solo
   conoce remotamente pueden mostrar placeholder. La caché en disco es FOTO D.

«Sincronizar ahora» conserva su función de subida. «Actualizar animales» descarga
la colección de animales explícitamente. No se implementó sincronización general
de potreros, gastos ni movimientos, ni polling/Realtime.

## Lectura y fusión

El arranque mantiene lectura local inmediata. Cuando no hay animales locales,
se conserva la carga inicial remota, ahora usando la misma fusión protegida.
La actualización explícita consulta aunque la colección local tenga datos.

Antes del GET se captura el estado local. La fusión es transaccional:
- Omite registros pendientes al inicio o al recibir la respuesta.
- Omite cualquier registro cambiado durante la petición, incluso si ya se subió.
- Conserva fotos locales que todavía no se han publicado.
- Para registros sin cambios pendientes acepta el estado del servidor, sin
  depender de la sincronización de relojes de los teléfonos.
- Mantiene el archivo local y checkpoint publicado si la referencia no cambió.
- Si cambió, retira la referencia local antigua y su checkpoint; no borra archivos.
- No considera una ausencia en la respuesta como una instrucción de eliminación.
- Un fallo remoto no vacía SQLite. Una sesión distinta o cerrada impide fusionar.

La consulta usa la selección existente de Supabase: no añade paginación general
ni resolución de conflictos entre cambios simultáneos de dos teléfonos.

## Imágenes y firmas

AnimalPhotoAvatar prioriza el archivo local. Si falta o no se puede decodificar,
solicita la imagen remota a través de una URL firmada. Las cuatro ubicaciones
existentes usan el mismo componente.

La firma usa la sesión del usuario, valida usuario/animal/ruta y dura 600 segundos.
Se comparte en memoria por referencia mientras hay consumidores. Se renueva
aproximadamente a los 570 segundos mientras esté observada.
Un 401/403 de imagen permite una renovación adicional; si vuelve a fallar se
ofrece «Reintentar foto». Otros fallos muestran ese placeholder sin bucles.
La sesión invalida los providers y una firma tardía de otra sesión se descarta.

No se persisten URLs firmadas ni se añaden rutas locales a payloads remotos.
Flutter puede retener imágenes en su caché habitual de memoria, pero no se ha
implementado descarga/cache en disco ni garantía offline para fotos remotas.

Una URL firmada es una credencial temporal: quien la tenga puede utilizarla hasta
que venza. La invalidación de la UI al cerrar sesión no revoca una URL ya emitida.
Referencia oficial:
https://supabase.com/docs/guides/storage/serving/downloads

## Alcance pendiente

FOTO D: caché durable, reconexión/backoff y protección del logout con pendientes.
FOTO E: limpieza física de fotos antiguas.
No se modificaron SQL, policies, eliminación de entidades ni tombstones.
Las pruebas usan SDK/HTTP simulado y widgets; falta la comprobación física en B.
