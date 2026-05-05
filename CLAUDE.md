# Mi Garaje Virtual — CLAUDE.md

## Proyecto

App móvil Android para gestión de flota personal de vehículos.
Nombre: **Mi Garaje Virtual** | Versión: 1.0.0-beta
Target: Android (mobile-first, 390×844px base)

## Stack

- **Flutter** (Dart, SDK ^3.7.2)
- **Supabase** — auth + base de datos (PostgreSQL)
- **Google Sign-In** — único método de autenticación
- **google_fonts** — Inter + JetBrains Mono vía Google Fonts

## Estructura de archivos

```
lib/
  main.dart                  # Entry point, Supabase init, AuthGate
  theme/
    app_theme.dart           # AppColors + AppTheme.dark
  models/
    vehicle.dart             # Vehicle, FuelType, VehicleType
  services/
    auth_service.dart        # Google Sign-In → Supabase auth
    vehicle_service.dart     # CRUD vehículos
    dashboard_service.dart   # Datos del dashboard
  screens/
    login_screen.dart        # Pantalla de login
    shell_screen.dart        # TopBar + BottomNav + contenido
    dashboard_screen.dart    # Dashboard principal
```

## Design System — "Noche Clásica"

Tema oscuro profundo, acento azul eléctrico. **Pixel-perfect respecto a los prototipos HTML/JSX de referencia.**

### Colores (ver AppColors en app_theme.dart)

| Token | Hex |
|---|---|
| background | `#03070F` |
| surface | `#050E1C` |
| card | `#0A1828` |
| cardHover | `#0D1E30` |
| accent | `#5B9DFF` |
| accentDim | `rgba(91,157,255,0.20)` |
| textPrimary | `#E8EEF8` |
| textSecondary | `rgba(232,238,248,0.78)` |
| textTertiary | `rgba(232,238,248,0.55)` |
| danger | `#FF4D4D` |
| warning | `#FFB830` |
| success | `#3DCC7E` |
| borderSubtle | `rgba(91,157,255,0.12)` |
| gasolina accent | `#5B9DFF` |
| diesel accent | `#FFB830` |
| eléctrico accent | `#3DCC7E` |

### Tipografía

| Uso | Fuente | Tamaño | Peso |
|---|---|---|---|
| Título pantalla | Inter | 17px | 700 |
| Título sección | Inter | 20px | 700 |
| Subtítulo | Inter | 16px | 700 |
| Cuerpo | Inter | 13–14px | 400–600 |
| Etiqueta uppercase | JetBrains Mono | 9–11px | 400–700 |
| Dato numérico | JetBrains Mono | 16–26px | 700 |
| Botón principal | Inter | 14–15px | 700 |
| Botón tracking | JetBrains Mono | 15px | 800 |

### Espaciado y radios

- Padding pantalla: 14–16px horizontal
- Gap entre tarjetas: 8–10px
- Padding tarjeta: 12–14px
- BorderRadius tarjeta grande: 12px | interna: 8–10px
- BorderRadius botón: 10px | FAB: 16px | chip/pill: 20px
- Bottom sheet: 20px top, 0 bottom

### Sombras y animaciones

- FAB: `0 4px 20px accent50`
- Bottom sheet overlay: `rgba(0,0,0,0.75)`
- Transición hover botón: 0.15–0.2s ease
- Drawer slide: 0.3s cubic-bezier(0.4,0,0.2,1)
- Screen fade: opacity 0→1, 0.2s ease
- Bottom sheet appear: translateY(20px)→0, 0.3s ease
- Pulse dot: scale 1→1.5→1, 1s infinite
- Snackbar timeout: 2500ms

## Shell (TopBar + BottomNav + Drawer)

**TopBar** (~52px):
- Fondo `surface`, borde inferior `borderSubtle`
- Chip vehículo activo (tap → VehicleDrawer): fondo `card`, borde `accent40`, radius 20px
- Avatar: 32×32px, gradiente acento, borde `accent50`

**BottomNav** (5 tabs):
- Inicio | Kilometraje | Combustible | Mantenimiento | Rutas
- Icono activo: color accent + glow
- Label: JetBrains Mono 9px

**VehicleDrawer** (izquierda, 78% ancho):
- Transform translateX(-100%) → 0
- Overlay `rgba(0,0,0,0.5)`

**FAB** (bottom-right, 16px):
- Fondo accent, radius 16px, sombra `accent50`
- Press: scale(0.95)

**Snackbar**: bottom 70px, auto-dismiss 2500ms, animación slideUp

## Pantallas (orden de desarrollo)

1. **Login** — hero 42% + formulario 58%, Google Sign-In + email
2. **Dashboard** — alertas urgentes, resumen 3 tarjetas, acciones rápidas, vehículo activo
3. **Kilometraje** — header fijo con totales, lista registros, FAB, bottom sheet form
4. **Combustible/Energía** — adapta a tipo vehículo (gasolina/diesel vs eléctrico), gráfico barras
5. **Mantenimiento** — tabs categoría, tarjetas con estado (vencido/pronto/ok), modal con 16 tipos
6. **Rutas** — lista historial, FAB iniciar, tracking activo (GPS simulado), detalle ruta

## Base de datos Supabase

### Tablas principales

**vehicles**
- `id` uuid PK, `user_id` text, `brand`, `model`, `plate`, `color` text
- `vehicle_type` text (car/moto/truck), `engine_type` text (gasolina/diesel/electrico/hibrido)
- `year` int, `initial_mileage`, `current_mileage` numeric
- `fuel_tank_capacity`, `battery_capacity` numeric (nullable)
- `image_base64` text (nullable)
- `last_maintenance_date`, `last_maintenance_mileage` (nullable)

**fuel_logs** (combustible gasolina/diesel)
- `vehicle_id` uuid, `date` timestamptz, `liters`, `cost`, `mileage`, `cost_per_liter` numeric
- `station` text, `is_tank_full` bool, `consumption` numeric (nullable)

**energy_logs** (cargas eléctricas)
- `vehicle_id` uuid, `date` date, `odometer`, `initial_level`, `final_level`, `energy_added` numeric
- `connector_type` text (nullable), `location` text (nullable)

**mileage_logs**
- `vehicle_id` uuid, `mileage`, `date` timestamptz, `notes` text

**maintenances**
- `vehicle_id` uuid, `date` timestamptz, `type`, `description`, `service_category` text
- `mileage`, `cost` numeric, `is_completed`, `is_urgent` bool
- `next_mileage` numeric (nullable), `next_date` timestamptz (nullable)

**routes**
- `vehicle_id` uuid, `start_time`, `end_time` timestamptz
- `points` jsonb, `total_distance`, `average_speed` numeric, `notes` text

**user_profiles**
- `id` uuid, `email`, `display_name`, `photo_url` text
- `role`, `membership`, `membership_status` text
- `legacy_firebase_uid` text (nullable)

**user_settings**
- `user_id` uuid, `distance_unit`, `fuel_unit`, `theme` text
- `maintenance_alerts` bool

## Convenciones de código

- Idioma UI: **español**
- Servicios en `lib/services/` — uno por dominio, acceso vía `Supabase.instance.client`
- Modelos en `lib/models/` con `fromJson` factory
- Screens en `lib/screens/` — un archivo por pantalla
- Widgets reutilizables dentro del screen que los usa; extraer a `lib/widgets/` solo si se reutilizan en 2+ screens
- Usar `AppColors.*` y `AppTheme.*` — nunca hardcodear colores
- Fuentes vía `google_fonts`: `GoogleFonts.inter()` y `GoogleFonts.jetBrainsMono()`
- Sin comentarios salvo que el motivo sea no obvio
- Sin manejo de errores para casos imposibles; validar solo en bordes del sistema (input usuario, respuestas Supabase)

## Flujo de autenticación

```
AuthGate (main.dart)
  → session == null → LoginScreen
  → session != null → ShellScreen
Supabase.onAuthStateChange reactivo — no polling
```

## Desarrollo pantalla a pantalla

Implementar **una pantalla a la vez**, en el orden listado arriba.
Confirmar con el usuario antes de pasar a la siguiente.
