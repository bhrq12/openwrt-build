#!/bin/bash
# OpenWrt Build Script
# 支持 workflow_call 和 workflow_dispatch 两种调用方式
#
# 环境变量（必需）:
#   PLATFORMS        - 空格分隔的平台列表，如 "ipq40xx x86_64"
#   ARTIFACT         - 编译产物类型: firmware | packages | both
#
# 环境变量（可选）:
#   OPENWRT_REPO     - OpenWrt 源码仓库地址
#   OPENWRT_VERSION  - 源码分支/tag/commit
#   OPENWRT_BRANCH   - 同 OPENWRT_VERSION（兼容旧名称）
#   ACCTL_REPO       - acctl 软件包仓库
#   ACCTL_BRANCH     - acctl 分支
#   TOOLCHAIN_DIR    - 已缓存的工具链目录路径
#   CUSTOM_CONFIG    - 自定义配置文件路径
#   BUILD_THREADS    - 编译线程数，默认 $(nproc)

set -euo pipefail

# ========== 配置区 ==========
OPENWRT_REPO="${OPENWRT_REPO:-https://github.com/coolsnowwolf/lede}"
OPENWRT_VERSION="${OPENWRT_VERSION:-${OPENWRT_BRANCH:-master}}"
ACCTL_REPO="${ACCTL_REPO:-https://github.com/bhrq12/acctl}"
ACCTL_BRANCH="${ACCTL_BRANCH:-main}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

# 允许被覆盖的环境变量（优先级：环境变量 > 上方默认值）
if [[ -n "${CUSTOM_OPENWRT_REPO:-}" ]]; then
    OPENWRT_REPO="$CUSTOM_OPENWRT_REPO"
fi
if [[ -n "${CUSTOM_ACCTL_REPO:-}" ]]; then
    ACCTL_REPO="$CUSTOM_ACCTL_REPO"
fi
if [[ -n "${CUSTOM_ACCTL_BRANCH:-}" ]]; then
    ACCTL_BRANCH="$CUSTOM_ACCTL_BRANCH"
fi

# ========== 颜色输出 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERR]${NC}  $1"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${MAGENTA}[DBG]${NC}  $1" || true; }
log_header(){ echo ""; echo -e "${BOLD}${BLUE}========== $1 ==========${NC}"; }

# ========== 初始化 ==========
WORKDIR="${GITHUB_WORKSPACE:-${HOME}/openwrt-build}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_REPO_DIR="${WORKSPACE:-${SCRIPT_DIR}/..}"

log_header "OpenWrt Build Script"
log_info "版本: 2.0 (支持工具链缓存)"
log_info "工作目录: ${WORKDIR}"
log_info "编译线程: ${BUILD_THREADS}"

# 初始化输出目录
mkdir -p "${WORKDIR}"/{output/firmware,output/packages,logs}

# ========== 平台配置映射 ==========
declare -A PLATFORM_TARGET
PLATFORM_TARGET[ipq40xx]="ipq40xx/generic"
PLATFORM_TARGET[x86_64]="x86/64"
PLATFORM_TARGET[bcm2711]="bcm2711/ bcm2711/CACHE_DIR"
PLATFORM_TARGET[ramips-mt7621]="ramips/mt7621"

# ========== 配置校验 ==========
validate_configs() {
    local missing=0
    for platform in $PLATFORMS; do
        local cfg="${CONFIG_REPO_DIR}/configs/${platform}.config"
        local placeholder="${CONFIG_REPO_DIR}/configs/${platform}.config.placeholder"
        
        if [[ -f "$cfg" ]]; then
            log_info "配置就绪: ${cfg}"
        elif [[ -f "$placeholder" ]]; then
            log_warn "使用 placeholder 配置: ${placeholder}"
            log_warn "建议替换为实际 .config 文件以获得完整功能"
        else
            log_error "缺失配置: configs/${platform}.config 或 .placeholder"
            missing=1
        fi
    done
    
    [[ $missing -eq 1 ]] && return 1 || return 0
}

# ========== 工具链恢复 ==========
restore_toolchain() {
    log_step "检查工具链缓存..."
    
    if [[ -z "${TOOLCHAIN_DIR:-}" ]] || [[ ! -d "$TOOLCHAIN_DIR" ]]; then
        log_info "无工具链缓存，将从源码编译"
        return 1
    fi
    
    log_info "发现工具链缓存: ${TOOLCHAIN_DIR}"
    echo "$(ls -lh "$TOOLCHAIN_DIR" 2>/dev/null | head -5)"
    return 0
}

# ========== 源码获取 ==========
get_source() {
    local platform_dir="$1"
    
    cd "$platform_dir"
    
    if [[ ! -d ".git" ]]; then
        log_step "克隆源码: ${OPENWRT_REPO} (${OPENWRT_VERSION})"
        git clone --depth=1 -b "$OPENWRT_VERSION" "$OPENWRT_REPO" . || {
            log_error "源码克隆失败"
            return 1
        }
        log_info "源码克隆完成"
    else
        log_step "更新源码..."
        git pull --ff-only origin "$OPENWRT_VERSION" || {
            log_warn "源码更新失败，使用现有版本继续"
        }
    fi
    
    # 记录源码版本信息
    {
        echo "OPENWRT_REPO=$OPENWRT_REPO"
        echo "OPENWRT_VERSION=$OPENWRT_VERSION"
        echo "COMMIT=$(git rev-parse HEAD 2>/dev/null || echo 'N/A')"
        echo "DATE=$(date -Iseconds)"
    } > "${WORKDIR}/logs/source_info.txt"
}

# ========== 应用 feeds ==========
apply_feeds() {
    log_step "应用 feeds 配置..."
    
    local feeds_conf="${CONFIG_REPO_DIR}/configs/feeds.conf"
    
    if [[ -f "$feeds_conf" ]]; then
        log_info "检测到自定义 feeds.conf"
        cat "$feeds_conf" >> feeds.conf.default
        ./scripts/feeds update -a 2>&1 | tee -a "${WORKDIR}/logs/feeds_update.log" || {
            log_warn "feeds update 存在非致命警告"
        }
        ./scripts/feeds install -a 2>&1 | tee -a "${WORKDIR}/logs/feeds_install.log" || {
            log_warn "feeds install 存在非致命警告"
        }
    else
        log_info "使用默认 feeds"
    fi
}

# ========== 应用配置 ==========
apply_config() {
    local platform="$1"
    local config_src="${CONFIG_REPO_DIR}/configs/${platform}.config"
    local config_placeholder="${CONFIG_REPO_DIR}/configs/${platform}.config.placeholder"
    
    log_step "应用平台配置: ${platform}"
    
    # 优先级: CUSTOM_CONFIG > .config > .placeholder
    if [[ -n "${CUSTOM_CONFIG:-}" ]] && [[ -f "$CUSTOM_CONFIG" ]]; then
        log_info "使用自定义配置: ${CUSTOM_CONFIG}"
        cp "$CUSTOM_CONFIG" .config
    elif [[ -f "$config_src" ]]; then
        cp "$config_src" .config
    elif [[ -f "$config_placeholder" ]]; then
        log_warn "使用 placeholder 配置"
        cp "$config_placeholder" .config
    else
        log_error "无可用配置文件"
        return 1
    fi
    
    # 验证配置
    if ! make defconfig > /dev/null 2>&1; then
        log_error "配置验证失败 (make defconfig)"
        make defconfig 2>&1 | tail -20
        return 1
    fi
    
    log_info "配置验证通过"
}

# ========== 添加 acctl ==========
add_acctl() {
    log_step "添加 acctl 软件包..."
    
    if [[ -d "package/acctl" ]]; then
        log_info "acctl 已存在，跳过"
        return 0
    fi
    
    if git clone --depth=1 -b "$ACCTL_BRANCH" "$ACCTL_REPO" package/acctl 2>&1 | tee -a "${WORKDIR}/logs/acctl_clone.log"; then
        log_info "acctl 添加成功"
    else
        log_warn "acctl 克隆失败，继续编译（acctl 可能不在范围内）"
    fi
}

# ========== 恢复工具链 ==========
inject_toolchain() {
    local platform_dir="$1"
    
    if [[ -z "${TOOLCHAIN_DIR:-}" ]] || [[ ! -d "$TOOLCHAIN_DIR" ]]; then
        return 1
    fi
    
    log_step "恢复工具链缓存..."
    
    cd "$platform_dir"
    
    # 检查是否已有 staging_dir
    if [[ -d "staging_dir" ]]; then
        log_info "备份现有 staging_dir"
        mv staging_dir staging_dir.fresh_build
    fi
    
    # 从缓存恢复
    cp -r "$TOOLCHAIN_DIR" staging_dir
    log_info "工具链已恢复: $(du -sh staging_dir | cut -f1)"
}

# ========== 编译固件 ==========
build_firmware() {
    local platform_dir="$1"
    local output_firmware="${WORKDIR}/output/firmware"
    
    cd "$platform_dir"
    
    log_step "开始编译固件 (线程: ${BUILD_THREADS})"
    
    local log_file="${WORKDIR}/logs/build-${PLATFORM}-firmware.log"
    
    if make -j"${BUILD_THREADS}" V=s 2>&1 | tee "$log_file"; then
        log_info "固件编译成功"
        
        # 收集产物
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" -o -name "*.img.gz" \) 2>/dev/null | while read -r f; do
            if [[ -f "$f" ]]; then
                local fname="$(basename "$f")"
                cp -v "$f" "${output_firmware}/${fname}"
                log_info "  → ${fname} ($(du -h "$f" | cut -f1))"
            fi
        done
        
        return 0
    else
        log_error "固件编译失败，详见: ${log_file}"
        return 1
    fi
}

# ========== 编译软件包 ==========
build_packages() {
    local platform_dir="$1"
    local output_packages="${WORKDIR}/output/packages"
    
    cd "$platform_dir"
    
    log_step "编译软件包 (线程: ${BUILD_THREADS})"
    
    local log_file="${WORKDIR}/logs/build-${PLATFORM}-packages.log"
    
    # 编译 acctl 包
    if [[ -d "package/acctl" ]]; then
        if make package/acctl/compile V=s -j"${BUILD_THREADS}" 2>&1 | tee "$log_file"; then
            log_info "acctl 编译成功"
            
            # 收集产物
            find bin/packages -type f -name "*.ipk" 2>/dev/null | while read -r f; do
                if [[ -f "$f" ]]; then
                    local fname="$(basename "$f")"
                    mkdir -p "${output_packages}"
                    cp -v "$f" "${output_packages}/${fname}"
                fi
            done
            
            # 生成包索引
            make package/index V=s || true
        else
            log_warn "acctl 编译失败"
            return 1
        fi
    else
        log_warn "acctl 不存在，跳过包编译"
    fi
    
    return 0
}

# ========== 单平台编译 ==========
build_platform() {
    local platform="$1"
    local start_time=$(date +%s)
    
    log_header "编译平台: ${platform}"
    
    local platform_dir="${WORKDIR}/build-${platform}"
    local output_firmware="${WORKDIR}/output/firmware"
    local output_packages="${WORKDIR}/output/packages"
    
    mkdir -p "$platform_dir" "$output_firmware" "$output_packages"
    
    # 1. 获取源码
    get_source "$platform_dir" || return 1
    
    # 2. 尝试恢复工具链
    if [[ -n "${TOOLCHAIN_DIR:-}" ]]; then
        inject_toolchain "$platform_dir"
    fi
    
    # 3. 应用配置
    apply_config "$platform" || return 1
    
    # 4. 添加 acctl
    add_acctl
    
    # 5. 应用 feeds
    apply_feeds
    
    # 6. 编译
    local failed=0
    
    if [[ "$ARTIFACT" == "firmware" || "$ARTIFACT" == "both" ]]; then
        build_firmware "$platform_dir" || failed=1
    fi
    
    if [[ "$ARTIFACT" == "packages" || "$ARTIFACT" == "both" ]]; then
        build_packages "$platform_dir" || failed=1
    fi
    
    # 7. 清理（保留下次复用）
    # 不清理源码，下次可用增量更新
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log_header "平台 ${platform} 完成"
    log_info "耗时: ${minutes}m ${seconds}s"
    
    return $failed
}

# ========== 产物摘要 ==========
show_summary() {
    log_header "Build Summary"
    
    echo ""
    echo "固件产物:"
    if [[ -d "${WORKDIR}/output/firmware" ]]; then
        find "${WORKDIR}/output/firmware" -type f | while read -r f; do
            echo "  $(du -h "$f" | cut -f1)  $(basename "$f")"
        done
    else
        echo "  (无固件产物)"
    fi
    
    echo ""
    echo "软件包产物:"
    if [[ -d "${WORKDIR}/output/packages" ]]; then
        find "${WORKDIR}/output/packages" -type f -name "*.ipk" | while read -r f; do
            echo "  $(du -h "$f" | cut -f1)  $(basename "$f")"
        done
    else
        echo "  (无软件包产物)"
    fi
    
    echo ""
    echo "编译参数:"
    echo "  平台列表: $PLATFORMS"
    echo "  产物类型: $ARTIFACT"
    echo "  OpenWrt:  $OPENWRT_REPO @ $OPENWRT_VERSION"
    echo "  acctl:    $ACCTL_REPO @ $ACCTL_BRANCH"
    echo "  线程数:   $BUILD_THREADS"
}

# ========== 主流程 ==========
main() {
    # 参数校验
    if [[ -z "${PLATFORMS:-}" ]]; then
        log_error "未设置 PLATFORMS 环境变量"
        echo ""
        echo "用法示例:"
        echo "  PLATFORMS='ipq40xx x86_64' ARTIFACT='firmware' ./scripts/build.sh"
        exit 1
    fi
    
    if [[ -z "${ARTIFACT:-}" ]]; then
        log_error "未设置 ARTIFACT 环境变量"
        exit 1
    fi
    
    log_info "========== 编译参数 =========="
    log_info "平台列表: ${PLATFORMS}"
    log_info "产物类型: ${ARTIFACT}"
    log_info "OpenWrt:  ${OPENWRT_REPO}"
    log_info "版本:     ${OPENWRT_VERSION}"
    log_info "acctl:    ${ACCTL_REPO} @ ${ACCTL_BRANCH}"
    log_info "工具链:   ${TOOLCHAIN_DIR:-无缓存}"
    log_info "自定义配置: ${CUSTOM_CONFIG:-无}"
    log_info "==============================="
    
    # 校验配置
    if ! validate_configs; then
        log_error "配置校验失败"
        exit 1
    fi
    
    # 尝试恢复工具链
    restore_toolchain
    
    # 编译各平台
    local failed_platforms=""
    local success_count=0
    local fail_count=0
    
    for platform in $PLATFORMS; do
        [[ -z "$platform" ]] && continue
        
        PLATFORM="$platform"
        
        if build_platform "$platform"; then
            ((success_count++))
        else
            ((fail_count++))
            failed_platforms="${failed_platforms} ${platform}"
        fi
    done
    
    # 产物摘要
    show_summary
    
    # 最终退出码
    log_header "Build Result"
    if [[ $fail_count -eq 0 ]]; then
        log_info "全部 ${success_count} 个平台编译成功 ✓"
        exit 0
    else
        log_error "${fail_count} 个平台编译失败:${failed_platforms}"
        log_warn "${success_count} 个平台编译成功"
        exit 1
    fi
}

# 执行
main "$@"
