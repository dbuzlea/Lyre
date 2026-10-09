#!/bin/bash
# Cuts the Gramophone's recorded sound effects out of the recordings in
# Scripts/GramophoneSoundSources and writes them to Lyre/Sounds, which the app target
# bundles. The sounds with no recording yet (the needle lifting, the crank's ratchet and
# the spring wound) are still the placeholders from make_gramophone_sounds.py.
#
# Each is trimmed to the part the app uses, faded at its ends so nothing clicks, and
# levelled (measured in mono, as it is written), then written as a 44.1 kHz mono 16-bit WAV: the app plays them as system
# sounds, which must be linear PCM, and which mix over the music without pausing it.
#
#   bash Lyre/Scripts/prepare_gramophone_sounds.sh        (from anywhere; needs ffmpeg)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/GramophoneSoundSources"
OUT="$HERE/../Lyre/Sounds"
mkdir -p "$OUT"

# cut <source> <output> <start s> <end s> <fade in s> <fade out s> <level dB> <peak|rms>
#   Levels by peak for clicks and knocks, by average loudness for the running sounds.
cut() {
    local src="$SRC/$1" out="$OUT/$2.wav" start="$3" end="$4" fade_in="$5" fade="$6" level="$7" by="$8"
    local length fade_at measured gain
    # printf, for the leading zero ffmpeg needs: bc writes 0.11 as ".11".
    length=$(printf '%.3f' "$(echo "$end - $start" | bc -l)")
    fade_at=$(printf '%.3f' "$(echo "$length - $fade" | bc -l)")
    # Measured in floating point: some recordings peak over full scale once decoded, and
    # a 16-bit meter would read those as 0 dB.
    local shape="atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,aformat=sample_fmts=dbl:channel_layouts=mono,afade=t=in:d=$fade_in,afade=t=out:st=$fade_at:d=$fade"
    local key="Peak level"
    [ "$by" = rms ] && key="RMS level"
    measured=$(ffmpeg -hide_banner -nostats -i "$src" -af "$shape,astats=measure_perchannel=none" -f null - 2>&1 \
        | sed -n "s/.*$key dB: \(-*[0-9.]*\).*/\1/p" | tail -1)
    gain=$(printf '%.2f' "$(echo "$level - ($measured)" | bc -l)")
    ffmpeg -loglevel error -y -i "$src" -af "$shape,volume=${gain}dB" -ac 1 -ar 44100 -c:a pcm_s16le "$out"
    printf '%-30s %6.0f ms  %+5.1f dB\n' "$2.wav" "$(echo "$length * 1000" | bc -l)" "$gain"
}

# The play switch (and the brake and speed levers, which share it): the one snap, at
# 0.16 s, and its short ring.
cut start-switch-flip.mp3         gramophone_switch       0.140 0.440 0.003 0.080 -2 peak
# A record in the bin or the drawer's stack tipped over to the next: a soft brush of
# card at 0.04 s, then the sleeve landing at 0.14 s. Kept below the switch: it's heard
# again and again, flipping through.
cut flipping-through-queue-transition-noise.mp3 \
                                  gramophone_flip         0.020 0.400 0.010 0.100 -6 peak
# The drawer: the recording is it sliding open (peaking at 1.0 s), a pause, and it
# sliding shut and knocking home (3.5 s). The room's hiss runs under both, so each fades
# in and out over it.
cut drawer-open-and-close.mp3     gramophone_drawer_open  0.200 1.950 0.050 0.300 -4 peak
cut drawer-open-and-close.mp3     gramophone_drawer_close 3.050 4.200 0.050 0.200 -4 peak
# The needle meeting the record: a brush as it nears (4.0 s), the touch (4.12 s), the
# scratch of the lead-in groove, and the first of the crackle, fading. What comes
# before it in the recording is the arm being handled, which isn't used.
cut record-vinyl-needle-drop-start-scratches-crackle.mp3 \
                                  gramophone_needle_drop  3.970 4.950 0.010 0.350 -6 peak
# Surface noise, played under the music: three pieces of the steady crackle, from
# different places in the recording (which repeats every 30 s, so from different places
# in that), each fading in and out over its overlap with the next.
cut vinyl-crackle-noise.mp3       gramophone_crackle_1   12.000 16.000 0.250 0.250 -44 rms
cut vinyl-crackle-noise.mp3       gramophone_crackle_2   47.000 51.000 0.250 0.250 -44 rms
cut vinyl-crackle-noise.mp3       gramophone_crackle_3   83.000 87.000 0.250 0.250 -44 rms
# The turntable turning, under the crackle: three pieces of its steady running, from
# stretches with no knocks in them, overlapping the same way.
cut turntable-running.mp3         gramophone_running_1    6.000 10.000 0.250 0.250 -42 rms
cut turntable-running.mp3         gramophone_running_2   30.000 34.000 0.250 0.250 -42 rms
cut turntable-running.mp3         gramophone_running_3   60.000 64.000 0.250 0.250 -42 rms
