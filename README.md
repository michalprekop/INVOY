# INVOY — web a Mac

Webová fakturačná aplikácia s Apple prihlásením, súkromným účtom a správou šablón.

- Web: https://invoy.xyz
- Mac (macOS 14+, Apple Silicon): https://invoy.xyz/download/mac
- Nainštalovaná kópia: `~/Applications/INVOY.app`.

## Názov a doména

Od verzie 1.2.0 sa produkt volá **INVOY**. Hlavná adresa je `https://invoy.xyz`; `www.invoy.xyz` sa presmeruje na hlavnú adresu. Pôvodná webová adresa zostáva funkčná aj počas šírenia DNS a používa rovnaké dáta. Jediná nainštalovaná aplikácia sa pri aktualizácii premenuje z `Faktúry.app` na `INVOY.app`.

Identita aplikácie `sk.faktury.desktop`, Apple Services ID, existujúce D1/R2 úložiská, formát záloh a kľúče lokálnych dát zostávajú kompatibilné s pôvodnou verziou. Ich zmena by odpojila existujúce účty, dáta alebo rozpracované údaje. Slovo „Faktúry“ v navigácii označuje druh dokumentov.

## Cloudový produkt

Administrácia je na **https://invoy.xyz/admin42** a vyžaduje prihlásený účet s rolou správcu. Starý odkaz `/?page=admin` presmeruje na novú adresu.

Prihlásenie cez Apple vytvorí účet čakajúci na aktiváciu. Správca v **Administrácia → Používatelia** klikne na riadok používateľa, aktivuje účet a zaškrtne dostupné šablóny vo veľkom formulári. Zoznam zobrazuje aj počet faktúr, uložených odberateľov a poslednú online aktivitu. Prvý prihlásený používateľ sa automaticky nestáva správcom. Šablóny sa vytvárajú v **Administrácia → Šablóny**, výberom rozloženia, farby, loga, textovej značky a pätičky. Knižnica aj editor automaticky zobrazujú skutočnú prvú stranu finálnej A4 faktúry s pevnými vymyslenými údajmi. Náhľad používa rovnaké vykreslenie ako PDF export, vrátane QR kódu, loga a pätičky; pri novej alebo upravenej šablóne sa obnoví bez ručného screenshotu. Ukážkové faktúry sa neukladajú do účtu. Šablóna sa používateľovi zobrazí až po pridelení.

Web aj Mac pracujú s rovnakým cloudovým účtom. Mac používa pôvodné natívne rozhranie, web rovnaké rozloženie: zoznam vľavo, úpravy priamo na faktúre vpravo. Faktúry a nastavenia sa ukladajú automaticky. Pri súbežnej úprave na inom zariadení server odmietne prepísanie novšej verzie; rozpracované zmeny zostávajú v zariadení. PDF je dostupné po platnom uložení. Čísla sú jedinečné v rámci účtu, vrátane koša. Kôš a história umožňujú obnovu. Šablóna na vystavenej faktúre je uložená spolu s dokumentom a neskoršia úprava alebo odobratie šablóny nemení jej vzhľad.

Údaje sú v Cloudflare D1, súkromné denné zálohy v R2. Používateľ si v Nastaveniach stiahne export alebo zálohu. Denná záloha je plánovaná na 02:15 UTC; správca vidí výsledok a môže ju spustiť aj ručne. Obnova pri strate počítača znamená prihlásiť sa do rovnakého Apple účtu. Prevádzková obnova databázy, bezpečnostné hranice a nasadenie sú v [docs/CLOUD.md](docs/CLOUD.md).

Mac distribúcia 1.2.37 je podpísaná Developer ID a notarizovaná Apple. Cloudová časť vyžaduje internet. Nový účet má v Nastaveniach prázdne logo aj podpis, kým si používateľ nenahrá vlastné. Pridelenie šablóny ani prepnutie účtu obrázky z iného profilu neprenesie. Nová inštalácia neobsahuje osobné údaje, bankové účty ani podpis pôvodného používateľa. Menu s menom účtu vpravo hore obsahuje **Nastavenia**, **Mac appka** a **Odhlásiť sa**, každú položku s príslušnou ikonou. Hlavné taby sú vycentrované; **Administrácia** sa zobrazuje iba správcom a v Macu otvára webovú administráciu. Na úzkych obrazovkách webu sú taby v samostatnom riadku. Logo firmy a podpis sa upravujú na spodku sekcie **Predvoľby faktúry**. Taby v Macu reagujú po celej ploche vrátane prázdnych okrajov. Náhľad vo Vzhľade sa vykresľuje na pozadí a pri návrate sa použije uložený výsledok; rýchle prepínanie zahodí zastarané požiadavky. Web pri prepínaní zbytočne neprepočítava zoznam faktúr a po dokončení ukladania rešpektuje posledný zvolený tab. Dropdowny používajú spoločný zaoblený zoznam, žltý otvorený ovládač a béžové podfarbenie položiek pri výbere, prejdení myšou aj ovládaní klávesnicou; podporujú klávesnicu aj zatvorenie klávesom Escape.

## Pôvodný lokálny režim

Pôvodné lokálne súbory zostávajú v pôvodnom priečinku a otvorenie cloudového účtu ich nemení. Od verzie 1.2.1 sa na prihlasovacej obrazovke už nezobrazuje vstup do pôvodnej lokálnej zálohy. Import do prázdneho cloudového účtu sa spúšťa vo webových **Nastaveniach → Zálohy → Importovať pôvodné faktúry**. Súbor musí byť pôvodný `database.json`; import zachová faktúry, odberateľov, nastavenia, obrázky a identifikátory. Opakovaný rovnaký import nevytvorí duplicity, obsadený účet sa neprepisuje.

## Funkcie

- Hornú lištu faktúry oddeľuje na webe aj Macu jemná sivobéžová čiara, takže s ňou papier pri skrolovaní nesplýva.

- Výber šablóny v lište faktúry zobrazuje ikonku maliarskej palety a čitateľný názov. Na úzkom mobile má vlastný riadok, aby sa názov nestratil medzi ikonovými tlačidlami.
- Pätička faktúry má tri rovnaké stĺpce: vystavil vľavo, web a e-mail pod sebou v strede, logo INVOY. s malým www.invoy.xyz vpravo. Ak je vyplnený telefón, zostáva pod kontaktmi. Rozloženie je rovnaké na webe, Macu a v PDF. Mac priebežne meria skutočnú výšku papiera, aby zostala celá pätička dostupná aj pri dlhšom obsahu.

- Pri zúžení okna sa faktúra prispôsobí dostupnej šírke a biely papier rastie podľa obsahu vrátane poznámky a pätičky. Ovládacie lišty sa zalomia; na webe do 760 px sa zoznam a detail zobrazujú samostatne s tlačidlom Späť na zoznam.
- Zoznam s veľkým náhľadom alebo tabuľka, hľadanie, filtre stavu a roka, zoradenie. Hľadanie a tlačidlo Nová faktúra tvoria skupinu vycentrovanú vo voľnom priestore hornej lišty na webe aj Macu. Výber faktúry ani stav automatického ukladania neposúvajú bočný zoznam.
- Nová faktúra, úprava a duplikovanie priamo na faktúre v hlavnom okne. Vľavo zostáva zoznam, vpravo upraviteľný papier s natívnymi textovými poľami a živými súčtami. QR kód sa počas úprav nepočíta ani nezobrazuje; vytvorí sa z aktuálnych platobných údajov až pri generovaní PDF. Editor nemá zoom ani zväčšovanie vykreslenej plochy; veľkosť písma zostáva rovnaká pri zmene šírky okna. Všetky zmeny sa ukladajú automaticky vrátane neúplných faktúr a rozpísaných čísel. Tlačidlo PDF priamo uloží súbor bez náhľadu a tlačového okna. Na Macu vždy otvorí systémové okno na výber miesta uloženia; na webe ho použije v podporovaných prehliadačoch, inak stiahne súbor podľa nastavení prehliadača.
- Faktúry sú rovno vystavené; stav sa určuje podľa úhrady a splatnosti. Vymazanie s potvrdením.
- Položky, množstvo, jednotka, cena, zľava, voliteľná DPH, poznámka a dátumy.
- Výber jedného účtu, evidencia uhradenej sumy, zostávajúca úhrada a preplatok.
- Nastavenia majú na webe aj Macu spoločný vycentrovaný rámec široký najviac 960 px, rovnaké okraje a dvojstĺpcový formulárový grid. Prepínanie všetkých piatich záložiek nemení šírku ani polohu hlavičky. Polia a tlačidlá používajú jednotnú výšku 40 px; na úzkom webe sa formuláre skladajú do jedného stĺpca.
- Správa odberateľov, dodávateľa, loga, podpisu a bankových účtov vrátane predvoleného účtu, ktorý má zaoblené žlté označenie široké podľa obsahu. Logo aj podpis podporujú PNG alebo JPEG do 0,5 MB (500 000 bajtov) pre každý obrázok na webe aj Macu.
- Celý riadok odberateľa sa pri prejdení myšou podfarbí a kliknutím otvorí úpravu. Odstránenie má samostatné tlačidlo a potvrdenie. Rovnaké ovládanie je na webe aj Macu.
- Položky faktúry nemajú samostatnú trojbodku. Pravé kliknutie na riadok otvorí voľby položky vrátane zľavy a odstránenia; na webe funguje aj Shift+F10 na označenom riadku.
- A4 PDF s viacstranovými položkami, diakritikou, logom a podpisom. Papier v editore používa rovnomerné zväčšenie pevného rozloženia A4, takže zmena šírky okna nemení jeho proporcie.
- Šablóny faktúr: pôvodný vzhľad **Boring default 01** a čiernobiela **Mono 01** s vektorovým logom Uncut Corners cez celú šírku gridu, malým nápisom FAKTÚRA vpravo pri čísle, hrubými plnými a tenkými čiernymi prerušovanými čiarami a písmom SF Mono vo všetkých textoch. Obe zachovávajú fakturačné údaje, podpis a platobný QR kód. Mono 01 používa v hlavičke dodané logo zo zdrojov aplikácie; uložené logá faktúr sa nemenia a Boring default 01 ich naďalej zobrazuje.
- **Manolo & Bay** zachováva rozloženie Mono 01 na bielom papieri, dopĺňa dodané SVG logo nad jemným znakom v hlavičke, svetlobéžové zvýraznenie `#F2EEEA` a pätičku „Vystavil: Dominika Vašek“, „manolobay.com“, „dominika@manolobay.com“. Platobný blok rozdeľuje voľné miesto rovnomerne medzi obsah štyroch stĺpcov. V editore na Macu aj webe má väčšie popisky a hodnoty; písmo exportovaného PDF zostáva nezmenené. Pätička zostáva pri spodnom okraji papiera; viacstranové PDF ju opakuje na každej strane. Je dostupná na webe aj Macu vrátane PDF. Cloudový katalóg ju obsahuje samostatne; správca ju prideľuje účtom v Administrácii. Existujúce faktúry ani predvolená šablóna sa automaticky nemenia.
- Globálny výber je v **Nastavenia → Vzhľad → Šablóna faktúry**. Platí pre nové aj existujúce faktúry s voľbou **Podľa globálnych nastavení**. Ikona šablóny v hornej lište faktúry alebo **Možnosti faktúry → Šablóna faktúry** umožňuje pevne zvoliť vzhľad iba pre danú faktúru. Zmena sa ukladá automaticky; duplikovanie zachová individuálnu voľbu. Staršie dáta a zálohy používajú pôvodný vzhľad, kým šablónu nezmeníte. Farba zvýraznení sa používa v Boring default 01.
- Písmo SF Mono v aplikácii aj PDF pre samostatné sumy, dátumy, množstvá a identifikátory v pôvodnej a Mono 01 šablóne. Manolo & Bay používa aj pre tieto údaje rovnaké bežné písmo ako ostatný text, vrátane aktívnych polí a dátumov v editore. Čísla vo vetách, názvoch, adresách a popisoch používajú rovnaké písmo ako okolitý text.
- Platobný QR kód na neuhradených faktúrach: PAY by square (SK) alebo QR Platba (CZ).
- Export a obnova kompletnej JSON zálohy vrátane obrázkov.

Úpravy fakturačných údajov v globálnych nastaveniach platia pre nové faktúry. Existujúce faktúry si uchovávajú kópiu údajov dodávateľa, odberateľa, účtu, loga a podpisu. Farba zvýraznení v Nastavenia → Vzhľad je spoločná pre náhľady a nové PDF exporty všetkých faktúr, bez zmeny ich údajov. Platobný QR kód zostáva čiernobiely a text má čitateľný kontrast aj pri svetlej farbe. Platné zmeny nastavení sa ukladajú automaticky krátko po dopísaní, aj pri odchode z nastavení a ukončení appky. Neplatné údaje zobrazia upozornenie a nenahradia uložené nastavenia. Formulár bankového účtu sa potvrdzuje tlačidlom Uložiť účet.

Faktúry nemajú tlačidlo Uložiť: platné zmeny sa zapíšu po 450 ms nečinnosti aj pri prepnutí alebo ukončení aplikácie. Rozpracovaný vstup sa nezávisle zapisuje okamžite, vrátane neúplnej ceny ako `250,`. Pri ďalšom spustení sa obnoví posledná rozpracovaná faktúra; ostatné zostávajú v zozname. Neúplné údaje nenahradia poslednú platnú faktúru a do dokončenia sa nedajú exportovať do PDF. Pri chybe zápisu sa zobrazí Neuložené a možnosť zopakovať uloženie; bežné ukončenie aplikácie sa pri neuložených zmenách zablokuje.

## Dáta

Pôvodné lokálne dáta sú v `~/Library/Application Support/sk.faktury.desktop/database.json`. Cloudový účet má oddelenú cache v `accounts/<user-id>/database.json` a synchronizačný stav v `cloud-sync.json`. Mac potrebuje internet na overenie účtu pri otvorení; počas práce uchová zmeny aj pri výpadku a synchronizáciu opakuje. Web uchová rozpísaný vstup oddelene pre účet v lokálnom úložisku prehliadača. Rozpracované faktúry a surový vstup sú v susednom `invoice-drafts.json`, zapisovanom atómovo. Export JSON zálohy zahŕňa aj tieto rozpracované údaje. Predchádzajúca verzia databázy zostáva v `database.previous.json`. Pred obnovením zálohy sa vytvorí aj samostatná kópia pôvodných dát vrátane rozpracovaných faktúr. Odporúča sa pravidelný export zálohy na iné úložisko.

Lokálny režim neposiela faktúry e-mailom, nesynchronizuje banku ani cloud, nepripája sa do SuperFaktúry a nevytvára ISDOC. Sadzby DPH sú nastaviteľné. Nové profily začínajú prázdne.

## Identita značky

Web a Mac používajú rovnaký schválený dizajn pracovného priestoru. Úpravy rozloženia, textov a ovládacích prvkov sa kontrolujú na oboch platformách v tom istom zadaní. Hlavička obsahuje iba logo a navigáciu; ponuka účtu je v **Nastavenia → Účet**. Systémová titulková lišta a systémové dialógy zostávajú natívne. Otvorený web kontroluje novú verziu pri návrate do okna a každú minútu; ponúknutá obnova najprv uloží faktúru aj nastavenia a pri chybe uloženia sa nespustí.

Schválená hlavná farba je **INVOY Yellow `#F5FF36`**. Finálne logo je **INVOY.** v jednom riadku, vrátane bodky, podľa pätičky variantu B. Web aj Mac používajú spoločné vektorové logo a teplé neutrálne pozadie. Hlavné tlačidlá a vybrané taby v aplikácii majú žlté pozadie s tmavým textom bez orámovania; ovládacie prvky majú jednotnú výšku 40 px. Vybraná faktúra používa neutrálne pozadie `#E9E7E0` s tmavým textom, aj keď je zoznam aktívny. Farby a logá používateľských faktúr určuje ich uložená šablóna. Natívna aplikácia načítava rovnaké SVG, ktoré build kopíruje do Resources; ikona Docku sa tiež vykresľuje z originálu. Vektorové originály a pravidlá použitia sú v [web/public/brand/README.md](web/public/brand/README.md).

## Vývoj a overenie

Úvodná stránka webu má dva zachované varianty. **Variant A** (pôvodný biely dizajn) je v `web/src/LandingA.tsx` a `web/src/landing.css`, dostupný na `https://invoy.xyz/?variant=a`. **Variant B** (teplé sivé pozadie, žlté akcenty a vrstvené ukážky) je v `web/src/LandingB.tsx` a `web/src/landing-b.css`, dostupný na `https://invoy.xyz/?variant=b` a je novým predvoleným úvodom. Výber rieši `web/src/Landing.tsx`; predvolený variant možno vrátiť zmenou `DEFAULT_VARIANT`. Parametre variantov zobrazia verejný úvod aj prihlásenému používateľovi, bežná adresa bez parametra naďalej otvorí jeho pracovný priestor. Používa lokálne uložené písmo Inter s licenciou v `web/public/fonts/Inter-LICENSE.txt`. Produktové obrázky v `web/src/assets/product` zachytávajú aktuálne rozhranie iba so syntetickými údajmi z izolovaného lokálneho náhľadu. Oba varianty úvodu používajú spoločný komponent `ProductPreview`: bezstratové WebP v rozlíšeniach 1328 × 747, 2656 × 1494 a 3984 × 2241 px, vždy v pomere 16 : 9. Náhľad Faktúra používa originálnu šablónu Manolo & Bay s vymyslenými fakturačnými údajmi. Prehliadač vyberá rozlíšenie podľa displeja; Vite pridáva do URL obsahový hash, takže aktualizáciu nezablokuje stará cache. Príkaz `npm run capture:product` náhľady znovu vytvorí a `npm run deploy` ich obnoví automaticky pred nasadením. Pri prvom použití na novom počítači spustite vo `web/` príkaz `npx playwright install chromium`. Generátor používa samostatný lokálny server na voľnom porte, ukážkový bežný účet a pevný dátum; nečíta skutočný účet ani lokálne faktúry. Po obnove vizuálne skontrolujte Faktúru aj Prehľad. Pre overenie úvodnej stránky spustite vo `web/` príkaz `npm run preview -- --landing` a otvorte `http://127.0.0.1:8792/`; prihlasovacie tlačidlá sa zobrazia, skutočné Apple prihlásenie zostáva v tomto náhľade vypnuté.

SwiftUI, AppKit, PDFKit, Core Image, Vision a Foundation. Kompresiu PAY by square
zabezpečuje systémová macOS knižnica liblzma; jej API hlavičky sú v `Sources/CLZMA`.
Nie je potrebný Homebrew ani externá služba počas behu aplikácie.

```sh
bash scripts/test-native.sh
env DEVELOPER_DIR=/Library/Developer/CommandLineTools bash scripts/build-app.sh
.build/release/INVOY --verify output/pdf
```

Testy pokrývajú desatinné výpočty, DPH, čiastočné úhrady, číslovanie, validáciu IBAN-u, údaje zachované vo faktúre a zálohy. Príkaz `--verify` overí PDF predlohy, iba jeden účet, viacstranový export a uloženie dát. Na izolované UI testy možno nastaviť `INVOY_DATA_DIR`.

Skript vytvorí pracovnú kópiu v `.build/distribution.noindex/INVOY.app`, mimo vyhľadávania Spotlight. Túto kópiu nespúšťajte ani nepripínajte do Docku; pri aktualizácii ňou nahraďte existujúcu aplikáciu v `~/Applications/INVOY.app` až po jej ukončení. Nevytvárajte ďalšiu nainštalovanú ani QA aplikáciu.

Po výmene nainštalovanej aplikácie spustite `python3 scripts/refresh-app-registration.py`. Obnoví jej registráciu v macOS a odregistruje staré pracovné kópie s rovnakým identifikátorom, ktoré môžu systému ponúkať pôvodnú ikonu Faktúr. Súbory aplikácií, zálohy ani fakturačné dáta nemaže. Ak už bol systémový prihlasovací dialóg otvorený, zatvorte ho a otvorte znova; samotná kontrola registrácie nepotvrdzuje aktualizáciu ikony v otvorenom dialógu.

`build-app.sh` vytvára vývojový ad-hoc podpis. Distribučné zostavenie robí `bash scripts/release-mac.sh`: Developer ID podpis, notarizácia, stapling a kontrola Gatekeeper. Výsledok je `output/release/INVOY-Mac.zip`. Kľúč a notársky profil musia byť dostupné v lokálnej Kľúčenke; nepíšu sa do Gitu.

Pred vydaním 1.1.1 boli pôvodné lokálne JSON súbory a predchádzajúca aplikácia zálohované do `output/pre-restore-20260928`; kontrolné súčty po inštalácii zostali totožné. Pôvodný lokálny wordmark je uchovaný v `~/Library/Application Support/sk.faktury.desktop/legacy-wordmark.svg` a nešíri sa v novej aplikácii. Pri obnove starej lokálnej inštalácie možno použiť `Faktury-1.1.0-before.zip` v tom istom záložnom priečinku.

## História a návrat k staršej verzii

Zdrojový kód INVOY je v [GitHub repozitári](https://github.com/michalprekop/INVOY).
Dokončené úpravy sa ukladajú do samostatných commitov a posielajú na GitHub.
Prvý bod obnovy `baseline-2026-09-27` obsahuje stav aplikácie pri zavedení Gitu;
staršie priebežné verzie pred týmto bodom v histórii nie sú.

Históriu zobrazí `git log --oneline`. Konkrétnu neskoršiu zmenu možno vrátiť pomocou
`git revert <hash-commitu>` a výsledok uložiť na GitHub cez `git push`.
Potom treba aplikáciu znovu zostaviť a nahradiť nainštalovanú kópiu podľa postupu vyššie.
Pri zmenách dátového formátu treba pred návratom overiť kompatibilitu a exportovať zálohu.

Git sleduje zdrojový kód a testy. Pôvodné osobné logo a podpis sú v aktuálnej verzii zo sledovania vyradené; staršia história zostáva zachovaná. Databáza faktúr, rozpracované údaje,
exportované PDF/JSON zálohy a zostavená aplikácia sa do repozitára neposielajú.
Návrat k staršiemu kódu sám osebe neobnoví staršie fakturačné údaje.

## Platobný QR kód

Predvolený formát je PAY by square; pre českého odberateľa sa automaticky použije
QR Platba. Vo faktúre možno formát zmeniť alebo QR vypnúť. Žiadny formát nie je
univerzálny pre všetky bankové aplikácie; zahraničný IBAN a cudzie meny závisia
aj od možností konkrétnej banky.

QR obsahuje výhradne účet vybraný vo faktúre, majiteľa účtu (ak nie je uvedený,
použije sa názov dodávateľa), zostávajúcu sumu, menu, VS, voliteľný KS/ŠS a správu
s číslom faktúry. Platba nemá naplánovaný dátum vykonania. QR sa negeneruje pre
uhradené faktúry ani hotovosť, kartu či dobierku. Neplatné údaje zobrazia upozornenie
namiesto chybného QR. V lokálnom režime platobné údaje neopúšťajú Mac. Cloudový režim ukladá faktúru do vlastného účtu a QR generuje v zariadení.

Špecifikácie:
- https://portal.bysquare.com/files/bysquare-PAYspecifications-1.2.0.pdf
- https://qr-platba.cz/pro-vyvojare/specifikace-formatu/
- https://pomoc.superfaktura.sk/ako-zapnem-qr-kod-na-fakture/

`--render-database <database.json> <output-directory> --expect-single-page`
overí všetky PDF aj načítanie QR z vyrenderovaných strán a vytvorí `qr-codes.json`.
`python3 scripts/verify-payment-qr.py <qr-codes.json>` nezávisle overí CRC32,
dekompresiu a všetky dôležité platobné údaje.
