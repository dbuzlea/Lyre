#!/bin/bash
# Cuts the Disc's sound effects out of the recordings in Scripts/DiscSoundSources and
# writes them to Lyre/Sounds, which the app target bundles.
#
# The recordings run long and hold several sounds each, so each is trimmed to the part
# the app uses, faded at its ends so nothing clicks, and levelled, as the Spool's are
# (see prepare_spool_sounds.sh). They are written as 44.1 kHz mono 16-bit WAVs: the app
# plays them as system sounds, which must be linear PCM, and which mix over the music
# without pausing it. The Disc's keys use the Spool's key press, so there's none here.
#
#   bash Lyre/Scripts/prepare_disc_sounds.sh        (from anywhere; needs ffmpeg)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/DiscSoundSources"
OUT="$HERE/../Lyre/Sounds"
mkdir -p "$OUT"

# Measured after the mix down to mono, so each lands at its level.
# cut <source> <output> <start s> <end s> <fade out s> <level dB> <peak|rms>
cut() {
    local src="$SRC/$1" out="$OUT/$2.wav" start="$3" end="$4" fade="$5" level="$6" by="$7"
    local length fade_at measured gain
    length=$(printf '%.3f' "$(echo "$end - $start" | bc -l)")
    fade_at=$(printf '%.3f' "$(echo "$length - $fade" | bc -l)")
    local shape="aformat=channel_layouts=mono,atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,afade=t=in:d=0.004,afade=t=out:st=$fade_at:d=$fade"
    if [ "$by" = rms ]; then
        shape="aformat=channel_layouts=mono,atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,afade=t=in:d=0.08,afade=t=out:st=$fade_at:d=$fade"
    fi
    local key=max_volume
    [ "$by" = rms ] && key=mean_volume
    measured=$(ffmpeg -hide_banner -nostats -i "$src" -af "$shape,volumedetect" -f null - 2>&1 \
        | sed -n "s/.*$key: \(-*[0-9.]*\) dB.*/\1/p")
    gain=$(printf '%.2f' "$(echo "$level - ($measured)" | bc -l)")
    # A limiter after the gain: the snaps' sharpest edges can otherwise reach full scale.
    ffmpeg -loglevel error -y -i "$src" -af "$shape,volume=${gain}dB,alimiter=limit=0.84:attack=0.5:release=20:level=disabled" \
        -ac 1 -ar 44100 -c:a pcm_s16le "$out"
    printf '%-24s %5.0f ms  %+5.1f dB\n' "$2.wav" "$(echo "$length * 1000" | bc -l)" "$gain"
}

# The lid's catch letting go (3.05 s) and the lid springing up with a snap (3.50 s).
cut inserting-cd-and-closing-door.mp3  disc_lid_open   3.000 3.720 0.080 -1 peak
# The disc pressed down onto the spindle: the scrape and clicks of its hub gripping.
cut inserting-cd-and-closing-door.mp3  disc_seat       4.530 5.280 0.080 -2 peak
# The lid pressed shut: the latch (5.60 s) and the snap of it closing (5.85 s).
cut inserting-cd-and-closing-door.mp3  disc_lid_close  5.560 6.060 0.080 -1 peak
# The motor bringing the disc up to speed: the whir rising out of quiet at 3.30 s and
# settling into its spin, faded out under the song coming in.
cut cd-whirring-in-drive.mp3           disc_spin_up    3.240 4.020 0.220 -24 rms
