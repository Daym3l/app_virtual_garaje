# Mi Garaje Virtual

App móvil Android para gestión de flota personal de vehículos. Registra combustible, kilometraje, mantenimientos y rutas de tus vehículos, con alertas y sincronización en la nube.

**Versión:** 0.3.0
**Plataforma:** Android (mobile-first)

## Características

- **Dashboard** — alertas urgentes de mantenimiento, resumen de vehículos, garantías activas
- **Kilometraje** — registro de odómetro con validación de cotas por fecha
- **Combustible / Energía** — se adapta al tipo de motor (gasolina/diésel o eléctrico), cálculo de consumo full-to-full
- **Mantenimiento** — multi-tipo, piezas estructuradas, categorías, estados (vencido/pronto/ok), intervalos por km y días
- **Rutas** — historial con tracking GPS y respaldo local offline
- **Notificaciones push** — alertas de mantenimiento vía FCM
- **Multi-vehículo** — coches, motos, camiones

## Stack

- **Flutter** (Dart, SDK ^3.7.2)
- **Supabase** — auth + base de datos PostgreSQL
- **Google Sign-In** — autenticación
- **Firebase Cloud Messaging** — notificaciones push
- **google_fonts** — Inter + JetBrains Mono

## Configuración

El proyecto requiere credenciales en un archivo `.env` en la raíz:

```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
GOOGLE_WEB_CLIENT_ID=...
```

Además se necesita `android/app/google-services.json` (Firebase) para FCM.

## Desarrollo

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

> **Importante:** las credenciales se inyectan vía `--dart-define-from-file=.env`. Sin esta bandera compilan vacías y la app falla al conectar con Supabase/Firebase.

## Build de release

```bash
flutter analyze
flutter build apk --release --dart-define-from-file=.env
```

APK generado en `build/app/outputs/flutter-apk/app-release.apk`.

## Estructura

```
lib/
  main.dart          # Entry point, Supabase init, AuthGate
  theme/             # Design system "Noche Clásica" (tema oscuro, acento azul)
  models/            # Modelos con fromJson factory
  services/          # Un servicio por dominio (auth, vehicle, dashboard, fcm...)
  screens/           # Una pantalla por archivo
  utils/             # Cálculos compartidos (consumo, etc.)
```

## Releases

Ver [releases en GitHub](https://github.com/Daym3l/app_virtual_garaje/releases).
