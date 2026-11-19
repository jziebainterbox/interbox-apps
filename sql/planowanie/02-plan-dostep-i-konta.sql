-- =====================================================================
--  PLAN PRODUKCJI, część A — dostęp i konta
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  NAJPIERW na projekcie PRÓBNYM („Test plan”). Można uruchomić ponownie.
--
--  Co robi:
--    * nowa tabela plan_dostep   — kto ma dostęp do planu:
--          'edycja'  = planista (to samo konto co w awizacji),
--          'sprzedaz'= podgląd planu, bez edycji, bez dostępu do awizacji,
--    * nowa tabela plan_zaproszenia — przygotowane konta sprzedaży
--      (admin przygotowuje, potem konto zakłada się jak w awizacji),
--    * funkcja plan_moja_rola() — rola zalogowanego w planie albo brak,
--    * JEDYNA zmiana istniejącego kodu awizacji: funkcja awizacja_nowe_konto()
--      przyjmuje dodatkowo konta z plan_zaproszenia. Pierwsza część funkcji
--      jest taka sama jak w awizacja-v1.3-uprawnienia.sql — konta awizacji
--      zakładają się dokładnie jak dotąd. Konto sprzedaży NIE dostaje profilu
--      w awizacji, więc awizacja go nie wpuszcza (moja_rola() = brak).
--    * konto „admin” dostaje dostęp do edycji planu.
--
--  Wycofanie: 02-wycofanie.sql (przywraca funkcję z v1.3).
-- =====================================================================


-- 1. Kto ma dostęp do planu ---------------------------------------------
create table if not exists public.plan_dostep (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  login      text not null unique check (login = lower(login)),
  imie       text,
  rola       text not null check (rola in ('edycja', 'sprzedaz')),
  aktywny    boolean not null default true,
  wyloguj_po timestamptz,
  utworzono  timestamptz not null default now()
);

-- konta sprzedaży przygotowane do założenia (ważne 1 dzień, jak w awizacji)
create table if not exists public.plan_zaproszenia (
  email      text primary key,
  login      text not null,
  imie       text,
  rola       text not null default 'sprzedaz' check (rola = 'sprzedaz'),
  wygasa     timestamptz not null default now() + interval '1 day'
);


-- 2. Rola zalogowanego w planie -----------------------------------------
--  edycja   — wymaga też aktywnego konta logistyki w awizacji i ważnej sesji
--             (zablokowanie / wylogowanie przez admina w awizacji działa i tu),
--  sprzedaz — wystarczy aktywny wpis w plan_dostep.
create or replace function public.plan_moja_rola() returns text
language sql stable security definer set search_path = public as $$
  select d.rola
  from public.plan_dostep d
  where d.user_id = auth.uid()
    and d.aktywny
    and (d.wyloguj_po is null
         or coalesce((auth.jwt() ->> 'iat')::bigint, 0) > extract(epoch from d.wyloguj_po)::bigint)
    and (d.rola = 'sprzedaz'
         or exists (select 1 from public.profile p
                     where p.id = d.user_id and p.aktywny and p.rola = 'logistyka'
                       and public.sesja_wazna()))
$$;

revoke all on function public.plan_moja_rola() from public, anon;
grant execute on function public.plan_moja_rola() to authenticated;


-- 3. Kłódki (RLS): tylko administrator zarządza dostępem ----------------
alter table public.plan_dostep      enable row level security;
alter table public.plan_zaproszenia enable row level security;

revoke all on public.plan_dostep, public.plan_zaproszenia from anon;
grant select, insert, update, delete on public.plan_dostep, public.plan_zaproszenia to authenticated;

drop policy if exists plan_dostep_odczyt on public.plan_dostep;
create policy plan_dostep_odczyt on public.plan_dostep for select to authenticated
  using (user_id = (select auth.uid()) or (select public.jestem_adminem()));

drop policy if exists plan_dostep_zmiana on public.plan_dostep;
create policy plan_dostep_zmiana on public.plan_dostep for all to authenticated
  using ((select public.jestem_adminem()))
  with check ((select public.jestem_adminem()));

drop policy if exists plan_zaproszenia_admin on public.plan_zaproszenia;
create policy plan_zaproszenia_admin on public.plan_zaproszenia for all to authenticated
  using ((select public.jestem_adminem()))
  with check ((select public.jestem_adminem()));


-- 4. Nowe konta: awizacja jak dotąd + konta sprzedaży z zaproszenia -----
create or replace function public.awizacja_nowe_konto() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k public.konta_oczekujace%rowtype;
  z public.plan_zaproszenia%rowtype;
begin
  -- (1) jak dotąd: konto przygotowane w programie Awizacja
  select * into k
  from public.konta_oczekujace
  where lower(email) = lower(new.email) and wygasa > now();

  if found then
    insert into public.profile (id, login, imie, rola, firma_id, admin, uprawnienia)
    values (new.id, lower(k.login), k.imie, k.rola, k.firma_id,
            k.rola = 'logistyka' and k.admin,
            case when k.rola = 'logistyka' then k.uprawnienia else '{}' end);

    delete from public.konta_oczekujace where email = k.email;
    return new;
  end if;

  -- (2) nowe: konto sprzedaży przygotowane w planie (bez profilu w awizacji)
  select * into z
  from public.plan_zaproszenia
  where lower(email) = lower(new.email) and wygasa > now();

  if found then
    insert into public.plan_dostep (user_id, login, imie, rola)
    values (new.id, lower(z.login), z.imie, z.rola);

    delete from public.plan_zaproszenia where email = z.email;
    return new;
  end if;

  -- (3) jak dotąd: każde inne konto jest odrzucane
  raise exception 'Konto % nie zostało przygotowane w programie Awizacja.', new.email;
end $$;


-- 5. Konto admin = edycja planu ------------------------------------------
insert into public.plan_dostep (user_id, login, imie, rola)
select p.id, p.login, p.imie, 'edycja'
from public.profile p
where p.login = 'admin' and p.rola = 'logistyka'
on conflict (user_id) do nothing;


-- kontrola
select 'plan, część A gotowa' as wynik,
       (select count(*) from public.plan_dostep) as w_dostepie,
       (select count(*) from public.profile)     as profili_awizacji;
