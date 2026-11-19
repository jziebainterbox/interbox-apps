# Struktura bazy (Supabase, projekt „Awizacje Inter-Box”)

Pliki uruchamia się w **Supabase → SQL Editor → New query → wklej cały plik → Run**, w kolejności numerów.
Każdy plik można uruchomić ponownie — niczego nie kasuje (wyjątek opisany w samym pliku).

## awizacje/
`00-baza.sql` (tabele, funkcje, zabezpieczenia RLS), potem po kolei: v1.2 … v1.13.

## planowanie/
`02-plan-dostep-i-konta.sql` → `04-plan-dane.sql` → `07-plan-podglad-okno.sql`.
`02-wycofanie.sql` — cofnięcie zmian z pliku 02 (tylko w razie problemów).

## Czego tu celowo nie ma
- **Danych** (awizacje, dostawcy, konta, plan) — są tylko w bazie.
- **`05-predkosci-dane.sql`** — prędkości z nazwami klientów i produktów; trzymane lokalnie.
- Plików prób i testów (konta testowe, symulacje) — trzymane lokalnie.
