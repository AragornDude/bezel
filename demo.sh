#!/usr/bin/env bash
# BEZEL: a five-second teaser for the terminal.
# Run:   bash bezel-teaser-v4.sh [--mute]
# Notes: best in a truecolor terminal (iTerm2, Ghostty, kitty, WezTerm).
#        Falls back to a 256-colour greyscale; NO_COLOR=1 gives monochrome.
#        Sound: BEZEL_MUTE=1 or --mute disables. Needs python3 (once) + a player.
set -u

if [[ ! -t 1 || ${TERM:-dumb} == dumb ]]; then
  printf 'BEZEL: Four edges. Your rules.\nRun in an interactive terminal to watch the demo.\n'
  exit 0
fi

rows=24 cols=80
read -r r c < <(stty size </dev/tty 2>/dev/null || stty size 2>/dev/null) && rows=$r cols=$c
if (( rows < 19 || cols < 50 )); then
  printf 'Please use a terminal at least 50 columns x 19 rows.\n'
  exit 0
fi

# ── palette ────────────────────────────────────────────────────────────────
ACC_R=226 ACC_G=182 ACC_B=140        # champagne accent (fingers only)
EDGE=60                               # resting outline (graphite)
LIT=240                               # lit edge (near-white)

truecolor=0 mono=0
[[ ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ]] && truecolor=1
[[ -n ${NO_COLOR:-} ]] && mono=1

if   (( mono ));      then BG=''
elif (( truecolor )); then BG=$'\033[48;2;0;0;0m'
else                       BG=$'\033[48;5;16m'
fi

gray() {   # 0-255 -> $G
  local v=$1
  (( v < 0 )) && v=0
  (( v > 255 )) && v=255
  if (( mono )); then
    if   (( v >= 140 )); then G=$'\033[0;1m'
    elif (( v < 90 ));   then G=$'\033[0;2m'
    else                      G=$'\033[0m'; fi
  elif (( truecolor )); then
    G=$'\033[38;2;'"$v;$v;${v}m"
  else
    G=$'\033[38;5;'"$(( 232 + v * 23 / 255 ))m"
  fi
}

tint() {   # 0-255 -> $T (accent, scaled toward black)
  local v=$1
  (( v < 0 )) && v=0
  (( v > 255 )) && v=255
  if (( mono )); then
    gray "$v"; T=$G
  elif (( truecolor )); then
    T=$'\033[38;2;'"$(( ACC_R * v / 255 ));$(( ACC_G * v / 255 ));$(( ACC_B * v / 255 ))m"
  elif (( v < 120 )); then
    gray "$v"; T=$G
  else
    T=$'\033[38;5;180m'
  fi
}

# ── sound ──────────────────────────────────────────────────────────────────
APID=''
WAV=${XDG_CACHE_HOME:-$HOME/.cache}/bezel-teaser-v4.wav
play_cmd=()
if [[ -z ${BEZEL_MUTE:-} && ${1:-} != --mute ]]; then
  if   command -v afplay >/dev/null 2>&1; then play_cmd=(afplay)
  elif command -v paplay >/dev/null 2>&1; then play_cmd=(paplay)
  elif command -v aplay  >/dev/null 2>&1; then play_cmd=(aplay -q)
  elif command -v ffplay >/dev/null 2>&1; then play_cmd=(ffplay -nodisp -autoexit -loglevel quiet)
  fi
fi

if (( ${#play_cmd[@]} )) && [[ ! -s $WAV ]]; then
  if command -v python3 >/dev/null 2>&1; then
    mkdir -p "${WAV%/*}"
    python3 - "$WAV" <<'PY' || { rm -f "$WAV"; play_cmd=(); }
import math, random, struct, sys, wave
SR = 44100; DUR = 5.0; N = int(SR * DUR); TAU = 2 * math.pi
L = [0.0] * N; R = [0.0] * N
rng = random.Random(7)

def mix(t, sig, amp, pan):
    a = (pan + 1) * math.pi / 4
    gl, gr = math.cos(a) * amp, math.sin(a) * amp
    i0 = int(t * SR)
    for k, s in enumerate(sig):
        i = i0 + k
        if i >= N: break
        L[i] += s * gl; R[i] += s * gr

def pluck(t, f, amp=.08, d=.55, bright=.35, pan=0.0):
    sig = []
    for i in range(int(d * SR)):
        x = i / SR
        env = (1 - math.exp(-x / .0015)) * math.exp(-x * 7 / d)
        s = (math.sin(TAU * f * x)
             + bright * math.sin(TAU * 2 * f * x) * math.exp(-x * 14)
             + .08 * math.sin(TAU * 3 * f * x) * math.exp(-x * 30))
        sig.append(s * env)
    mix(t, sig, amp, pan)

def thud(t, amp=.25, f0=110, f1=48, d=.25, k=16, pan=0.0):
    sig = []; ph = 0.0
    for i in range(int(d * SR)):
        x = i / SR
        ph += TAU * (f1 + (f0 - f1) * math.exp(-x * 28)) / SR
        sig.append(math.sin(ph) * (1 - math.exp(-x / .002)) * math.exp(-x * k))
    mix(t, sig, amp, pan)

def tick(t, amp=.12, f=2600, pan=0.0):
    sig = []; prev = 0.0
    for i in range(int(.02 * SR)):
        x = i / SR
        nz = rng.uniform(-1, 1); hp = nz - prev; prev = nz
        sig.append((.5 * hp + math.sin(TAU * f * x)) * math.exp(-x * 220))
    mix(t, sig, amp, pan)

def whoosh(t, d, amp, f0, f1, pan=0.0):
    n = int(d * SR); sig = []; y1 = y2 = 0.0
    for i in range(n):
        u = i / n
        a = 1 - math.exp(-TAU * (f0 + (f1 - f0) * u) / SR)
        y1 += a * (rng.uniform(-1, 1) - y1); y2 += a * (y1 - y2)
        sig.append(y2 * math.sin(math.pi * u) ** 2 * 3)
    mix(t, sig, amp, pan)

fr = lambda n: n / 24.0
P1 = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]    # C5 D5 E5 G5 A5 C6
P2 = [659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5]   # E5 G5 A5 C6 D6 E6

# intro
thud(.10, .20)
pluck(.30, 392.0, .06, .8, .25)

# volume (left edge): soft touch, airy sweep, rising pentatonic steps
thud(fr(14), .10, pan=-.4)
whoosh(fr(15), .75, .05, 500, 2200, -.4)
for k, f in enumerate(P1):
    pluck(fr(16 + k * 3), f, .055 + .008 * k, .5, .35, -.4)

# brightness (right edge): brighter timbre, higher register
thud(fr(38), .10, pan=.4)
whoosh(fr(39), .75, .05, 700, 3000, .4)
for k, f in enumerate(P2):
    pluck(fr(40 + k * 3), f, .045 + .007 * k, .45, .55, .4)

# workspaces: three-finger swipe, tick on page change
thud(fr(62), .08)
whoosh(fr(63), .55, .06, 400, 2500)
tick(fr(69), .12)
pluck(fr(69), 783.99, .05, .35, .3)

# finale: four edges light (L, T, R, B), then wordmark
for t, f, p in ((80, 523.25, -.5), (84, 659.25, 0), (88, 783.99, .5), (92, 1046.5, 0)):
    pluck(fr(t), f, .08, .9, .4, p)
thud(fr(94), .26, 80, 50, .95, 5)
for f, a in ((261.63, .06), (392.0, .05), (659.25, .04)):
    pluck(fr(94), f, a, 1.0, .3)
pluck(fr(100), 1046.5, .035, .7, .5)

# small damped-comb room, kept short so nothing rings
def reverb(src, delays, fb=.62, damp=.35):
    wet = [0.0] * N
    for ms in delays:
        d = int(ms * SR / 1000); y = [0.0] * N; lp = 0.0
        for i in range(N):
            fbv = y[i - d] if i >= d else 0.0
            lp = (1 - damp) * fbv + damp * lp
            y[i] = src[i] + fb * lp
            wet[i] += y[i] - src[i]
    return [s + .3 * w for s, w in zip(src, wet)]

Lc = reverb(L, (29.7, 37.1, 41.1, 43.7))
Rc = reverb(R, (30.9, 36.3, 42.7, 45.1))

peak = max(max(map(abs, Lc)), max(map(abs, Rc))) or 1
sc = .75 / peak
fade = int(.35 * SR)
out = bytearray()
for i in range(N):
    m = 1.0
    if i > N - fade:
        x = (N - i) / fade; m = x * x * (3 - 2 * x)
    out += struct.pack('<hh',
        int(max(-1, min(1, Lc[i] * sc * m)) * 32767),
        int(max(-1, min(1, Rc[i] * sc * m)) * 32767))
with wave.open(sys.argv[1], 'wb') as wf:
    wf.setnchannels(2); wf.setsampwidth(2); wf.setframerate(SR)
    wf.writeframes(bytes(out))
PY
  else
    play_cmd=()
  fi
fi
[[ -s $WAV ]] || play_cmd=()

# ── terminal lifecycle ─────────────────────────────────────────────────────
cleanup() {
  [[ -n ${APID:-} ]] && kill "$APID" 2>/dev/null
  printf '\033[?2026l\033[0m\033[?25h\033[?1049l'
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf '\033[?1049h\033[?25l%s\033[2J' "$BG"

# ── geometry ───────────────────────────────────────────────────────────────
BW=38 BH=9
TOP=$(( (rows - 17) / 2 + 1 ))
LEFT=$(( (cols - (BW + 2)) / 2 + 1 ))
LABEL_R=$TOP
BOX_TOP=$(( TOP + 2 ))
METER_R=$(( TOP + 14 ))
CAP_R=$(( TOP + 16 ))
BAND_C=$(( (cols - 50) / 2 + 1 ))

SP=$(printf '%*s' "$BW" '')
BAND=$(printf '%*s' 50 '')
HL='' HLB=''
for ((i=0; i<BW; i++)); do HL+='─'; HLB+='━'; done

# ── motion helpers (integer maths, 0..1000 = 0..1) ─────────────────────────
prog() {   # frame start duration -> P, smoothstep-eased
  local t=$(( ($1 - $2) * 1000 / $3 ))
  (( t < 0 )) && t=0
  (( t > 1000 )) && t=1000
  P=$(( t * t * (3000 - 2 * t) / 1000000 ))
}

fadeio() { # frame total fade-in fade-out -> FD
  local a=$(( $1 * 1000 / $3 )) b=$(( ($2 - 1 - $1) * 1000 / $4 ))
  (( a > 1000 )) && a=1000
  (( b > 1000 )) && b=1000
  (( b < 0 )) && b=0
  (( b < a )) && a=$b
  FD=$(( a * a * (3000 - 2 * a) / 1000000 ))
}

# ── drawing primitives (append to the frame buffer $F) ─────────────────────
put() {    # row text level: centred on the terminal
  local lv=$3
  (( mono && lv < 40 )) && return 0
  gray "$lv"
  F+=$'\033['"$1;$(( (cols - ${#2}) / 2 + 1 ))H${G}$2"
}

dot() {    # y x level glyph: inside the trackpad
  (( mono && $3 < 40 )) && return 0
  tint "$3"
  F+=$'\033['"$(( BOX_TOP + 1 + $1 ));$(( LEFT + 1 + $2 ))H${T}$4"
}

draw_box() {   # uses edge levels eL eT eR eB
  local y c sl sr gl gr
  gray $(( (eL + eT) / 2 )); c=$G
  F+=$'\033['"$BOX_TOP;${LEFT}H${c}╭"
  gray "$eT"; (( eT >= 140 )) && F+="$G$HLB" || F+="$G$HL"
  gray $(( (eR + eT) / 2 )); F+="$G╮"
  for ((y=0; y<BH; y++)); do
    gray "$eL"; sl=$G; gl='│'; (( eL >= 140 )) && gl='┃'
    gray "$eR"; sr=$G; gr='│'; (( eR >= 140 )) && gr='┃'
    F+=$'\033['"$(( BOX_TOP + 1 + y ));${LEFT}H${sl}${gl}${SP}${sr}${gr}"
  done
  gray $(( (eL + eB) / 2 )); c=$G
  F+=$'\033['"$(( BOX_TOP + BH + 1 ));${LEFT}H${c}╰"
  gray "$eB"; (( eB >= 140 )) && F+="$G$HLB" || F+="$G$HL"
  gray $(( (eR + eB) / 2 )); F+="$G╯"
}

meter() {  # filled-cells: a hairline with a champagne knob
  local n=$1 i s
  (( mono && FD < 150 )) && return 0
  gray $(( 235 * FD / 1000 )); s=$G
  for ((i=0; i<n; i++)); do s+='━'; done
  tint $(( 255 * FD / 1000 )); s+="${T}●"
  gray $(( 60 * FD / 1000 )); s+=$G
  for ((i=n+1; i<24; i++)); do s+='─'; done
  F+=$'\033['"$METER_R;$(( (cols - 24) / 2 + 1 ))H$s"
}

pip() {    # col level glyph
  gray "$2"
  F+=$'\033['"$METER_R;$1H${G}$3"
}

swipe_vertical() {   # x f: one finger gliding up, with a fading trail
  local k lv g
  for k in 4 2 0; do
    case $k in 4) lv=70 g='·';; 2) lv=140 g='•';; *) lv=255 g='●';; esac
    prog $(( $2 - k )) 3 17
    dot $(( 7 - 6 * P / 1000 )) "$1" $(( lv * FD / 1000 )) "$g"
  done
}

# ── scenes ─────────────────────────────────────────────────────────────────
scene_intro() {      # 12 frames
  local f=$1 base
  fadeio "$f" 12 8 4
  prog "$f" 0 9; base=$(( EDGE * P / 1000 ))
  eL=$base eT=$base eR=$base eB=$base
  draw_box
  put "$LABEL_R" 'B E Z E L' $(( 150 * FD / 1000 ))
  prog "$f" 4 7
  put "$CAP_R" 'A little movement.' $(( 215 * P / 1000 * FD / 1000 ))
}

scene_volume() {     # 24 frames
  local f=$1 n
  fadeio "$f" 24 5 5
  eL=$(( EDGE + (LIT - EDGE) * FD / 1000 )) eT=$EDGE eR=$EDGE eB=$EDGE
  draw_box
  put "$LABEL_R" 'V O L U M E' $(( 150 * FD / 1000 ))
  swipe_vertical 1 "$f"
  prog "$f" 3 17; n=$(( 5 + 14 * P / 1000 ))
  meter "$n"
  put "$CAP_R" 'A little louder.' $(( 215 * FD / 1000 ))
}

scene_brightness() { # 24 frames
  local f=$1 n
  fadeio "$f" 24 5 5
  eR=$(( EDGE + (LIT - EDGE) * FD / 1000 )) eL=$EDGE eT=$EDGE eB=$EDGE
  draw_box
  put "$LABEL_R" 'B R I G H T N E S S' $(( 150 * FD / 1000 ))
  swipe_vertical $(( BW - 2 )) "$f"
  prog "$f" 3 17; n=$(( 7 + 13 * P / 1000 ))
  meter "$n"
  put "$CAP_R" 'A little brighter.' $(( 215 * FD / 1000 ))
}

scene_spaces() {     # 20 frames
  local f=$1 k lv g off xs c g0 g1
  fadeio "$f" 20 5 5
  eT=$(( EDGE + (LIT - EDGE) * FD / 1000 )) eL=$EDGE eR=$EDGE eB=$EDGE
  draw_box
  put "$LABEL_R" 'W O R K S P A C E S' $(( 150 * FD / 1000 ))
  for k in 3 0; do
    case $k in 3) lv=90 g='·';; *) lv=255 g='●';; esac
    prog $(( f - k )) 3 12; xs=$(( 7 + 12 * P / 1000 ))
    for off in 0 7 14; do
      dot 4 $(( xs + off )) $(( lv * FD / 1000 )) "$g"
    done
  done
  prog "$f" 3 12
  g0='●' g1='○'; (( P >= 500 )) && g0='○' g1='●'
  c=$(( cols / 2 ))
  pip $(( c - 4 )) $(( (255 - 185 * P / 1000) * FD / 1000 )) "$g0"
  pip "$c"         $(( (70 + 185 * P / 1000) * FD / 1000 )) "$g1"
  pip $(( c + 4 )) $(( 70 * FD / 1000 )) '○'
  put "$CAP_R" 'A little more room.' $(( 215 * FD / 1000 ))
}

scene_finale() {     # 40 frames: four edges light in turn, then the wordmark
  local f=$1 lit=$(( LIT - EDGE )) S M
  prog "$f" 0 5;  eL=$(( EDGE + lit * P / 1000 ))
  prog "$f" 4 5;  eT=$(( EDGE + lit * P / 1000 ))
  prog "$f" 8 5;  eR=$(( EDGE + lit * P / 1000 ))
  prog "$f" 12 5; eB=$(( EDGE + lit * P / 1000 ))
  prog "$f" 26 12; S=$(( 110 * P / 1000 ))
  prog "$f" 36 3;  M=$(( 1000 - P ))
  eL=$(( (eL - S) * M / 1000 )) eT=$(( (eT - S) * M / 1000 ))
  eR=$(( (eR - S) * M / 1000 )) eB=$(( (eB - S) * M / 1000 ))
  draw_box
  prog "$f" 14 10
  put $(( BOX_TOP + 5 )) 'B  E  Z  E  L' $(( 255 * P / 1000 * M / 1000 ))
  prog "$f" 20 10
  put "$CAP_R" 'Four edges. Your rules.' $(( 205 * P / 1000 * M / 1000 ))
}

# ── main loop: 120 frames over 5 seconds, paced against the clock ──────────
FRAMES=120

if (( ${#play_cmd[@]} )); then
  "${play_cmd[@]}" "$WAV" >/dev/null 2>&1 &
  APID=$!
fi

# clock starts after audio launch so frames and sound share a timeline
if [[ -n ${EPOCHREALTIME:-} ]]; then t=$EPOCHREALTIME; start=${t/[.,]/}; fi

for ((tick=0; tick<FRAMES; tick++)); do
  F=$'\033[?2026h'"$BG"          # synchronized output: one clean paint per frame
  for r in "$LABEL_R" "$METER_R" "$CAP_R"; do F+=$'\033['"$r;${BAND_C}H$BAND"; done

  if   (( tick < 12 )); then scene_intro      "$tick"
  elif (( tick < 36 )); then scene_volume     $(( tick - 12 ))
  elif (( tick < 60 )); then scene_brightness $(( tick - 36 ))
  elif (( tick < 80 )); then scene_spaces     $(( tick - 60 ))
  else                       scene_finale     $(( tick - 80 ))
  fi

  F+=$'\033[?2026l'
  printf '%s' "$F"

  if [[ -n ${EPOCHREALTIME:-} ]]; then
    t=$EPOCHREALTIME; now=${t/[.,]/}
    rem=$(( start + (tick + 1) * 5000000 / FRAMES - now ))
    if (( rem > 0 )); then
      printf -v d '%d.%06d' $(( rem / 1000000 )) $(( rem % 1000000 ))
      sleep "$d"
    fi
  else
    sleep 0.04
  fi
done
