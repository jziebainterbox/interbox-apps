-- =====================================================================
--  PLAN PRODUKCJI, część D — plan_podglad() z oknem dat
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  NAJPIERW na projekcie PRÓBNYM. Można uruchomić ponownie.
--  Wymaga: 04-plan-dane.sql.
--
--  Po co: strona podglądu (TV / sprzedaż) nie powinna pobierać CAŁEGO planu
--  z całej historii przy każdym odświeżeniu. Funkcja zwraca teraz tylko
--  zlecenia z podanego zakresu dat (domyślnie: 14 dni wstecz, 60 dni naprzód;
--  maksymalnie 400 dni), w tej samej postaci co dotąd.
--  Zlecenie zaczęte dzień przed początkiem zakresu też jest brane
--  (zmiana nocna wchodzi w zakres).
-- =====================================================================

-- stara wersja bez parametrów musi zniknąć, inaczej wywołanie byłoby niejednoznaczne
drop function if exists public.plan_podglad();

create or replace function public.plan_podglad(p_od date default null, p_do date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  pokaz jsonb;
  od    date;
  doo   date;
begin
  if public.plan_moja_rola() is null then
    raise exception 'Brak dostępu do planu.';
  end if;

  od  := coalesce(p_od, current_date - 14);
  doo := coalesce(p_do, current_date + 60);
  if doo - od > 400 then
    raise exception 'Zakres dat jest za duży (maksymalnie 400 dni).';
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
              from public.plan_zlecenia z
              where z.data between od - 1 and doo)
  );
end $$;

revoke all on function public.plan_podglad(date, date) from public, anon;
grant execute on function public.plan_podglad(date, date) to authenticated;

select 'plan_podglad z oknem dat gotowy' as wynik;
