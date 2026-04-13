#!/bin/bash
# OpenWrt Build Environment Setup Script
# 用法: ./scripts/setup.sh
# 功能: 在本地 Ubuntu/Debian/macOS 机器上准备 OpenWrt 编译环境
# 注意: GitHub Actions 已预装所有依赖，无需在 CI 中运行此脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        *)          echo "unknown";;
    esac
}

# 检查并安装依赖（Linux）
install_deps_ubuntu() {
    log_info "检测到 Ubuntu/Debian，正在安装编译依赖..."

    local DEPS=(
        build-essential
        git
        libncurses-dev
        libncurses5-dev
        libssl-dev
        python3
        unzip
        zlib1g-dev
        gawk
        gettext
        baseline
        file
        gcc-multilib
        g++-multilib
        ccache
        time
    )

    # 检查是否 root
    if [ "$(id -u)" -eq 0 ]; then
        apt-get update
        apt-get install -y "${DEPS[@]}"
    else
        log_warn "检测到非 root 用户，尝试使用 sudo..."
        sudo apt-get update
        sudo apt-get install -y "${DEPS[@]}"
    fi

    log_info "依赖安装完成"
}

# 检查并安装依赖（macOS）
install_deps_macos() {
    log_info "检测到 macOS，正在安装编译依赖..."

    # 检查 Xcode Command Line Tools
    if ! command -v gcc &>/dev/null && ! command -v clang &>/dev/null; then
        log_info "安装 Xcode Command Line Tools..."
        xcode-select --install
    fi

    # 使用 Homebrew 安装依赖
    if command -v brew &>/dev/null; then
        log_info "使用 Homebrew 安装依赖..."
        brew install coreutils gcc gawk python3 gettext ccache
    else
        log_warn "Homebrew 未安装，部分依赖可能缺失"
        log_warn "安装方式: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi

    log_info "macOS 依赖检查完成"
}

# 检查必要工具
check_tools() {
    log_info "检查必要工具..."

    local MISSING=()
    for cmd in git make gcc g++ python3 python3-config; do
        if ! command -v "$cmd" &>/dev/null; then
            MISSING+=("$cmd")
        fi
    done

    if [ ${#MISSING[@]} -gt 0 ]; then
        log_error "缺少必要工具: ${MISSING[*]}"
        log_info "在 Ubuntu/Debian 上运行: sudo apt-get install ${MISSING[*]}"
        log_info "在 macOS 上使用 Homebrew 安装缺失工具"
        return 1
    fi

    log_info "必要工具检查通过 ✓"
}

# 检查磁盘空间（建议 > 30GB）
check_disk() {
    local available
    available=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | tr -d 'G')

    if [ "${available:-0}" -lt 30 ]; then
        log_warn "可用磁盘空间约 ${available}GB，建议预留 30GB 以上"
    else
        log_info "磁盘空间充足 (${available}GB) ✓"
    fi
}

# 验证项目结构
check_project_structure() {
    log_info "验证项目结构..."

    local required=(
        ".github/workflows/build.yml"
        "configs/feeds.conf"
        "scripts/build.sh"
    )

    for item in "${required[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$item" ] && [ ! -d "$PROJECT_ROOT/$item" ]; then
            log_error "缺少必要文件/目录: $item"
            return 1
        fi
    done

    # 检查平台配置
    local platform_configs=("$PROJECT_ROOT"/configs/*.config*)
    if [ ! -f "${platform_configs[0]}" ]; then
        log_warn "configs/ 目录下未找到任何 .config 文件"
        log_info "请参考 configs/*.config.placeholder 创建平台配置"
    else
        log_info "找到平台配置: ${#platform_configs[@]} 个"
    fi

    log_info "项目结构检查通过 ✓"
}

# 主流程
main() {
    echo "========================================"
    echo "  OpenWrt 编译环境初始化"
    echo "========================================"
    echo ""

    local os
    os=$(detect_os)
    log_info "操作系统: $os"

    check_tools || {
        log_error "工具检查失败，请先安装缺失依赖"
        exit 1
    }

    check_disk
    check_project_structure

    case "$os" in
        linux)
            install_deps_ubuntu
            ;;
        macos)
            install_deps_macos
            ;;
        *)
            log_warn "未知操作系统，跳过自动安装依赖"
            ;;
    esac

    echo ""
    echo "========================================"
    log_info "环境检查完成！"
    echo ""
    log_info "下一步:"
    echo "  1. 准备平台 .config 文件（见 configs/*.config.placeholder）"
    echo "  2. 修改 scripts/build.sh 中的 ACCTL_REPO 为你的实际仓库地址"
    echo "  3. 在 GitHub 上 Fork 本仓库 → Actions → OpenWrt Build → Run workflow"
    echo ""
    echo "提示: 本地编译请确保已克隆 OpenWrt 源码仓库（见 build.sh 中的 OPENWRT_REPO）"
    echo "========================================"
}

main "$@"
