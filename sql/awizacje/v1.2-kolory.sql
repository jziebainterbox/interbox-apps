-- =====================================================================
--  AWIZACJA v1.2 — kolory firm
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Uruchomić RAZ, przed wgraniem programu v1.2 na GitHub.
--  Można uruchomić ponownie — nie zmienia kolorów już nadanych.
--
--  Co robi:
--    * dodaje do tabeli firm kolumnę „kolor”,
--    * nadaje kolory firmom, które już są (każda inny, po kolei),
--    * każda nowa firma dostaje sama kolor, którego nikt jeszcze nie ma
--      (gdy wszystkie 12 są zajęte – ten używany najrzadziej).
-- =====================================================================

alter table public.firmy
  add column if not exists kolor text check (kolor is null or kolor ~ '^#[0-9A-Fa-f]{6}$');

-- 12 kolorów (te same co w programie)
create or replace function public.awz_paleta() returns text[]
language sql immutable as $$
  select array['#2F6FDE','#E0483A','#1E9E6A','#8E44AD','#C76B12','#0F8B9C',
               '#B83280','#6B4F2A','#3D4DB7','#6E8A12','#D4A017','#1A1A1A']
$$;

-- pierwszy kolor, którego nie ma żadna inna firma (albo najrzadziej używany)
create or replace function public.awz_wolny_kolor(p_pomin bigint default null) returns text
language sql stable security definer set search_path = public as $$
  select p.k
  from unnest(public.awz_paleta()) with ordinality as p(k, nr)
  left join public.firmy f
         on upper(f.kolor) = upper(p.k)
        and f.id is distinct from p_pomin
  group by p.k, p.nr
  order by count(f.id), p.nr
  limit 1
$$;

-- nowa firma bez koloru dostaje go automatycznie
create or replace function public.firmy_kolor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kolor is null or new.kolor = '' then
    new.kolor := public.awz_wolny_kolor(new.id);
  end if;
  new.kolor := upper(new.kolor);
  return new;
end $$;

drop trigger if exists firmy_kolor on public.firmy;
create trigger firmy_kolor
  before insert or update on public.firmy
  for each row execute function public.firmy_kolor();

-- firmy, które już są: kolory po kolei (najstarsza firma = pierwszy kolor)
do $$
declare r record;
begin
  for r in select id from public.firmy where kolor is null order by id loop
    update public.firmy set kolor = public.awz_wolny_kolor(r.id) where id = r.id;
  end loop;
end $$;

select id, nazwa, kolor from public.firmy order by id;
