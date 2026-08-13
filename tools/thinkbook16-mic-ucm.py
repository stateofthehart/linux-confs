#!/usr/bin/env python3
"""Generate a ThinkBook 16 G7 QOY UCM profile from the T14s one.

The ThinkBook currently resolves to LENOVO-T14s.conf, because x1e80100.conf's
regex lists both machines. That is right for everything except the internal
microphones: the T14s profile wires the two capture decimators to DMIC0 and
DMIC1, and on this board those inputs are silent.

Measured on the hardware (see PORTING.md): the internal mic array sits on the
`dmic2` pin bank (gpio8/gpio9), reachable as DMIC2/DMIC3, and only DEC1 ever
returns samples. DEC0 must still select a DMIC from the *other* bank (DMIC0 or
DMIC1) or the dmic2 bank produces nothing at all -- so DMIC0EnableSeq is kept
even though DEC0 itself stays silent. The result is a working mono microphone
on the right channel.

Only SectionDevice."Mic" is changed; every other device is copied verbatim, so
speakers, headphones, headset and HDMI keep the T14s behaviour that already
works.
"""
import os
import re
import sys

UCM = "/usr/share/alsa/ucm2"
SRC_HIFI = f"{UCM}/Qualcomm/x1e80100/T14s-HiFi.conf"
SRC_CARD = f"{UCM}/Qualcomm/x1e80100/LENOVO-T14s.conf"
DST_HIFI = f"{UCM}/Qualcomm/x1e80100/ThinkBook16-HiFi.conf"
DST_CARD = f"{UCM}/Qualcomm/x1e80100/LENOVO-ThinkBook-16.conf"
CARD_LONGNAME = "LENOVO-21NH-ThinkBook16G7QOY-LNVNB161216"
LINK = f"{UCM}/conf.d/x1e80100/{CARD_LONGNAME}.conf"

NEW_MIC = '''SectionDevice."Mic" {
\tComment "Internal microphones"

\t# Board-specific: the mic array is on the dmic2 pin bank (gpio8/gpio9), not
\t# dmic01 as on the T14s. Measured: DEC1 returns audio from DMIC2 or DMIC3;
\t# DEC0 returns digital silence from every input. DEC0 must nevertheless be
\t# left selecting a dmic01-bank input, or the dmic2 bank stays unclocked and
\t# both channels go silent. Hence: DEC0 -> DMIC0 (clock only), DEC1 -> DMIC3.
\tInclude.vadm0e.File "/codecs/qcom-lpass/va-macro/DMIC0EnableSeq.conf"
\tInclude.vadm0d.File "/codecs/qcom-lpass/va-macro/DMIC0DisableSeq.conf"

\tEnableSequence [
\t\tcset "name='VA DEC1 MUX' VA_DMIC"
\t\tcset "name='VA DMIC MUX1' DMIC3"
\t\tcset "name='VA_AIF1_CAP Mixer DEC1' 1"
\t\tcset "name='VA_DEC1 Volume' 100"
\t]

\tDisableSequence [
\t\tcset "name='VA_AIF1_CAP Mixer DEC1' 0"
\t\tcset "name='VA DMIC MUX1' ZERO"
\t]

\tValue {
\t\tCapturePriority 100
\t\tCapturePCM "hw:${CardId},3"
\t}
}'''



def is_thinkbook():
    """Refuse to touch UCM on anything but the board this was measured on."""
    try:
        with open("/proc/device-tree/model", "rb") as fh:
            return b"ThinkBook 16 Gen 7 QOY" in fh.read()
    except OSError:
        return False


def main():
    if not is_thinkbook():
        print("not a ThinkBook 16 G7 QOY — nothing to do")
        return
    if not os.path.exists(SRC_HIFI):
        sys.exit("donor profile missing: " + SRC_HIFI)

    hifi = open(SRC_HIFI, encoding="utf-8").read()

    # Replace the whole SectionDevice."Mic" block. It ends at the first
    # closing brace in column 0 after the header.
    m = re.search(r'SectionDevice\."Mic"\s*\{.*?^\}', hifi, re.S | re.M)
    if not m:
        sys.exit("could not locate SectionDevice.\"Mic\" in " + SRC_HIFI)
    hifi = hifi[:m.start()] + NEW_MIC + hifi[m.end():]

    header = ("# Derived from T14s-HiFi.conf by linux-confs install.sh.\n"
              "# Only SectionDevice.\"Mic\" differs -- see the comment there.\n")
    open(DST_HIFI, "w", encoding="utf-8").write(header + hifi)
    print("wrote", DST_HIFI)

    card = open(SRC_CARD, encoding="utf-8").read()
    card = card.replace("/Qualcomm/x1e80100/T14s-HiFi.conf",
                        "/Qualcomm/x1e80100/ThinkBook16-HiFi.conf")
    open(DST_CARD, "w", encoding="utf-8").write(card)
    print("wrote", DST_CARD)

    # An exact card-longname file in conf.d/<driver>/ wins over the generic
    # x1e80100.conf regex dispatch.
    if os.path.islink(LINK) or os.path.exists(LINK):
        os.remove(LINK)
    os.symlink("../../Qualcomm/x1e80100/LENOVO-ThinkBook-16.conf", LINK)
    print("linked", LINK)


if __name__ == "__main__":
    main()
