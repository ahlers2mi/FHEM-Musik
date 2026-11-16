#!/usr/bin/perl
#
# Minimaler FHEM-Ersatz, damit 98_Musik.pm ohne laufende FHEM-Instanz
# getestet werden kann (Vorbild: FHEM-HeatManager/t/fhem_stub.pl).
# Wird von den .t-Dateien per require geladen und lädt selbst das Modul.

use strict;
use warnings;

our (%defs, %attr, $init_done, $readingFnAttributes, $NOW);
our @CMDS;      # alle per AnalyzeCommandChain gesendeten Befehle
our @TIMERS;    # [zeit, funktion, arg]

$init_done           = 1;
$readingFnAttributes = "";
$NOW                 = 1_800_000_000;

sub Log3 { }
sub AttrVal {
    my ($n, $a, $d) = @_;
    return (exists $attr{$n} && defined $attr{$n}{$a} && $attr{$n}{$a} ne "")
        ? $attr{$n}{$a} : $d;
}
sub ReadingsVal {
    my ($n, $r, $d) = @_;
    return $d if (!exists $defs{$n} || !exists $defs{$n}{READINGS}{$r});
    return $defs{$n}{READINGS}{$r}{VAL};
}
sub ReadingsAge {
    my ($n, $r, $d) = @_;
    return $d if (!exists $defs{$n} || !exists $defs{$n}{READINGS}{$r});
    return $NOW - ($defs{$n}{READINGS}{$r}{TS} // $NOW);
}
sub gettimeofday         { return $NOW; }
sub InternalTimer        { my ($tm, $fn, $arg) = @_; push @TIMERS, [$tm, $fn, $arg]; }
sub RemoveInternalTimer  { my ($arg) = @_; @TIMERS = grep { $_->[2] != $arg } @TIMERS; }
sub readingsBeginUpdate  { }
sub readingsEndUpdate    { }
sub readingsBulkUpdate   { my ($h,$r,$v)=@_; $h->{READINGS}{$r}{VAL}=$v; }
sub readingsSingleUpdate { my ($h,$r,$v)=@_; $h->{READINGS}{$r}{VAL}=$v; }
sub AnalyzeCommandChain  { my (undef, $c) = @_; push @CMDS, $c; return undef; }

my $modul = __FILE__;
$modul =~ s{/[^/]+$}{};
$modul .= "/../FHEM/98_Musik.pm";
do $modul or die "Konnte $modul nicht laden: " . ($@ || $!) . "\n";

# ---------------------------------------------------------------------------
# Testhilfen
# ---------------------------------------------------------------------------
our $FAILS = 0;
our $COUNT = 0;

sub ok {
    my ($c, $msg) = @_;
    $COUNT++;
    if ($c) { print "ok    $msg\n"; }
    else    { print "FAIL  $msg\n"; $FAILS++; }
}

# Testanlage wie beim Nutzer (Stand 16.11.2026)
sub setup {
    my (%a) = @_;
    %defs = (); %attr = (); @CMDS = (); @TIMERS = ();
    my $h = { NAME => "musik", TYPE => "Musik", READINGS => {} };
    $defs{musik} = $h;
    $defs{Denon}            = { NAME => "Denon",           TYPE => "DENON_AVR",      READINGS => { volume => { VAL => 35 } } };
    $defs{Denon_X4300h}     = { NAME => "Denon_X4300h",    TYPE => "DENON_AVR",      READINGS => { volume => { VAL => 49 } } };
    $defs{Denon_X4300h_Z2}  = { NAME => "Denon_X4300h_Z2", TYPE => "DENON_AVR_ZONE", READINGS => { volume => { VAL => 32 } } };
    $defs{Denon_X4300h_Z3}  = { NAME => "Denon_X4300h_Z3", TYPE => "DENON_AVR_ZONE", READINGS => { volume => { VAL => 39 } } };
    $defs{rem_HEOSPlayer1730582485} = { NAME => "rem_HEOSPlayer1730582485", TYPE => "DoRemoteDevice", READINGS => { volume => { VAL => 36 } } };
    $attr{musik} = {
        musikRooms => join("\n",
            "# Raum|Aliase = zone=<Denon> heos=<HEOS-Player>",
            "Wohnzimmer|Wohnbereich = zone=Denon heos=rem_HEOSPlayer847926702",
            "Esszimmer|Küche = zone=Denon_X4300h_Z2 heos=rem_HEOSPlayer1579933734",
            "Terrasse West|Westterrasse,Terrasse,Sandkasten,Draußen,Garten = zone=Denon_X4300h_Z3 heos=rem_HEOSPlayer1579933734",
            "Terrasse Ost|Ostterrasse = zone=Denon_X4300h heos=rem_HEOSPlayer1579933734",
            "Badezimmer|Bad = heos=rem_HEOSPlayer1730582485"),
        musikFavorites => "RADIO_BOB_-_NRW,Antenne_Münster,RADIO_21_-_NRW,Radio_Kiepenkerl,NDR_2_Hamburg,Radio_Bollerwagen,Beliebte_Songs,Roxette,Unheilig,Creedence_Clearwater_Revival,J.B.O.,Guns_N_Roses,Mumford_&_Sons,Enya,Best_of_70er,Elvis_Presley,Die_Ärzte,Country_Rock,Montgomery_Gentry,RADIO_BOB_70er_Rock,Singer_Songwriter,Wir_Sind_Helden,Rock_Antenne,Die_Prinzen,Entspannter_Rock,WDR2,WDR4",
        musikDefaultRoom => "Wohnzimmer",
        %a,
    };
    $defs{MyAlexa} = { NAME => "MyAlexa", TYPE => "alexa", READINGS => {} };
    $attr{MyAlexa}{echoRooms} = "#<deviceId>=<room>\n" . ("e" x 50) . "=Esszimmer\n" . ("b" x 50) . "=Badezimmer\n" . ("s" x 50) . "=Schlafzimmer";
    return $h;
}

# Echo meldet sich (vor $age Sekunden)
sub echo {
    my ($c, $age) = @_;
    $defs{MyAlexa}{READINGS}{echoId} = { VAL => ($c x 50) . "restderid", TS => $NOW - ($age // 2) };
}

# Satz auswerten -> (antwort, befehle-als-string)
sub say {
    my ($text, $room) = @_;
    my $h = $defs{musik};
    @CMDS = (); @TIMERS = ();
    my $a = Musik_Talk("musik", $text, $room);
    return ($a, join(" ; ", @{$h->{helper}{cmds}}));
}

1;
