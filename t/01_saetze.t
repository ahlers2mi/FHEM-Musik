#!/usr/bin/perl
#
# Sätze, wie sie von Alexa/talk ankommen -> Antwort und Befehle.

use strict;
use warnings;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
require(dirname(abs_path(__FILE__)) . "/fhem_stub.pl");
our ($FAILS, $COUNT, @CMDS, @TIMERS, %defs, %attr, $NOW);

my ($a, $c);
setup();

print "=== HEOS-Favoriten ===\n";
echo("e");                                   # Echo Esszimmer
($a, $c) = say("tür WDR2");
ok($a eq "WDR2 läuft im Esszimmer", "Hörfehler 'tür WDR2' -> $a");
ok($c eq "set Denon_X4300h_Z2 on ; set Denon_X4300h_Z2 input OnlineMusic ; set rem_HEOSPlayer1579933734 channel 26", "  Befehle: $c");

($a, $c) = say("spiel wdr 2");
ok($a eq "WDR2 läuft im Esszimmer", "'spiel wdr 2' -> $a");
($a, $c) = say("radio WDR zwei");
ok($a eq "WDR2 läuft im Esszimmer", "'radio WDR zwei' -> $a");
($a, $c) = say("spiel wdr vier im wohnzimmer");
ok($a eq "WDR4 läuft im Wohnzimmer" && $c =~ /set Denon on.*rem_HEOSPlayer847926702 channel 27$/, "'wdr vier im wohnzimmer' -> $a | $c");
($a, $c) = say("spiel kiepenkerl");
ok($a eq "Radio Kiepenkerl läuft im Esszimmer" && $c =~ /channel 4$/, "'kiepenkerl' -> $a");
($a, $c) = say("mach radio bob an");
ok($a =~ /^Meinst du RADIO BOB - NRW oder RADIO BOB 70er Rock\?$/ && $c eq "", "'radio bob' mehrdeutig -> $a");
($a, $c) = say("spiel antenne münster");
ok($a eq "Antenne Münster läuft im Esszimmer" && $c =~ /channel 2$/, "'antenne münster' -> $a");
($a, $c) = say("spiel NDR zwei");
ok($a eq "NDR 2 Hamburg läuft im Esszimmer" && $c =~ /channel 5$/, "'NDR zwei' -> $a");
($a, $c) = say("spiel roxette");
ok($a eq "Roxette läuft im Esszimmer" && $c =~ /channel 8$/, "'roxette' = Favorit -> $a");
($a, $c) = say("spiel radio kipenkerl");
ok($a eq "Radio Kiepenkerl läuft im Esszimmer", "Tippfehler 'kipenkerl' -> $a");

print "\n=== Spotify ===\n";
($a, $c) = say("spiel musik von amy macdonald");
ok($a eq "Ich spiele Musik von amy macdonald im Esszimmer" && $c =~ /\+8s set rem_spotify playArtistByName amy macdonald$/, "Interpret -> $a | $c");
($a, $c) = say("spiel das lied smells like teen spirit von nirvana im esszimmer und wohnzimmer");
ok($a eq "Ich spiele smells like teen spirit von nirvana im Esszimmer und Wohnzimmer", "Lied 2 Räume -> $a");
ok($c =~ /set Denon_X4300h_Z2 on.*set Denon on.*playTrackByName smells like teen spirit nirvana$/, "  Befehle: $c");
($a, $c) = say("spiel die playlist sommer hits");
ok($a eq "Ich spiele die Playlist sommer hits im Esszimmer" && $c =~ /playPlaylistByName sommer hits$/, "Playlist -> $a");
($a, $c) = say("spiel musik");
ok($a eq "Ich spiele den Spotify DJ im Esszimmer" && $c =~ /\+8s set d_spotify_dj on$/, "Musik allein -> DJ");
($a, $c) = say("spiel nirvana im bad");
ok($a eq "Ich spiele Musik von nirvana im Badezimmer" && $c eq "+8s set rem_spotify playArtistByName nirvana", "Bad ohne Zone -> $a | $c");
($a, $c) = say("spiel musik von roxette");
ok($c =~ /channel 8$/, "'musik von roxette' = Favorit genau gleich");
($a, $c) = say("spiel musik von enyaa");
ok($c =~ /playArtistByName enyaa$/, "'musik von' erzwingt Interpret bei unscharfem Treffer");

print "\n=== Raum ===\n";
echo("e", 100);                              # zu alt
($a, $c) = say("spiel wdr2");
ok($a eq "WDR2 läuft im Wohnzimmer", "Echo-Raum zu alt -> Standardraum");
echo("s");                                   # Schlafzimmer hat keine Musik
($a, $c) = say("spiel wdr2");
ok($a eq "WDR2 läuft im Wohnzimmer", "Echo Schlafzimmer -> Standardraum");
echo("b");
($a, $c) = say("spiel wdr2");
ok($a eq "WDR2 läuft im Badezimmer" && $c eq "set rem_HEOSPlayer1730582485 channel 26", "Echo Bad -> $a | $c");
($a, $c) = say("spiel wdr2 in der küche");
ok($a eq "WDR2 läuft im Esszimmer", "Alias Küche -> $a");
($a, $c) = say("spiel wdr2 auf der terrasse west");
ok($a eq "WDR2 läuft im Terrasse West" && $c =~ /Denon_X4300h_Z3 on/, "Terrasse West (längster Alias) -> $a");
($a, $c) = say("wdr2", "Wohnzimmer");
ok($a eq "WDR2 läuft im Wohnzimmer", "Raum als Parameter");
($a, $c) = say("spiel wdr2 im esszimmer und auf der terrasse");
ok($c =~ /Z2 on.*Z3 on/ && ($c =~ tr/;//) && (() = $c =~ /channel 26/g) == 1, "2 Räume, 1 HEOS-Player -> 1x channel: $c");

print "\n=== Steuern ===\n";
echo("e");
($a, $c) = say("musik aus");
ok($a eq "Ich schalte die Musik überall aus" && $c =~ /set Denon zoneMain off/ && $c =~ /set Denon_X4300h_Z2 off/ && $c =~ /set rem_HEOSPlayer1730582485 stop/, "'musik aus' ohne Raum -> überall: $c");
($a, $c) = say("musik im esszimmer aus");
ok($c eq "set Denon_X4300h_Z2 off", "'musik im esszimmer aus' -> $c");
($a, $c) = say("musik an");
ok($a eq "Ich schalte die Musik im Esszimmer ein" && $c eq "set Denon_X4300h_Z2 on ; set Denon_X4300h_Z2 input OnlineMusic", "'musik an' -> Echo-Raum");
($a, $c) = say("musik stop");
ok($c eq "set rem_HEOSPlayer1579933734 stop", "stop -> $c");
($a, $c) = say("pause");
ok($c eq "set rem_HEOSPlayer1579933734 pause", "pause -> $c");
($a, $c) = say("nächstes lied");
ok($c eq "set rem_HEOSPlayer1579933734 next", "nächstes lied -> $c");
($a, $c) = say("musik weiter");
ok($c eq "set rem_HEOSPlayer1579933734 play", "weiter -> $c");

print "\n=== Lautstärke ===\n";
($a, $c) = say("lauter");
ok($c eq "set Denon_X4300h_Z2 volume 37" && $a eq "Lautstärke im Esszimmer auf 37", "lauter -> $c");
($a, $c) = say("musik leiser um 10");
ok($c eq "set Denon_X4300h_Z2 volume 22", "leiser um 10 -> $c");
($a, $c) = say("lautstärke auf 25 im wohnzimmer");
ok($c eq "set Denon volume 25", "auf 25 im wohnzimmer -> $c");
($a, $c) = say("lauter auf 90");
ok($c eq "set Denon_X4300h_Z2 volume 60", "Obergrenze 60 -> $c");
($a, $c) = say("lauter im bad");
ok($c eq "set rem_HEOSPlayer1730582485 volume 41", "Bad ohne Zone -> HEOS-Volume: $c");

print "\n=== Simulation / disable ===\n";
setup(musikSimulate => 1);
echo("e");
($a, $c) = say("tür wdr2");
ok($a eq "WDR2 läuft im Esszimmer" && !@CMDS && $c =~ /channel 26/, "Simulation: nichts gesendet, aber protokolliert");
ok(ReadingsVal("musik", "state", "") =~ /^Test: favorit 26/, "  state: " . ReadingsVal("musik", "state", ""));
setup();
($a, $c) = say("spiel musik von nirvana");
ok(@TIMERS == 1 && $TIMERS[0][1] eq "Musik_Later", "Spotify verzögert per InternalTimer");
Musik_Later($TIMERS[0][2]);
ok($CMDS[-1] eq "set rem_spotify playArtistByName nirvana", "  nach Ablauf gesendet: $CMDS[-1]");
setup(disable => 1);
($a, $c) = say("wdr2");
ok($a eq "Das Musikmodul ist ausgeschaltet" && $c eq "", "disable");

print "\n$COUNT Tests, $FAILS Fehler\n";
exit($FAILS ? 1 : 0);
