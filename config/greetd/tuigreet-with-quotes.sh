#!/bin/bash
# Random quote selector for tuigreet
# Rotates through famous quotes on each login

QUOTES_FILE="/etc/greetd/quotes.txt"

# Pick a random quote
if [ -f "$QUOTES_FILE" ]; then
    QUOTE=$(shuf -n 1 "$QUOTES_FILE")
else
    QUOTE="Welcome to Sway"
fi

# Run tuigreet with the random quote
exec tuigreet \
    --cmd sway \
    --greeting "$QUOTE" \
    --time \
    --asterisks \
    --theme 'border=magenta;text=white;prompt=green;time=blue;action=cyan;button=yellow;container=black'
