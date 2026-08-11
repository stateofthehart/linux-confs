#!/bin/sh
# Launch a polkit authentication agent from wherever this distro installs it.
#   Arch/CachyOS:  /usr/lib/polkit-gnome/...          (polkit-gnome)
#   Ubuntu/Debian: /usr/lib/policykit-1-gnome/...     (policykit-1-gnome)
#   Fedora:        polkit-gnome DOES NOT EXIST. Fedora 44 ships mate-polkit,
#                  lxqt-policykit, xfce-polkit and polkit-kde instead; we
#                  prefer mate-polkit (GTK, no extra desktop deps).
# Any of these satisfies sway's need for an agent — the protocol is the same,
# only the dialog theming differs. First one found wins.
for p in /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
         /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
         /usr/libexec/polkit-gnome-authentication-agent-1 \
         /usr/libexec/polkit-mate-authentication-agent-1 \
         /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
         /usr/bin/lxqt-policykit-agent \
         /usr/libexec/xfce-polkit \
         /usr/lib/polkit-kde-authentication-agent-1; do
    [ -x "$p" ] && exec "$p"
done
echo "polkit-agent.sh: no polkit authentication agent found" >&2
exit 1
