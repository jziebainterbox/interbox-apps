-- =====================================================================
--  AWIZACJA v1.5 — usuwanie kont (tylko konto „admin”)
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * dodaje funkcję usun_konto(): konto znika na stałe (login i hasło),
--    * wywołać ją może WYŁĄCZNIE zalogowane konto o loginie „admin”
--      (inni administratorzy też nie), nie można usunąć samego siebie,
--    * awizacje tej osoby zostają – w programie widać przy nich „konto usunięte”,
--    * blokowanie kont działa jak dotąd (konto zostaje i jest podpisane).
-- =====================================================================

create or replace function public.usun_konto(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  ja  public.profile%rowtype;
  cel public.profile%rowtype;
begin
  select * into ja from public.profile where id = auth.uid();
  if not found or ja.login <> 'admin' or not ja.aktywny then
    raise exception 'Konta może usuwać tylko administrator (login admin).';
  end if;
  if p_id = ja.id then
    raise exception 'Nie można usunąć własnego konta.';
  end if;
  select * into cel from public.profile where id = p_id;
  if not found then
    raise exception 'Nie ma takiego konta.';
  end if;

  delete from public.profile where id = p_id;
  begin
    delete from auth.users where id = p_id;      -- login i hasło znikają
  exception when insufficient_privilege then
    null;  -- gdyby Supabase nie pozwolił: bez profilu konto i tak nie ma dostępu do niczego
  end;
end $$;

revoke all on function public.usun_konto(uuid) from public, anon;
grant execute on function public.usun_konto(uuid) to authenticated;

select 'usun_konto gotowe' as wynik;
