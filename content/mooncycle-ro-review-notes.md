# MoonCycle — revizie localizare română

Versiune pregătită pe 27 octombrie 2026, pentru integrare și verificare în aplicație.

## Fișiere
- `mooncycle-ro-revizuit.json` — structura originală păstrată (`_about`, `app`, `partner`, `her`). Au fost modificate numai valorile `ro`.
- `mooncycle-ro-modificari.csv` — comparație între textele inițiale și variantele revizuite, după secțiune și ID.

## Control tehnic
- Verificate 1.119 intrări: 569 interfață, 230 partener, 320 pentru ea.
- Modificate 551 valori: 267 interfață, 162 partener, 122 pentru ea.
- Toate valorile `id`, `where`, `en` și structura principală au rămas identice.
- Validare automată reușită: variabilele dintre acolade (`{n}`, `{name}`, `{date}`, `{symptom}` etc.) sunt identice cu cele din original și cele din `en`, fără lipsuri sau variabile suplimentare.
- Fișierul JSON este valid și păstrează diacriticele UTF-8.

## Stil
- Interfață: familiar, clar, adresare la singular cu „tu”; text de buton scurt unde e posibil.
- Partener: glume adaptate idiomatic în română (inițiativa lui, timpul în doi, vase, planuri), fără clișee despre hormoni și dispoziția ei.
- Pentru ea: limbaj empatic, cu termeni medicali standard, fără inventarea diagnosticului pe baza ciclului.
- Termeni preferați: „partajare”, „recomandare” sau „mesaj”, „mesaj rapid/bilețel” în loc de „semnal”, „flux menstrual”, „medicul de familie”, „Ajutor acum”.

## De verificat înainte de lansare
1. **Previzualizare vizuală pe ambele platforme:** lungimea unor texte românești poate depăși spațiul disponibil; verificați butoanele și cardurile pe ecrane mici.
2. **Flexiunea variabilelor:** unele construcții sunt valabile doar când `{n}` are valoarea 1 în șablonul singular; verificați selectarea corectă a șablonului. `{name}` este păstrat astfel încât să nu fie nevoie de genitivul numelui.
3. **Propozițiile construite din fragmente:** testați `opening.P02` împreună cu `windowPhrase.*`, `card.H01` cu `when.*` și `loggedPhrase.*`, precum și toate valorile variabilei `{reason}`. Validarea placeholders nu garantează acordurile în fiecare combinație.
4. **Ajutor medical pentru România:** există rutare către 112 și medicul de familie. Secțiunea cu 0800 801 200 trebuie verificată inclusiv pentru programul real și pentru numărul format de buton. Pagini publice diferă privind zilele de funcționare; nu afișați „non-stop” pentru acea linie. Verificați că butonul apelează numărul afișat.
5. **Screening de col uterin:** mesajele originale au referințe NHS/UK; pentru utilizatoarele din România verificați regulile locale, eligibilitatea, sursa și logica de afișare (nu doar traducerea).
6. **Conținut medical și protecția datelor:** revizia este lingvistică/editorială, nu aviz clinic, legal sau verificare a implementării. Păstrați evaluarea separată a textelor medicale și a fluxului de date AI.
7. **Coerența vocabularului:** dacă în aplicație secțiunea „Azi” / „Partener” / „Ajutor acum” apare sub alt nume, adaptați toate referințele vizibile la denumirea reală.

