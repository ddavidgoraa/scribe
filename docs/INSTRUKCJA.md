# Scribe — instrukcja obsługi

Scribe to minimalistyczny edytor Markdown dla macOS z obsługą wzorów matematycznych (LaTeX), wzorowany na iA Writer.
Piszesz w zwykłych plikach `.md`: aplikacja niczego w nich nie dopisuje, a formatowanie widać od razu podczas pisania.

Wersja: 0.1 · Wymagania: macOS 14 Sonoma lub nowszy, Mac z procesorem Apple (M1 i nowsze).

---

## Spis treści

1. [Instalacja](#1-instalacja)
2. [Pierwsze uruchomienie: biblioteka](#2-pierwsze-uruchomienie-biblioteka)
3. [Notatki: tworzenie, nazwy, zapis](#3-notatki-tworzenie-nazwy-zapis)
4. [Pisanie: podgląd na żywo](#4-pisanie-podgląd-na-żywo)
5. [Matematyka](#5-matematyka)
6. [Obrazki](#6-obrazki)
7. [Formatowanie skrótami](#7-formatowanie-skrótami)
8. [Szukanie: Quick Open i wyszukiwanie w bibliotece](#8-szukanie-quick-open-i-wyszukiwanie-w-bibliotece)
9. [Tryby pisania: fokus i maszyna do pisania](#9-tryby-pisania-fokus-i-maszyna-do-pisania)
10. [Wygląd i ustawienia](#10-wygląd-i-ustawienia)
11. [Kopiowanie jako HTML](#11-kopiowanie-jako-html)
12. [Zmiany plików poza Scribe](#12-zmiany-plików-poza-scribe)
13. [Ściągawka skrótów](#13-ściągawka-skrótów)
14. [Ograniczenia wersji 0.1](#14-ograniczenia-wersji-01)

---

## 1. Instalacja

1. Otwórz plik `Scribe-0.1.0-arm64.dmg`.
2. Przeciągnij **Scribe** do folderu **Applications**.
3. Uruchom Scribe z Launchpada lub folderu Aplikacje.

Aplikacja nie jest jeszcze notaryzowana przez Apple, więc przy pierwszym uruchomieniu macOS ją zablokuje. Żeby ją odblokować:

- otwórz **Ustawienia systemowe → Prywatność i ochrona**, przewiń w dół i kliknij **Otwórz mimo to**, **albo**
- w Terminalu wpisz:
  ```sh
  xattr -dr com.apple.quarantine /Applications/Scribe.app
  ```

Wystarczy to zrobić raz.

## 2. Pierwsze uruchomienie: biblioteka

**Biblioteka** to zwykły folder na dysku z Twoimi notatkami (np. `~/Documents/Notatki`, folder w iCloud Drive albo repozytorium git).

- Przy pierwszym uruchomieniu kliknij **Open Library…** albo naciśnij **⌘O** i wskaż folder.
- Scribe zapamiętuje ten folder i otwiera go przy kolejnych uruchomieniach.
- Żeby przełączyć się na inny folder, ponownie użyj **⌘O**. Naraz otwarta jest jedna biblioteka.

### Panel biblioteki (sidebar)

- Pokazuje drzewo podfolderów i notatek. Widoczne są tylko pliki `.md` i `.markdown`, a inne pliki (np. obrazki) są pomijane.
- Ukryte pliki i foldery (zaczynające się od kropki, np. `.git`) są pomijane.
- Kliknij notatkę, żeby ją otworzyć. Kliknięcie folderu go rozwija.
- **Sortowanie:** menu **View → Sort Notes By**, do wyboru:
  - **Name**: alfabetycznie, z naturalną kolejnością liczb („Notatka 2” przed „Notatka 10”);
  - **Date Modified**: najnowsze na górze.

  Foldery są zawsze na górze, alfabetycznie.
- **Menu kontekstowe** (prawy przycisk myszy):
  - na folderze: **New Note** (nowa notatka w tym folderze), **Show in Finder**;
  - na notatce: **Rename…** (zmiana nazwy), **Show in Finder**;
  - na pustym miejscu panelu: **New Note** w głównym folderze biblioteki.
- **⌘⇧L** chowa i pokazuje panel.

## 3. Notatki: tworzenie, nazwy, zapis

### Nowa notatka

**⌘N** (albo ikona ołówka na pasku narzędzi) tworzy plik `Untitled.md` w folderze aktualnie otwartej notatki. Jeśli żadna nie jest otwarta, plik trafia do głównego folderu biblioteki. Kolejne puste notatki dostają nazwy `Untitled 2.md`, `Untitled 3.md` itd.

### Nazwa z pierwszej linii

Nie musisz nadawać nazw ręcznie, bo Scribe nazywa notatkę według jej **pierwszej linii**:

- wpisz `# Lista zakupów`, a po zapisie plik zmieni nazwę na `Lista zakupów.md`;
- gdy zmienisz pierwszą linię, nazwa pliku też się zmieni.

Zasada działa także po ponownym uruchomieniu aplikacji. Dotyczy notatek, które:

- nazywają się `Untitled` lub `Untitled N`, albo
- mają nazwę zgodną z pierwszą linią (również z dopiskiem ` 2`, ` 3`, gdy nazwa była zajęta).

**Ręczna zmiana nazwy na inną niż pierwsza linia wyłącza tę funkcję dla danej notatki.**

Szczegóły:

- znaki `#` na początku linii są pomijane;
- znaki niedozwolone w nazwach plików (`/`, `\`, `:`) są zamieniane na `-`;
- nazwa ma najwyżej 80 znaków;
- gdy nazwa jest zajęta, Scribe dopisze ` 2`, ` 3` itd.

Funkcję można wyłączyć w **Settings (⌘,) → Name notes after their first line**.

### Zmiana nazwy ręcznie

Kliknij notatkę w panelu prawym przyciskiem → **Rename…**, wpisz nową nazwę (bez `.md`) i zatwierdź.

### Zapis

**Nie ma przycisku „Zapisz”**, bo Scribe zapisuje wszystko sam:

- około 1 sekundy po tym, jak przestaniesz pisać,
- przy przełączeniu na inną notatkę,
- przy przejściu do innej aplikacji,
- przy zamykaniu Scribe.

Zapis jest atomowy: plik nigdy nie zostaje zapisany do połowy, nawet przy awarii. **⌘Z** cofa zmiany jak w każdym edytorze.

## 4. Pisanie: podgląd na żywo

Scribe pokazuje sformatowany tekst od razu, bez osobnego okna podglądu. Znaczniki Markdown (`**`, `#`, `[]()` itd.) są **ukryte**, dopóki kursor ich nie dotknie:

| Element | Kiedy widać znaczniki |
|---|---|
| **pogrubienie**, *kursywa*, ~~przekreślenie~~, `kod`, linki, przypisy, `$wzór$` | gdy kursor dotyka elementu (także tuż przed nim lub tuż za nim) |
| nagłówki `#` | gdy kursor jest w linii nagłówka |
| bloki: `$$ … $$`, bloki kodu ```` ``` ````, cytaty `>` | gdy kursor jest wewnątrz bloku |

- Gdy **zaznaczasz tekst myszą**, znaczniki się nie odsłaniają, więc tekst nie skacze pod kursorem.
- Znaczniki **zawsze widoczne** (przygaszone): listy (`-`, `1.`), pola zadań (`[ ]`, `[x]`), tabele, linia pozioma (`---`), definicje przypisów, HTML.
- Plik na dysku zawsze zawiera pełny Markdown. Ukrywanie dotyczy tylko wyświetlania.

### Obsługiwana składnia

CommonMark i GitHub Flavored Markdown oraz rozszerzenia:

| Składnia | Przykład |
|---|---|
| Nagłówki | `# H1` … `###### H6`, albo podkreślenie `===` / `---` |
| Pogrubienie / kursywa | `**pogrubienie**`, `*kursywa*`, `***oba***` |
| Przekreślenie | `~~tekst~~` |
| Kod w linii / blok kodu | `` `kod` ``, ```` ```swift … ``` ```` |
| Linki | `[tekst](https://adres)`, `<https://adres>` |
| Obrazki | `![opis](assets/zdjecie.png)` |
| Cytaty | `> cytat` |
| Listy, listy zadań | `- punkt`, `1. punkt`, `- [ ] zadanie`, `- [x] zrobione` |
| Tabele | `\| a \| b \|` z wierszem `\|---\|---\|` |
| Przypisy | `tekst[^1]` oraz `[^1]: treść przypisu` |
| Wzory | `$…$`, `$$…$$`, zob. [Matematyka](#5-matematyka) |

Tabele są wyświetlane jako wyrównany tekst o stałej szerokości znaków. Nie ma edytora komórek.

## 5. Matematyka

### Wzór w tekście

Otocz wzór pojedynczymi znakami dolara: `$E = mc^2$`.

Gdy kursor jest poza wzorem, widzisz go wyrenderowanego w linii tekstu. Gdy kursor go dotknie, widzisz źródło LaTeX.

### Wzór blokowy

Umieść wzór w osobnych liniach między `$$`:

```
$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$
```

- Gdy kursor jest poza blokiem, wzór jest wyświetlany jako duży, wyrenderowany blok.
- Gdy edytujesz blok, widzisz źródło, a **pod nim podgląd na żywo**, który zmienia się przy każdym znaku.

### Błędy

Jeśli wzór zawiera błąd (np. nieznaną komendę), Scribe pokazuje go jako **czerwone źródło**. Najedź na niego myszą, żeby zobaczyć komunikat błędu.

### Co jest obsługiwane

Wzory renderuje biblioteka SwiftMath. Obsługuje ona duży podzbiór LaTeX-a: ułamki, pierwiastki, indeksy, całki, sumy, litery greckie, macierze i większość symboli. Niektóre rzadsze polecenia i środowiska z pakietów AMS mogą nie działać.

**Wskazówka:** nawiasy klamrowe `{ }` we wzorze muszą być domknięte, inaczej fragment nie zostanie rozpoznany jako wzór.

Skrót **⌘⇧M** otacza zaznaczenie znakami `$`. Gdy zaznaczenie obejmuje kilka linii, tworzy blok `$$`.

## 6. Obrazki

Obrazek wstawiony w **osobnej linii**:

```
![Wykres](assets/wykres.png)
```

jest wyświetlany jako podgląd dopasowany do szerokości kolumny tekstu. Gdy kursor dotknie linii, zobaczysz źródło.

- Ścieżki są liczone **względem folderu notatki**. Działają też ścieżki bezwzględne (`/…`), z tyldą (`~/…`) oraz ze spacjami: `![x](<moje zdjęcie.png>)` albo `![x](moje%20zdjęcie.png)`.
- Obrazki z internetu (`https://…`) **nie są pobierane**. Widać wtedy tylko opis.
- Obrazek w środku zdania nie jest wyświetlany jako podgląd. Widać tylko jego opis.
- Gdy podmienisz plik obrazka na dysku, nowy podgląd pojawi się przy kolejnej edycji okolicy obrazka lub po ponownym otwarciu notatki.

## 7. Formatowanie skrótami

Wszystkie polecenia są w menu **Format** i działają jak przełączniki: drugie użycie usuwa formatowanie.

| Skrót | Działanie |
|---|---|
| **⌘B** | pogrubienie `**…**` |
| **⌘I** | kursywa `*…*` |
| **⌘⇧X** | przekreślenie `~~…~~` |
| **⌘⇧C** | kod `` `…` `` |
| **⌘⇧M** | wzór `$…$` (kilka linii: blok `$$`) |
| **⌘K** | link `[zaznaczenie](url)`, z zaznaczonym słowem `url` do nadpisania. Gdy zaznaczysz adres, powstaje `[](adres)` |
| **⌘1** … **⌘6** | nagłówek poziomu 1–6. Ten sam poziom drugi raz usuwa nagłówek |

- Bez zaznaczenia **⌘B**, **⌘I** itd. wstawiają pustą parę znaczników z kursorem w środku.
- Spacja na końcu zaznaczenia jest pomijana.
- Każdą zmianę cofniesz przez **⌘Z**.

## 8. Szukanie: Quick Open i wyszukiwanie w bibliotece

### Quick Open: ⌘P

Szybkie otwieranie notatki po nazwie:

1. Naciśnij **⌘P** i zacznij pisać fragment nazwy lub ścieżki, np. `plan` albo `proj sc`.
2. Dopasowanie jest „rozmyte”: litery nie muszą stać obok siebie, a wielkość liter i polskie znaki nie mają znaczenia (`ges` znajdzie `Gęś`).
3. **↑ / ↓** wybiera wynik, **⏎** otwiera, **Esc** zamyka okno.

### Wyszukiwanie w bibliotece: ⌘⇧F

Szukanie po treści wszystkich notatek:

1. Naciśnij **⌘⇧F**. Kursor przejdzie do pola wyszukiwania nad panelem biblioteki.
2. Wpisz jedno lub kilka słów. Wyniki pojawiają się na bieżąco.
3. Kliknij linię w wynikach: notatka się otworzy, a trafienie zostanie zaznaczone i przewinięte na ekran.
4. Kliknij nazwę notatki w nagłówku wyniku, żeby otworzyć ją bez przewijania.
5. Wyczyść pole wyszukiwania, żeby wrócić do drzewa notatek.

Jak działa wyszukiwanie:

- **wielkość liter i polskie znaki są ignorowane**: `lukasz` znajdzie „Łukasz”, a `zolc` znajdzie „żółć”;
- przy kilku słowach notatka musi zawierać **wszystkie** (w treści lub w nazwie);
- notatki, których **nazwa** pasuje do zapytania, są na górze, a pozostałe są ułożone według liczby trafień;
- przy każdej notatce widać do 5 pasujących linii.

Indeks wyszukiwania aktualizuje się sam, także gdy pliki zmieniają się poza Scribe.

### Szukanie w bieżącej notatce: ⌘F

Standardowy pasek wyszukiwania macOS:

- **⌘F** otwiera pasek, **⌘G** / **⌘⇧G** przechodzą do następnego i poprzedniego trafienia;
- **⌘E** używa zaznaczonego tekstu jako wyszukiwanej frazy;
- **⌥⌘F** otwiera zamianę tekstu.

## 9. Tryby pisania: fokus i maszyna do pisania

Oba tryby włączysz w menu **View**. Ustawienie jest zapamiętywane.

### Fokus: ⌘D

Wszystko poza **bieżącym akapitem** blednie, więc widzisz tylko to, nad czym pracujesz.

Akapit to blok tekstu między pustymi liniami, więc tekst złamany ręcznie w kilku liniach jest podświetlony w całości. Przygasają też wzory, obrazki i bloki kodu poza akapitem.

### Maszyna do pisania: ⌘T

Linia z kursorem pozostaje **na środku ekranu**, a tekst przesuwa się pod nią. Na początku i końcu dokumentu jest dodatkowy margines, żeby nawet pierwsza i ostatnia linia mogły stanąć pośrodku.

Tryby można łączyć.

## 10. Wygląd i ustawienia

- **Kolumna tekstu** ma około 64 znaków szerokości i jest wyśrodkowana w oknie, jak w iA Writer.
- **Jasny i ciemny motyw** zmieniają się automatycznie razem z ustawieniem macOS.
- **Rozmiar tekstu:**
  - **⌘+** powiększa,
  - **⌘−** pomniejsza,
  - **⌘0** przywraca 16 pt.

  Dostępny zakres to 12–26 pt.

### Okno ustawień: ⌘,

| Ustawienie | Opis |
|---|---|
| **Font** | iA Writer **Duo** (domyślny), **Mono** lub **Quattro**. Kod zawsze jest pisany fontem Mono |
| **Size** | rozmiar tekstu (12–26 pt) |
| **Name notes after their first line** | automatyczne nazywanie notatek, zob. [Nazwa z pierwszej linii](#nazwa-z-pierwszej-linii) |

## 11. Kopiowanie jako HTML

**Edit → Copy as HTML** (**⌥⌘C**) kopiuje zaznaczony fragment, a bez zaznaczenia całą notatkę, jako HTML:

- wklejony do aplikacji obsługującej formatowanie (Mail, Pages, edytory stron) daje sformatowany tekst;
- wklejony do zwykłego edytora tekstu daje kod HTML.

Wzory są w tej wersji kopiowane jako źródło LaTeX (w elemencie `<span class="math">`).

## 12. Zmiany plików poza Scribe

Notatki to zwykłe pliki, więc możesz je edytować innymi programami, synchronizować (iCloud, Dropbox) albo trzymać w gicie. Scribe obserwuje folder biblioteki:

- **nowe, usunięte i przemianowane pliki** pojawiają się w panelu automatycznie;
- jeśli plik **otwartej notatki** zmieni się na dysku, a Ty nie masz niezapisanych zmian, notatka po cichu się przeładuje, a kursor zostanie na swoim miejscu;
- jeśli masz **niezapisane zmiany**, nad tekstem pojawi się pasek:
  - **Reload**: weź wersję z dysku (Twoje zmiany przepadną),
  - **Keep Mine**: zachowaj swoją wersję i nadpisz plik;
- jeśli plik otwartej notatki zostanie **usunięty**:
  - bez niezapisanych zmian notatka się zamknie,
  - z niezapisanymi zmianami pojawi się pasek **Close / Keep Mine**, gdzie **Keep Mine** odtworzy plik.

Dopóki pasek jest widoczny, autozapis jest wstrzymany, więc nic nie zostanie nadpisane bez Twojej decyzji.

## 13. Ściągawka skrótów

| Skrót | Działanie |
|---|---|
| **⌘O** | otwórz bibliotekę (folder) |
| **⌘N** | nowa notatka |
| **⌘P** | Quick Open: otwórz notatkę po nazwie |
| **⌘⇧F** | szukaj w całej bibliotece |
| **⌘F** | szukaj w notatce |
| **⌘B / ⌘I** | pogrubienie / kursywa |
| **⌘⇧X** | przekreślenie |
| **⌘⇧C** | kod |
| **⌘⇧M** | wzór |
| **⌘K** | link |
| **⌘1 … ⌘6** | nagłówek 1–6 |
| **⌥⌘C** | kopiuj jako HTML |
| **⌘D** | tryb fokus |
| **⌘T** | tryb maszyny do pisania |
| **⌘⇧L** | pokaż/ukryj panel biblioteki |
| **⌘+ / ⌘− / ⌘0** | większy / mniejszy / domyślny tekst |
| **⌘,** | ustawienia |
| **⌘Z / ⌘⇧Z** | cofnij / ponów |

## 14. Ograniczenia wersji 0.1

- **Brak eksportu** do HTML/PDF (jest tylko „Copy as HTML”). Eksport jest planowany w wersji 0.2.
- **Wklejanie i przeciąganie obrazków** do edytora nie jest jeszcze obsługiwane. Obrazki dodawaj jako pliki w folderze i wstawiaj składnią `![](ścieżka)`.
- **Jedna biblioteka i jedno okno** naraz.
- **Tabele** są widoczne jako tekst, bez edytora komórek.
- **Fokus na zdaniu** (a nie na akapicie) jest planowany w wersji 0.2.
- Strzałki przechodzą także przez ukryte znaczniki. Gdy kursor dotknie elementu, jego znaczniki się odsłonią.
- Interfejs jest po angielsku. Polska wersja jest planowana w wersji 0.2.
- Aplikacja działa tylko na Macach z procesorem Apple i nie jest notaryzowana (zob. [Instalacja](#1-instalacja)).

### Gdzie Scribe trzyma dane

- Twoje notatki: wyłącznie w wybranym folderze, jako zwykłe pliki `.md`.
- Ustawienia aplikacji (ścieżka biblioteki, sortowanie, font, tryby): w preferencjach macOS pod identyfikatorem `dev.dawidgora.scribe`.

Scribe nie wysyła niczego do internetu.
