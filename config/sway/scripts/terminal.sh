#!/usr/bin/env bash
# Launch the terminal, working around a GPU driver bug on Qualcomm machines.
#
# On Adreno GPUs (the `msm` kernel driver, Snapdragon laptops) kitty's cursor
# is drawn incorrectly: it visibly jumps back and forth by a character while
# typing. The typed text is never wrong, only the cursor, which is what makes
# it look like a terminal bug rather than a driver one.
#
# Isolated on specter (ThinkBook 16 G7 QOY, Fedora 44) by elimination:
#   - synced all monitors to the same refresh rate -> still glitched
#   - reproduced outside tmux, and on every monitor -> not tmux, not one screen
#   - foot was clean, but foot is software-rendered AND uses a block cursor and
#     a different font, so that alone did not isolate it
#   - LIBGL_ALWAYS_SOFTWARE=1 kitty -> clean. It is the GL path.
#
# So force software GL for the TERMINAL ONLY. Doing this session-wide (via
# environment.d or a profile) would push sway, Chrome and video decode onto
# llvmpipe too -- a real performance and battery regression, and it would waste
# the GPU firmware this machine needs extracted from Windows to work at all.
# A terminal pushes almost no pixels, so software GL costs nothing here.
#
# Everything non-Qualcomm is left completely untouched.

if [[ -d /sys/module/msm ]]; then
  export LIBGL_ALWAYS_SOFTWARE=1
fi

exec kitty "$@"
