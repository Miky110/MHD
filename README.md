# MHD Mikylov

Mobilní aplikace pro fiktivní dopravní systém MHD Mikylov se zaměřením na Bukovany u Sokolova a okolí.

## Aktuální funkce

- palubní obrazovka řidiče vhodná pro telefon nebo tablet,
- ruční výběr linky a odjezdu,
- aktuální a následující zastávka,
- ruční posun mezi zastávkami,
- české hlasové hlášení při příjezdu a odjezdu,
- ukázkové linky 1, 3 a 7,
- společný základ pro Android a iOS.

## Automatická sestavení

Workflow **Sestavení mobilních aplikací** se spustí po každém pushi do `main`, pro pull request a také ručně na kartě Actions. Po skončení jsou v části **Artifacts** dostupné:

- `MHD-Mikylov-Android-APK` – instalovatelný release APK,
- `MHD-Mikylov-iOS-unsigned` – nepodepsané IPA pro další podpis.

Nepodepsané IPA nelze běžně nainstalovat do iPhonu. Pro distribuovatelnou IPA je nutný Apple Developer účet, distribuční certifikát a provisioning profil.

## Místní spuštění

```bash
flutter create --project-name mhd_mikylov --org cz.mikylov .
flutter pub get
flutter run
```

## Serverová synchronizace

Databázové schéma je v `supabase/migrations/001_initial_schema.sql`. Aplikace je
ve výchozím nastavení připojená k projektu MHD Mikylov. Hodnoty lze pro jiné
prostředí přepsat při sestavení:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=PUBLIC_KEY
```

Bez těchto hodnot aplikace bezpečně pokračuje pouze s lokální SQLite databází.
Do mobilní aplikace nikdy nevkládej `service_role` nebo jiný tajný serverový klíč.

Nativní adresáře `android/` a `ios/` se v CI vytvářejí automaticky, aby se verzoval jen udržovaný společný zdrojový kód.
