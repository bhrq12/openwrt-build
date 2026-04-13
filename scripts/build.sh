#!/bin/bash
# OpenWrt Build Script
# 用法: PLATFORMS="platform1 platform2" ARTIFACT="firmware|packages|both" ./scripts/build.sh
# 依赖环境变量: PLATFORMS, ARTIFACT
# GITHUB_WORKSPACE 由 GitHub Actions 自动注入

set -euo pipefail

# ========== 配置区 ==========
OPENWRT_REPO="https://github.com/coolsnowwolf/lede"
OPENWRT_BRANCH="master"
# ⚠️ 修改为你的 acctl 仓库地址后再使用
ACCTL_REPO="https://github.com/bhrq12/acctl"
ACCTL_BRANCH="main"
BUILD_THREADS=4

# ========== 颜色输出 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 初始化 ==========
WORKDIR="${GITHUB_WORKSPACE:-/tmp/openwrt-build}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_REPO_DIR="${WORKDIR}"

log_info "OpenWrt 云编译构建脚本"
log_info "工作目录: $WORKDIR"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 加载自定义 feeds.conf（如果存在）
FEEDS_CONF=""
if [ -f "${CONFIG_REPO_DIR}/configs/feeds.conf" ]; then
    log_info "检测到自定义 feeds.conf，将在后处理阶段追加"
    FEEDS_CONF="${CONFIG_REPO_DIR}/configs/feeds.conf"
fi

# 确认 .config 存在
validate_configs() {
    for platform in $PLATFORMS; do
        local cfg="${CONFIG_REPO_DIR}/configs/${platform}.config"
        # 优先用 .config，找不到再看 .config.placeholder
        if [ ! -f "$cfg" ]; then
            cfg="${CONFIG_REPO_DIR}/configs/${platform}.config.placeholder"
        fi
        if [ ! -f "$cfg" ]; then
            log_error "平台 $platform 缺少配置文件: configs/${platform}.config"
            log_error "请参考 configs/*.config.placeholder 创建配置后重试"
            return 1
        fi
        log_info "配置就绪: $cfg"
    done
    return 0
}

# ========== 平台配置映射 ==========
declare -A PLATFORM_CONFIG
PLATFORM_CONFIG[ipq40xx]="target/linux/ipq40xx"
PLATFORM_CONFIG[x86_64]="target/linux/x86"
PLATFORM_CONFIG[bcm2711]="target/linux/bcm2711"
PLATFORM_CONFIG[ramips-mt7621]="target/linux/ramips/mt7621"

# ========== 单平台编译函数 ==========
build_platform() {
    local platform=$1
    log_info "=========================================="
    log_info "开始编译平台: $platform"
    log_info "=========================================="

    local platform_dir="${WORKDIR}/build-${platform}"
    local config_src="${CONFIG_REPO_DIR}/configs/${platform}.config"
    local config_placeholder="${CONFIG_REPO_DIR}/configs/${platform}.config.placeholder"
    local output_firmware="${WORKDIR}/output/firmware"
    local output_packages="${WORKDIR}/output/packages"

    # 确定实际使用的配置文件
    if [ -f "$config_src" ]; then
        local active_config="$config_src"
    else
        local active_config="$config_placeholder"
    fi

    mkdir -p "$platform_dir" "$output_firmware" "$output_packages"

    cd "$platform_dir"

    # 1. 克隆/更新源码
    if [ ! -d ".git" ]; then
        log_step "克隆 OpenWrt 源码..."
        git clone --depth=1 -b "$OPENWRT_BRANCH" "$OPENWRT_REPO" .
        log_info "源码克隆完成 (lean/lede master)"
    else
        log_step "更新 OpenWrt 源码..."
        git pull --ff-only origin "$OPENWRT_BRANCH"
        log_info "源码更新完成"
    fi

    # 2. 添加 acctl 软件包
    log_step "添加 acctl 软件包..."
    if [ -d "package/acctl" ]; then
        log_warn "acctl 已存在，跳过添加"
    else
        log_info "从 $ACCTL_REPO (分支: $ACCTL_BRANCH) 克隆..."
        git clone --depth=1 -b "$ACCTL_BRANCH" "$ACCTL_REPO" "package/acctl" || {
            log_warn "acctl 克隆失败，继续编译（acctl 可能不在编译范围内）"
        }
    fi

    # 3. 应用自定义 feeds.conf（如有）
    if [ -n "$FEEDS_CONF" ] && [ -f "$FEEDS_CONF" ]; then
        log_step "应用自定义 feeds 配置..."
        cat "$FEEDS_CONF" >> feeds.conf.default
        ./scripts/feeds update -a || log_warn "feeds update 存在非致命警告"
        ./scripts/feeds install -a || log_warn "feeds install 存在非致命警告"
    fi

    # 4. 应用平台配置
    log_step "应用平台配置: $active_config"
    cp "$active_config" .config
    log_info "执行 make defconfig（验证配置合法性）..."
    make defconfig

    # 5. 编译固件
    if [[ "$ARTIFACT" == "firmware" || "$ARTIFACT" == "both" ]]; then
        log_step "开始编译固件 (线程数: $BUILD_THREADS)..."
        if make -j"$BUILD_THREADS" V=s; then
            log_info "固件编译成功，收集产物..."
            find bin/targets -name "*.bin" -o -name "*.img" 2>/dev/null \
                | while IFS= read -r f; do
                    [ -f "$f" ] && cp -v "$f" "$output_firmware/"
                done
            log_info "固件已输出: $output_firmware"
        else
            log_error "固件编译失败，请检查日志"
            return 1
        fi
    fi

    # 6. 编译软件包
    if [[ "$ARTIFACT" == "packages" || "$ARTIFACT" == "both" ]]; then
        log_step "开始编译 acctl 软件包..."
        if make package/acctl/compile V=s -j"$BUILD_THREADS"; then
            log_info "软件包编译成功，收集产物..."
            make package/index V=s
            find bin/packages -name "*.ipk" 2>/dev/null \
                | while IFS= read -r f; do
                    [ -f "$f" ] && cp -v "$f" "$output_packages/"
                done
            log_info "软件包已输出: $output_packages"
        else
            log_error "软件包编译失败，请检查日志"
            return 1
        fi
    fi

    log_info "=========================================="
    log_info "平台 $platform 编译完成 ✓"
    log_info "=========================================="
    return 0
}

# ========== 主流程 ==========
if [ -z "${PLATFORMS:-}" ]; then
    log_error "未设置 PLATFORMS 环境变量"
    log_info "用法: PLATFORMS=\"ipq40xx\" ARTIFACT=\"firmware\" ./scripts/build.sh"
    exit 1
fi

if [ -z "${ARTIFACT:-}" ]; then
    log_error "未设置 ARTIFACT 环境变量"
    exit 1
fi

log_info "编译参数: PLATFORMS=$PLATFORMS"
log_info "编译参数: ARTIFACT=$ARTIFACT"

if ! validate_configs; then
    log_error "配置校验失败，终止编译"
    exit 1
fi

FAILED=0
for platform in $PLATFORMS; do
    if [ -z "${PLATFORM_CONFIG[$platform]:-}" ]; then
        log_error "不支持的平台: $platform"
        continue
    fi

    if ! build_platform "$platform"; then
        log_error "平台 $platform 编译失败"
        FAILED=1
        # 不立即退出，支持多平台继续编译其他平台
    fi
done

echo ""
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    log_info "全部编译任务完成！"
else
    log_warn "存在编译失败的任务，请查看上方日志"
fi
echo "=========================================="
echo ""

# 展示产物摘要
if [ -d "${WORKDIR}/output/firmware" ]; then
    log_info "固件产物:"
    ls -lh "${WORKDIR}/output/firmware/" 2>/dev/null || true
fi
if [ -d "${WORKDIR}/output/packages" ]; then
    log_info "软件包产物:"
    find "${WORKDIR}/output/packages" -name "*.ipk" 2>/dev/null \
        | while IFS= read -r f; do
            echo "  $(ls -lh "$f" | awk '{print $5, $9}')"
        done
fi

[ $FAILED -eq 0 ]
