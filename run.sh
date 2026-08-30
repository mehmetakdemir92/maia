#!/bin/bash
# Derler, simülatöre kurar ve çalıştırır.
#
# "Application failed preflight checks" hatasına karşı iki katmanlı koruma:
#   1) ÖNLEME  — kurulumdan önce cihazın boot'unun BİTMESİNİ bekler.
#      Hatanın asıl sebebi buydu: Xcode, cihaz daha boot ederken
#      (Run'a basınca cihazı kendisi boot edip 1 sn sonra install atıyor)
#      kurulum gönderiyor; SpringBoard'ın LaunchServices önbelleği geride
#      kalıyor ve açılış isteği "LaunchServicesDataMismatch" ile reddediliyor.
#   2) ONARIM — yine de olursa SpringBoard'ı yeniden başlatıp tekrar dener.
#
# Kullanım:  ./run.sh
#            DEVICE="iPhone 16 Pro" ./run.sh
#            SCHEME=maia ./run.sh

set -uo pipefail
cd "$(dirname "$0")" || exit 1

SCHEME="${SCHEME:-maia}"
BUNDLE_ID="${BUNDLE_ID:-com.mehmetakdemir.maia}"
DEVICE="${DEVICE:-iPhone 17 Pro}"

# --- 1) Cihazı bul ---------------------------------------------------------
UDID=$(xcrun simctl list devices available \
       | grep -F "$DEVICE (" | head -1 \
       | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
if [ -z "$UDID" ]; then
  echo "✗ '$DEVICE' simülatörü bulunamadı. Mevcut cihazlar:" >&2
  xcrun simctl list devices available | grep -E "^\s+i(Phone|Pad)" >&2
  exit 1
fi
echo "→ cihaz: $DEVICE ($UDID)"

# --- 2) Boot et ve boot BİTENE KADAR bekle (asıl önlem) --------------------
echo "→ simülatör hazırlanıyor…"
xcrun simctl bootstatus "$UDID" -b || exit 1
open -a Simulator --args -CurrentDeviceUDID "$UDID"

# --- 3) Derle --------------------------------------------------------------
echo "→ derleniyor (scheme: $SCHEME)…"
xcodebuild -project maia.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "id=$UDID" build > build.full.log 2>&1
STATUS=$?

{
  echo "=== exit: $STATUS ==="
  echo "=== error / warning ==="
  grep -E "error:|warning:|note:" build.full.log | sed 's|.*/maia/|maia/|' | sort -u
  echo
  echo "=== son 40 satır ==="
  tail -40 build.full.log
} > build.log

if [ $STATUS -ne 0 ]; then
  echo "✗ derleme başarısız — ayrıntı: build.log"
  grep -E "error:" build.full.log | sed 's|.*/maia/|maia/|' | sort -u | head -20
  exit $STATUS
fi

APP=$(xcodebuild -project maia.xcodeproj -scheme "$SCHEME" -configuration Debug \
      -destination "id=$UDID" -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{d=$2} / FULL_PRODUCT_NAME =/{n=$2} \
                     END{gsub(/^ +| +$/,"",d); gsub(/^ +| +$/,"",n); print d"/"n}')
if [ ! -d "$APP" ]; then
  echo "✗ derlenen .app bulunamadı: $APP" >&2
  exit 1
fi

# --- 4) Kur + çalıştır, gerekirse SpringBoard'ı onarıp tekrar dene ---------
install_and_launch() {
  xcrun simctl install "$UDID" "$APP" 2>&1 || return 1
  xcrun simctl launch "$UDID" "$BUNDLE_ID" 2>&1 || return 1
}

for attempt in 1 2 3; do
  out=$(install_and_launch)
  if [ $? -eq 0 ]; then
    echo "→ $out"
    echo "✓ çalışıyor"
    exit 0
  fi

  echo "$out"
  if echo "$out" | grep -q "preflight checks"; then
    echo "→ LaunchServices önbelleği geride kalmış; SpringBoard yeniden başlatılıyor…"
    xcrun simctl spawn "$UDID" launchctl kickstart -k system/com.apple.SpringBoard \
      >/dev/null 2>&1
    # SpringBoard'ın açılış isteği kabul etmeye hazır olmasını bekle
    for _ in $(seq 1 20); do
      sleep 1
      xcrun simctl spawn "$UDID" launchctl print system/com.apple.SpringBoard \
        >/dev/null 2>&1 && break
    done
    sleep 3
    continue
  fi

  echo "✗ kurulum/çalıştırma başarısız (preflight dışı bir hata)" >&2
  exit 1
done

echo "✗ 3 denemede de açılamadı." >&2
exit 1
