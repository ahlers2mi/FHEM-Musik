# FHEM-Musik

FHEM-Modul `98_Musik.pm`: Musik per Sprache. Ein Satz (z. B. von Alexa über
Talk2Fhem) rein, Musik im richtigen Raum – HEOS-Favoriten, Spotify, Steuerung
und Lautstärke an einer Stelle statt in vielen einzelnen Talk-Regeln.

## Was es kann

| Satz (Beispiele) | Ergebnis |
|---|---|
| „spiel WDR2“, „Radio WDR zwei“, „tür WDR2“ (Hörfehler) | HEOS-Favorit WDR2 im Raum des Echos |
| „spiel Kiepenkerl in der Küche“ | Favorit „Radio Kiepenkerl“ im Esszimmer |
| „spiel Radio Bob“ | Nachfrage: „Meinst du RADIO BOB - NRW oder RADIO BOB 70er Rock?“ |
| „spiel das Lied Smells like teen spirit von Nirvana“ | Spotify `playTrackByName` |
| „spiel die Playlist Sommerhits“ | Spotify `playPlaylistByName` |
| „spiel Musik“ | Spotify DJ (wartet nur, wenn die Zone erst eingeschaltet wird) |
| „spiel Musik von Amy Macdonald im Wohnzimmer“ / „spiel Nirvana“ | Spotify `playArtistByName` |
| „Musik an“ / „Musik aus“ | Zone an (OnlineMusic) / ohne Raum überall aus |
| „stop“, „Pause“, „weiter“, „nächstes Lied“ | HEOS-Player des Raums |
| „lauter“, „leiser um 10“, „Lautstärke auf 25“ | Lautstärke der Zone (ohne Zone: HEOS-Box) |

**Raum:** genannt („im Esszimmer“, „in der Küche“, „überall“) > Raum des Echos
(`attr MyAlexa echoRooms` + Reading `echoId`, max. 30 s alt) > `musikDefaultRoom`.

**Favoriten-Vergleich:** Text und Favoriten werden normalisiert (klein,
Umlaute, Zahlwörter → Ziffern, Füllwörter wie spiel/Radio/Sender/Tür weg).
Gleich > als ganzes Wort enthalten/Anfang > ähnlich (Levenshtein ≤ Länge/5).
Bei Gleichstand fragt die Antwort nach. „Musik von X“ nimmt einen Favoriten
nur, wenn er genau X heißt, sonst Spotify.

## Installation

```
update add https://raw.githubusercontent.com/ahlers2mi/FHEM-Musik/main/controls_Musik.txt
update all
reload 98_Musik
define musik Musik
attr musik musikSimulate 1
```

## Konfiguration

```
attr musik musikRooms
Wohnzimmer|Wohnbereich = zone=Denon heos=rem_HEOSPlayer847926702
Esszimmer|Küche = zone=Denon_X4300h_Z2 heos=rem_HEOSPlayer1579933734
Terrasse West|Westterrasse,Terrasse,Sandkasten,Draußen,Garten = zone=Denon_X4300h_Z3 heos=rem_HEOSPlayer1579933734
Terrasse Ost|Ostterrasse = zone=Denon_X4300h heos=rem_HEOSPlayer1579933734
Badezimmer|Bad = heos=rem_HEOSPlayer1730582485

attr musik musikFavorites RADIO_BOB_-_NRW,Antenne_Münster,...,WDR2,WDR4
```

`musikFavorites` in derselben Reihenfolge wie die HEOS-Favoriten (Kanal 1..n).

Weitere Attribute: `musikDefaultRoom`, `musikSpotify`, `musikSpotifyDJ`,
`musikSpotifyDelay`, `musikEchoDevice`, `musikEchoMaxAge`, `musikVolumeStep`,
`musikVolumeMax`, `musikSimulate`, `disable` – siehe Commandref.

## Talk2Fhem

Eine Regel ersetzt die bisherigen Musik-Regeln:

```
(?:^|\s)(spiel\S*|musik|radio|lied|song|titel|playlist|lauter|leiser|lautstärke|anlage|nächste\S*|pause|stop|stopp)(?:\s|$) =
   (answer=>'Musik_Talk("musik","$0")')
```

## Test

```
set musik text tür WDR2
```

Readings `last_text`, `last_room`, `last_action`, `last_answer`,
`last_commands`. Mit `musikSimulate 1` wird nichts geschaltet.

Tests ohne FHEM: `sh t/run.sh`

## Lizenz

GPL v2 oder höher (wie FHEM).
