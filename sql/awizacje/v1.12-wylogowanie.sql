-- =====================================================================
--  AWIZACJA v1.12 — administrator może wylogować dowolnego użytkownika
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * funkcja wyloguj_uzytkownika(): kończy wszystkie sesje danej osoby
--      (na każdym komputerze i telefonie); wywołać ją może WYŁĄCZNIE
--      zalogowane konto o loginie „admin”,
--    * stara sesja od razu traci dostęp do danych (nawet zanim program
--      sam się wyloguje); po ponownym zalogowaniu wszystko działa normalnie,
--    * konto NIE jest blokowane – to tylko wylogowanie.
-- =====================================================================

alter table public.profile add column if not exists wyloguj_po timestamptz;

-- czy sesja (token) zalogowanego powstała po ostatnim wylogowaniu przez admina?
create or replace function public.sesja_wazna() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.wyloguj_po is null
        or coalesce((auth.jwt() ->> 'iat')::bigint, 0) > extract(epoch from p.wyloguj_po)::bigint
      from public.profile p where p.id = auth.uid()), true)
$$;

-- rola zalogowanego: + nieważna sesja = brak dostępu
create or replace function public.moja_rola() returns text
language sql stable security definer set search_path = public as $$
  select p.rola
  from public.profile p
  left join public.firmy f on f.id = p.firma_id
  where p.id = auth.uid()
    and p.aktywny
    and (p.rola = 'logistyka' or coalesce(f.aktywna, false))
    and public.sesja_wazna()
$$;

create or replace function public.jestem_adminem() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin from public.profile p
                    where p.id = auth.uid() and p.aktywny and p.rola = 'logistyka'), false)
     and public.sesja_wazna()
$$;

create or replace function public.mam_uprawnienie(p_upr text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin or p_upr = any (p.uprawnienia) from public.profile p
                    where p.id = auth.uid() and p.aktywny and p.rola = 'logistyka'), false)
     and public.sesja_wazna()
$$;


create or replace function public.wyloguj_uzytkownika(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  ja public.profile%rowtype;
begin
  select * into ja from public.profile where id = auth.uid();
  if not found or ja.login <> 'admin' or not ja.aktywny then
    raise exception 'Wylogowywać innych może tylko administrator (login admin).';
  end if;
  if p_id = ja.id then
    raise exception 'Nie można wylogować samego siebie – użyj „Wyloguj” w prawym górnym rogu.';
  end if;

  update public.profile set wyloguj_po = now() where id = p_id;
  if not found then
    raise exception 'Nie ma takiego konta.';
  end if;

  -- usuń sesje, żeby nie dało się ich odświeżyć (gdyby Supabase nie pozwolił – wystarczy wyloguj_po)
  begin
    delete from auth.sessions where user_id = p_id;
  exception when insufficient_privilege or undefined_table then
    null;
  end;
end $$;

revoke all on function public.wyloguj_uzytkownika(uuid) from public, anon;
grant execute on function public.wyloguj_uzytkownika(uuid) to authenticated;

select 'wyloguj_uzytkownika gotowe' as wynik;
