#!/bin/sh
# Auto sign-up + login for the Whs-Guest captive portal with a random name/email.
# Usage: ./login.sh        (IFACE=wlan0 by default; set IFACE= to disable binding)
# Binding to the wifi interface keeps the portal requests off the VPN (tun0).

IFACE="${IFACE-wlan0}"
UA='Mozilla/5.0 (X11; Linux x86_64; rv:158.0) Gecko/20100101 Firefox/158.0'
TMP=$(mktemp -d)
JAR="$TMP/jar"
trap 'rm -rf "$TMP"' EXIT

c() { # curl with shared cookie jar, UA, and optional interface
  if [ -n "$IFACE" ]; then
    curl -s -m 20 --interface "$IFACE" -A "$UA" -b "$JAR" -c "$JAR" "$@"
  else
    curl -s -m 20 -A "$UA" -b "$JAR" -c "$JAR" "$@"
  fi
}

die() {
  echo "error: $*" >&2
  rm -rf ./last-run-debug
  cp -r "$TMP" ./last-run-debug 2>/dev/null && echo "debug files in ./last-run-debug" >&2
  exit 1
}

online() { [ "$(c -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204)" = 204 ]; }

# ---- random identity ----
FIRST="Alex Sam Jordan Taylor Casey Riley Morgan Jamie Drew Quinn Avery Parker Logan Reese Dakota Skyler Rowan Emery Finley Harper"
LAST="Smith Johnson Lee Brown Davis Miller Wilson Moore Clark Lewis Walker Hall Young King Wright Scott Green Baker Adams Nelson"
pick() { echo "$1" | tr ' ' '\n' | shuf -n1; }
NAME="$(pick "$FIRST") $(pick "$LAST")"
LOCAL="$(tr -dc 'a-z0-9' </dev/urandom | head -c 10)"
EMAIL="$LOCAL@random.com"
echo "identity: $NAME <$EMAIL>"

online && { echo "already online"; exit 0; }

# ---- 1. find the portal login page (follows redirects) ----
PORTAL=$(c -L -o "$TMP/portal.html" -w '%{url_effective}' http://neverssl.com/)
case "$PORTAL" in
  *guest.rjuhsd.us*) ;;
  *) die "not redirected to the guest portal (got: $PORTAL). Is $IFACE on Whs-Guest?" ;;
esac
q() { echo "$PORTAL" | tr '?&' '\n\n' | sed -n "s/^$1=//p" | head -n1; } # still url-encoded

# ---- 2. sign up as the random guest ----
c -L -o "$TMP/signup.html" "https://guest.rjuhsd.us/guest/rjuhsd_2.php?_browser=1" \
  -e "$PORTAL" \
  --data-raw "url=$(q url)&switchip=$(q switchip)&apmac=$(q apmac)&ip=$(q ip)&cmd=login" \
  --data-urlencode "visitor_name=$NAME" \
  --data-urlencode "email=$EMAIL" \
  --data-raw "&expire_after=24&role_id=2&mac=$(q mac)&remote_addr=$(q ip)&essid=$(q essid)&apgroup=&apname=$(q apname)&vcname=$(q vcname)&auto_update_account=1&creator_accept_terms=1" \
  || die "sign-up request failed"

# ---- 3. walk the forms: receipt page -> router login ----
# Each page has a form with hidden inputs; resubmit it until we're online.
BODY="$TMP/signup.html"
REFERER="https://guest.rjuhsd.us/guest/rjuhsd_2.php"
for step in 1 2 3 4; do
  ACTION=$(tr '\n' ' ' <"$BODY" | grep -io '<form[^>]*>' | head -n1 | sed -n 's/.*action=["'\'']\([^"'\'']*\).*/\1/p')

  # no form on the sign-up response: the receipt is a separate GET
  if [ -z "$ACTION" ] && ! grep -qi '<input' "$BODY"; then
    [ "$step" = 1 ] || break
    c -L -o "$TMP/receipt.html" "https://guest.rjuhsd.us/guest/rjuhsd_2_receipt.php" -e "$REFERER" || die "receipt fetch failed"
    BODY="$TMP/receipt.html"
    continue
  fi

  case "$ACTION" in
    http*) URL="$ACTION" ;;
    /*)    URL="https://guest.rjuhsd.us$ACTION" ;;
    "")    URL="https://guest.rjuhsd.us/guest/rjuhsd_2_receipt.php" ;;
    *)     URL="https://guest.rjuhsd.us/guest/$ACTION" ;;
  esac

  # collect <input name=.. value=..> pairs
  set --
  for tag in $(tr '\n' ' ' <"$BODY" | grep -io '<input[^>]*>' | sed 's/ /\x01/g'); do
    tag=$(echo "$tag" | tr '\001' ' ')
    n=$(echo "$tag" | sed -n 's/.*name=["'\'']\([^"'\'']*\).*/\1/p')
    v=$(echo "$tag" | sed -n 's/.*value=["'\'']\([^"'\'']*\).*/\1/p')
    [ -n "$n" ] && set -- "$@" --data-urlencode "$n=$v"
  done

  echo "step $step -> $URL"
  c -L -o "$TMP/step$step.html" "$URL" -e "$REFERER" "$@" || die "POST to $URL failed"
  BODY="$TMP/step$step.html"
  REFERER="$URL"
  online && break
done

# ---- 4. confirm ----
sleep 2
if online; then
  echo "online as $NAME"
else
  die "still captive; the portal flow may have changed"
fi
