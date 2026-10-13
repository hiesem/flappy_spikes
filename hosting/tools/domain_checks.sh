#!/usr/bin/env bash
# PRD-2.3 §6.2 / §11.7 domain checks with curl. Usage:
#   hosting/tools/domain_checks.sh                       # the live domain (https://flappyspikes.com)
#   hosting/tools/domain_checks.sh https://<preview>.web.app nocf   # a preview channel: skips the Cloudflare-only rows
# Prints one PASS / FAIL line per check and exits non-zero on any FAIL.
set -u
B=${1:-https://flappyspikes.com}; MODE=${2:-cf}
HOST=${B#https://}
PLAY='https://play.google.com/store/apps/details?id=com.flappyspikes.flappy_spikes&referrer=utm_source%3Dflappyspikes.com%26utm_medium%3Dweb_link%26utm_campaign%3Dshare_link'
A='Mozilla/5.0 (Linux; Android 16; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36'
I='Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
DC='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
DF='Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0'
DS='Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15'
GB='Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
fails=0
ok() { if [ "$1" = "$2" ]; then echo "PASS  $3"; else echo "FAIL  $3  (got: $1, want: $2)"; fails=$((fails + 1)); fi; }
hdr() { curl -s -o /dev/null -A "$1" -w '%{http_code} %{redirect_url}' "$2"; }

if [ "$MODE" = cf ]; then
  ok "$(hdr "$A" "$B/get")" "302 $PLAY" "/get Android -> Play with referrer"
  ok "$(hdr "$A" "https://www.$HOST/get")" "302 $PLAY" "www /get Android -> Play (one hop)"
  ok "$(hdr "$I" "$B/get")" "302 $B/" "/get iPhone -> / (Rule 2 off)"
  for ua in "$DC" "$DF" "$DS" 'WhatsApp/2.24.1 A' 'facebookexternalhit/1.1' 'Twitterbot/1.0' 'TelegramBot (like TwitterBot)' 'Slackbot-LinkExpanding 1.0'; do
    ok "$(hdr "$ua" "$B/get")" "302 $B/" "/get ${ua%% *} -> /"
  done
  ok "$(hdr "$DC" "https://www.$HOST/")" "301 $B/" "www / -> 301 /"
  ok "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://$HOST/")" "301 $B/" "http -> https"
fi
ref=$(curl -s -A "$DC" "$B/" | md5sum)
for ua in "$A" "$I" "$DC" "$GB"; do
  ok "$(curl -s -o /dev/null -A "$ua" -w '%{http_code}' "$B/")" 200 "/ 200 for ${ua:0:40}"
  ok "$(curl -s -A "$ua" "$B/" | md5sum)" "$ref" "/ identical HTML for ${ua:0:40}"
done
for t in og:title og:description og:image og:url twitter:card; do
  curl -s "$B/" | grep -q "property=\"$t\"\|name=\"$t\"" && echo "PASS  / has $t" || { echo "FAIL  / lacks $t"; fails=$((fails + 1)); }
done
for p in /privacy /delete-data /support /how-to-play /birds /story /games-like-flappy-bird /versus; do
  ok "$(hdr "$A" "$B$p")" "200 " "$p 200 on Android (no redirect)"
done
ok "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$B/og.png")" "200 image/png" "/og.png"
ok "$(curl -s -o /dev/null -A "$A" -w '%{http_code} %{content_type}' "$B/app-ads.txt")" "200 text/plain; charset=utf-8" "/app-ads.txt type"
ok "$(curl -s "$B/app-ads.txt" | md5sum)" "$(curl -s https://hiesem.github.io/app-ads.txt | md5sum)" "/app-ads.txt byte-identical to GitHub"
ok "$(curl -s -o /dev/null -w '%{http_code}' "$B/no-such-page")" 404 "/no-such-page 404"
curl -s "$B/no-such-page" | grep -q '<meta name="robots" content="noindex">' && echo "PASS  404 noindex" || { echo "FAIL  404 noindex"; fails=$((fails + 1)); }
ok "$(hdr "$DC" "$B/privacy.html" | cut -d' ' -f1)" 301 "/privacy.html -> /privacy"
ok "$(hdr "$DC" "$B/privacy/" | cut -d' ' -f1)" 301 "/privacy/ -> /privacy"
for p in /robots.txt /sitemap.xml; do ok "$(curl -s -o /dev/null -w '%{http_code}' "$B$p")" 200 "$p"; done
for u in $(curl -s "$B/sitemap.xml" | grep -o '<loc>[^<]*' | cut -c6-); do
  ok "$(curl -s -o /dev/null -w '%{http_code}' "$B${u#https://flappyspikes.com}")" 200 "sitemap $u"
done
if [ "$MODE" = cf ]; then
  for p in / /privacy /support /delete-data /404; do
    curl -s "$B$p" | grep -q 'hello@duoleads.com' && { echo "FAIL  $p has a plain address"; fails=$((fails + 1)); } || echo "PASS  $p address obfuscated"
  done
  curl -s -o /dev/null "$B/"; ok "$(curl -s -D - -o /dev/null "$B/" | grep -i '^cf-cache-status' | tr -d '\r' | cut -d' ' -f2)" HIT "cf-cache-status HIT on repeat"
fi
echo "$fails failed"; exit $((fails > 0))
