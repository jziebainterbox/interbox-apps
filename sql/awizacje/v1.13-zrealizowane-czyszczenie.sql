-- =====================================================================
--  AWIZACJA v1.13 — „zrealizowane” i czyszczenie awizacji przez admina
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Można uruchomić ponownie — sam plik niczego nie kasuje.
--
--  Co robi:
--    * awizacja dostaje znacznik „zrealizowana” (kiedy i kto zaznaczył),
--      zaznacza i odznacza biuro (logistyka); dostawca tylko widzi,
--      a zrealizowanej awizacji nie może już zmienić ani odwołać,
--    * funkcja wyczysc_awizacje(): usuwa WSZYSTKIE awizacje (np. po testach,
--      przed startem); wywołać ją może WYŁĄCZNIE konto o loginie „admin”.
--      Dostawcy, konta, przerwy i blokady zostają.
-- =====================================================================

alter table public.awizacje add column if not exists zrealizowana timestamptz;
alter table public.awizacje add column if not exists zrealizowal  uuid;

create or replace function public.awizacje_realizacja() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rola text := public.moja_rola();
begin
  if tg_op = 'INSERT' then
    new.zrealizowana := null;
    new.zrealizowal  := null;
    return new;
  end if;

  if rola = 'przewoznik' then
    if old.zrealizowana is not null then
      raise exception 'Ta awizacja jest już zrealizowana – zmiany tylko przez logistykę.';
    end if;
    new.zrealizowana := old.zrealizowana;
    new.zrealizowal  := old.zrealizowal;
  elsif new.zrealizowana is distinct from old.zrealizowana then
    new.zrealizowal := case when new.zrealizowana is null then null else auth.uid() end;
  else
    new.zrealizowal := old.zrealizowal;
  end if;
  return new;
end $$;

drop trigger if exists awizacje_realizacja on public.awizacje;
create trigger awizacje_realizacja
  before insert or update on public.awizacje
  for each row execute function public.awizacje_realizacja();


create or replace function public.wyczysc_awizacje() returns int
language plpgsql security definer set search_path = public as $$
declare
  ja  public.profile%rowtype;
  ile int;
begin
  select * into ja from public.profile where id = auth.uid();
  if not found or ja.login <> 'admin' or not ja.aktywny or not public.sesja_wazna() then
    raise exception 'Czyścić awizacje może tylko administrator (login admin).';
  end if;
  delete from public.awizacje where id is not null;   -- zajętość znika razem z nimi
  get diagnostics ile = row_count;
  return ile;
end $$;

revoke all on function public.wyczysc_awizacje() from public, anon;
grant execute on function public.wyczysc_awizacje() to authenticated;

select 'v1.13 gotowe' as wynik, count(*) as awizacji_w_bazie from public.awizacje;
