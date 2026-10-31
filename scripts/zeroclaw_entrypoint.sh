#!/bin/sh
# zeroclaw_entrypoint.sh - container entrypoint for the ZeroClaw agents
#
# Optionally themes the dashboard, then hands over to zeroclaw. Since ZeroClaw
# v0.8.5 the dashboard's model picker is filled from the server's model catalog
# (/api/config/catalog/models), so the bundle no longer needs patching for that.
set -eu

DIST=/zeroclaw-data/web/dist
INDEX="$DIST/index.html"

# ZEROCLAW_UI_THEME_CSS: path to a stylesheet injected into the dashboard's
# index.html (the admin agent uses configs/admin-theme.css so the privileged
# tier is visually distinct). Injection is idempotent and independent of the
# bundle's hashed asset names.
if [ -n "${ZEROCLAW_UI_THEME_CSS:-}" ]; then
    if [ ! -r "$ZEROCLAW_UI_THEME_CSS" ]; then
        echo "zeroclaw_entrypoint: theme file $ZEROCLAW_UI_THEME_CSS is not readable" >&2
        exit 1
    fi
    if ! grep -q 'id="lab-theme"' "$INDEX"; then
        tmp="$INDEX.tmp"
        awk -v css="$ZEROCLAW_UI_THEME_CSS" '
            /<\/head>/ && !done {
                print "<style id=\"lab-theme\">"
                while ((getline line < css) > 0) print line
                print "</style>"
                done = 1
            }
            { print }
        ' "$INDEX" > "$tmp"
        if ! grep -q 'id="lab-theme"' "$tmp"; then
            echo "zeroclaw_entrypoint: no </head> in $INDEX; theme not applied" >&2
            rm -f "$tmp"
            exit 1
        fi
        cat "$tmp" > "$INDEX"
        rm -f "$tmp"
    fi
fi

# New databases and state files private to the agent user (ZeroClaw v0.8.6+ refuses
# group- or world-readable SQLite files)
umask 077
exec zeroclaw "$@"
