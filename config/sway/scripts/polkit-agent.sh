#!/bin/sh
# Launch the polkit-gnome authentication agent from wherever this distro
# installs it — the path is the only thing that differs.
#   Arch/CachyOS:  /usr/lib/polkit-gnome/...          (polkit-gnome)
#   Ubuntu/Debian: /usr/lib/policykit-1-gnome/...     (policykit-1-gnome)
#   Fedora et al.: /usr/libexec/...
for p in /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
         /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
         /usr/libexec/polkit-gnome-authentication-agent-1; do
    [ -x "$p" ] && exec "$p"
done
echo "polkit-agent.sh: no polkit-gnome agent found" >&2
exit 1
