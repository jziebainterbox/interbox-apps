-- =====================================================================
--  WYCOFANIE części A planu (02-plan-dostep-i-konta.sql)
--  Przywraca funkcję awizacja_nowe_konto() dokładnie z awizacja-v1.3-uprawnienia.sql.
--  Tabele plan_dostep / plan_zaproszenia i funkcja plan_moja_rola() zostają
--  (nie przeszkadzają awizacji) — usuń je tylko, jeśli naprawdę chcesz
--  (odkomentuj trzy linie na końcu).
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
-- =====================================================================

create or replace function public.awizacja_nowe_konto() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k public.konta_oczekujace%rowtype;
begin
  select * into k
  from public.konta_oczekujace
  where lower(email) = lower(new.email) and wygasa > now();

  if not found then
    raise exception 'Konto % nie zostało przygotowane w programie Awizacja.', new.email;
  end if;

  insert into public.profile (id, login, imie, rola, firma_id, admin, uprawnienia)
  values (new.id, lower(k.login), k.imie, k.rola, k.firma_id,
          k.rola = 'logistyka' and k.admin,
          case when k.rola = 'logistyka' then k.uprawnienia else '{}' end);

  delete from public.konta_oczekujace where email = k.email;
  return new;
end $$;

-- drop function if exists public.plan_moja_rola();
-- drop table if exists public.plan_zaproszenia;
-- drop table if exists public.plan_dostep;

select 'wycofane: awizacja_nowe_konto() jak w v1.3' as wynik;
