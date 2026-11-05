#!/bin/sh
# Auto sign-up + login for the Whs-Guest captive portal (Aruba/ClearPass guest self-registration).
# Usage: ./login.sh          (IFACE=wlan0 by default; set IFACE= to disable binding)
# Binding to the wifi interface keeps the portal requests off the VPN (tun0).
#
# Env knobs:
#   IFACE         interface to bind curl to ("" = don't bind)              default wlan0
#   EMAIL_DOMAIN  domain for the throwaway guest email                     default gmail.com
#   CF_UA         User-Agent (set by login-browser.sh to match the browser that solved Cloudflare)
#   CF_COOKIE     "name=value; ..." cookies from the browser (cf_clearance, GSID) for Cloudflare
#   DEBUG         if set, always dump the fetched pages to ./last-run-debug (not only on error)
#
# Exit: 0 online, 1 generic failure, 2 Cloudflare challenge and no CF_COOKIE (run login-browser.sh).
set -f    # no pathname expansion: portal field values may contain * ? [ and must survive the form walk

IFACE="${IFACE-wlan0}"
UA="${CF_UA:-Mozilla/5.0 (X11; Linux x86_64; rv:158.0) Gecko/20100101 Firefox/158.0}"
CF_COOKIE="${CF_COOKIE-}"
EMAIL_DOMAIN="${EMAIL_DOMAIN:-gmail.com}"   # @random.com gets guest accounts auto-denied; use a real-looking domain
BASE="https://guest.rjuhsd.us"
TMP=$(mktemp -d)
JAR="$TMP/jar"
trap 'rm -rf "$TMP"' EXIT

c() { # curl with shared cookie jar, UA, browser cookies, and optional interface binding
  if [ -n "$IFACE" ]; then
    curl -s -m 20 --interface "$IFACE" -A "$UA" -b "$CF_COOKIE" -b "$JAR" -c "$JAR" "$@"
  else
    curl -s -m 20 -A "$UA" -b "$CF_COOKIE" -b "$JAR" -c "$JAR" "$@"
  fi
}

dump() { rm -rf ./last-run-debug; cp -r "$TMP" ./last-run-debug 2>/dev/null && echo "debug files in ./last-run-debug" >&2; }
die()  { echo "error: $*" >&2; dump; exit 1; }

# a Cloudflare interstitial: curl can't solve it, but login-browser.sh can and passes CF_COOKIE back
# only the interstitial block page, not residual cf scripts that survive on an already-cleared page
is_cf() { grep -iqE 'Just a moment|__cf_chl_|cf-mitigated|Attention Required!|Checking (if the site connection is secure|your browser)' "$1" 2>/dev/null; }
cf_guard() {
  is_cf "$1" || return 0
  [ -n "$CF_COOKIE" ] && return 0      # we already have a clearance cookie; a stale hit is not fatal
  dump
  echo "error: Cloudflare challenge and no clearance cookie. Run ./login-browser.sh (it solves it in Firefox, then calls this)." >&2
  exit 2
}

# decode the handful of HTML entities that appear in hidden form values, so they are re-sent verbatim
unent() { printf '%s' "$1" | sed -e 's/&amp;/\&/g' -e "s/&#0*39;/'/g" -e "s/&#x0*27;/'/g" -e 's/&quot;/"/g' -e 's/&lt;/</g' -e 's/&gt;/>/g'; }

online() { [ "$(c -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204)" = 204 ]; }
# the gate takes a moment to program after the controller accepts the login
wait_online() { for _ in 1 2 3 4 5; do online && return 0; sleep 1; done; return 1; }

# first client-side redirect target (<meta refresh ... URL=...> or window.location = "...") in a fetched page.
# Captive shells bounce through these and curl does not follow them, so url_effective would miss the params.
client_redirect() {
  flat=$(tr '\n' ' ' <"$1")
  # <meta http-equiv=refresh content="0; URL=/guest/rjuhsd_2.php?...">  (case-insensitive; keep the whole target)
  t=$(printf '%s' "$flat" | grep -io 'content="[^"]*"' | sed -nE 's/.*content="[0-9]+; *url=([^"]*)".*/\1/Ip' | head -n1)
  # window.top.location.href = "\/guest\/rjuhsd_2.php?..."  (JS may escape the slashes)
  [ -n "$t" ] || t=$(printf '%s' "$flat" | grep -io 'location\.\(href\|replace\)[^;]*' | sed -nE "s/.*['\"]([^'\"]+)['\"].*/\1/p" | head -n1)
  printf '%s' "$t" | tr -d '\\'
}

# ---- random, realistic-looking identity ----
FIRST="Alex Sam Jordan Taylor Casey Riley Morgan Jamie Drew Quinn Avery Parker Logan Reese Dakota Skyler Rowan Emery Finley Harper"
LAST="Smith Johnson Lee Brown Davis Miller Wilson Moore Clark Lewis Walker Hall Young King Wright Scott Green Baker Adams Nelson"
pick() { echo "$1" | tr ' ' '\n' | shuf -n1; }
FN=$(pick "$FIRST"); LN=$(pick "$LAST")
NAME="$FN $LN"
NUM=$(( $(od -An -N2 -tu2 /dev/urandom) % 900 + 100 ))
LOCAL=$(printf '%s.%s%s' "$FN" "$LN" "$NUM" | tr 'A-Z' 'a-z')
EMAIL="$LOCAL@$EMAIL_DOMAIN"
echo "identity: $NAME <$EMAIL>"

online && { echo "already online"; exit 0; }

# ---- 1. reach the real portal page, following HTTP *and* client-side (meta/JS) redirects ----
PORTAL=$(c -L -o "$TMP/portal.html" -w '%{url_effective}' http://neverssl.com/)
cf_guard "$TMP/portal.html"
i=0
while [ "$i" -lt 5 ]; do
  # stop once we have the real portal URL with the session context (mac/switchip), so we don't
  # mis-follow some unrelated script on the form page itself
  case "$PORTAL" in *mac=*|*switchip=*) break ;; esac
  t=$(client_redirect "$TMP/portal.html")
  [ -n "$t" ] || break
  t=$(unent "$t")
  case "$t" in
    http*) PORTAL="$t" ;;
    //*)   PORTAL="https:$t" ;;
    /*)    PORTAL="$BASE$t" ;;
    *)     PORTAL="${PORTAL%/*}/$t" ;;
  esac
  c -L -o "$TMP/portal.html" "$PORTAL" >/dev/null || break
  cf_guard "$TMP/portal.html"
  i=$((i + 1))
done
case "$PORTAL" in
  *guest.rjuhsd.us*) ;;
  *) die "not redirected to the guest portal (ended at: $PORTAL). Is $IFACE on Whs-Guest?" ;;
esac
# the controller passes the session context in the final portal URL's query string
q() { echo "$PORTAL" | tr '?&' '\n\n' | sed -n "s/^$1=//p" | head -n1; }   # still url-encoded
[ -n "$(q mac)" ] && [ -n "$(q switchip)" ] || echo "warning: portal URL has no mac/switchip params ($PORTAL)" >&2

# ---- 2. sign up as the random guest ----
c -L -o "$TMP/signup.html" "$BASE/guest/rjuhsd_2.php?_browser=1" \
  -e "$PORTAL" \
  --data-raw "url=$(q url)&switchip=$(q switchip)&apmac=$(q apmac)&ip=$(q ip)&cmd=login" \
  --data-urlencode "visitor_name=$NAME" \
  --data-urlencode "email=$EMAIL" \
  --data-raw "expire_after=24&role_id=2&mac=$(q mac)&remote_addr=$(q ip)&essid=$(q essid)&apgroup=&apname=$(q apname)&vcname=$(q vcname)&auto_update_account=1&creator_accept_terms=1" \
  || die "sign-up request failed"
cf_guard "$TMP/signup.html"

# ---- 3. walk the forms: receipt -> controller login -> online ----
# Each page is a form of hidden inputs; resubmit it (first form on the page) until we are online.
BODY="$TMP/signup.html"
REFERER="$BASE/guest/rjuhsd_2.php"
for step in 1 2 3 4; do
  ACTION=$(tr '\n' ' ' <"$BODY" | grep -io '<form[^>]*>' | head -n1 | sed -n 's/.*action=["'\'']\([^"'\'']*\).*/\1/p')

  # no form and no inputs on the sign-up response: the receipt is a separate GET
  if [ -z "$ACTION" ] && ! grep -qi '<input' "$BODY"; then
    [ "$step" = 1 ] || break
    c -L -o "$TMP/receipt.html" "$BASE/guest/rjuhsd_2_receipt.php" -e "$REFERER" || die "receipt fetch failed"
    cf_guard "$TMP/receipt.html"
    BODY="$TMP/receipt.html"
    continue
  fi

  case "$ACTION" in
    http*) URL="$ACTION" ;;
    //*)   URL="https:$ACTION" ;;
    /*)    URL="$BASE$ACTION" ;;
    "")    URL="$BASE/guest/rjuhsd_2_receipt.php" ;;
    *)     URL="$BASE/guest/$ACTION" ;;
  esac
  URL=$(unent "$URL")

  # collect <input name=.. value=..> pairs, entity-decoding each value
  set --
  for tag in $(tr '\n' ' ' <"$BODY" | grep -io '<input[^>]*>' | sed 's/ /\x01/g'); do
    tag=$(printf '%s' "$tag" | tr '\001' ' ')
    n=$(printf '%s' "$tag" | sed -n 's/.*name=["'\'']\([^"'\'']*\).*/\1/p')
    v=$(printf '%s' "$tag" | sed -n 's/.*value=["'\'']\([^"'\'']*\).*/\1/p')
    [ -n "$n" ] && set -- "$@" --data-urlencode "$n=$(unent "$v")"
  done

  echo "step $step -> $URL"
  # the controller (securelogin.hpe.com) often serves a non-public cert; allow it only for that host
  insecure=""
  case "$URL" in *securelogin.hpe.com*|*securelogin.arubanetworks.com*) insecure="-k" ;; esac
  # shellcheck disable=SC2086
  c $insecure -L -o "$TMP/step$step.html" "$URL" -e "$REFERER" "$@" || die "POST to $URL failed"
  cf_guard "$TMP/step$step.html"
  BODY="$TMP/step$step.html"
  REFERER="$URL"
  online && break
done

# ---- 4. confirm, and if still captive say why when the portal tells us ----
if wait_online; then
  echo "online as $NAME"
  exit 0
fi
reason=$(tr '\n' ' ' <"$BODY" | sed 's/<[^>]*>/ /g' | tr -s ' ' \
         | grep -ioE 'has not been approved|pending[^.]{0,40}approv[a-z]*|awaiting sponsor|not authorized|access denied|login failed|account (is )?disabled|invalid (user|login|password)[^.]{0,30}' \
         | head -n1)
[ -n "$reason" ] && die "still captive — portal says: \"$reason\" (try a different EMAIL_DOMAIN; the guest account may need approval)"
die "still captive; the portal flow may have changed (see ./last-run-debug)"
