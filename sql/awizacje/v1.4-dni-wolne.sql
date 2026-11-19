-- =====================================================================
--  AWIZACJA v1.4 — dni wolne blokują wszystkich
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * w dzień wolny (Ustawienia → Dni wolne) nikt nie wpisze ani nie
--      przesunie awizacji na ten dzień – także biuro (wcześniej tylko przewoźnik),
--    * awizacje wpisane wcześniej na ten dzień zostają; można je odwołać.
-- =====================================================================

create or replace function public.awizacje_przed_zapisem() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  u     public.ustawienia%rowtype;
  rola  text := public.moja_rola();
  lp    timestamp;
  lk    timestamp;
  m0    int;
  m1    int;
  czas_zmieniony boolean;
begin
  -- zapis z panelu Supabase / SQL Editora (bez zalogowanego użytkownika) = administrator
  if rola is null and (coalesce(auth.role(), '') = 'service_role' or session_user <> 'authenticator') then
    rola := 'admin';
  end if;
  if rola is null then
    raise exception 'Brak uprawnień – konto albo firma jest zablokowana.';
  end if;

  select * into u from public.ustawienia where id = 1;

  if tg_op = 'INSERT' then
    new.utworzyl := auth.uid();
    new.utworzono := now();
    new.status := 'aktywna';
    new.zmienil := null;  new.zmieniono := null;
    new.odwolal := null;  new.odwolano := null;  new.powod_odwolania := null;
  else
    new.id := old.id;
    new.utworzyl := old.utworzyl;
    new.utworzono := old.utworzono;
    new.zmienil := auth.uid();
    new.zmieniono := now();
  end if;

  new.nr_rej := upper(regexp_replace(trim(coalesce(new.nr_rej, '')), '\s+', ' ', 'g'));
  if new.nr_rej = '' then
    raise exception 'Podaj numer rejestracyjny.';
  end if;

  if rola = 'przewoznik' then
    new.firma_id := public.moja_firma();
    if tg_op = 'UPDATE' then
      if old.status <> 'aktywna' then
        raise exception 'Ta awizacja jest już odwołana.';
      end if;
      if old.poczatek < now() + make_interval(mins => u.odwolanie_min) then
        raise exception 'Zmiana lub odwołanie jest możliwe najpóźniej % min przed oknem. Zadzwoń do logistyki.', u.odwolanie_min;
      end if;
    end if;
  end if;

  -- odwołanie: zapamiętaj kto i kiedy, godzin już nie zmieniamy
  if new.status = 'odwolana' then
    if tg_op = 'UPDATE' then
      new.poczatek := old.poczatek;
      new.koniec := old.koniec;
      new.rampa_id := old.rampa_id;
      if old.status = 'aktywna' then
        new.odwolal := auth.uid();
        new.odwolano := now();
      else
        new.odwolal := old.odwolal;
        new.odwolano := old.odwolano;
      end if;
    else
      new.odwolal := auth.uid();
      new.odwolano := now();
    end if;
    return new;
  end if;

  -- przywrócenie odwołanej (tylko logistyka – przewoźnik odpadł wyżej)
  if tg_op = 'UPDATE' and old.status = 'odwolana' then
    new.odwolal := null;
    new.odwolano := null;
    new.powod_odwolania := null;
  end if;

  czas_zmieniony := tg_op = 'INSERT'
    or new.poczatek <> old.poczatek
    or new.koniec <> old.koniec
    or new.rampa_id <> old.rampa_id
    or old.status <> 'aktywna';

  if not czas_zmieniony then
    return new;
  end if;

  if not exists (select 1 from public.rampy r where r.id = new.rampa_id and r.aktywna) then
    raise exception 'Ta rampa jest nieaktywna.';
  end if;

  -- dzień wolny: nikt nie wpisze awizacji (także biuro)
  if rola <> 'admin' and (new.poczatek at time zone u.strefa)::date = any (u.dni_wolne) then
    raise exception 'Ten dzień jest wolny – nie można wpisać awizacji.';
  end if;

  if rola = 'przewoznik' then
    lp := new.poczatek at time zone u.strefa;
    lk := new.koniec at time zone u.strefa;
    m0 := extract(hour from lp)::int * 60 + extract(minute from lp)::int;
    m1 := round(extract(epoch from (lk - date_trunc('day', lp))) / 60)::int;

    if new.poczatek < now() + make_interval(mins => u.min_wyprzedzenie) then
      raise exception 'Rezerwacja jest możliwa najpóźniej % min przed oknem.', u.min_wyprzedzenie;
    end if;
    if lp::date > (now() at time zone u.strefa)::date + u.dni_naprzod then
      raise exception 'Można rezerwować najwyżej % dni naprzód.', u.dni_naprzod;
    end if;
    if not (extract(isodow from lp)::int = any (u.dni_robocze)) or lp::date = any (u.dni_wolne) then
      raise exception 'Ten dzień jest wolny – rampa nie przyjmuje aut.';
    end if;
    if extract(second from lp) <> 0 or m0 < u.od_min or m1 > u.do_min then
      raise exception 'Rampa przyjmuje auta od % do %.', public.awz_hhmm(u.od_min), public.awz_hhmm(u.do_min);
    end if;
    if (m0 - u.od_min) % u.okno_min <> 0 or (m1 - m0) % u.okno_min <> 0 then
      raise exception 'Rezerwacja musi zaczynać się i kończyć na granicy okna (% min).', u.okno_min;
    end if;
    if (m1 - m0) > u.max_okien * u.okno_min then
      raise exception 'Jedna rezerwacja może trwać najwyżej % min.', u.max_okien * u.okno_min;
    end if;
  end if;

  return new;
end $$;

select dni_wolne from public.ustawienia where id = 1;
