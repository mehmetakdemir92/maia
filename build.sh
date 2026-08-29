#!/bin/bash
# Derleyip sonucu build.log'a yazar. Claude bu dosyayı okuyabiliyor.
# Kullanım:  ./build.sh
cd "$(dirname "$0")" || exit 1
SCHEME="${1:-maia}"

echo "→ derleniyor (scheme: $SCHEME)…"
xcodebuild -project maia.xcodeproj -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' -configuration Debug \
  build > build.full.log 2>&1
STATUS=$?

# Tam log çok uzun; sadece hata/uyarı satırlarını ve özeti ayıkla.
{
  echo "=== exit: $STATUS ==="
  echo "=== error / warning ==="
  grep -E "error:|warning:|note:" build.full.log | sed 's|.*/maia/|maia/|' | sort -u
  echo
  echo "=== son 40 satır ==="
  tail -40 build.full.log
} > build.log

grep -c "error:" build.full.log | xargs echo "hata sayısı:"
echo "→ build.log yazıldı"
