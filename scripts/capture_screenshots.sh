#!/bin/bash
# App Store 用のスクリーンショットを、シミュレータでデモデータを表示して自動で撮る。
#
#   scripts/capture_screenshots.sh [シミュレータの UDID]    # 省略時は "Recolle Screenshots 6.9"
#
# 保存先: build/screenshots/raw-<dark|light>/<名前>.png（シミュレータの実寸。iPhone 17 Pro Max は 1320×2868）
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Recolle Screenshots 6.9"
UDID="${1:-$(xcrun simctl list devices | grep "$NAME" | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)}"
[ -n "$UDID" ] || { echo "シミュレータ '$NAME' が見つかりません"; exit 1; }
OUT="build/screenshots/raw-${APPEARANCE:-dark}"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null
# 外観（dark / light）。既定はダーク。例: APPEARANCE=light scripts/capture_screenshots.sh
xcrun simctl ui "$UDID" appearance "${APPEARANCE:-dark}"
# 時刻・電波・バッテリーをきれいな表示にそろえる
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

flutter test integration_test/app_store_screenshots_test.dart -d "$UDID" \
  --dart-define=DEMO_MODE=true 2>&1 | while IFS= read -r line; do
  echo "$line"
  case "$line" in
    *SHOT:DONE*) ;;
    *SHOT:*)
      name="${line##*SHOT:}"
      xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 && echo "→ 保存: $OUT/$name.png"
      ;;
  esac
done
