# FHEM-Musik – Projektwissen

FHEM-Modul `FHEM/98_Musik.pm`: Musik per Sprache (Talk2Fhem/Alexa) – Raum,
HEOS-Favoriten, Spotify, Steuerung, Lautstärke. Angelegt 16.11.2026.

## Arbeitsweise

- Version bei jeder funktionalen Änderung anheben (Kopfzeile `# Version:`,
  `$MUSIK_VERSION`). `controls_Musik.txt` erzeugt die Action nach jedem Push
  der .pm neu – vor dem nächsten Push auf dem aktuellen `main` aufsetzen.
- Vor jedem Commit: `sh t/run.sh` (muss „ALLES GRUEN“ melden). Neue Sätze als
  Test in `t/01_saetze.t` aufnehmen, besonders echte Hörfehler aus dem Log.
- Stil wie FHEM-HeatManager: Kopfblock mit „Funktionen:“, Kasten-Kommentar je
  Funktion, Commandref mit `<a id="Musik-…">`-Ankern.
- Nie Funktionen in den Namensraum `main` importieren (`use X ();`).
- Timer-Rückrufe in eval (ein die() im Timer beendet FHEM).
- Keine github.com-URL in der .pm. Repo ist öffentlich: keine Tokens,
  Passwörter, IPs mit Zugangsdaten.
- Module heißen beim Nutzer 98_*, 99_* ist für Utils.

## Anlage (Stand 16.11.2026)

- Main-FHEM: talk (Talk2Fhem), MyAlexa (echoRooms/echoId), Funktionen
  `my_AlexaTalk`, `clean_talk`, `my_echo_raum` in `99_myT2FUtils.pm`.
- Denon/HEOS liegen im Backend-FHEM, in Main als DoRemoteDevice `rem_*`
  (set wird durchgereicht). Denon (X4800, Wohnzimmer, 192.168.69.20),
  Denon_X4300h (Terrasse Ost) mit Zonen Z2 Esszimmer, Z3 Terrasse West.
  HEOS-Player: rem_HEOSPlayer847926702 (X4800), rem_HEOSPlayer1579933734
  (X4300H, alle X4300-Zonen), rem_HEOSPlayer1730582485 (HEOS1, Bad).
  `channel 1..27` = HEOS-Favoriten; Namen nur statisch
  (rp_HEOSPlayer1579933734_channel setList, talk heos_channels).
- Spotify: rem_spotify (playTrackByName, playArtistByName,
  playPlaylistByName, transferPlayback …), DJ über Dummy d_spotify_dj.
- Offen: ob die Spotify-*ByName-Befehle eine Geräte-ID annehmen (gezielt an
  den Player des Raums statt an das aktive Gerät).
