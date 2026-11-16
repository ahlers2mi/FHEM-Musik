#!/usr/bin/perl
#
# v0.2.0: Spotify wartet nur, wenn die Zone aus war oder erst auf
# OnlineMusic umgeschaltet wird. Läuft sie schon, geht es sofort los.

use strict;
use warnings;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
require(dirname(abs_path(__FILE__)) . "/fhem_stub.pl");
our ($FAILS, $COUNT, @CMDS, @TIMERS, %defs, %attr, $NOW);

sub rd { my ($d, %r) = @_; $defs{$d}{READINGS}{$_} = { VAL => $r{$_} } foreach (keys %r); }

my ($a, $c);

print "=== Zone aus -> an, OnlineMusic, 8 s warten ===\n";
setup(); echo("e");
rd("Denon_X4300h_Z2", power => "off", input => "OnlineMusic");
($a, $c) = say("spiel musik");
ok($c eq "set Denon_X4300h_Z2 on ; set Denon_X4300h_Z2 input OnlineMusic ; +8s set d_spotify_dj on", "aus: $c");

print "\n=== Zone an, OnlineMusic -> sofort ===\n";
rd("Denon_X4300h_Z2", power => "on", input => "OnlineMusic");
($a, $c) = say("spiel musik");
ok($c eq "set d_spotify_dj on", "läuft schon: $c");
ok(!@TIMERS && $CMDS[-1] eq "set d_spotify_dj on", "  ohne Timer sofort gesendet");
($a, $c) = say("spiel musik von nirvana");
ok($c eq "set rem_spotify playArtistByName nirvana", "Interpret sofort: $c");
($a, $c) = say("tür wdr2");
ok($c eq "set rem_HEOSPlayer1579933734 channel 26", "Favorit ohne Zonenbefehle: $c");

print "\n=== Zone an, anderer Eingang -> umschalten, 2 s ===\n";
rd("Denon_X4300h_Z2", power => "on", input => "Sat/Cbl");
($a, $c) = say("spiel das lied hey jude von the beatles");
ok($c eq "set Denon_X4300h_Z2 input OnlineMusic ; +2s set rem_spotify playTrackByName hey jude the beatles", "Eingang: $c");
$attr{musik}{musikInputDelay} = 4;
($a, $c) = say("spiel musik");
ok($c =~ /\+4s set d_spotify_dj on$/, "musikInputDelay 4: $c");

print "\n=== Hauptzone: power on, zoneMain off zählt als aus ===\n";
rd("Denon", power => "on", zoneMain => "off", input => "OnlineMusic");
($a, $c) = say("spiel musik im wohnzimmer");
ok($c eq "set Denon on ; set Denon input OnlineMusic ; +8s set d_spotify_dj on", "zoneMain off: $c");
rd("Denon", power => "on", zoneMain => "on", input => "OnlineMusic");
($a, $c) = say("spiel musik im wohnzimmer");
ok($c eq "set d_spotify_dj on", "zoneMain on: $c");

print "\n=== zwei Räume: längste Wartezeit zählt ===\n";
rd("Denon_X4300h_Z2", power => "on", input => "OnlineMusic");
rd("Denon", power => "off", zoneMain => "off");
($a, $c) = say("spiel musik von nirvana im esszimmer und wohnzimmer");
ok($c eq "set Denon on ; set Denon input OnlineMusic ; +8s set rem_spotify playArtistByName nirvana", "Esszimmer an, Wohnzimmer aus: $c");

print "\n=== Bad (nur HEOS) -> sofort ===\n";
($a, $c) = say("spiel nirvana im bad");
ok($c eq "set rem_spotify playArtistByName nirvana", "Bad: $c");

print "\n$COUNT Tests, $FAILS Fehler\n";
exit($FAILS ? 1 : 0);
