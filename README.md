# INTER-BOX — aplikacje firmowe

Jedno miejsce dla aplikacji INTER-BOX: wspólny wygląd (INTER-BOX UI), aplikacje i struktura bazy danych.

## Aplikacje

| Aplikacja | Folder | Adres | Dla kogo |
|---|---|---|---|
| **Awizacje** — rezerwacja okien na rampie | `awizacje/` | https://jziebainterbox.github.io/interbox-apps/awizacje/ | biuro, dostawcy |
| **Planer produkcji** — plan pracy maszyn | `planer/` | https://jziebainterbox.github.io/interbox-apps/planer/ | planiści |
| **Plan produkcji** — podgląd planu (TV, sprzedaż) | `podglad/` | https://jziebainterbox.github.io/interbox-apps/podglad/ | TV na hali, sprzedaż |
| **Wzornik INTER-BOX UI** — katalog wyglądu | `katalog/` | https://jziebainterbox.github.io/interbox-apps/katalog/ | budowa nowych aplikacji |

Wszystkie aplikacje korzystają z jednej bazy Supabase (projekt „Awizacje Inter-Box”) i jednego konta użytkownika.
Dane są w bazie, za logowaniem — w tym repozytorium nie ma danych firmy ani haseł (jest tylko publiczny klucz Supabase, który z założenia jest jawny; dostępu pilnują zabezpieczenia RLS w bazie).

## Struktura

```
wspolne/     INTER-BOX UI v1 (interbox-ui-v1.css) + logo
katalog/     wzornik: wszystkie elementy wyglądu na żywo + kod + zasady
awizacje/    Awizacje
planer/      Planer produkcji
podglad/     Plan produkcji — podgląd na TV / dla sprzedaży
sql/         struktura bazy: plik bazowy + kolejne zmiany każdego modułu
```

## Zasady pracy

1. **Najpierw test, potem produkcja.** Każda zmiana sprawdzona w trybie demo / na kopii testowej.
2. **Każda zmiana opisana** w historii („Awizacje v1.13 – …”) i w `CHANGELOG.md`.
3. **Zmiana bazy = nowy plik w `sql/`**, nigdy edycja już uruchomionego. Pliki uruchamia się w Supabase SQL Editor w kolejności numerów.
4. **Wygląd tylko z INTER-BOX UI** (`wspolne/`, katalog). Wyjątek: podgląd planu na TV ma ciemny wygląd (nie razi w oczy na hali); wspólny jest tylko jego ekran logowania.
5. **Nowa aplikacja** startuje z szablonu (logowanie + szkielet) i dostaje własny folder.

## Stare adresy

Wcześniejsze adresy (`…/awizacjeinterbox/`, `…/planowanie/`, `…/pptv/podglad.html`) przekierowują tutaj.
