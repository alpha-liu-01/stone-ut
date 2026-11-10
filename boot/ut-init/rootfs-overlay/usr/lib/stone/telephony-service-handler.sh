#!/bin/sh
# Start lomiri-telephony-service-handler with the UCM port names
# (tools/patch-telephony-ports.py). The patched copy has to live in /usr/bin:
# the handler only treats itself as installed (and reads
# /usr/share/lomiri-telephony-service/protocols) when it runs from there;
# from anywhere else it waits on D-Bus for its own name, twice 25 s, and
# never handles a call.
# Only use it while the stock binary is the build it was made from; after an
# update run the stock handler (calls work, the dialer just gets no
# earpiece/speaker/Bluetooth choice until the patch is redone).
STOCK=/usr/bin/lomiri-telephony-service-handler
PATCHED=/usr/bin/lomiri-telephony-service-handler-stone
STOCK_SHA256=f369e392762191d0469e2ecc512a2c03d016e2bca7374cb18ca03295c072d639
if [ -x "$PATCHED" ] && [ "$(sha256sum < "$STOCK" | cut -c1-64)" = "$STOCK_SHA256" ]; then
    exec "$PATCHED" "$@"
fi
echo "telephony-service-handler: stock binary changed, running it unpatched" >&2
exec "$STOCK" "$@"
