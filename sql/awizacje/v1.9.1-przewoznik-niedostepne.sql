-- =====================================================================
--  AWIZACJA v1.9.1 — przewoźnik widzi tylko „niedostępne”
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Uruchomić PO pliku awizacja-v1.9-odblokowanie-okien.sql.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * gdy przewoźnik trafi na przerwę albo blokadę, baza odpowiada
--      tylko „Ten czas jest niedostępny” – bez godzin i powodu,
--    * biuro dalej widzi pełny komunikat (przerwa / blokada, godziny, powód).
-- =====================================================================

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
      -- przewoźnik nie musi wiedzieć dlaczego – tylko że niedostępne
      if public.moja_rola() = 'przewoznik' then
        return 'Ten czas jest niedostępny – wybierz inną godzinę.';
      end if;
      return (case when b.rodzaj = 'przerwa' then 'W tym czasie jest przerwa' else 'Ten czas jest zablokowany' end)
          || ' (' || public.awz_hhmm(b.od_min) || '–' || public.awz_hhmm(b.do_min)
          || coalesce(' · ' || nullif(trim(b.opis), ''), '') || ') – wybierz inną godzinę.';
    end if;
  end loop;
  return null;
end $$;

select 'v1.9.1 gotowe' as wynik;
