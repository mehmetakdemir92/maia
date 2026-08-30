#!/bin/bash
# "Application failed preflight checks" hatasını anında onarır.
#
# Hata SpringBoard'ın LaunchServices önbelleğinin geride kalmasından çıkıyor
# (loglarda: Retry attempt failed ... reason "LaunchServicesDataMismatch").
# Sadece SpringBoard'ı yeniden başlatmak yeterli — simülatörü kapatmaya,
# erase etmeye ya da uygulamayı silmeye gerek yok, veri kaybı olmaz.
#
# Kullanım:  ./scripts/simheal.sh

set -uo pipefail

UDID=$(xcrun simctl list devices booted \
       | sed -nE 's/.*\(([0-9A-Fa-f-]{36})\) \(Booted\).*/\1/p' | head -1)

if [ -z "$UDID" ]; then
  echo "✗ açık simülatör yok." >&2
  exit 1
fi

echo "→ SpringBoard yeniden başlatılıyor ($UDID)…"
xcrun simctl spawn "$UDID" launchctl kickstart -k system/com.apple.SpringBoard \
  >/dev/null 2>&1

for _ in $(seq 1 25); do
  sleep 1
  if xcrun simctl spawn "$UDID" launchctl print system/com.apple.SpringBoard \
       >/dev/null 2>&1; then
    sleep 3
    echo "✓ hazır — Xcode'da tekrar Run'a basabilirsin."
    exit 0
  fi
done

echo "✗ SpringBoard beklenen sürede açılmadı; simülatörü yeniden başlat." >&2
exit 1
