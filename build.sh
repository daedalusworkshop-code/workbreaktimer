#!/bin/bash

# ==========================================
# 1. 获取动态路径
# ==========================================
# 这句代码能获取到当前脚本文件所在的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ==========================================
# 2. 定义变量 (路径全部基于脚本所在目录)
# ==========================================
PROJECT="$SCRIPT_DIR/WorkRestTimer.xcodeproj"
SCHEME="WorkRestTimer"
CONFIG="Release"
DERIVED="/tmp/WorkRestTimerDerivedData"
OUT="$SCRIPT_DIR/dist"

echo "========================================"
echo "🚀 开始构建: $SCHEME"
echo "📂 项目路径: $SCRIPT_DIR"
echo "========================================"

# ==========================================
# 3. 清理工作 (工作开始前清理 dist)
# ==========================================
if [ -d "$OUT" ]; then
    echo "🧹 发现旧的 dist 目录，正在清理..."
    rm -rf "$OUT"
fi

# ==========================================
# 4. 执行构建
# ==========================================
echo "🔨 正在使用 xcodebuild 编译项目..."
# 执行构建，并将多余的日志重定向丢弃，只显示报错，让终端看起来清爽一点 (如果需要看详细日志，可以去掉 > /dev/null)
xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -derivedDataPath "$DERIVED" \
           -destination 'platform=macOS' \
           clean build > /dev/null

# 检查上一条命令（xcodebuild）是否执行成功
if [ $? -ne 0 ]; then
    echo "❌ 编译失败，请在 Xcode 中检查项目配置或代码错误。"
    exit 1
fi

# ==========================================
# 5. 打包产物
# ==========================================
echo "📦 编译成功，准备提取 .app 文件..."
mkdir -p "$OUT"

# 查找生成的 .app 文件
APP_PATH="$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 -name '*.app' -print -quit)"

if [ -n "$APP_PATH" ]; then
    cp -R "$APP_PATH" "$OUT/"
    echo "✅ 构建完成！"
    echo "🎉 应用程序已输出至: $OUT/$(basename "$APP_PATH")"
else
    echo "❌ 错误：编译成功了，但在产物目录中找不到 .app 文件。"
    exit 1
fi
