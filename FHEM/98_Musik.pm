##############################################################################
# 98_Musik.pm
#
# FHEM-Modul für Musik per Sprache: ein Satz rein, Musik im richtigen Raum.
#
# Funktionen:
#   * Raum: genannter Raum ("... im Esszimmer", "in der Küche"), sonst der
#     Raum des Echos, das den Befehl gehört hat (attr MyAlexa echoRooms +
#     Reading echoId, höchstens musikEchoMaxAge Sekunden alt), sonst
#     musikDefaultRoom. Räume, Zonen und Player stehen in musikRooms.
#   * Steuern: an, aus, stop, pause, weiter, nächster, zurück, lauter, leiser,
#     "lauter auf 30", "Lautstärke 25". "aus" ohne Raum = überall aus.
#   * HEOS-Favoriten (musikFavorites, Reihenfolge = Kanalnummer): unscharfer
#     Vergleich nach Normalisierung ("wdr 2", "WDR zwei", "Kiepenkerl",
#     Hörfehler wie "tür wdr2"). Bei Gleichstand fragt die Antwort nach.
#   * Spotify, wenn kein Favorit passt: "das Lied X von Y" -> playTrackByName,
#     "Playlist X" -> playPlaylistByName, "Musik" allein -> Spotify DJ,
#     sonst Interpret -> playArtistByName.
#   * Vor dem Abspielen: Zone an, Eingang OnlineMusic. Gewartet wird nur,
#     wenn die Zone aus war (musikSpotifyDelay) bzw. erst umgeschaltet wird
#     (musikInputDelay); läuft sie schon auf OnlineMusic, startet Spotify sofort.
#   * Antwort als Text für talk/Alexa ("WDR2 läuft im Esszimmer").
#
# Aufruf aus Talk2Fhem: answer=>'Musik_Talk("<name>","$0")'.
# Test: set <name> text <satz> (Readings last_*). Mit musikSimulate 1 wird
# nur protokolliert (Reading last_commands), nichts geschaltet.
#
# Das Modul steuert nur über konfigurierbare Fremdgeräte (Attribute) und hält
# keine eigene Hardware.
#
# Autor:    ahlers2mi
# Version:  v0.2.0
# Lizenz:   GPL v2 oder höher (wie FHEM)
##############################################################################

package main;

use strict;
use warnings;

use vars qw(%defs %attr $init_done $readingFnAttributes);

my $MUSIK_VERSION = "v0.2.0";

# Zahlwörter, die Alexa bei Sendernamen ausschreibt
my %MUSIK_NUM = (null => 0, eins => 1, zwei => 2, zwo => 2, drei => 3,
                 vier => 4, fuenf => 5, sechs => 6, sieben => 7, acht => 8,
                 neun => 9, zehn => 10, elf => 11, zwoelf => 12,
                 einundzwanzig => 21, siebziger => 70, achtziger => 80,
                 neunziger => 90);

# Wörter, die beim Sender-/Interpretenvergleich keine Rolle spielen
# (normalisiert: Umlaute als ae/oe/ue, ß als ss)
my %MUSIK_FILL = map { $_ => 1 } qw(
    bitte mal doch alexa spiel spiele spielt spielen mach mache starte start
    starten stell stelle schalte schalt leg lege auf an ein ich will moechte
    hoeren den die das der dem einen radio sender radiosender kanal musik
    lieder lied song titel favorit favoriten tuer im in von);

my $MUSIK_RPRE = '(?:(?:im|in der|in|auf der|auf|und)\s+)?';

##############################################################################
# Musik_Initialize
#   Modul bei FHEM anmelden: Funktionen und Attribute.
##############################################################################
sub Musik_Initialize {
    my ($hash) = @_;
    $hash->{DefFn}    = "Musik_Define";
    $hash->{UndefFn}  = "Musik_Undef";
    $hash->{SetFn}    = "Musik_Set";
    $hash->{AttrList} = "disable:0,1 "
                      . "musikSimulate:0,1 "
                      . "musikRooms:textField-long "
                      . "musikFavorites:textField-long "
                      . "musikDefaultRoom "
                      . "musikSpotify "
                      . "musikSpotifyDJ "
                      . "musikSpotifyDelay "
                      . "musikInputDelay "
                      . "musikEchoDevice "
                      . "musikEchoMaxAge "
                      . "musikVolumeStep "
                      . "musikVolumeMax "
                      . $readingFnAttributes;
    return;
}

##############################################################################
# Musik_Define
#   define <name> Musik
##############################################################################
sub Musik_Define {
    my ($hash, $def) = @_;
    my @a = split(/\s+/, $def);
    return "Syntax: define <name> Musik" if (@a != 2);
    $hash->{VERSION} = $MUSIK_VERSION;
    readingsSingleUpdate($hash, "state", "bereit", 0)
        if (!defined($hash->{READINGS}{state}));
    return;
}

##############################################################################
# Musik_Undef
#   Aufräumen: verzögerte Befehle verwerfen.
##############################################################################
sub Musik_Undef {
    my ($hash) = @_;
    foreach my $t (@{$hash->{helper}{timers} // []}) { RemoveInternalTimer($t); }
    $hash->{helper}{timers} = [];
    return;
}

##############################################################################
# Musik_Set
#   set <name> text <satz>   - Satz auswerten (wie aus talk)
##############################################################################
sub Musik_Set {
    my ($hash, $name, $cmd, @args) = @_;
    return "set $name needs an argument" if (!defined($cmd));
    if ($cmd eq "text") {
        return "Syntax: set $name text <satz>" if (!@args);
        Musik_Handle($hash, join(" ", @args), undef);
        return undef;
    }
    return "Unknown argument $cmd, choose one of text:textField";
}

##############################################################################
# Musik_Talk
#   Aufruf aus Talk2Fhem: Musik_Talk("<name>", "$0" [, "<raum>"]).
#   Gibt den Antwortsatz zurück.
##############################################################################
sub Musik_Talk {
    my ($name, $text, $room) = @_;
    my $hash = $defs{$name // ""};
    return "Das Musikmodul $name gibt es nicht"
        if (!$hash || ($hash->{TYPE} // "") ne "Musik");
    return Musik_Handle($hash, $text, $room);
}

##############################################################################
# Musik_Rooms
#   musikRooms auswerten. Zeilenformat:
#     Raum|Alias1,Alias2 = zone=<Denon-Gerät> heos=<HEOS-Player>
#   Liefert eine Liste von Hashes {name, aliases[], zone, heos}.
##############################################################################
sub Musik_Rooms {
    my ($name) = @_;
    my @r;
    foreach my $l (split(/\n/, AttrVal($name, "musikRooms", ""))) {
        next if ($l =~ /^\s*(#|$)/);
        my ($left, $right) = split(/=/, $l, 2);
        next if (!defined($right));
        my ($room, $al) = split(/\|/, $left, 2);
        $room =~ s/^\s+|\s+$//g;
        my @aliases = ($room, map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x }
                              split(/,/, $al // ""));
        my %e = (name => $room, aliases => [grep { $_ ne "" } @aliases]);
        while ($right =~ /(\w+)=(\S+)/g) { $e{$1} = $2; }
        push(@r, \%e);
    }
    return @r;
}

##############################################################################
# Musik_Norm
#   Text für Vergleiche vereinfachen: klein, Umlaute ausschreiben,
#   Zahlwörter -> Ziffern, nur a-z, 0-9 und Leerzeichen.
##############################################################################
sub Musik_Norm {
    my ($t) = @_;
    $t = lc($t // "");
    $t =~ s/ä|Ä/ae/g; $t =~ s/ö|Ö/oe/g; $t =~ s/ü|Ü/ue/g; $t =~ s/ß/ss/g;
    $t =~ s/[^a-z0-9 ]+/ /g;
    $t = join(" ", map { exists $MUSIK_NUM{$_} ? $MUSIK_NUM{$_} : $_ } split(/\s+/, $t));
    $t =~ s/\s+/ /g;
    $t =~ s/^\s+|\s+$//g;
    return $t;
}

##############################################################################
# Musik_Strip
#   Füllwörter aus einem normalisierten Text entfernen.
##############################################################################
sub Musik_Strip {
    my ($t) = @_;
    return join(" ", grep { $_ ne "" && !$MUSIK_FILL{$_} } split(/\s+/, $t));
}

##############################################################################
# Musik_Lev
#   Levenshtein-Abstand zweier Zeichenketten.
##############################################################################
sub Musik_Lev {
    my ($s, $t) = @_;
    my @d = (0 .. length($t));
    for my $i (1 .. length($s)) {
        my @n = ($i);
        for my $j (1 .. length($t)) {
            my $c = substr($s, $i - 1, 1) eq substr($t, $j - 1, 1) ? 0 : 1;
            my $m = $d[$j] + 1;
            $m = $n[$j - 1] + 1 if ($n[$j - 1] + 1 < $m);
            $m = $d[$j - 1] + $c if ($d[$j - 1] + $c < $m);
            push(@n, $m);
        }
        @d = @n;
    }
    return $d[-1];
}

##############################################################################
# Musik_Favorites
#   musikFavorites (kommagetrennt, Reihenfolge = HEOS-Kanal 1..n,
#   _ = Leerzeichen).
##############################################################################
sub Musik_Favorites {
    my ($name) = @_;
    my $i = 0;
    my @f;
    foreach my $x (split(/[,\n]/, AttrVal($name, "musikFavorites", ""))) {
        $x =~ s/_/ /g;
        $x =~ s/^\s+|\s+$//g;
        next if ($x eq "");
        $i++;
        push(@f, { name => $x, channel => $i });
    }
    return @f;
}

##############################################################################
# Musik_MatchFavorite
#   Bester Favorit zum Suchtext.
#   Rückgabe: (favorit, score, zweiter-mit-gleichem-score)
#   score: 3 = gleich, 2 = als ganze Wörter enthalten / Anfang, 1 = ähnlich
#   (Levenshtein <= Länge/5), 0 = nichts.
##############################################################################
sub Musik_MatchFavorite {
    my ($name, $q) = @_;
    my $qn = Musik_Strip(Musik_Norm($q));
    (my $qc = $qn) =~ s/ //g;
    return (undef, 0) if (length($qc) < 2);
    my @best;
    my $bs = 0;
    foreach my $f (Musik_Favorites($name)) {
        my $fn = Musik_Strip(Musik_Norm($f->{name}));
        (my $fc = $fn) =~ s/ //g;
        next if ($fc eq "");
        my $s = 0;
        if ($fc eq $qc) {
            $s = 3;
        } elsif (length($qc) >= 3 && (" $fn " =~ /\s\Q$qn\E\s/ || index($fc, $qc) == 0)) {
            $s = 2;
        } else {
            my $l = length($fc) > length($qc) ? length($fc) : length($qc);
            $s = 1 if ($l >= 5 && Musik_Lev($fc, $qc) <= int($l / 5));
        }
        next if ($s == 0);
        if    ($s > $bs)  { @best = ($f); $bs = $s; }
        elsif ($s == $bs) { push(@best, $f); }
    }
    return (undef, 0) if (!@best);
    return ($best[0], $bs, (@best > 1 ? $best[1] : undef));
}

##############################################################################
# Musik_FindRooms
#   Genannte Räume aus dem Text holen.
#   Rückgabe: (\@raeume, resttext, ueberall)
##############################################################################
sub Musik_FindRooms {
    my ($name, $t) = @_;
    my @found;
    my $all = 0;
    $all = 1 if ($t =~ s/(?<!\S)$MUSIK_RPRE(?:überall|ueberall|ganzen haus|alle(?:n)? räume(?:n)?)(?!\S)//i);
    my @al;
    foreach my $r (Musik_Rooms($name)) { push(@al, [$_, $r]) foreach (@{$r->{aliases}}); }
    # längste Aliase zuerst ("Terrasse West" vor "Terrasse"); Reihenfolge
    # im Ergebnis wie im Satz
    my $orig = lc($t);
    my %pos;
    foreach my $a (sort { length($b->[0]) <=> length($a->[0]) } @al) {
        my $x = $a->[0];
        if ($t =~ s/(?<!\S)$MUSIK_RPRE\Q$x\E(?!\S)//i) {
            next if (grep { $_->{name} eq $a->[1]{name} } @found);
            push(@found, $a->[1]);
            $pos{$a->[1]{name}} = index($orig, lc($x));
        }
    }
    @found = sort { $pos{$a->{name}} <=> $pos{$b->{name}} } @found;
    $t =~ s/\s+/ /g;
    $t =~ s/^\s+|\s+$//g;
    $t =~ s/\s+(?:im|in der|in|auf der|auf|und)$//i;
    return (\@found, $t, $all);
}

##############################################################################
# Musik_EchoRoom
#   Raum des Echos, das zuletzt gesprochen hat (wie my_echo_raum):
#   attr <echoDevice> echoRooms "<id-präfix>=<raum>", Reading echoId.
##############################################################################
sub Musik_EchoRoom {
    my ($name) = @_;
    my $ed  = AttrVal($name, "musikEchoDevice", "MyAlexa");
    my $id  = ReadingsVal($ed, "echoId", "");
    my $age = ReadingsAge($ed, "echoId", 9999);
    return "" if ($id eq "" || $age > AttrVal($name, "musikEchoMaxAge", 30));
    foreach my $l (split(/\n/, AttrVal($ed, "echoRooms", ""))) {
        next if ($l =~ /^\s*#/);
        my ($eid, $room) = split(/=/, $l, 2);
        next if (!defined($room));
        $room =~ s/^\s+|\s+$//g;
        return $room if (length($eid) >= 40 && index($id, $eid) == 0);
    }
    return "";
}

##############################################################################
# Musik_RoomByName
#   Raumeintrag zu einem Namen/Alias (ohne Groß-/Kleinschreibung).
##############################################################################
sub Musik_RoomByName {
    my ($name, $n) = @_;
    return undef if (!defined($n) || $n eq "");
    foreach my $r (Musik_Rooms($name)) {
        return $r if (grep { lc($_) eq lc($n) } @{$r->{aliases}});
    }
    return undef;
}

##############################################################################
# Musik_Do
#   Befehl ausführen (sofort oder nach $delay s). Im Simulationsmodus nur
#   protokollieren. Alle Befehle landen in $hash->{helper}{cmds}.
##############################################################################
sub Musik_Do {
    my ($hash, $cmd, $delay) = @_;
    $delay //= 0;
    push(@{$hash->{helper}{cmds}}, ($delay ? "+${delay}s " : "") . $cmd);
    return if (AttrVal($hash->{NAME}, "musikSimulate", 0));
    if ($delay) {
        my $t = { hash => $hash, cmd => $cmd };
        push(@{$hash->{helper}{timers}}, $t);
        InternalTimer(gettimeofday() + $delay, "Musik_Later", $t, 0);
        return;
    }
    my $err = AnalyzeCommandChain(undef, $cmd);
    Log3($hash->{NAME}, 2, "$hash->{NAME}: $cmd -> $err") if (defined($err) && $err ne "");
    return;
}

##############################################################################
# Musik_Later
#   InternalTimer-Rückruf für verzögerte Befehle.
##############################################################################
sub Musik_Later {
    my ($t) = @_;
    my $hash = $t->{hash};
    $hash->{helper}{timers} = [grep { $_ != $t } @{$hash->{helper}{timers} // []}];
    # eval: ein die() im Timer würde FHEM beenden
    my $err = eval { AnalyzeCommandChain(undef, $t->{cmd}) };
    $err = $@ if ($@);
    Log3($hash->{NAME}, 2, "$hash->{NAME}: $t->{cmd} -> $err") if (defined($err) && $err ne "");
    return;
}

##############################################################################
# Musik_ZoneOn / Musik_ZoneOff
#   Denon-Zone einschalten (Eingang OnlineMusic) bzw. ausschalten.
#   Hauptzone (TYPE DENON_AVR) über zoneMain, Nebenzonen über on/off.
#   Räume ohne Zone (nur HEOS-Box): aus = stop.
##############################################################################
sub Musik_ZoneOn {
    my ($hash, $r) = @_;
    return 0 if (!$r->{zone});
    my $name = $hash->{NAME};
    my $z = $r->{zone};
    my $isOn = Musik_ZoneIsOn($z);
    my $inOk = (ReadingsVal($z, "input", "") eq "OnlineMusic");
    Musik_Do($hash, "set $z on") if (!$isOn);
    Musik_Do($hash, "set $z input OnlineMusic") if (!$isOn || !$inOk);
    return AttrVal($name, "musikSpotifyDelay", 8) if (!$isOn);
    return AttrVal($name, "musikInputDelay", 2)   if (!$inOk);
    return 0;
}

##############################################################################
# Musik_ZoneIsOn
#   Läuft die Zone? Hauptzone (DENON_AVR): power und zoneMain on,
#   Nebenzone: power on (sonst state).
##############################################################################
sub Musik_ZoneIsOn {
    my ($z) = @_;
    my $type = $defs{$z} ? ($defs{$z}{TYPE} // "") : "";
    my $pw = ReadingsVal($z, "power", ReadingsVal($z, "state", "off"));
    return 0 if ($pw ne "on");
    return 0 if ($type eq "DENON_AVR" && ReadingsVal($z, "zoneMain", "on") ne "on");
    return 1;
}

##############################################################################
# Musik_RoomsOn
#   Alle Zonen der Räume einschalten, längste nötige Wartezeit zurückgeben.
##############################################################################
sub Musik_RoomsOn {
    my ($hash, @rooms) = @_;
    my $d = 0;
    foreach my $r (@rooms) { my $x = Musik_ZoneOn($hash, $r); $d = $x if ($x > $d); }
    return $d;
}

sub Musik_ZoneOff {
    my ($hash, $r) = @_;
    if ($r->{zone}) {
        my $z = $r->{zone};
        my $type = $defs{$z} ? ($defs{$z}{TYPE} // "") : "";
        Musik_Do($hash, $type eq "DENON_AVR" ? "set $z zoneMain off" : "set $z off");
    } elsif ($r->{heos}) {
        Musik_Do($hash, "set $r->{heos} stop");
    }
    return;
}

##############################################################################
# Musik_Volume
#   Lautstärke an der Zone, ohne Zone am HEOS-Player.
#   $how: set | up | down. Begrenzung auf musikVolumeMax (Standard 60).
##############################################################################
sub Musik_Volume {
    my ($hash, $r, $how, $val) = @_;
    my $dev = $r->{zone} || $r->{heos};
    return undef if (!$dev);
    my $cur = ReadingsVal($dev, "volume", 30);
    $cur = 30 if ($cur !~ /^\d+(\.\d+)?$/);
    my $step = AttrVal($hash->{NAME}, "musikVolumeStep", 5);
    my $new = $how eq "set" ? $val
            : $how eq "up"  ? $cur + ($val // $step)
            :                 $cur - ($val // $step);
    my $max = AttrVal($hash->{NAME}, "musikVolumeMax", 60);
    $new = 0    if ($new < 0);
    $new = $max if ($new > $max);
    $new = int($new + 0.5);
    Musik_Do($hash, "set $dev volume $new");
    return $new;
}

##############################################################################
# Musik_SpotifyPlay
#   Spotify-Befehl, ggf. verzögert (die Zone muss erst anlaufen).
##############################################################################
sub Musik_SpotifyPlay {
    my ($hash, $cmd, $delay) = @_;
    my $sp = AttrVal($hash->{NAME}, "musikSpotify", "rem_spotify");
    Musik_Do($hash, "set $sp $cmd", $delay);
    return;
}

##############################################################################
# Musik_Handle
#   Satz auswerten, schalten, Readings schreiben, Antwort liefern.
##############################################################################
sub Musik_Handle {
    my ($hash, $text, $room) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{cmds} = [];
    my ($ans, $act, $rn) = Musik_Decide($hash, $text // "", $room);
    my $sim  = AttrVal($name, "musikSimulate", 0);
    my $cmds = join(" ; ", @{$hash->{helper}{cmds}});
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "last_text",     $text // "");
    readingsBulkUpdate($hash, "last_room",     $rn // "");
    readingsBulkUpdate($hash, "last_action",   $act);
    readingsBulkUpdate($hash, "last_answer",   $ans);
    readingsBulkUpdate($hash, "last_commands", $cmds eq "" ? "-" : $cmds);
    readingsBulkUpdate($hash, "state",         ($sim ? "Test: " : "") . $act);
    readingsEndUpdate($hash, 1);
    Log3($name, 3, "$name: '" . ($text // "") . "' -> $act"
                 . ($sim ? " (Simulation)" : "") . " [$cmds]");
    return $ans;
}

##############################################################################
# Musik_Decide
#   Die eigentliche Auswertung. Rückgabe: (antwort, aktion, raumname)
##############################################################################
sub Musik_Decide {
    my ($hash, $text, $room) = @_;
    my $name = $hash->{NAME};
    return ("Das Musikmodul ist ausgeschaltet", "disabled", "")
        if (AttrVal($name, "disable", 0));

    my $t = lc($text);
    $t =~ s/[?!.,;:]+/ /g;
    $t =~ s/(?<!\S)(?:bitte|mal|doch|alexa)(?!\S)//g;
    $t =~ s/\s+/ /g;
    $t =~ s/^\s+|\s+$//g;

    # --- Raum ---------------------------------------------------------------
    my ($found, $rest, $all) = Musik_FindRooms($name, $t);
    my @rooms = @$found;
    my $named = (@rooms || $all) ? 1 : 0;
    if (!@rooms && !$all && defined($room) && $room ne "") {
        my $r = Musik_RoomByName($name, $room);
        if ($r) { push(@rooms, $r); $named = 1; }
    }
    if (!@rooms && !$all) {
        my $r = Musik_RoomByName($name, Musik_EchoRoom($name))
             // Musik_RoomByName($name, AttrVal($name, "musikDefaultRoom", "Wohnzimmer"));
        push(@rooms, $r) if ($r);
    }
    @rooms = Musik_Rooms($name) if ($all);
    return ("Ich kenne keinen Raum für Musik", "kein Raum", "") if (!@rooms);
    my $r  = $rooms[0];
    my $rn = $all ? "überall" : join(" und ", map { $_->{name} } @rooms);
    my $im = $all ? "überall" : "im $rn";

    # --- Aus ----------------------------------------------------------------
    if ($rest =~ /(?<!\S)(?:aus|ausschalten|abschalten|ausmachen)$/) {
        my @off = $named ? @rooms : Musik_Rooms($name);
        Musik_ZoneOff($hash, $_) foreach (@off);
        my $wo = $named ? $im : "überall";
        return ("Ich schalte die Musik $wo aus", "aus", $named ? $rn : "überall");
    }

    # --- Steuern (HEOS-Player des ersten Raums) -----------------------------
    my @ctl = (
        ['(?:^|\s)(?:stop|stopp|stoppen)$',                       "stop",  "Musik gestoppt"],
        ['(?:^|\s)(?:pause|pausieren|anhalten)$',                 "pause", "Pause"],
        ['^(?:musik\s+)?(?:weiter|fortsetzen|weiter abspielen)$', "play",  "Es geht weiter"],
        ['(?:^|\s)(?:nächste[rns]?|naechste[rns]?|überspringen|skip)(?:\s|$)', "next", "Nächster Titel"],
        ['(?:^|\s)(?:vorherige[rns]?|letzte[rns]?)\s+(?:lied|titel|song)', "prev", "Vorheriger Titel"],
    );
    foreach my $c (@ctl) {
        next if ($rest !~ /$c->[0]/);
        my $p = $r->{heos};
        return ("Für $r->{name} ist kein Player eingetragen", "kein Player", $r->{name}) if (!$p);
        Musik_Do($hash, "set $p $c->[1]");
        return ("$c->[2] $im", $c->[1], $rn);
    }

    # --- Lautstärke ---------------------------------------------------------
    if ($rest =~ /(?:^|\s)(?:lauter|leiser|lautstärke|lautstaerke)(?:\s|$)/) {
        my ($how, $val);
        if    ($rest =~ /(?:auf|lautstärke|lautstaerke)\D*?(\d+)/) { ($how, $val) = ("set", $1); }
        elsif ($rest =~ /lauter/) { ($how, $val) = ("up",   ($rest =~ /(\d+)/ ? $1 : undef)); }
        elsif ($rest =~ /leiser/) { ($how, $val) = ("down", ($rest =~ /(\d+)/ ? $1 : undef)); }
        else  { return ("Wie laut soll es sein?", "lautstärke unklar", $rn); }
        my @v = grep { defined } map { Musik_Volume($hash, $_, $how, $val) } @rooms;
        return ("Für $rn ist keine Lautstärke einstellbar", "kein Gerät", $rn) if (!@v);
        return ("Lautstärke $im auf $v[0]", "lautstärke $v[0]", $rn);
    }

    # --- Nur an -------------------------------------------------------------
    if ($rest =~ /^(?:die )?(?:musik|anlage|denon)\s+(?:an|ein|einschalten|anschalten|anmachen|starten?)$/) {
        Musik_ZoneOn($hash, $_) foreach (@rooms);
        return ("Ich schalte die Musik $im ein", "an", $rn);
    }

    # --- Inhalt: Lied / Playlist / DJ / Favorit / Interpret -------------------
    my $q = $rest;
    $q =~ s/\s+(?:an|ein|anmachen|einschalten|starten|hören|hoeren|spielen|abspielen|laufen lassen)$//;
    $q =~ s/^(?:spiel\S*|mach\S*|start\S*|stell\S*|leg\S*|ich (?:will|möchte|moechte)(?:\s+\S+)?\s+hören)\s+//;
    $q =~ s/^(?:spiel\S*|mach\S*|start\S*|stell\S*|leg\S*)$//;
    $q =~ s/^\s+|\s+$//g;

    if ($q =~ /^(?:das |den |ein )?(?:lied|song|titel)\s+(.+?)(?:\s+von\s+(.+))?$/) {
        my ($title, $artist) = ($1, $2);
        my $d = Musik_RoomsOn($hash, @rooms);
        Musik_SpotifyPlay($hash, "playTrackByName $title" . ($artist ? " $artist" : ""), $d);
        return ("Ich spiele $title" . ($artist ? " von $artist" : "") . " $im", "lied $title", $rn);
    }
    if ($q =~ /^(?:die |meine )?(?:playlist|wiedergabeliste)\s+(.+)$/) {
        my $pl = $1;
        my $d = Musik_RoomsOn($hash, @rooms);
        Musik_SpotifyPlay($hash, "playPlaylistByName $pl", $d);
        return ("Ich spiele die Playlist $pl $im", "playlist $pl", $rn);
    }
    if ($q =~ /^(?:(?:die |etwas |irgendwas |den )?(?:musik|lieder|radio|dj|spotify dj|spotify))?$/) {
        my $d = Musik_RoomsOn($hash, @rooms);
        Musik_Do($hash, "set " . AttrVal($name, "musikSpotifyDJ", "d_spotify_dj") . " on", $d);
        return ("Ich spiele den Spotify DJ $im", "dj", $rn);
    }

    # "Musik von X" -> Interpret; Favorit nur, wenn er genau so heißt
    my $artistForced = ($q =~ s/^(?:musik|lieder|songs|was|etwas)\s+von\s+//) ? 1 : 0;

    my ($fav, $score, $alt) = Musik_MatchFavorite($name, $q);
    if ($fav && ($score == 3 || (!$artistForced && $score >= 1))) {
        return ("Meinst du $fav->{name} oder $alt->{name}?", "nachfrage", $rn)
            if ($alt && $score < 3);
        my %seen;
        foreach my $x (@rooms) {
            Musik_ZoneOn($hash, $x);
            next if (!$x->{heos} || $seen{$x->{heos}}++);
            Musik_Do($hash, "set $x->{heos} channel $fav->{channel}");
        }
        return ("$fav->{name} läuft $im", "favorit $fav->{channel} $fav->{name}", $rn);
    }

    my $artist = $q;
    $artist =~ s/^(?:musik|radio|sender)\s+//;
    return ("Was soll ich spielen?", "unklar", $rn) if ($artist eq "");
    my $d = Musik_RoomsOn($hash, @rooms);
    Musik_SpotifyPlay($hash, "playArtistByName $artist", $d);
    return ("Ich spiele Musik von $artist $im", "interpret $artist", $rn);
}

1;

=pod
=item helper
=item summary    music by voice: room, HEOS favourites, Spotify
=item summary_DE Musik per Sprache: Raum, HEOS-Favoriten, Spotify
=begin html

<a id="Musik"></a>
<h3>Musik</h3>
<ul>
  Evaluates a spoken sentence (e.g. from Talk2Fhem/Alexa) and plays music in
  the right room: HEOS favourites (fuzzy match), Spotify track, playlist or
  artist, transport and volume control. See the German description.
</ul>

=end html

=begin html_DE

<a id="Musik"></a>
<h3>Musik</h3>
<ul>
  Wertet einen gesprochenen Satz aus (z. B. aus Talk2Fhem/Alexa) und spielt
  Musik im richtigen Raum.<br><br>

  <a id="Musik-define"></a>
  <b>Define</b>
  <ul><code>define &lt;name&gt; Musik</code></ul><br>

  <b>Aufruf aus Talk2Fhem</b>
  <ul><code>&lt;regex&gt; = (answer=&gt;'Musik_Talk("musik","$0")')</code></ul><br>

  <b>Reihenfolge der Auswertung</b>
  <ol>
    <li>Raum: genannt &gt; Echo-Raum &gt; musikDefaultRoom; „überall“ = alle Räume</li>
    <li>„… aus“ (ohne Raum: überall)</li>
    <li>stop, pause, weiter, nächster, vorheriges Lied</li>
    <li>lauter/leiser [um N], „auf N“, „Lautstärke N“</li>
    <li>„Musik an“</li>
    <li>„das Lied X [von Y]“, „Playlist X“, „Musik“ allein (Spotify DJ)</li>
    <li>HEOS-Favorit (unscharf, bei Gleichstand Nachfrage)</li>
    <li>sonst Interpret über Spotify</li>
  </ol><br>

  <a id="Musik-set"></a>
  <b>Set</b>
  <ul>
    <li><a id="Musik-set-text"></a><code>text &lt;satz&gt;</code> – Satz auswerten
      wie aus talk; Ergebnis in den Readings <code>last_*</code>.</li>
  </ul><br>

  <a id="Musik-attr"></a>
  <b>Attribute</b>
  <ul>
    <li><a id="Musik-attr-musikRooms"></a><code>musikRooms</code> – eine Zeile je Raum:<br>
      <code>Raum|Alias1,Alias2 = zone=&lt;Denon-Gerät&gt; heos=&lt;HEOS-Player&gt;</code><br>
      zone ist optional (z. B. Bad nur mit HEOS-Box).</li>
    <li><a id="Musik-attr-musikFavorites"></a><code>musikFavorites</code> – HEOS-Favoriten
      kommagetrennt in Kanalreihenfolge (1..n), <code>_</code> = Leerzeichen.</li>
    <li><a id="Musik-attr-musikDefaultRoom"></a><code>musikDefaultRoom</code> – Raum ohne
      Angabe und ohne Echo-Raum (Standard Wohnzimmer).</li>
    <li><a id="Musik-attr-musikSpotify"></a><code>musikSpotify</code> – Spotify-Gerät
      (Standard rem_spotify).</li>
    <li><a id="Musik-attr-musikSpotifyDJ"></a><code>musikSpotifyDJ</code> – Schalter für den
      Spotify DJ (Standard d_spotify_dj, wird mit <code>on</code> gesetzt).</li>
    <li><a id="Musik-attr-musikSpotifyDelay"></a><code>musikSpotifyDelay</code> – Sekunden
      zwischen Zone an und Spotify-Start, nur wenn die Zone aus war (Standard 8).</li>
    <li><a id="Musik-attr-musikInputDelay"></a><code>musikInputDelay</code> – Sekunden
      Wartezeit, wenn die Zone an ist, aber erst auf OnlineMusic umgeschaltet wird
      (Standard 2). Läuft sie schon auf OnlineMusic, startet Spotify sofort.</li>
    <li><a id="Musik-attr-musikEchoDevice"></a><code>musikEchoDevice</code> – Gerät mit
      Reading echoId und Attribut echoRooms (Standard MyAlexa).</li>
    <li><a id="Musik-attr-musikEchoMaxAge"></a><code>musikEchoMaxAge</code> – höchstes Alter
      von echoId in Sekunden (Standard 30).</li>
    <li><a id="Musik-attr-musikVolumeStep"></a><code>musikVolumeStep</code> – Schritt für
      lauter/leiser (Standard 5).</li>
    <li><a id="Musik-attr-musikVolumeMax"></a><code>musikVolumeMax</code> – Obergrenze
      (Standard 60).</li>
    <li><a id="Musik-attr-musikSimulate"></a><code>musikSimulate</code> – 1 = nichts
      schalten, nur protokollieren (Reading last_commands).</li>
    <li><a id="Musik-attr-disable"></a><code>disable</code></li>
  </ul>
</ul>

=end html_DE

=cut
