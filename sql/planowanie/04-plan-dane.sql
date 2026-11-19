-- =====================================================================
--  PLAN PRODUKCJI, część B — dane planu
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  NAJPIERW na projekcie PRÓBNYM („Test plan”). Można uruchomić ponownie.
--  Wymaga: 02-plan-dostep-i-konta.sql (plan_moja_rola()).
--
--  Co robi (wszystko NOWE, nic z awizacji nie jest zmieniane):
--    * plan_maszyny      — maszyny w kolejności wyświetlania,
--    * plan_zlecenia     — kafelki planu (1 wiersz = 1 zlecenie),
--    * plan_predkosci    — realne prędkości [ark/h] produkt × maszyna
--                          (dane z Excela wgrywa osobny plik 05-…),
--    * plan_ustawienia   — m.in. które pola widzi sprzedaż (uwagi, ilości),
--    * funkcja plan_podglad() — plan w postaci JSON dla ekranu TV / sprzedaży
--                          (te same pola co dziś plan.json; BEZ prędkości
--                          i bez pól kalkulatora),
--    * kłódki: edytuje i czyta tabele tylko 'edycja' (planista);
--      'sprzedaz' czyta wyłącznie przez plan_podglad(); anonim nic.
--    * włączone odświeżanie na żywo (realtime) dla zleceń i maszyn.
--
--  Godziny zapisane jak w programie: dziesiętnie (11.55 = 11:33),
--  koniec po północy = po_polnocy true + koniec_h = godzina następnego dnia.
-- =====================================================================


-- 1. Tabele -------------------------------------------------------------
create table if not exists public.plan_maszyny (
  nazwa      text primary key,
  kolejnosc  int  not null default 1,
  aktywna    boolean not null default true
);

create table if not exists public.plan_zlecenia (
  id            text primary key,                       -- jak w programie (np. t8k2m…)
  maszyna       text not null references public.plan_maszyny (nazwa) on update cascade,
  data          date not null,
  start_h       numeric(7,4) not null check (start_h >= 0 and start_h <= 24),
  koniec_h      numeric(7,4) not null check (koniec_h >= 0 and koniec_h <= 24),
  po_polnocy    boolean not null default false,
  nazwa         text not null default '',
  nr_zlecenia   text not null default '',
  typ_surowca   text not null default '',
  ilosc_surowca text not null default '',
  ilosc         integer,
  kolor         text not null default '#3b82f6',
  uwagi         text not null default '',
  zrobione      boolean not null default false,
  produkt_kalk  text not null default '',               -- pola kalkulatora czasu (tylko dla planisty)
  arkusze_kalk  integer,
  zmieniono     timestamptz not null default now(),
  zmienil       uuid
);
create index if not exists plan_zlecenia_data_idx on public.plan_zlecenia (data, maszyna);

create table if not exists public.plan_predkosci (
  maszyna          text not null,
  produkt          text not null,
  predkosc         integer not null check (predkosc between 1 and 20000),
  pewnosc          text not null default 'n' check (pewnosc in ('w','s','n','k','b','m')),
  przebiegi        integer not null default 0,
  minuty           integer not null default 0,
  szacunek         boolean not null default false,
  excel_predkosc   integer,                             -- wartość z Excela (null = dodane ręcznie)
  zrodlo           text not null default 'excel' check (zrodlo in ('excel','poprawiona','reczna')),
  zmieniono        timestamptz not null default now(),
  primary key (maszyna, produkt)
);

create table if not exists public.plan_ustawienia (
  klucz   text primary key,
  wartosc jsonb not null
);
insert into public.plan_ustawienia (klucz, wartosc)
values ('pokaz_sprzedazy', '{"note": true, "qty": true, "materialQty": true}')
on conflict (klucz) do nothing;

insert into public.plan_maszyny (nazwa, kolejnosc) values
  ('Klett', 1), ('Curioni', 2), ('Lih Sheng 1', 3), ('Lih Sheng 2', 4),
  ('Sklejarka 1', 5), ('Sklejarka 2', 6), ('Sklejarka IIcz.', 7),
  ('Kaszerownica', 8), ('E-commerce', 9)
on conflict (nazwa) do nothing;


-- 2. Kto i kiedy zmienił zlecenie / prędkość -----------------------------
create or replace function public.plan_audyt() returns trigger
language plpgsql set search_path = public as $$
begin
  new.zmieniono := now();
  if tg_table_name = 'plan_zlecenia' then
    new.zmienil := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists plan_zlecenia_audyt on public.plan_zlecenia;
create trigger plan_zlecenia_audyt before insert or update on public.plan_zlecenia
  for each row execute function public.plan_audyt();

drop trigger if exists plan_predkosci_audyt on public.plan_predkosci;
create trigger plan_predkosci_audyt before insert or update on public.plan_predkosci
  for each row execute function public.plan_audyt();


-- 3. Kłódki (RLS): czyta i zmienia tylko planista ('edycja') -------------
alter table public.plan_maszyny    enable row level security;
alter table public.plan_zlecenia   enable row level security;
alter table public.plan_predkosci  enable row level security;
alter table public.plan_ustawienia enable row level security;

revoke all on public.plan_maszyny, public.plan_zlecenia, public.plan_predkosci, public.plan_ustawienia from anon;
grant select, insert, update, delete
  on public.plan_maszyny, public.plan_zlecenia, public.plan_predkosci, public.plan_ustawienia to authenticated;

drop policy if exists plan_maszyny_edycja on public.plan_maszyny;
create policy plan_maszyny_edycja on public.plan_maszyny for all to authenticated
  using ((select public.plan_moja_rola()) = 'edycja')
  with check ((select public.plan_moja_rola()) = 'edycja');

drop policy if exists plan_zlecenia_edycja on public.plan_zlecenia;
create policy plan_zlecenia_edycja on public.plan_zlecenia for all to authenticated
  using ((select public.plan_moja_rola()) = 'edycja')
  with check ((select public.plan_moja_rola()) = 'edycja');

drop policy if exists plan_predkosci_edycja on public.plan_predkosci;
create policy plan_predkosci_edycja on public.plan_predkosci for all to authenticated
  using ((select public.plan_moja_rola()) = 'edycja')
  with check ((select public.plan_moja_rola()) = 'edycja');

drop policy if exists plan_ustawienia_edycja on public.plan_ustawienia;
create policy plan_ustawienia_edycja on public.plan_ustawienia for all to authenticated
  using ((select public.plan_moja_rola()) = 'edycja')
  with check ((select public.plan_moja_rola()) = 'edycja');


-- 4. Plan dla ekranu TV i sprzedaży: jeden JSON, okrojone pola -----------
--  Dostępny dla 'edycja' i 'sprzedaz'. Pola uwagi / ilość / ilość surowca
--  zależą od ustawienia pokaz_sprzedazy (planista je zmienia).
--  Nie ma tu prędkości ani pól kalkulatora.
create or replace function public.plan_podglad() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  pokaz jsonb;
begin
  if public.plan_moja_rola() is null then
    raise exception 'Brak dostępu do planu.';
  end if;

  select wartosc into pokaz from public.plan_ustawienia where klucz = 'pokaz_sprzedazy';
  pokaz := coalesce(pokaz, '{"note": true, "qty": true, "materialQty": true}'::jsonb);

  return jsonb_build_object(
    'publishedAt', now(),
    'machines', (select coalesce(jsonb_agg(m.nazwa order by m.kolejnosc, m.nazwa), '[]'::jsonb)
                   from public.plan_maszyny m where m.aktywna),
    'tasks', (select coalesce(jsonb_agg(
                jsonb_strip_nulls(jsonb_build_object(
                  'id', z.id,
                  'machine', z.maszyna,
                  'date', z.data,
                  'start', z.start_h,
                  'end', z.koniec_h,
                  'endNextDay', z.po_polnocy,
                  'label', z.nazwa,
                  'orderNumber', nullif(z.nr_zlecenia, ''),
                  'materialType', nullif(z.typ_surowca, ''),
                  'materialQty', case when coalesce((pokaz ->> 'materialQty')::boolean, false) then nullif(z.ilosc_surowca, '') end,
                  'qty', case when coalesce((pokaz ->> 'qty')::boolean, false) then z.ilosc end,
                  'note', case when coalesce((pokaz ->> 'note')::boolean, false) then nullif(z.uwagi, '') end,
                  'color', z.kolor,
                  'done', z.zrobione
                )) order by z.data, z.start_h), '[]'::jsonb)
              from public.plan_zlecenia z)
  );
end $$;

revoke all on function public.plan_podglad() from public, anon;
grant execute on function public.plan_podglad() to authenticated;


-- 5. Odświeżanie na żywo (jeśli tabele nie są jeszcze dodane) ------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.plan_zlecenia;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.plan_maszyny;
  exception when duplicate_object then null;
  end;
exception when undefined_object then
  raise notice 'Brak publikacji supabase_realtime — odświeżanie na żywo pominięte.';
end $$;


-- kontrola
select 'plan, część B gotowa' as wynik,
       (select count(*) from public.plan_maszyny)   as maszyn,
       (select count(*) from public.plan_zlecenia)  as zlecen,
       (select count(*) from public.plan_ustawienia) as ustawien;
