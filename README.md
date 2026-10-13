# Sistema de Gestión Administrativa CECyTEO

Aplicación web basada en el prototipo HTML entregado. Incluye autenticación, tablero de procesos, estados y prioridades, búsqueda y filtros, repositorio privado de evidencias, directorio de usuarios, administración de cuentas sin envío de correo e informe imprimible. Está configurada para Supabase Free y despliegue en Vercel desde un repositorio de GitHub.

## Requisitos

- Node.js 20.19+ o 22.12+.
- Un proyecto Supabase Free.
- Un repositorio de GitHub conectado al proyecto de Vercel.

## Configuración de Supabase

1. Crea un proyecto en el plan Free y conserva la URL y la llave publishable del proyecto. No uses la llave `service_role` en el navegador.
2. En SQL Editor, ejecuta `supabase/migrations/20261013000100_initial_schema.sql`.
3. Crea el primer usuario desde **Authentication → Users → Add user**. En SQL Editor, asigna ese usuario como administrador (sustituye el UUID):

   ```sql
   update public.profiles set role = 'Administrador' where id = 'UUID_DEL_USUARIO';
   update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"Administrador"}'::jsonb where id = 'UUID_DEL_USUARIO';
   ```

   Cierra sesión y vuelve a entrar para renovar el token con el rol administrativo.
4. Desactiva el registro público en **Authentication → Settings → User Signups**. El administrador creará usuarios desde la aplicación; se generará una contraseña temporal para entregar directamente a cada persona, sin depender de correo SMTP.
5. Despliega la función de administración de cuentas desde la raíz del proyecto:

   ```sh
   supabase functions deploy admin-manage-users
   ```

   La plataforma inyecta las claves de servidor en Edge Functions. No las copies al frontend.

## Ejecución local

```sh
npm install
cp .env.example .env.local
```

Completa `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` en `.env.local`, luego:

```sh
npm run dev
```

## Publicación en Vercel

1. Sube esta carpeta a un repositorio de GitHub y conéctalo al proyecto de Vercel. El repositorio configurado como público hace visible el código fuente.
2. En **Vercel → Project → Settings → Environment Variables**, define `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` para **Production**, **Preview** y **Development**.
3. Vercel detecta Vite automáticamente. Usa `npm run build` como comando de compilación y `dist` como directorio de salida.
4. Cada cambio en la rama conectada inicia un nuevo despliegue. Los valores de las variables se incluyen durante la compilación, así que después de modificarlos hay que crear un nuevo despliegue.

La llave publishable está diseñada para el navegador y los datos quedan protegidos por RLS. Nunca incluyas `service_role` ni llaves secretas en el código, en GitHub o en variables `VITE_*`. La función de administración se despliega por separado con el flujo manual `.github/workflows/deploy-supabase-function.yml`, que requiere los secretos `SUPABASE_ACCESS_TOKEN` y `SUPABASE_PROJECT_REF` en GitHub Actions.

## Roles y datos

- Administrador: acceso al directorio completo, alta y restablecimiento de cuentas, y borrado de actividades/evidencias.
- Personal administrativo, docente y supervisor: acceso autenticado al tablero, actualización de actividades y carga de evidencias.
- Los siete procesos del prototipo se insertan como datos iniciales una sola vez.
- Los archivos son privados, tienen un límite de 10 MB y se descargan mediante URL temporal autenticada.
- Las contraseñas temporales se muestran una sola vez al administrador. El usuario debe cambiarlas al iniciar sesión.
- Los perfiles y actividades se comparten dentro del espacio institucional. Las políticas RLS están en la migración.

## Límites del plan gratuito

Supabase Free incluye hasta 2 proyectos activos, 500 MB de base de datos por proyecto, 1 GB de Storage, 5 GB de transferencia y 500,000 invocaciones de Edge Functions. Los proyectos con poca actividad pueden pausarse después de 7 días; no incluye respaldos automáticos. Al superar cuotas, renovar el servicio sin costo puede requerir esperar al siguiente periodo o reducir uso. No se activan add-ons ni planes pagos en este proyecto. Consulta los [límites de facturación de Supabase](https://supabase.com/docs/guides/platform/billing-on-supabase) y la [disponibilidad de GitHub Pages en GitHub Free](https://docs.github.com/en/pages/getting-started-with-github-pages).

El prototipo incluía usuarios ficticios y un selector que permitía suplantarlos. La aplicación utiliza cuentas autenticadas y permisos comprobados en Supabase.
