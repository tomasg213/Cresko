-- =====================================================================
-- Normalización de documentos de identidad:
-- - Cédula (ci): prefijo "V-" y puntos cada tres dígitos. Ej: V-12.345.678
-- - RIF: prefijo "J-" y guion antes del último dígito. Ej: J-12345678-9
-- - Pasaporte: prefijo "E-". Ej: E-123456789
--
-- Se normalizan los valores existentes y se crean triggers para que todo
-- insert/update (API, checkout, importación de respaldos) quede formateado.
-- =====================================================================

create or replace function public.cresko_doc_digits(p_value text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_value, ''), '[^0-9]', '', 'g');
$$;

create or replace function public.cresko_format_ci(p_value text)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text := public.cresko_doc_digits(p_value);
  v_len int := length(v_digits);
  v_out text := '';
  v_i int;
begin
  if v_len = 0 then
    return '';
  end if;
  for v_i in 1..v_len loop
    v_out := v_out || substr(v_digits, v_i, 1);
    if v_i < v_len and (v_len - v_i) % 3 = 0 then
      v_out := v_out || '.';
    end if;
  end loop;
  return 'V-' || v_out;
end;
$$;

create or replace function public.cresko_format_rif(p_value text)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text := public.cresko_doc_digits(p_value);
  v_len int := length(v_digits);
begin
  if v_len = 0 then
    return '';
  end if;
  if v_len <= 1 then
    return 'J-' || v_digits;
  end if;
  return 'J-' || substr(v_digits, 1, v_len - 1) || '-' || substr(v_digits, v_len, 1);
end;
$$;

create or replace function public.cresko_format_passport(p_value text)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text := public.cresko_doc_digits(p_value);
begin
  if length(v_digits) = 0 then
    return '';
  end if;
  return 'E-' || v_digits;
end;
$$;

create or replace function public.cresko_format_document(p_type text, p_value text)
returns text
language plpgsql
immutable
as $$
begin
  if p_value is null or p_value = '' then
    return p_value;
  end if;
  if p_type = 'ci' then
    return public.cresko_format_ci(p_value);
  elsif p_type = 'rif' then
    return public.cresko_format_rif(p_value);
  elsif p_type = 'passport' then
    return public.cresko_format_passport(p_value);
  end if;
  return p_value;
end;
$$;

-- =====================================================================
-- Actualizar los valores existentes
-- =====================================================================

update public.parties
set document_id = public.cresko_format_document(document_type, document_id)
where document_id is not null and document_id <> '';

update public.organizations
set tax_id = public.cresko_format_rif(tax_id)
where tax_id is not null and tax_id <> '';

-- =====================================================================
-- Triggers: normalizar todo documento al guardar (incluye import backups)
-- =====================================================================

create or replace function public.cresko_normalize_party_document()
returns trigger
language plpgsql
as $$
begin
  NEW.document_id := public.cresko_format_document(NEW.document_type, NEW.document_id);
  return NEW;
end;
$$;

drop trigger if exists parties_normalize_document on public.parties;
create trigger parties_normalize_document
  before insert or update of document_type, document_id on public.parties
  for each row execute function public.cresko_normalize_party_document();

create or replace function public.cresko_normalize_org_tax_id()
returns trigger
language plpgsql
as $$
begin
  NEW.tax_id := public.cresko_format_rif(NEW.tax_id);
  return NEW;
end;
$$;

drop trigger if exists organizations_normalize_tax_id on public.organizations;
create trigger organizations_normalize_tax_id
  before insert or update of tax_id on public.organizations
  for each row execute function public.cresko_normalize_org_tax_id();