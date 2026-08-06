#!/usr/bin/env bash
# 编译 OmniBar → 默认同步到 /Applications/OmniBar.app → 重启运行（供命令行快速迭代）
# 用法:
#   ./build-run.sh               # 编译 + 同步到 /Applications + 运行
#   ./build-run.sh --no-install  # 只编译并从 DerivedData 运行，不同步 /Applications
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/OmniBar.xcodeproj"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/OmniBar-*/Build/Products/Debug/OmniBar.app"
INSTALL_APP="/Applications/OmniBar.app"

# 参数解析：默认同步安装；--no-install 跳过
NO_INSTALL=0
for arg in "$@"; do
  if [ "$arg" = "--no-install" ]; then NO_INSTALL=1; fi
done

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

RUN_APP="$APP"
if [ "$NO_INSTALL" -eq 0 ]; then
  if [ -w "/Applications" ]; then
    echo "▸ 同步到 $INSTALL_APP …"
    rm -rf "$INSTALL_APP"
    ditto "$APP" "$INSTALL_APP"
    RUN_APP="$INSTALL_APP"
    echo "✓ 已同步（$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_APP/Contents/Info.plist" 2>/dev/null)）"
  else
    echo "⚠ 无法写入 /Applications，跳过同步（直接运行编译产物）"
  fi
else
  echo "▸ 跳过同步（--no-install）"
fi

echo "▸ 启动 $RUN_APP"
# 用 open（LaunchServices）启动：由 launchd 托管，脱离本脚本进程树，
# 避免后台 & 启动的实例在脚本所在 shell 会话结束后被回收
open "$RUN_APP"
sleep 2
if pgrep -x OmniBar >/dev/null; then
  echo "✓ 已在运行（launchd 托管）"
else
  echo "✗ 启动失败；请查看 ~/Library/Logs/DiagnosticReports/ 是否有崩溃报告"
  exit 1
fi
