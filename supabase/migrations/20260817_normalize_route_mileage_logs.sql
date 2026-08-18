-- Normaliza los registros de kilometraje creados por rutas.
--
-- Antes de v0.5.1 esos registros se guardaban con la hora real de fin de ruta y
-- con decimales, mientras que los manuales usan mediodía UTC (día de calendario)
-- y enteros. Resultado: dentro de un mismo día una ruta de la tarde quedaba por
-- encima de un registro manual creado después, y las diferencias entre registros
-- salían descuadradas por los decimales.
--
-- Este script deja las filas antiguas con la misma convención que las nuevas.
-- Zona horaria de referencia: America/Havana (la del usuario). Cambiarla si la
-- flota pasa a otra zona.
--
-- Ejecutar por pasos en el SQL Editor de Supabase, revisando cada uno.

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 1 — Ver qué se va a cambiar (no modifica nada)
-- ─────────────────────────────────────────────────────────────────────────────

WITH afectados AS (
  SELECT
    ml.id,
    ml.vehicle_id,
    ml.date                                        AS fecha_actual,
    (
      ((ml.date AT TIME ZONE 'America/Havana')::date + time '12:00')
      AT TIME ZONE 'UTC'
    )                                              AS fecha_nueva,
    ml.mileage                                     AS km_actual,
    round(ml.mileage)                              AS km_nuevo,
    ml.notes
  FROM mileage_logs ml
  WHERE (
      EXISTS (SELECT 1 FROM routes r WHERE r.id = ml.id)
      OR ml.notes LIKE 'Ruta #%'
      OR ml.notes LIKE 'Ruta automática%'
    )
)
SELECT *
FROM afectados
WHERE fecha_actual <> fecha_nueva
   OR km_actual    <> km_nuevo
ORDER BY vehicle_id, fecha_actual;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 2 — Copia de seguridad de las filas afectadas
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS mileage_logs_backup_20260817 AS
SELECT ml.*
FROM mileage_logs ml
WHERE (
    EXISTS (SELECT 1 FROM routes r WHERE r.id = ml.id)
    OR ml.notes LIKE 'Ruta #%'
    OR ml.notes LIKE 'Ruta automática%'
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 3 — Normalizar fecha (mediodía UTC del día local) y redondear el odómetro
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

UPDATE mileage_logs ml
SET
  date = (
    ((ml.date AT TIME ZONE 'America/Havana')::date + time '12:00')
    AT TIME ZONE 'UTC'
  ),
  mileage = round(ml.mileage)
WHERE (
    EXISTS (SELECT 1 FROM routes r WHERE r.id = ml.id)
    OR ml.notes LIKE 'Ruta #%'
    OR ml.notes LIKE 'Ruta automática%'
  )
  AND (
    ml.date <> (
      ((ml.date AT TIME ZONE 'America/Havana')::date + time '12:00')
      AT TIME ZONE 'UTC'
    )
    OR ml.mileage <> round(ml.mileage)
  );

-- Revisar el número de filas afectadas antes de confirmar.
COMMIT;
-- ROLLBACK;  -- usar en su lugar si el conteo no cuadra

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 4 — Odómetro del vehículo sin decimales
--
-- El odómetro pasa a guardarse como entero. Se toma el mayor entre el valor
-- actual redondeado y el último registro de kilometraje, para no hacerlo
-- retroceder por el redondeo.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

UPDATE vehicles v
SET current_mileage = GREATEST(
      round(v.current_mileage),
      COALESCE((
        SELECT max(ml.mileage) FROM mileage_logs ml WHERE ml.vehicle_id = v.id
      ), 0)
    )
WHERE v.current_mileage <> round(v.current_mileage);

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 5 — created_at con valor por defecto
--
-- La columna existe pero las filas que inserta la app quedan con NULL, así que
-- no sirve para ordenar dentro de un mismo día. Con el default, los registros
-- nuevos sí llevan la hora real de inserción.
--
-- Las filas antiguas no tienen forma de recuperar su hora real: se rellenan con
-- la fecha del registro más un desplazamiento por odómetro, que es el único
-- orden fiable que queda (el odómetro solo avanza).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

ALTER TABLE mileage_logs
  ALTER COLUMN created_at SET DEFAULT now();

WITH ordenados AS (
  SELECT
    id,
    row_number() OVER (PARTITION BY vehicle_id, date ORDER BY mileage) AS orden
  FROM mileage_logs
  WHERE created_at IS NULL
)
UPDATE mileage_logs ml
SET created_at = ml.date + (o.orden * interval '1 second')
FROM ordenados o
WHERE ml.id = o.id;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 6 — Verificar
-- ─────────────────────────────────────────────────────────────────────────────

-- Solo los registros de rutas deberían estar a mediodía UTC: los manuales y los
-- de la web conservan su propia convención hasta que se ejecute
-- 20260818_normalize_all_mileage_log_dates.sql, que unifica la tabla entera.
SELECT ml.id, ml.vehicle_id, ml.date, ml.mileage, ml.notes
FROM mileage_logs ml
WHERE (
    EXISTS (SELECT 1 FROM routes r WHERE r.id = ml.id)
    OR ml.notes LIKE 'Ruta #%'
    OR ml.notes LIKE 'Ruta automática%'
  )
  AND (
    (ml.date AT TIME ZONE 'UTC')::time <> time '12:00'
    OR ml.mileage <> round(ml.mileage)
  )
ORDER BY ml.vehicle_id, ml.date;

-- Orden final tal como lo lee la app (fecha desc, luego orden de creación).
-- Sin filtro por vehículo, para poder ejecutar el script de una sola pasada.
SELECT vehicle_id, date, mileage, notes, created_at
FROM mileage_logs
ORDER BY vehicle_id, date DESC, created_at DESC
LIMIT 50;

-- ─────────────────────────────────────────────────────────────────────────────
-- Deshacer (si hiciera falta)
-- ─────────────────────────────────────────────────────────────────────────────

-- UPDATE mileage_logs ml
-- SET date = b.date, mileage = b.mileage
-- FROM mileage_logs_backup_20260817 b
-- WHERE ml.id = b.id;

-- Cuando todo esté comprobado:
-- DROP TABLE mileage_logs_backup_20260817;
