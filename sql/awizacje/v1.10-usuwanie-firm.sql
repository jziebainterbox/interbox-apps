-- =====================================================================
--  AWIZACJA v1.10 — usuwanie firm przewoźników (tylko konto „admin”)
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * dodaje funkcję usun_firme(): firma znika na stałe razem z kontami
--      jej przewoźników (login i hasło przestają działać),
--    * wywołać ją może WYŁĄCZNIE zalogowane konto o loginie „admin”,
--    * wszystkie awizacje tej firmy (minione i przyszłe) ZOSTAJĄ –
--      w programie widać przy nich „firma usunięta”.
-- =====================================================================

-- awizacje mają zostać po usunięciu firmy: zdejmij powiązanie awizacje → firmy
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.awizacje'::regclass and contype = 'f'
              and confrelid = 'public.firmy'::regclass
  loop
    execute format('alter table public.awizacje drop constraint %I', c.conname);
  end loop;
end $$;


create or replace function public.usun_firme(p_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare
  ja    public.profile%rowtype;
  k     record;
  konta int := 0;
begin
  select * into ja from public.profile where id = auth.uid();
  if not found or ja.login <> 'admin' or not ja.aktywny then
    raise exception 'Firmy może usuwać tylko administrator (login admin).';
  end if;
  if not exists (select 1 from public.firmy where id = p_id) then
    raise exception 'Nie ma takiej firmy.';
  end if;

  delete from public.konta_oczekujace where firma_id = p_id;

  for k in select id from public.profile where firma_id = p_id loop
    delete from public.profile where id = k.id;
    begin
      delete from auth.users where id = k.id;   -- login i hasło znikają
    exception when insufficient_privilege then
      null;  -- bez profilu konto i tak nie ma dostępu do niczego
    end;
    konta := konta + 1;
  end loop;

  delete from public.firmy where id = p_id;
  return konta;
end $$;

revoke all on function public.usun_firme(bigint) from public, anon;
grant execute on function public.usun_firme(bigint) to authenticated;

select 'usun_firme gotowe' as wynik;
