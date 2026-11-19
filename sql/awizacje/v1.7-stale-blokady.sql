-- =====================================================================
--  AWIZACJA v1.7 — stałe blokady (co tydzień, jak przerwy)
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Wcześniej musi być uruchomiony awizacja-v1.6-przerwy-blokady.sql.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * blokada może mieć konkretny dzień (jednorazowa – jak dotąd)
--      albo nie mieć dnia, tylko dni tygodnia (stała – co tydzień),
--    * strażnik awizacji sprawdza oba rodzaje.
-- =====================================================================

-- zdejmij warunek „blokada musi mieć dzień”
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.blokady'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%dzien IS NOT NULL%'
  loop
    execute format('alter table public.blokady drop constraint %I', c.conname);
  end loop;
end $$;

-- bez dnia trzeba wskazać choć jeden dzień tygodnia
alter table public.blokady drop constraint if exists blokady_dzien_albo_dni;
alter table public.blokady add constraint blokady_dzien_albo_dni
  check (dzien is not null or cardinality(dni) > 0);


-- czy czas awizacji nachodzi na przerwę / blokadę? zwraca komunikat albo null
create or replace function public.awz_kolizja_blokady(p_rampa int, p_od timestamptz, p_do timestamptz)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  strefa text := coalesce((select u.strefa from public.ustawienia u where u.id = 1), 'Europe/Warsaw');
  lp  timestamp := p_od at time zone strefa;
  m0  int := extract(hour from lp)::int * 60 + extract(minute from lp)::int;
  m1  int := round(extract(epoch from ((p_do at time zone strefa) - date_trunc('day', lp))) / 60)::int;
  b   public.blokady%rowtype;
begin
  select * into b from public.blokady x
   where (x.rampa_id is null or x.rampa_id = p_rampa)
     and x.od_min < m1 and x.do_min > m0
     and ((x.dzien is not null and x.dzien = lp::date)
       or (x.dzien is null and extract(isodow from lp)::int = any (x.dni)))
   order by x.od_min
   limit 1;
  if not found then
    return null;
  end if;
  return (case when b.rodzaj = 'przerwa' then 'W tym czasie jest przerwa' else 'Ten czas jest zablokowany' end)
      || ' (' || public.awz_hhmm(b.od_min) || '–' || public.awz_hhmm(b.do_min)
      || coalesce(' · ' || nullif(trim(b.opis), ''), '') || ') – wybierz inną godzinę.';
end $$;

select rodzaj, case when dzien is null then 'stała' else 'jednorazowa' end as typ, count(*) as ile
  from public.blokady group by 1, 2 order by 1, 2;
