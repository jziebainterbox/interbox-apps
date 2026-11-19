-- =====================================================================
--  AWIZACJA v1.9 — odblokowanie pojedynczego okna z blokady / przerwy
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Wcześniej muszą być uruchomione pliki v1.6 i v1.7.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * nowy rodzaj wpisu w tabeli blokady: „wyjatek” = odblokowany kawałek
--      konkretnej blokady albo przerwy w konkretnym dniu (np. wt 12:00–12:30),
--    * blokada / przerwa działa dalej w pozostałe dni i godziny,
--    * usunięcie całej blokady usuwa też jej wyjątki,
--    * strażnik awizacji uwzględnia wyjątki.
-- =====================================================================

alter table public.blokady add column if not exists wyjatek_dla bigint
  references public.blokady (id) on delete cascade;

-- rodzaj: przerwa / blokada / wyjatek
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.blokady'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%rodzaj%przerwa%'
  loop
    execute format('alter table public.blokady drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.blokady add constraint blokady_rodzaj_check
  check (rodzaj in ('przerwa', 'blokada', 'wyjatek'));

alter table public.blokady drop constraint if exists blokady_wyjatek_ok;
alter table public.blokady add constraint blokady_wyjatek_ok
  check (rodzaj <> 'wyjatek' or (wyjatek_dla is not null and dzien is not null));

create index if not exists blokady_wyjatek_dla on public.blokady (wyjatek_dla, dzien);


-- czy czas awizacji nachodzi na przerwę / blokadę (z pominięciem odblokowanych okien)?
create or replace function public.awz_kolizja_blokady(p_rampa int, p_od timestamptz, p_do timestamptz)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  strefa text := coalesce((select u.strefa from public.ustawienia u where u.id = 1), 'Europe/Warsaw');
  lp  timestamp := p_od at time zone strefa;
  d   date := (p_od at time zone strefa)::date;
  m0  int := extract(hour from lp)::int * 60 + extract(minute from lp)::int;
  m1  int := round(extract(epoch from ((p_do at time zone strefa) - date_trunc('day', lp))) / 60)::int;
  b   public.blokady%rowtype;
  w   record;
  a1  int;
  a2  int;
  pos int;
begin
  for b in select * from public.blokady x
            where x.rodzaj <> 'wyjatek'
              and (x.rampa_id is null or x.rampa_id = p_rampa)
              and x.od_min < m1 and x.do_min > m0
              and ((x.dzien is not null and x.dzien = d)
                or (x.dzien is null and extract(isodow from lp)::int = any (x.dni)))
            order by x.od_min
  loop
    a1 := greatest(b.od_min, m0);
    a2 := least(b.do_min, m1);
    pos := a1;
    for w in select y.od_min, y.do_min from public.blokady y
              where y.rodzaj = 'wyjatek' and y.wyjatek_dla = b.id and y.dzien = d
                and y.do_min > a1 and y.od_min < a2
              order by y.od_min
    loop
      exit when w.od_min > pos;            -- dziura: ten kawałek jest zablokowany
      pos := greatest(pos, w.do_min);
    end loop;
    if pos < a2 then
      return (case when b.rodzaj = 'przerwa' then 'W tym czasie jest przerwa' else 'Ten czas jest zablokowany' end)
          || ' (' || public.awz_hhmm(b.od_min) || '–' || public.awz_hhmm(b.do_min)
          || coalesce(' · ' || nullif(trim(b.opis), ''), '') || ') – wybierz inną godzinę.';
    end if;
  end loop;
  return null;
end $$;

select rodzaj, count(*) as ile from public.blokady group by 1 order by 1;
