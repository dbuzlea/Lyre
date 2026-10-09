#!/bin/bash
# Cuts the Spool's sound effects out of the recordings in Scripts/SpoolSoundSources and
# writes them to Lyre/Sounds, which the app target bundles.
#
# The recordings have silence around the sound, and some hold more than one sound, so
# each is trimmed to the part the app uses, faded at its ends so nothing clicks, and
# levelled. They are written as 44.1 kHz mono 16-bit WAVs: the app plays them as system
# sounds, which must be linear PCM, and which mix over the music without pausing it.
#
#   bash Lyre/Scripts/prepare_spool_sounds.sh        (from anywhere; needs ffmpeg)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/SpoolSoundSources"
OUT="$HERE/../Lyre/Sounds"
mkdir -p "$OUT"

# cut <source> <output> <start s> <end s> <fade out s> <level dB> <peak|rms>
#   Levels by peak for clicks and knocks, by average loudness for the rewind whir.
cut() {
    local src="$SRC/$1" out="$OUT/$2.wav" start="$3" end="$4" fade="$5" level="$6" by="$7"
    local length fade_at measured gain
    # printf, for the leading zero ffmpeg needs: bc writes 0.11 as ".11".
    length=$(printf '%.3f' "$(echo "$end - $start" | bc -l)")
    fade_at=$(printf '%.3f' "$(echo "$length - $fade" | bc -l)")
    local shape="atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,afade=t=in:d=0.003,afade=t=out:st=$fade_at:d=$fade"
    if [ "$by" = rms ]; then
        shape="atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,afade=t=in:d=$fade,afade=t=out:st=$fade_at:d=$fade"
    fi
    local key=max_volume
    [ "$by" = rms ] && key=mean_volume
    measured=$(ffmpeg -hide_banner -nostats -i "$src" -af "$shape,volumedetect" -f null - 2>&1 \
        | sed -n "s/.*$key: \(-*[0-9.]*\) dB.*/\1/p")
    gain=$(printf '%.2f' "$(echo "$level - ($measured)" | bc -l)")
    ffmpeg -loglevel error -y -i "$src" -af "$shape,volume=${gain}dB" -ac 1 -ar 44100 -c:a pcm_s16le "$out"
    printf '%-28s %5.0f ms  %+5.1f dB\n' "$2.wav" "$(echo "$length * 1000" | bc -l)" "$gain"
}

# A transport key going down: the single click in the recording, at 0.66 s.
cut button-press.mp3              spool_button_press      0.650 0.800 0.040 -3 peak
# A held key let go. The recording is a press (0.78 s) and, after a pause, the release
# (2.28 s) with its small rattle; the press is already heard as the key went down, so
# only the release is used.
cut button-press-and-release.mp3  spool_button_release    2.265 2.680 0.060 -3 peak
# Eject: the door's catch and the tape coming out with it.
cut cassette-eject.mp3            spool_cassette_eject    0.025 0.500 0.060 -1 peak
# A tape sliding in and dropping onto its spindles.
cut cassette-insert.mp3           spool_cassette_insert   0.015 0.720 0.060 -1 peak
# The door swinging shut; its slam lands about 0.1 s in, as the door does.
cut closing-cassette-door.mp3     spool_door_close        0.025 0.470 0.060 -1 peak
# Rewinding: three pieces of the steady whir in the middle of the recording, taken from
# different places so the loop doesn't repeat one piece. Each fades in and out over its
# overlap with the next. Kept faint: it plays under the music.
cut rewind_cassette_tape.mp3      spool_rewind_1          8.000 8.700 0.100 -36 rms
cut rewind_cassette_tape.mp3      spool_rewind_2         13.000 13.700 0.100 -36 rms
cut rewind_cassette_tape.mp3      spool_rewind_3         18.000 18.700 0.100 -36 rms
