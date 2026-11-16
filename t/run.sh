#!/bin/sh
#
# Alle Tests laufen lassen. Braucht nur perl - keine FHEM-Installation.
#
#   sh t/run.sh
#
# Rückgabewert 0 = alles grün, sonst Anzahl fehlgeschlagener Dateien.

dir=$(dirname "$0")
rc=0

if perl -c "$dir/../FHEM/98_Musik.pm" 2>&1 | grep -q "syntax OK"; then
    echo "ok    98_Musik.pm syntax OK"
else
    echo "FAIL  98_Musik.pm syntax"
    perl -c "$dir/../FHEM/98_Musik.pm"
    rc=$((rc + 1))
fi

for t in "$dir"/*.t; do
    echo
    echo "--- $t"
    if ! perl "$t"; then
        rc=$((rc + 1))
    fi
done

echo
if [ "$rc" -eq 0 ]; then
    echo "ALLES GRUEN"
else
    echo "$rc Datei(en) mit Fehlern"
fi
exit "$rc"
