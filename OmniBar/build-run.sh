#!/usr/bin/env bash
# 编译 OmniBar 并在成功后自动重启运行（供命令行快速迭代）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/OmniBar.xcodeproj"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/OmniBar-*/Build/Products/Debug/OmniBar.app"

echo "▸ 编译 Debug…"
xcodebuild build -project "$PROJECT" -scheme OmniBar -configuration Debug -destination 'platform=macOS' -quiet

# 取唯一匹配的 app（有多个 DerivedData 时取最新的）
APP="$(ls -td $APP_PATH 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
  echo "✗ 未找到编译产物"; exit 1
fi

echo "▸ 关闭旧进程…"
pkill -x OmniBar 2>/dev/null || true
sleep 1

echo "▸ 启动 $APP"
"$APP/Contents/MacOS/OmniBar" >/tmp/omnibar_run.log 2>&1 &
sleep 2
if pgrep -x OmniBar >/dev/null; then
  echo "✓ 已在运行；日志: /tmp/omnibar_run.log"
else
  echo "✗ 启动失败"; cat /tmp/omnibar_run.log; exit 1
fi