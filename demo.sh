#!/usr/bin/env bash
# A five-second, illustrated Bezel teaser. Run: bash demo.sh
set -euo pipefail

if [[ ! -t 1 || ${TERM:-dumb} == dumb ]]; then
    printf 'BEZEL — Four edges. Your rules.\nRun in an interactive terminal to watch the demo.\n'
    exit 0
fi

amber=$'\033[38;2;199;139;95m'
cream=$'\033[38;2;220;211;199m'
dim=$'\033[38;2;100;88;77m'
reset=$'\033[0m'
if [[ -n ${NO_COLOR:-} ]]; then amber='' cream='' dim='' reset=''; fi

cleanup() { printf '\033[0m\033[?25h\033[?1049l'; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf '\033[?1049h\033[?25l\033[2J'

rows=24 cols=80
if command -v stty >/dev/null 2>&1; then
    read -r rows cols < <(stty size </dev/tty 2>/dev/null) || { rows=24; cols=80; }
fi
if ((rows < 18 || cols < 50)); then
    cleanup
    trap - EXIT
    printf 'Use a terminal at least 50 columns × 18 rows.\n'
    exit 0
fi
row=$(( (rows-16)/2+1 ))
col=$(( (cols-46)/2+1 ))

# Each frame is composed before a single write, keeping the picture steady.
line() {
    local text="$2" style="${3:-$cream}" padding
    padding=$(( (46-${#text})/2 )); ((padding>=0)) || padding=0
    printf -v segment '\033[%d;%dH%46s\033[%d;%dH%s%s%s' \
        "$((row+$1))" "$col" '' "$((row+$1))" "$((col+padding))" "$style" "$text" "$reset"
    frame+="$segment"
}

# Seventy-five frames, timed against elapsed time rather than accumulated sleeps.
start=${EPOCHREALTIME/./}
for ((tick=0; tick<75; tick++)); do
    frame='' segment=''
    title='' caption='' meter='' edge='' fingers=1 progress=0
    if ((tick<12)); then
        title='B E Z E L'
        caption='A little movement.'
    elif ((tick<30)); then
        title='VOLUME'
        caption='A little louder.'
        edge=left; progress=$((tick-12))
        for ((i=0;i<16;i++)); do
            if ((i<4+progress/2)); then meter+='━'; else meter+='─'; fi
        done
    elif ((tick<47)); then
        title='BRIGHTNESS'
        caption='A little brighter.'
        edge=right; progress=$((tick-30))
        for ((i=0;i<16;i++)); do
            if ((i<3+progress/2)); then meter+='━'; else meter+='─'; fi
        done
    elif ((tick<62)); then
        title='WORKSPACES'
        caption='A little more room.'
        edge=top; fingers=3; progress=$((tick-47))
        if ((progress<7)); then meter='[ 01 ]    02     03'; else meter='  01    [ 02 ]   03'; fi
    else
        title='B E Z E L'
        caption='Four edges. Your rules.'
    fi

    line 0 "$title" "$amber"
    line 1 ''
    top='╭────────────────────────────╮'
    [[ $edge != top ]] || top='╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮'
    line 2 "$top" "$dim"
    for ((y=0;y<7;y++)); do
        left='│'; right='│'; body=''
        [[ $edge != left ]] || left='┃'
        [[ $edge != right ]] || right='┃'
        for ((x=0;x<28;x++)); do
            cell=' '
            if [[ $edge == left || $edge == right ]]; then
                target_x=2; [[ $edge != right ]] || target_x=25
                target_y=$((5-progress/4)); ((target_y>=1)) || target_y=1
                if ((x==target_x && y==target_y)); then cell='●'
                elif ((x==target_x && y==target_y+1)); then cell='·'; fi
            elif [[ $edge == top ]]; then
                for ((finger=0;finger<fingers;finger++)); do
                    if ((y==1 && x==3+finger*6+progress/2)); then cell='●'; fi
                done
            fi
            body+="$cell"
        done
        line "$((y+3))" "$left$body$right" "${edge:+$amber}"
    done
    line 10 '╰────────────────────────────╯' "$dim"
    line 11 ''
    line 12 "$meter" "$amber"
    line 13 ''
    line 14 "$caption"
    line 15 ''
    printf '%s' "$frame"

    now=${EPOCHREALTIME/./}
    remaining=$((start+(tick+1)*5000000/75-now))
    if ((remaining>0)); then
        printf -v delay '%d.%06d' "$((remaining/1000000))" "$((remaining%1000000))"
        sleep "$delay"
    fi
done
