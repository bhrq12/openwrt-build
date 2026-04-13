# configs 目录说明

本目录存放 OpenWrt 编译所需的平台配置文件。编译流程通过 `workflows/build.yml` 调用 `scripts/build.sh` 读取这些配置。

---

## 目录结构

```
configs/
├── README.md              # 本文档
├── ipq40xx.config         # ipq40xx 平台配置
├── x86_64.config          # x86_64 平台配置
├── bcm2711.config         # bcm2711/Raspberry Pi 4 平台配置
├── ramips-mt7621.config   # 联发科 MT7621 平台配置（如小米 AX3000T）
└── feeds.config           # 全局 feeds 扩展配置
```

---

## 平台配置（`*.config`）

### 作用

每个平台配置文件对应一个目标设备/架构。在触发编译时，通过 `dispatch.yml` 或 `build.yml` 指定平台名称，脚本会自动读取对应的 `.config` 文件并应用。

### 配置格式

OpenWrt 使用 Kconfig 格式（与 Linux 内核相同），核心行以 `CONFIG_` 开头：

```bash
# ========== 必须配置 ==========

# 目标架构（如 x86_64 / bcm2711 / ipq40xx / ramips）
CONFIG_TARGET_xxx=y

# 目标设备（具体设备型号）
CONFIG_TARGET_xxx_DEVICE_yyy=y

# ========== 可选配置 ==========

# LuCI Web 管理界面
CONFIG_PACKAGE_luci=y

# acctl 软件包（必须开启）
CONFIG_PACKAGE_luci-app-acctl=y
CONFIG_PACKAGE_acctl=y

# 常用软件包示例（取消注释启用）
# CONFIG_PACKAGE_curl=y
# CONFIG_PACKAGE_wget=y
# CONFIG_PACKAGE_openssh-sftp-server=y
# CONFIG_PACKAGE_block-mount=y          # 挂载配置
# CONFIG_PACKAGE_luci-app-wol=y          # 网络唤醒
# CONFIG_PACKAGE_luci-app-ddns=y         # 动态 DNS
# CONFIG_PACKAGE_luci-app-ssr-plus=y     # 科学上网（需自行适配）
```

### 各平台说明

| 平台 | 目标设备 | 备注 |
|------|----------|------|
| `ipq40xx.config` | 高通 IPQ40xx 系列路由器（如小米 AX3600/AX1800、Netgear R7800 等） | 主流 Wi-Fi 5/6 路由器 |
| `x86_64.config` | x86_64 架构设备（PC、软路由、虚拟机等） | 通用性强，支持最多插件 |
| `bcm2711.config` | Raspberry Pi 4 / 400 | ARM64 SBC，需 SD 卡或 USB 启动 |
| `ramips-mt7621.config` | 联发科 MT7621 设备（如小米 AX3000T、红米 AC2100、Newifi D2 等） | MTK 方案，价格便宜 |

### 如何更新配置

**方法一：本地 menuconfig（推荐）**

```bash
# 1. 克隆 OpenWrt 源码
git clone https://github.com/coolsnowwolf/lede
cd lede

# 2. 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 3. 打开图形化配置界面
make menuconfig

# 4. 选择平台和软件包后，导出配置
./scripts/diffconfig > defconfig

# 5. 复制内容到 configs/{platform}.config
cat defconfig
# 复制输出到对应配置文件

# 6. 推送到 GitHub
git add configs/
git commit -m "Update x86_64 config"
git push
```

**方法二：使用 GitHub Actions 自动导出**

1. Fork 本仓库
2. 在 GitHub Actions 中手动触发 `build.yml`，选择目标平台
3. 构建完成后，在 Actions 日志中搜索 `make diffconfig` 输出
4. 将导出的配置复制到对应的 `.config` 文件

---

## feeds.config

### 作用

此文件的内容会在编译时被追加到 OpenWrt 源码根目录的 `feeds.conf.default` 文件中。用于扩展软件包来源。

### 文件格式

```bash
# 远程软件包仓库
src-git <name> <url>[<branch>]

# 本地软件包（相对于 OpenWrt 源码目录）
src-link <name> <path>
```

### 常用示例

```bash
# ========== 扩展软件包 ==========

# Lean 的 packages 扩展（已内置，可不填）
# src-git lean_packages https://github.com/coolsnowwolf/packages

# ImmortalWrt 扩展包
# src-git immortal_packages https://github.com/immortalwrt/immortalwrt_packages

# ========== LuCI 主题 ==========

# 主题仓库（替换为你的 fork）
# src-git luci_theme https://github.com/你的用户名/luci-theme-argon

# ========== 本地软件包 ==========

# 链接本地 package 目录（相对于 OpenWrt 源码）
# src-link mypkgs ../mypackages

# 链接 acctl 软件包（如果不用 workflow 自动 clone）
# src-git acctl https://github.com/bhrq12/acctl
```

### 注意事项

- 此文件追加到 `feeds.conf.default`，不会覆盖默认的 feeds 源
- `src-git` 格式：`src-git 名称 Git仓库地址[分支]`，分支用 `^<tag>` 或 `:master` 指定
- `src-link` 使用相对路径，相对于 OpenWrt 源码根目录
- 注释用 `#` 开头，空白行会被忽略

---

## 工具链缓存与配置的关系

**重要**：工具链缓存的 Hash 基于 `tools/` 和 `toolchain/` 目录的 commit，与平台配置无关。

- **修改 `.config` 文件** → 只重新编译固件，工具链缓存不变
- **修改 feeds.config** → 重新编译固件，工具链缓存不变
- **更新 OpenWrt 源码版本** → 工具链 Hash 变化 → 重建工具链
- **源码的 tools/toolchain 目录有更新** → 工具链 Hash 变化 → 重建工具链

---

## 添加新平台

1. 在 `configs/` 目录下创建 `{platform}.config` 文件
2. 参考现有配置，用 `menuconfig` 导出正确的 `CONFIG_TARGET_*` 和 `CONFIG_TARGET_*_DEVICE_*` 行
3. 如需扩展 feeds，在 `feeds.config` 中添加对应行
4. 如需在 `dispatch.yml` 的下拉选项中支持新平台，在 `build.yml` 和 `dispatch.yml` 的 options 中添加

```bash
# 示例：添加 Rockchip ARMv8 平台
# 在 configs/rockchip-armv8.config 中添加：
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s=y
```

---

## 常见问题

**Q: 编译失败提示 "不可用的配置"**
A: 检查 `.config` 文件中的 `CONFIG_TARGET_*` 是否与平台名称一致（如 `ipq40xx.config` 需包含 `CONFIG_TARGET_ipq40xx=y`）。

**Q: 找不到某个软件包**
A: 该软件包可能未在 feeds 中注册。尝试在 `feeds.config` 中添加对应仓库，或将软件包放入 `package/` 目录后使用 `src-link` 引用。

**Q: 工具链缓存命中率低**
A: 每次源码分支/tag 变化，或源码的 `tools/toolchain` 目录有更新，都会导致 Hash 变化。这是正常行为，确保编译出的固件与源码版本一致。
