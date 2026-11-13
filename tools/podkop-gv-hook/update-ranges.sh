#!/bin/sh
# Обновить в sing-box-hook.jq список адресов Google из https://www.gstatic.com/ipranges/goog.json.
# Запускать на компьютере (нужны curl и jq), потом заново install.sh на роутере.
set -e
F=$(dirname "$0")/sing-box-hook.jq
J=$(curl -fsS https://www.gstatic.com/ipranges/goog.json)
R=$(echo "$J" | jq -c '[.prefixes[] | (.ipv4Prefix // .ipv6Prefix)]')
D=$(echo "$J" | jq -r '.creationTime' | cut -c1-10)
T=$(mktemp)
awk -v r="$R" -v d="$D" '
  /as \$google$/ { print "| " r " as $google"; next }
  /^# Адреса Google:/ { print "# Адреса Google: https://www.gstatic.com/ipranges/goog.json (" d ")"; next }
  { print }' "$F" > "$T"
echo '{"route":{"rules":[]},"outbounds":[]}' | jq -f "$T" >/dev/null
cat "$T" > "$F"; rm -f "$T"
echo "обновлено: $(echo "$R" | jq length) диапазонов, $D"
