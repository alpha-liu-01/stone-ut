#!/bin/sh
# UBports' unified recovery ramdisk that boot/ut-init/build-boot-image.sh
# merges into the boot image (docs/roadmap-release.md item 1). Kept for old
# instructions; tools/fetch-inputs.sh pins and fetches it with the other inputs.
exec sh "$(dirname "$0")/fetch-inputs.sh" recovery
