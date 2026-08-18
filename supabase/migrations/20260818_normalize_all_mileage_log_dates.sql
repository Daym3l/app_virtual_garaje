-- Unifica la fecha de TODOS los registros de kilometraje a mediodía UTC.
--
-- Continuación de 20260817_normalize_route_mileage_logs.sql, que solo tocó los
-- registros creados por rutas. Quedaron tres convenciones distintas conviviendo:
--
--   00:00:00+00  selector de fecha antiguo (solo día). En UTC-4 esa medianoche
--                es las 20:00 del día anterior: al mostrarse en hora local el
--                registro se corre un día.
--   16:00:00+00  la web: mediodía local (12:00 en UTC-4).
--   hora real    entradas antiguas de la app y de rutas previas al arreglo.
--   12:00:00+00  convención actual de la app.
--
-- Todas pasan a mediodía UTC, que es día de calendario en cualquier zona
-- razonable y deja el orden dentro del día en manos del odómetro.
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

WITH objetivo AS (
  SELECT
    ml.id,
    ml.vehicle_id,
    ml.date AS fecha_actual,
    (
      (
        CASE
          WHEN (ml.date AT TIME ZONE 'UTC')::time = time '00:00'
            THEN (ml.date AT TIME ZONE 'UTC')::date
          ELSE (ml.date AT TIME ZONE 'America/Havana')::date
        END
      ) + time '12:00'
    ) AT TIME ZONE 'UTC' AS fecha_nueva,
    ml.mileage AS km_actual,
    round(ml.mileage) AS km_nuevo,
    ml.notes
  FROM mileage_logs ml
)
SELECT
  fecha_actual,
  fecha_nueva,
  fecha_actual::date <> fecha_nueva::date AS cambia_de_dia,
  km_actual,
  km_nuevo,
  notes,
  vehicle_id,
  id
FROM objetivo
WHERE fecha_actual <> fecha_nueva
   OR km_actual <> km_nuevo
ORDER BY vehicle_id, fecha_actual;

-- Cuántas filas cambian de día (las de medianoche UTC, que hoy se muestran
-- corridas). Debería coincidir con las que están a 00:00:00+00.
WITH objetivo AS (
  SELECT
    ml.date AS fecha_actual,
    (
      (
        CASE
          WHEN (ml.date AT TIME ZONE 'UTC')::time = time '00:00'
            THEN (ml.date AT TIME ZONE 'UTC')::date
          ELSE (ml.date AT TIME ZONE 'America/Havana')::date
        END
      ) + time '12:00'
    ) AT TIME ZONE 'UTC' AS fecha_nueva
  FROM mileage_logs ml
)
SELECT count(*) AS cambian_de_dia
FROM objetivo
WHERE fecha_actual::date <> fecha_nueva::date;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 2 — Copia de seguridad completa de la tabla
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS mileage_logs_backup_20260818 AS
SELECT * FROM mileage_logs;

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 3 — Normalizar fecha y redondear el odómetro
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

UPDATE mileage_logs ml
SET
  date = (
    (
      CASE
        WHEN (ml.date AT TIME ZONE 'UTC')::time = time '00:00'
          THEN (ml.date AT TIME ZONE 'UTC')::date
        ELSE (ml.date AT TIME ZONE 'America/Havana')::date
      END
    ) + time '12:00'
  ) AT TIME ZONE 'UTC',
  mileage = round(ml.mileage)
WHERE ml.date <> (
    (
      CASE
        WHEN (ml.date AT TIME ZONE 'UTC')::time = time '00:00'
          THEN (ml.date AT TIME ZONE 'UTC')::date
        ELSE (ml.date AT TIME ZONE 'America/Havana')::date
      END
    ) + time '12:00'
  ) AT TIME ZONE 'UTC'
  OR ml.mileage <> round(ml.mileage);

-- Revisar el número de filas afectadas antes de confirmar.
COMMIT;
-- ROLLBACK;  -- usar en su lugar si el conteo no cuadra

-- ─────────────────────────────────────────────────────────────────────────────
-- Paso 4 — Verificar
-- ─────────────────────────────────────────────────────────────────────────────

-- Ninguna fila debería salir: todas a mediodía UTC y sin decimales.
SELECT id, vehicle_id, date, mileage, notes
FROM mileage_logs
WHERE (date AT TIME ZONE 'UTC')::time <> time '12:00'
   OR mileage <> round(mileage)
ORDER BY vehicle_id, date;

-- Comparación día a día con el respaldo: solo deberían aparecer las filas que
-- estaban a medianoche UTC, y su día debe quedarse igual (no correrse).
SELECT
  b.date AS antes,
  ml.date AS despues,
  b.date::date  AS dia_antes_utc,
  (ml.date AT TIME ZONE 'America/Havana')::date AS dia_despues_local,
  ml.mileage,
  ml.notes
FROM mileage_logs ml
JOIN mileage_logs_backup_20260818 b ON b.id = ml.id
WHERE b.date <> ml.date
ORDER BY ml.vehicle_id, ml.date;

-- Orden tal como lo lee la app (fecha desc, luego odómetro desc).
SELECT vehicle_id, date, mileage, notes
FROM mileage_logs
ORDER BY vehicle_id, date DESC, mileage DESC
LIMIT 50;

-- ─────────────────────────────────────────────────────────────────────────────
-- Deshacer (si hiciera falta)
-- ─────────────────────────────────────────────────────────────────────────────

-- UPDATE mileage_logs ml
-- SET date = b.date, mileage = b.mileage
-- FROM mileage_logs_backup_20260818 b
-- WHERE ml.id = b.id;

-- Cuando todo esté comprobado:
-- DROP TABLE mileage_logs_backup_20260818;
-- DROP TABLE mileage_logs_backup_20260817;
