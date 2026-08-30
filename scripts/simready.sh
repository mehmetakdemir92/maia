#!/bin/bash
# Xcode "Run"a basmadan ÖNCE simülatörün boot'unu tamamlamasını garanti eder.
#
# Neden: Xcode Run'a basınca kapalı simülatörü kendisi boot ediyor ve ~1 sn
# sonra kurulum isteğini gönderiyor. Cihaz henüz boot ederken gelen bu kurulum
# SpringBoard'ın LaunchServices önbelleğini geride bırakıyor; sonraki açılış
# isteği "LaunchServicesDataMismatch" ile reddediliyor ve Xcode bunu
#   "Application failed preflight checks"  /  Busy
# olarak gösteriyor. Bu script kurulumdan önce boot'un bitmesini beklediği için
# yarış hiç oluşmuyor.
#
# maia.xcscheme içinde Build pre-action olarak bağlıdır; elle de çalıştırılabilir.

LOG="${TMPDIR:-/tmp}/simready.log"
exec >>"$LOG" 2>&1
echo "--- $(date '+%F %T') simready ---"

# Simülatör derlemelerine özel. Archive ve gerçek cihaz derlemelerinde
# hiçbir şey boot edilmemeli — pre-action Archive sırasında da çalışır.
if [ -n "${PLATFORM_NAME:-}" ] && [ "${PLATFORM_NAME}" != "iphonesimulator" ]; then
  echo "platform=${PLATFORM_NAME} — simülatör değil, atlanıyor"
  exit 0
fi
echo "platform=${PLATFORM_NAME:-<tanimsiz>}"

DEVICE="${SIMREADY_DEVICE:-iPhone 17 Pro}"

# Xcode'un seçtiği cihaz > zaten açık olan cihaz > varsayılan isim
UDID="${TARGET_DEVICE_IDENTIFIER:-}"

if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl list devices booted \
         | sed -nE 's/.*\(([0-9A-Fa-f-]{36})\) \(Booted\).*/\1/p' | head -1)
fi

if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl list devices available \
         | grep -F "$DEVICE (" | head -1 \
         | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
fi

if [ -z "$UDID" ]; then
  echo "uygun simülatör bulunamadı; atlanıyor"
  exit 0          # build'i asla engelleme
fi

echo "cihaz: $UDID"
# Zaten açıksa anında döner; değilse boot edip boot BİTENE kadar bekler.
xcrun simctl bootstatus "$UDID" -b
echo "hazır"
exit 0
