#!/usr/bin/env bash
#
# tg-seek.sh — Seek Telegram Desktop music playback via MPRIS2/DBus
#
# Usage:
#   tg-seek.sh forward [seconds]   # default 5s
#   tg-seek.sh backward [seconds]  # default 5s
#   tg-seek.sh to <seconds>        # absolute position
#   tg-seek.sh status              # show current track info
#
# MPRIS2 positions are in microseconds (µs).

DEST="org.mpris.MediaPlayer2.TelegramDesktop"
PATH_OBJ="/org/mpris/MediaPlayer2"
IFACE="org.mpris.MediaPlayer2.Player"
PROPS="org.freedesktop.DBus.Properties"

get_prop() {
    gdbus call --session \
        --dest "$DEST" \
        --object-path "$PATH_OBJ" \
        --method "$PROPS.Get" \
        "$IFACE" "$1" 2>/dev/null
}

get_all() {
    gdbus call --session \
        --dest "$DEST" \
        --object-path "$PATH_OBJ" \
        --method "$PROPS.GetAll" \
        "$IFACE" 2>/dev/null
}

seek_relative() {
    local offset_us="$1"
    gdbus call --session \
        --dest "$DEST" \
        --object-path "$PATH_OBJ" \
        --method "$IFACE.Seek" \
        -- "$offset_us" >/dev/null 2>&1
}

set_position() {
    local track_id="$1"
    local position_us="$2"
    gdbus call --session \
        --dest "$DEST" \
        --object-path "$PATH_OBJ" \
        --method "$IFACE.SetPosition" \
        "$track_id" "$position_us" >/dev/null 2>&1
}

extract_int64() {
    echo "$1" | grep -oP '(?:int64 )\K[-0-9]+'
}

# Telegram sometimes reports mpris:length=0 via MPRIS because it sets
# the duration once on track start before streaming headers are parsed,
# and never updates it. Retry a few times to let it catch up.
MAX_LENGTH_RETRIES=10
LENGTH_RETRY_DELAY=0.3

get_length_us() {
    local all="$1"
    echo "$all" | grep -oP "'mpris:length': <int64 \K[0-9]+" || echo "0"
}

wait_for_length() {
    local len_us i all
    all=$(get_all)
    len_us=$(get_length_us "$all")

    if [ "${len_us:-0}" -gt 0 ] 2>/dev/null; then
        echo "$len_us"
        return 0
    fi

    for (( i=0; i<MAX_LENGTH_RETRIES; i++ )); do
        sleep "$LENGTH_RETRY_DELAY"
        all=$(get_all)
        len_us=$(get_length_us "$all")
        if [ "${len_us:-0}" -gt 0 ] 2>/dev/null; then
            echo "$len_us"
            return 0
        fi
    done

    echo "0"
    return 1
}

extract_string() {
    local key="$1" data="$2"
    echo "$data" | grep -oP "'$key': <'[^']*'>" | grep -oP "(?<=<')[^']*"
}

extract_array_string() {
    local key="$1" data="$2"
    echo "$data" | grep -oP "'$key': <\[.*?\]>" | grep -oP "(?<=\[')[^']*"
}

format_time() {
    local total_s="$1"
    local m=$((total_s / 60))
    local s=$((total_s % 60))
    printf "%d:%02d" "$m" "$s"
}

check_running() {
    if ! gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ListNames 2>/dev/null | grep -q "$DEST"; then
        echo "Error: Telegram Desktop MPRIS2 not found on DBus."
        echo "Make sure Telegram is running and playing music."
        exit 1
    fi
}

cmd_status() {
    local all
    all=$(get_all)

    local pos_raw
    pos_raw=$(get_prop Position)
    local pos_us
    pos_us=$(extract_int64 "$pos_raw")
    local pos_s=$(( (pos_us + 500000) / 1000000 ))

    local len_us
    len_us=$(get_length_us "$all")
    if [ "${len_us:-0}" -eq 0 ] 2>/dev/null; then
        len_us=$(wait_for_length)
    fi
    local len_s=$(( (len_us + 500000) / 1000000 ))

    local title
    title=$(extract_string "xesam:title" "$all")
    local artist
    artist=$(extract_array_string "xesam:artist" "$all")
    local status
    status=$(extract_string "PlaybackStatus" "$all")
    local can_seek
    can_seek=$(echo "$all" | grep -oP "'CanSeek': <\K[a-z]+")

    echo "Track:    ${artist:-(unknown)} — ${title:-(unknown)}"
    echo "Status:   $status"
    echo "Position: $(format_time $pos_s) / $(format_time $len_s)"
    echo "CanSeek:  $can_seek"
}

cmd_forward() {
    local secs="${1:-5}"
    local offset_us=$((secs * 1000000))
    seek_relative "$offset_us"
    echo "Seeked forward ${secs}s"
}

cmd_backward() {
    local secs="${1:-5}"
    local offset_us=$((-secs * 1000000))
    seek_relative "$offset_us"
    echo "Seeked backward ${secs}s"
}

cmd_to() {
    local target_s="$1"
    if [ -z "$target_s" ]; then
        echo "Usage: tg-seek.sh to <seconds>"
        exit 1
    fi
    local target_us=$((target_s * 1000000))

    local all
    all=$(get_all)
    local track_id
    track_id=$(echo "$all" | grep -oP "'mpris:trackid': <objectpath '\K[^']+")

    if [ -z "$track_id" ]; then
        echo "Error: cannot determine track ID"
        exit 1
    fi

    local len_us
    len_us=$(get_length_us "$all")
    if [ "${len_us:-0}" -eq 0 ] 2>/dev/null; then
        len_us=$(wait_for_length)
    fi

    if [ "${len_us:-0}" -eq 0 ] 2>/dev/null; then
        # Duration still unknown — fall back to relative seek from current position
        local pos_raw pos_us offset_us
        pos_raw=$(get_prop Position)
        pos_us=$(extract_int64 "$pos_raw")
        offset_us=$((target_us - pos_us))
        seek_relative "$offset_us"
        echo "Seeked to ~$(format_time $target_s) (relative fallback, duration unknown)"
    else
        set_position "$track_id" "$target_us"
        echo "Seeked to $(format_time $target_s)"
    fi
}

check_running

case "${1:-status}" in
    forward|fwd|f|+)
        cmd_forward "$2"
        ;;
    backward|bwd|b|-)
        cmd_backward "$2"
        ;;
    to|abs|goto)
        cmd_to "$2"
        ;;
    status|info|s)
        cmd_status
        ;;
    *)
        echo "Usage: tg-seek.sh {forward|backward|to|status} [seconds]"
        echo ""
        echo "Commands:"
        echo "  forward  [N]    Seek forward N seconds (default 5)"
        echo "  backward [N]    Seek backward N seconds (default 5)"
        echo "  to <N>          Seek to absolute position N seconds"
        echo "  status          Show current track info"
        echo ""
        echo "Aliases: fwd/f/+, bwd/b/-, abs/goto, info/s"
        exit 1
        ;;
esac
