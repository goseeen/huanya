#!/bin/zsh
set -eu
cd "${0:A:h}/.."

RISEUP_ARCHES=("$@")
if (( $# == 0 )); then RISEUP_ARCHES=(x86_64 arm64); fi
for RISEUP_ARCH in "${RISEUP_ARCHES[@]}"; do
    case "$RISEUP_ARCH" in
        x86_64|arm64) ;;
        *) echo "不支持的架构：$RISEUP_ARCH；请使用 x86_64 或 arm64。" >&2; exit 2 ;;
    esac
done

RISEUP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
RISEUP_PACKAGE_ROOT="$PWD/dist/releases/$RISEUP_VERSION"
RISEUP_STAGING_ROOT="$PWD/.build/installers-$$"
mkdir -p "$RISEUP_PACKAGE_ROOT" "$RISEUP_STAGING_ROOT"

for RISEUP_ARCH in "${RISEUP_ARCHES[@]}"; do
    /bin/zsh scripts/build.sh "$RISEUP_ARCH"
    RISEUP_APP="$PWD/dist/$RISEUP_ARCH/缓芽.app"
    if [[ "$RISEUP_ARCH" == x86_64 ]]; then
        RISEUP_LABEL="Intel"
        RISEUP_DEVICE="Intel 处理器 Mac"
    else
        RISEUP_LABEL="AppleSilicon"
        RISEUP_DEVICE="M 系列 Apple 芯片 Mac（原生 arm64，无需 Rosetta）"
    fi
    RISEUP_STAGE="$RISEUP_STAGING_ROOT/$RISEUP_ARCH"
    mkdir -p "$RISEUP_STAGE"
    ditto "$RISEUP_APP" "$RISEUP_STAGE/缓芽.app"
    ln -s /Applications "$RISEUP_STAGE/Applications"
    cat > "$RISEUP_STAGE/安装说明.txt" <<EOF
缓芽 · huǎn yá $RISEUP_VERSION · $RISEUP_LABEL / $RISEUP_ARCH

适用电脑：$RISEUP_DEVICE
系统要求：macOS 13 或更新版本。

安装：
1. 将「缓芽.app」拖到旁边的 Applications 文件夹。
2. 弹出此磁盘映像，再从「应用程序」中打开「缓芽」。
3. 两个架构版本选装与你的电脑匹配的一个即可。更新前请先退出正在运行的缓芽。
4. 从旧名版本升级时，先退出「起身 RiseUp」，将「应用程序」中的旧应用移到废纸篓，再放入「缓芽.app」。只替换应用，不清理其数据目录；新旧版本共用设置与统计，请勿同时运行。

首次打开：
本包使用本地临时签名，尚未经过 Apple Developer ID 签名或公证。
如果系统阻止打开，请在确认文件来源后，前往「系统设置 → 隐私与安全性」选择「仍要打开」。
不需要关闭系统安全保护。

使用：
默认每 30 分钟喝水、20 分钟护眼、45 分钟起身拉伸，可分别调整。
护眼与拉伸的休息时长可在「提醒计划 → 休息时长 → 自定义」中输入分钟和秒，支持 10 秒至 10 分钟。
默认桌面浮窗；如切换系统通知，请在应用「设置」中允许通知。
关闭主窗口后仍在菜单栏运行，按 ⌘Q 完全退出。可在设置中开启登录时启动，默认关闭。
包含空闲暂停、合并提醒、休息前预告、快捷杯量与撤销、忙碌模式、拉伸图卡和更细的统计。
「健康统计」中的各时段工作量支持整列悬停，查看小时范围与累计工作分钟数。
拉伸图卡每 20 秒自动切换，也可手动切换；手动切换后重新计时 20 秒。
本轮使用时长为估算：睡眠唤醒、跨天、重启或连续空闲 / 锁屏满 5 分钟后重新计时。
自动重置不会增加休息次数，也不会改动历史记录。
菜单栏倒计时和全局快捷键可在设置中开启，默认关闭。
快捷键：⌃⌥⌘W 记录默认杯量，⌃⌥⌘R 开始拉伸休息。
更新应用保留既有设置与记录；请勿同时运行两个版本。
统计数据只保存在本机 ~/Library/Application Support/RiseUp/state.json。
本轮使用与工作时长属于计时估算，不识别实际坐姿。
EOF
    RISEUP_DMG="$RISEUP_PACKAGE_ROOT/huanya-$RISEUP_VERSION-$RISEUP_LABEL-$RISEUP_ARCH.dmg"
    if [[ -e "$RISEUP_DMG" ]]; then
        echo "安装包已存在，保留原文件：$RISEUP_DMG。请使用新的发布版本号。" >&2
        exit 1
    fi
    hdiutil create -volname "缓芽 · huǎn yá $RISEUP_LABEL" -srcfolder "$RISEUP_STAGE" -format UDZO -ov "$RISEUP_DMG"
    hdiutil verify -quiet "$RISEUP_DMG"
    echo "已打包：$RISEUP_DMG"
done

(
    cd "$RISEUP_PACKAGE_ROOT"
    shasum -a 256 huanya-*.dmg > SHA256SUMS.txt
)
echo "指定架构的安装包已生成，SHA-256 校验值位于 $RISEUP_PACKAGE_ROOT/SHA256SUMS.txt。"
/bin/zsh scripts/verify-packages.sh "${RISEUP_ARCHES[@]}"
