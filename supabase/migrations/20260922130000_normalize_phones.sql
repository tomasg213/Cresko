-- =====================================================================
-- Normalización de teléfonos a código de país (+58 Venezuela).
-- Si el usuario escribió un 0 al inicio, se reemplaza por el código de
-- país. Se aplica a parties.phone (API, checkout, import de respaldos).
-- =====================================================================

create or replace function public.cresko_format_phone(p_value text)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text := regexp_replace(coalesce(p_value, ''), '[^0-9]', '', 'g');
begin
  if v_digits = '' then
    return nullif(p_value, '');
  end if;
  if left(v_digits, 1) = '0' then
    v_digits := '58' || substr(v_digits, 2);
  elsif left(v_digits, 2) <> '58' then
    v_digits := '58' || v_digits;
  end if;
  return '+' || v_digits;
end;
$$;

create or replace function public.cresko_normalize_party_phone()
returns trigger
language plpgsql
as $$
begin
  NEW.phone := public.cresko_format_phone(NEW.phone);
  return NEW;
end;
$$;

drop trigger if exists parties_normalize_phone on public.parties;
create trigger parties_normalize_phone
  before insert or update of phone on public.parties
  for each row execute function public.cresko_normalize_party_phone();

update public.parties
set phone = public.cresko_format_phone(phone)
where phone is not null and phone <> '';