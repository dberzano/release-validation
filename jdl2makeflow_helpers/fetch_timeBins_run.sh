#!/bin/bash -e
ALIDPGSCRIPT="$(find "$ALIDPG_ROOT" -name "$1" -print -quit || true)"
[[ $ALIDPGSCRIPT ]] || { echo "Cannot find $1 in $ALIDPG_ROOT"; exit 1; }
[[ -x $ALIDPGSCRIPT ]] || ALIDPGSCRIPT="bash $ALIDPGSCRIPT"

# See if we can retrieve output file already
cat > copyHere.C <<EOF
void copyHere() {
  TFile::Cp("$ALIEN_JDL_OUTPUTDIR/timeBins.log", "timeBins.log");
}
EOF
root -l -b -q copyHere.C
rm -f copyHere.C
[[ ! -e timeBins.log ]] || { echo "timeBins.log was found and retrieved, exiting!"; exit 0; }

# Execute actual procVDTime script now
shift
exec $ALIDPGSCRIPT "$@"
