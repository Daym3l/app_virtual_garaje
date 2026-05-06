-- Función que retorna los mantenimientos que requieren alerta push
create or replace function get_maintenance_alerts()
returns table (
  user_id        uuid,
  display_name   text,
  fcm_token      text,
  email          text,
  maintenance_id uuid,
  type           text,
  description    text,
  next_date      date,
  next_mileage   int,
  is_urgent      boolean,
  current_mileage int,
  days_remaining  int,
  km_remaining    int
)
language sql
security definer
as $$
  select
    up.id                                                    as user_id,
    up.display_name,
    up.fcm_token,
    up.email,
    m.id                                                     as maintenance_id,
    m.type,
    m.description,
    m.next_date::date,
    m.next_mileage::int,
    m.is_urgent,
    v.current_mileage::int,
    case
      when m.next_date is not null
      then (m.next_date::date - current_date)
      else null
    end::int                                                 as days_remaining,
    case
      when m.next_mileage is not null
      then (m.next_mileage - v.current_mileage)::int
      else null
    end                                                      as km_remaining
  from user_profiles up
  inner join user_settings us   on us.user_id = up.id
  inner join vehicles v         on v.user_id = up.id::text
  inner join maintenances m     on m.vehicle_id = v.id
  where
    up.membership_status = 'active'
    and (up.membership_expires_at is null or up.membership_expires_at > now())
    and us.maintenance_alerts = true
    and up.fcm_token is not null
    and m.is_completed = false
    and (
      (m.next_date is not null and m.next_date::date <= current_date + interval '7 days')
      or
      (m.next_mileage is not null and v.current_mileage >= m.next_mileage - 500)
      or
      m.is_urgent = true
    )
  order by up.id, km_remaining asc nulls last;
$$;
