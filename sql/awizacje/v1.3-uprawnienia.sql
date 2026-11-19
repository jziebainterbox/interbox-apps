-- =====================================================================
--  AWIZACJA v1.3 — administrator i uprawnienia
--  Supabase → SQL Editor → New query → wklej CAŁY plik → Run.
--  Uruchomić RAZ, przed wgraniem programu v1.3 na GitHub
--  (wcześniej musi być uruchomiony awizacja-v1.2-kolory.sql).
--  Można uruchomić ponownie — nic nie kasuje.
--
--  Co robi:
--    * konto „admin” zostaje administratorem,
--    * tylko administrator zakłada konta, zmienia hasła, blokuje i nadaje uprawnienia,
--    * uprawnienie „firmy”      – dodawanie i edycja firm przewoźników,
--    * uprawnienie „ustawienia” – godziny, dni wolne, rampy,
--    * rezerwacje i listę tygodnia ma każdy z biura (bez zmian),
--    * zawsze musi zostać co najmniej jeden aktywny administrator.
-- =====================================================================

alter table public.profile          add column if not exists admin       boolean not null default false;
alter table public.profile          add column if not exists uprawnienia text[]  not null default '{}';
alter table public.konta_oczekujace add column if not exists admin       boolean not null default false;
alter table public.konta_oczekujace add column if not exists uprawnienia text[]  not null default '{}';

-- konto „admin” = administrator (tylko jeśli jeszcze nikt nim nie jest)
update public.profile set admin = true
 where login = 'admin' and not exists (select 1 from public.profile where admin);

-- stare zaproszenie dla „admin” z pierwszej instalacji nie jest już potrzebne
delete from public.konta_oczekujace where login = 'admin';


-- funkcje: czy zalogowany jest administratorem / ma uprawnienie ----------
create or replace function public.jestem_adminem() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin from public.profile p
                    where p.id = auth.uid() and p.aktywny and p.rola = 'logistyka'), false)
$$;

create or replace function public.mam_uprawnienie(p_upr text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin or p_upr = any (p.uprawnienia) from public.profile p
                    where p.id = auth.uid() and p.aktywny and p.rola = 'logistyka'), false)
$$;


-- nowe konto przejmuje uprawnienia nadane przy zakładaniu -----------------
create or replace function public.awizacja_nowe_konto() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k public.konta_oczekujace%rowtype;
begin
  select * into k
  from public.konta_oczekujace
  where lower(email) = lower(new.email) and wygasa > now();

  if not found then
    raise exception 'Konto % nie zostało przygotowane w programie Awizacja.', new.email;
  end if;

  insert into public.profile (id, login, imie, rola, firma_id, admin, uprawnienia)
  values (new.id, lower(k.login), k.imie, k.rola, k.firma_id,
          k.rola = 'logistyka' and k.admin,
          case when k.rola = 'logistyka' then k.uprawnienia else '{}' end);

  delete from public.konta_oczekujace where email = k.email;
  return new;
end $$;


-- ochrona: zawsze co najmniej jeden aktywny administrator -----------------
create or replace function public.profile_ochrona_admina() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.admin and old.aktywny and (not new.admin or not new.aktywny) then
    if not exists (select 1 from public.profile
                    where id <> old.id and admin and aktywny and rola = 'logistyka') then
      raise exception 'Musi zostać co najmniej jeden aktywny administrator.';
    end if;
  end if;
  if new.rola <> 'logistyka' then
    new.admin := false;
    new.uprawnienia := '{}';
  end if;
  return new;
end $$;

drop trigger if exists profile_ochrona_admina on public.profile;
create trigger profile_ochrona_admina
  before update on public.profile
  for each row execute function public.profile_ochrona_admina();


-- zmiana hasła innym – tylko administrator --------------------------------
create or replace function public.ustaw_haslo(p_login text, p_haslo text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid;
begin
  if not public.jestem_adminem() then
    raise exception 'Tylko administrator może zmieniać hasła innych kont.';
  end if;
  if length(coalesce(p_haslo, '')) < 6 then
    raise exception 'Hasło musi mieć co najmniej 6 znaków.';
  end if;
  select id into uid from public.profile where login = lower(p_login);
  if uid is null then
    raise exception 'Nie ma konta %.', p_login;
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_haslo, extensions.gen_salt('bf')),
         updated_at = now()
   where id = uid;
end $$;

revoke all on function public.ustaw_haslo(text, text) from public, anon;
grant execute on function public.ustaw_haslo(text, text) to authenticated;


-- nowe kłódki ---------------------------------------------------------------
-- konta: zmienia tylko administrator (czytać mogą wszyscy z biura – do podpisów „kto utworzył”)
drop policy if exists profile_zmiana on public.profile;
create policy profile_zmiana on public.profile for update to authenticated
  using ((select public.jestem_adminem()))
  with check ((select public.jestem_adminem()));

-- przygotowanie nowych kont: tylko administrator
drop policy if exists oczekujace_logistyka on public.konta_oczekujace;
drop policy if exists oczekujace_admin     on public.konta_oczekujace;
create policy oczekujace_admin on public.konta_oczekujace for all to authenticated
  using ((select public.jestem_adminem()))
  with check ((select public.jestem_adminem()));

-- firmy: dodawanie i zmiana – administrator albo uprawnienie „firmy”
drop policy if exists firmy_dodawanie on public.firmy;
drop policy if exists firmy_zmiana    on public.firmy;
create policy firmy_dodawanie on public.firmy for insert to authenticated
  with check ((select public.mam_uprawnienie('firmy')));
create policy firmy_zmiana on public.firmy for update to authenticated
  using ((select public.mam_uprawnienie('firmy')))
  with check ((select public.mam_uprawnienie('firmy')));

-- rampy i ustawienia – administrator albo uprawnienie „ustawienia”
drop policy if exists rampy_dodawanie   on public.rampy;
drop policy if exists rampy_zmiana      on public.rampy;
drop policy if exists ustawienia_zmiana on public.ustawienia;
create policy rampy_dodawanie on public.rampy for insert to authenticated
  with check ((select public.mam_uprawnienie('ustawienia')));
create policy rampy_zmiana on public.rampy for update to authenticated
  using ((select public.mam_uprawnienie('ustawienia')))
  with check ((select public.mam_uprawnienie('ustawienia')));
create policy ustawienia_zmiana on public.ustawienia for update to authenticated
  using ((select public.mam_uprawnienie('ustawienia')))
  with check ((select public.mam_uprawnienie('ustawienia')));

select login, rola, admin, uprawnienia, aktywny from public.profile order by admin desc, login;
