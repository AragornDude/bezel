#!/usr/bin/env bash
# A short terminal film. Run: bash demo.sh [--mute]
# Export its soundtrack: bash demo.sh --soundtrack /tmp/bezel.wav
set -u

soundtrack='' mute=${BEZEL_MUTE:-}
while (( $# )); do
  case "$1" in
    --mute) mute=1; shift ;;
    --soundtrack)
      [[ $# -ge 2 ]] || { printf 'Specify a WAV output path.\n' >&2; exit 2; }
      soundtrack=$2; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z $soundtrack ]]; then
  if [[ ! -t 1 || ${TERM:-dumb} == dumb ]]; then
    printf 'BEZEL: Four edges. Your rules.\nRun in an interactive terminal to watch the film.\n'
    exit 0
  fi
  rows=24 cols=80
  read -r r c < <(stty size </dev/tty 2>/dev/null || stty size 2>/dev/null) && rows=$r cols=$c
  if (( rows < 21 || cols < 60 )); then
    printf 'Please use a terminal at least 60 columns x 21 rows.\n'
    exit 0
  fi
fi

# ── palette ────────────────────────────────────────────────────────────────
ACC_R=226 ACC_G=182 ACC_B=140        # champagne accent (fingers only)
EDGE=76                               # resting outline (graphite)
LIT=218                               # lit edge (near-white)

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
WAV=${soundtrack:-${XDG_CACHE_HOME:-$HOME/.cache}/bezel-film-v6.wav}
play_cmd=()
if [[ -z $mute && -z $soundtrack ]]; then
  if   command -v afplay >/dev/null 2>&1; then play_cmd=(afplay)
  elif command -v paplay >/dev/null 2>&1; then play_cmd=(paplay)
  elif command -v aplay  >/dev/null 2>&1; then play_cmd=(aplay -q)
  elif command -v ffplay >/dev/null 2>&1; then play_cmd=(ffplay -nodisp -autoexit -loglevel quiet)
  fi
fi

if { (( ${#play_cmd[@]} )) || [[ -n $soundtrack ]]; } && [[ ! -s $WAV ]]; then
  if command -v python3 >/dev/null 2>&1; then
    mkdir -p "${WAV%/*}"
    python3 - "$WAV" <<'PY' || { rm -f "$WAV"; play_cmd=(); }
import math, random, struct, sys, wave
SR = 44100; DUR = 7.5; N = int(SR * DUR); TAU = 2 * math.pi
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

fr = lambda n: n / 30.0
P1 = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]    # C5 D5 E5 G5 A5 C6
P2 = [659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5]   # E5 G5 A5 C6 D6 E6

# intro
thud(.10, .20)
pluck(.30, 392.0, .06, .8, .25)

# volume (left edge): soft touch, airy sweep, rising pentatonic steps
thud(fr(22), .10, pan=-.4)
whoosh(fr(24), 1.0, .05, 500, 2200, -.4)
for k, f in enumerate(P1):
    pluck(fr(25 + k * 5), f, .055 + .008 * k, .5, .35, -.4)

# brightness (same edge, two fingers): brighter timbre, higher register
thud(fr(70), .10, pan=-.25)
whoosh(fr(72), 1.0, .05, 700, 3000, -.25)
for k, f in enumerate(P2):
    pluck(fr(73 + k * 5), f, .045 + .007 * k, .45, .55, -.25)

# workspaces: three-finger swipe, tick on page change
thud(fr(118), .08)
whoosh(fr(120), .8, .06, 400, 2500)
tick(fr(136), .12)
pluck(fr(136), 783.99, .05, .35, .3)

# finale: four edges light (L, T, R, B), then wordmark
for t, f, p in ((158, 523.25, -.5), (164, 659.25, 0), (170, 783.99, .5), (176, 1046.5, 0)):
    pluck(fr(t), f, .08, .9, .4, p)
thud(fr(181), .26, 80, 50, .95, 5)
for f, a in ((261.63, .06), (392.0, .05), (659.25, .04)):
    pluck(fr(181), f, a, 1.0, .3)
pluck(fr(191), 1046.5, .035, .7, .5)

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
if [[ -n $soundtrack ]]; then
  [[ -s $WAV ]] || { printf 'Soundtrack needs Python 3.\n' >&2; exit 1; }
  printf '%s\n' "$WAV"
  exit 0
fi

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
BW=44 BH=10
TOP=$(( (rows - 19) / 2 + 1 ))
LEFT=$(( (cols - (BW + 2)) / 2 + 1 ))
LABEL_R=$TOP
BOX_TOP=$(( TOP + 2 ))
METER_R=$(( TOP + 15 ))
CAP_R=$(( TOP + 18 ))
BAND_C=$(( (cols - 50) / 2 + 1 ))

SP=$(printf '%*s' "$BW" '')
BAND=$(printf '%*s' 50 '')
HL=''
for ((i=0; i<BW; i++)); do HL+='─'; done

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
  gray "$eT"; F+="$G$HL"
  gray $(( (eR + eT) / 2 )); F+="$G╮"
  for ((y=0; y<BH; y++)); do
    gray "$eL"; sl=$G; gl='│'
    gray "$eR"; sr=$G; gr='│'
    F+=$'\033['"$(( BOX_TOP + 1 + y ));${LEFT}H${sl}${gl}${SP}${sr}${gr}"
  done
  gray $(( (eL + eB) / 2 )); c=$G
  F+=$'\033['"$(( BOX_TOP + BH + 1 ));${LEFT}H${c}╰"
  gray "$eB"; F+="$G$HL"
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

contact() { # fractional row (thousandths), x, brightness
  local y=$(( $1 / 1000 )) part=$(( $1 % 1000 ))
  dot "$y" "$2" $(( $3 * (1000 - part) / 1000 )) '●'
  if (( part )); then dot $(( y + 1 )) "$2" $(( $3 * part / 1000 )) '●'; fi
}

swipe_vertical() { # x, frame: restrained trail and sub-row crossfade
  local k y
  for k in 5 0; do
    prog $(( $2 - k )) 8 27
    y=$(( 8000 - 6500 * P / 1000 ))
    if (( k )); then dot $(( y / 1000 )) "$1" $(( 90 * FD / 1000 )) '·'
    else contact "$y" "$1" $(( 255 * FD / 1000 )); fi
  done
}

scene_intro() {
  local f=$1 base
  fadeio "$f" 18 10 5
  prog "$f" 0 12; base=$(( EDGE * P / 1000 ))
  eL=$base eT=$base eR=$base eB=$base
  draw_box
  put "$LABEL_R" 'B E Z E L' $(( 220 * FD / 1000 ))
  put "$CAP_R" 'A little movement.' $(( 160 * FD / 1000 ))
}

scene_volume() {
  local f=$1 n
  fadeio "$f" 48 7 7
  eL=$(( EDGE + (LIT - EDGE) * FD / 1000 )) eT=$EDGE eR=$EDGE eB=$EDGE
  draw_box
  put "$LABEL_R" 'V O L U M E' $(( 220 * FD / 1000 ))
  swipe_vertical 1 "$f"
  prog "$f" 8 27; n=$(( 5 + 14 * P / 1000 ))
  meter "$n"
  put "$CAP_R" 'One finger.' $(( 178 * FD / 1000 ))
}

scene_brightness() {
  local f=$1 n
  fadeio "$f" 48 7 7
  eL=$(( EDGE + (LIT - EDGE) * FD / 1000 )) eT=$EDGE eR=$EDGE eB=$EDGE
  draw_box
  put "$LABEL_R" 'B R I G H T N E S S' $(( 220 * FD / 1000 ))
  swipe_vertical 1 "$f"
  swipe_vertical 6 "$f"
  prog "$f" 8 27; n=$(( 7 + 13 * P / 1000 ))
  meter "$n"
  put "$CAP_R" 'Same edge. Two fingers.' $(( 178 * FD / 1000 ))
}

scene_spaces() {
  local f=$1 k lv off xs c g0 g1
  fadeio "$f" 42 7 7
  eT=$(( EDGE + (LIT - EDGE) * FD / 1000 )) eL=$EDGE eR=$EDGE eB=$EDGE
  draw_box
  put "$LABEL_R" 'W O R K S P A C E S' $(( 220 * FD / 1000 ))
  for k in 5 0; do
    lv=54; (( k == 0 )) && lv=255
    prog $(( f - k )) 8 24; xs=$(( 7 + 15 * P / 1000 ))
    for off in 0 7 14; do dot 0 $(( xs + off )) $(( lv * FD / 1000 )) '●'; done
  done
  prog "$f" 8 24
  g0='●' g1='○'; (( P >= 500 )) && g0='○' g1='●'
  c=$(( cols / 2 ))
  pip $(( c - 4 )) $(( (255 - 185 * P / 1000) * FD / 1000 )) "$g0"
  pip "$c"         $(( (70 + 185 * P / 1000) * FD / 1000 )) "$g1"
  pip $(( c + 4 )) $(( 70 * FD / 1000 )) '○'
  put "$CAP_R" 'Three fingers. More room.' $(( 178 * FD / 1000 ))
}

scene_finale() {
  local f=$1 lit=$(( LIT - EDGE )) S M
  prog "$f" 0 8;  eL=$(( EDGE + lit * P / 1000 ))
  prog "$f" 6 8;  eT=$(( EDGE + lit * P / 1000 ))
  prog "$f" 12 8; eR=$(( EDGE + lit * P / 1000 ))
  prog "$f" 18 8; eB=$(( EDGE + lit * P / 1000 ))
  prog "$f" 34 16; S=$(( 80 * P / 1000 ))
  prog "$f" 61 7; M=$(( 1000 - P ))
  eL=$(( (eL - S) * M / 1000 )) eT=$(( (eT - S) * M / 1000 ))
  eR=$(( (eR - S) * M / 1000 )) eB=$(( (eB - S) * M / 1000 ))
  draw_box
  prog "$f" 25 14
  put $(( BOX_TOP + 5 )) 'B  E  Z  E  L' $(( 255 * P * M / 1000000 ))
  prog "$f" 33 12
  put "$CAP_R" 'Four edges. Your rules.' $(( 205 * P * M / 1000000 ))
}

# ── main loop: 225 frames over 7.5 seconds ────────────────────────────────
FRAMES=225

if (( ${#play_cmd[@]} )); then
  "${play_cmd[@]}" "$WAV" >/dev/null 2>&1 &
  APID=$!
fi

# clock starts after audio launch so frames and sound share a timeline
if [[ -n ${EPOCHREALTIME:-} ]]; then t=$EPOCHREALTIME; start=${t/[.,]/}; fi

for ((tick=0; tick<FRAMES; tick++)); do
  F=$'\033[?2026h'"$BG"          # synchronized output: one clean paint per frame
  for r in "$LABEL_R" "$METER_R" "$CAP_R"; do F+=$'\033['"$r;${BAND_C}H$BAND"; done

  if   (( tick < 18 )); then scene_intro      "$tick"
  elif (( tick < 66 )); then scene_volume     $(( tick - 18 ))
  elif (( tick < 114 )); then scene_brightness $(( tick - 66 ))
  elif (( tick < 156 )); then scene_spaces     $(( tick - 114 ))
  else                       scene_finale     $(( tick - 156 ))
  fi

  F+=$'\033[?2026l'
  printf '%s' "$F"

  if [[ -n ${EPOCHREALTIME:-} ]]; then
    t=$EPOCHREALTIME; now=${t/[.,]/}
    rem=$(( start + (tick + 1) * 7500000 / FRAMES - now ))
    if (( rem > 0 )); then
      printf -v d '%d.%06d' $(( rem / 1000000 )) $(( rem % 1000000 ))
      sleep "$d"
    fi
  else
    sleep 0.033333
  fi
done
