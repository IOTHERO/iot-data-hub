#!/usr/bin/env bash
# Assembles data/index.html from tools/web/: the Relay-8 module's theme (head.html: styles and
# fonts), the hub's extra styles, the icon symbols and the page body. Run from the firmware folder.
set -euo pipefail
cd "$(dirname "$0")/web"
{
  cat head.html
  cat extra.css
  awk 'FNR==NR{sym=sym $0 "\n"; next} /^@@SYMBOLS@@$/{printf "%s", sym; next} {print}' symbols.part body.html
} > ../../data/index.html
echo "data/index.html: $(wc -c < ../../data/index.html) bytes"
