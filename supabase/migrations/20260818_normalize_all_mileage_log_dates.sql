-- Unifica las fechas de calendario a MEDIODÍA UTC en las tres tablas que las
-- guardan como timestamptz: mileage_logs, fuel_logs y maintenances.
--
-- Convención única (documentada en CLAUDE.md de la app y de la web):
--
--   Una fecha de calendario se ancla siempre a mediodía, nunca a medianoche.
--   · timestamptz de día  → el día a las 12:00 UTC
--   · columnas `date`     → texto 'YYYY-MM-DD' (sin hora, no se tocan aquí)
--   · instantes reales    → tal cual (routes.start_time/end_time)
--
-- Mediodía está a 12 horas de las dos medianoches, así que ninguna zona
-- horaria real puede correr el día al convertir en cualquiera de los dos
-- sentidos. Eso es lo que fallaba: convivían tres convenciones.
--
--   00:00:00+00  selector de solo-día antiguo. En UTC-4 esa medianoche es las
--                20:00 del día anterior: el registro se muestra corrido.
--   16:00:00+00  la web, que usaba mediodía LOCAL.
--   hora real    entradas antiguas de la app y rutas previas al arreglo.
--   12:00:00+00  convención correcta.
--
-- Día de destino:
--   · si la hora es exactamente 00:00 UTC, el día es el de la propia fecha UTC
--     (venía de un selector de solo-día: 2026-05-06 00:00Z significa 06/05).
--   · en cualquier otro caso, el día local (America/Havana), que es el día en
--     que el usuario vio y registró el dato.
--
-- Ejecutar por pasos en el SQL Editor, revisando cada uno.

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 1 — Ver qué se va a cambiar (no modifica nada)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION dia_a_mediodia_utc(ts timestamptz)
RETURNS timestamptz
LANGUAGE sql IMMUTABLE AS $$
  SELECT (
    (
      CASE
        WHEN (ts AT TIME ZONE 'UTC')::time = time '00:00'
          THEN (ts AT TIME ZONE 'UTC')::date
        ELSE (ts AT TIME ZONE 'America/Havana')::date
      END
    ) + time '12:00'
  ) AT TIME ZONE 'UTC';
$$;

SELECT 'mileage_logs' AS tabla, count(*) AS filas_a_cambiar,
       count(*) FILTER (WHERE date::date <> dia_a_mediodia_utc(date)::date) AS cambian_de_dia
FROM mileage_logs
WHERE date <> dia_a_mediodia_utc(date) OR mileage <> round(mileage)
UNION ALL
SELECT 'fuel_logs', count(*),
       count(*) FILTER (WHERE date::date <> dia_a_mediodia_utc(date)::date)
FROM fuel_logs
WHERE date <> dia_a_mediodia_utc(date)
UNION ALL
SELECT 'maintenances', count(*),
       count(*) FILTER (WHERE date::date <> dia_a_mediodia_utc(date)::date)
FROM maintenances
WHERE date <> dia_a_mediodia_utc(date);

-- Detalle de mileage_logs.
SELECT
  date                     AS fecha_actual,
  dia_a_mediodia_utc(date) AS fecha_nueva,
  date::date <> dia_a_mediodia_utc(date)::date AS cambia_de_dia,
  mileage                  AS km_actual,
  round(mileage)           AS km_nuevo,
  notes, vehicle_id, id
FROM mileage_logs
WHERE date <> dia_a_mediodia_utc(date) OR mileage <> round(mileage)
ORDER BY vehicle_id, date;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 2 — Copias de seguridad
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS mileage_logs_backup_20260818 AS SELECT * FROM mileage_logs;
CREATE TABLE IF NOT EXISTS fuel_logs_backup_20260818    AS SELECT * FROM fuel_logs;
CREATE TABLE IF NOT EXISTS maintenances_backup_20260818 AS SELECT * FROM maintenances;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 3 — Normalizar
--
-- El odómetro se redondea solo en mileage_logs. En fuel_logs y maintenances la
-- columna `mileage` se deja intacta: ahí el valor lo escribe el usuario y no
-- alimenta el odómetro del vehículo.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

UPDATE mileage_logs
SET date = dia_a_mediodia_utc(date),
    mileage = round(mileage)
WHERE date <> dia_a_mediodia_utc(date) OR mileage <> round(mileage);

UPDATE fuel_logs
SET date = dia_a_mediodia_utc(date)
WHERE date <> dia_a_mediodia_utc(date);

UPDATE maintenances
SET date = dia_a_mediodia_utc(date)
WHERE date <> dia_a_mediodia_utc(date);

-- Revisar los conteos antes de confirmar.
COMMIT;
-- ROLLBACK;  -- usar en su lugar si algo no cuadra

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 4 — Verificar
-- ─────────────────────────────────────────────────────────────────────────────

-- Ninguna fila debería salir: todo a mediodía UTC.
SELECT 'mileage_logs' AS tabla, id, date, mileage::text AS valor FROM mileage_logs
WHERE (date AT TIME ZONE 'UTC')::time <> time '12:00' OR mileage <> round(mileage)
UNION ALL
SELECT 'fuel_logs', id, date, mileage::text FROM fuel_logs
WHERE (date AT TIME ZONE 'UTC')::time <> time '12:00'
UNION ALL
SELECT 'maintenances', id, date, mileage::text FROM maintenances
WHERE (date AT TIME ZONE 'UTC')::time <> time '12:00';

-- Ningún día debe haberse corrido respecto al respaldo. Solo deberían aparecer
-- las filas que estaban a medianoche UTC, y con el mismo día que antes.
SELECT b.date AS antes, m.date AS despues,
       b.date::date AS dia_antes_utc,
       (m.date AT TIME ZONE 'America/Havana')::date AS dia_despues_local,
       m.notes
FROM mileage_logs m
JOIN mileage_logs_backup_20260818 b ON b.id = m.id
WHERE b.date <> m.date
ORDER BY m.vehicle_id, m.date;

-- Orden tal como lo lee la app (fecha desc, luego odómetro desc).
SELECT vehicle_id, date, mileage, notes
FROM mileage_logs
ORDER BY vehicle_id, date DESC, mileage DESC
LIMIT 50;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 5 — created_at con valor por defecto (opcional)
--
-- La app no lo usa para ordenar (ordena por odómetro), pero deja registrada la
-- hora real de inserción de aquí en adelante. Las filas viejas se rellenan por
-- orden de odómetro dentro de cada día, el único orden fiable que queda.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

ALTER TABLE mileage_logs ALTER COLUMN created_at SET DEFAULT now();

WITH ordenados AS (
  SELECT id, row_number() OVER (PARTITION BY vehicle_id, date ORDER BY mileage) AS orden
  FROM mileage_logs
  WHERE created_at IS NULL
)
UPDATE mileage_logs ml
SET created_at = ml.date + (o.orden * interval '1 second')
FROM ordenados o
WHERE ml.id = o.id;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Limpieza
-- ─────────────────────────────────────────────────────────────────────────────

-- Deshacer (si hiciera falta):
-- UPDATE mileage_logs m SET date = b.date, mileage = b.mileage
--   FROM mileage_logs_backup_20260818 b WHERE m.id = b.id;
-- UPDATE fuel_logs f SET date = b.date
--   FROM fuel_logs_backup_20260818 b WHERE f.id = b.id;
-- UPDATE maintenances t SET date = b.date
--   FROM maintenances_backup_20260818 b WHERE t.id = b.id;

-- Cuando todo esté comprobado:
-- DROP FUNCTION dia_a_mediodia_utc(timestamptz);
-- DROP TABLE mileage_logs_backup_20260818;
-- DROP TABLE fuel_logs_backup_20260818;
-- DROP TABLE maintenances_backup_20260818;
-- DROP TABLE mileage_logs_backup_20260817;
