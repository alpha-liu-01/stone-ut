#!/bin/sh
# Turn call-audio.sh on while ofono has a call that needs the voice path,
# and off when it is gone. Polls org.ofono VoiceCallManager.GetCalls on the
# system bus (phablet is allowed by ofono-phablet.conf).
#
# Route: earpiece by default; write "speaker" to
# ~/.config/stone/call-route to use the loudspeaker instead.
CTL=${STONE_CALL_AUDIO:-/usr/lib/stone/call-audio.sh}
ROUTE_FILE=${HOME}/.config/stone/call-route
current=off

route() { r=$(cat "$ROUTE_FILE" 2>/dev/null); [ "$r" = speaker ] && echo speaker || echo earpiece; }

calls() {
    for m in /ril_0 /ril_1; do
        dbus-send --system --print-reply --reply-timeout=2000 --dest=org.ofono \
            "$m" org.ofono.VoiceCallManager.GetCalls 2>/dev/null
    done | grep -A1 '"State"' | grep -oE '"(dialing|alerting|active|held|incoming|waiting|disconnected)"' | tr -d '"'
}

trap '"$CTL" off; exit 0' INT TERM

while :; do
    st=$(calls)
    want=off
    # The voice path is needed for ringback (alerting) and the call itself.
    # An incoming call that has not been answered yet does not need it.
    echo "$st" | grep -qE '^(dialing|alerting|active|held)$' && want=$(route)
    if [ "$want" != "$current" ]; then
        if [ "$want" = off ]; then
            "$CTL" off
        else
            "$CTL" on "$want"
        fi
        echo "call audio: $current -> $want ($(echo $st))"
        current=$want
        recorded=
    fi
    # Debug (STONE_CALL_REC_UL=1): once per call, record 8 s of the uplink
    # after the call is answered, to tell "mic never reaches the DSP" from
    # "the DSP sends it but the far end hears nothing".
    if [ -n "${STONE_CALL_REC_UL:-}" ] && [ "$current" != off ] && [ -z "$recorded" ] &&
            echo "$st" | grep -qx active; then
        recorded=1
        "$CTL" rec-ul 8 "${XDG_RUNTIME_DIR:-/tmp}/stone-uplink-$(date +%s).raw" &
    fi
    sleep 0.5
done
