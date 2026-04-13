# OpenWrt 云编译配置仓库

> 纯配置驱动，不存放源码。交互式选择平台/版本/工具链策略，手动触发编译。

---

## 功能特性

- 🔧 **多平台支持**: ipq40xx / x86_64 / bcm2711 / ramips-mt7621 / 全平台
- 📦 **产物可选**: 固件 (.bin) / 软件包 (.ipk) / 两者都编译
- 🔒 **手动触发**: workflow_dispatch 安全可控，无自动构建
- 📁 **配置分离**: 每个平台独立 .config，方便按设备定制
- ⚡ **工具链缓存**: 首次编译后自动缓存到 Releases，后续编译节省 50%+ 时间
- 🔀 **多平台并行**: 一次选择多个平台，并行编译

---

## 工作流架构

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                               GitHub Actions                                   │
│                                                                               │
│  ┌────────────────┐       workflow_call                                      │
│  │  dispatch.yml  │ ───────────────────────────────────────────┐              │
│  │  (交互入口)     │                                          ▼              │
│  │                │      ┌────────────────────────────────────────────────┐   │
│  │  交互选项:      │      │              build.yml (主工作流)               │   │
│  │  - 平台多选     │      │              (基础编译流程)                     │   │
│  │  - 源码版本     │      │                                                │   │
│  │  - 工具链策略   │      │  1. 检查/下载工具链缓存                          │   │
│  │  - 产物类型     │      │  2. 克隆/更新 OpenWrt 源码                     │   │
│  │  - 自定义配置   │      │  3. 添加 acctl 软件包                          │   │
│  └────────────────┘      │  4. 应用 feeds 配置                             │   │
│                           │  5. 应用平台配置                                 │   │
│                           │  6. 编译固件/软件包                              │   │
│                           │  7. 上传产物到 Artifacts                        │   │
│                           └────────────────────────────────────────────────┘   │
│                                                                               │
│                           toolchain.yml (可独立触发)                         │
│                           (工具链编译 + 上传 Releases)                        │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 工作流说明

| 工作流 | 触发方式 | 用途 |
|--------|----------|------|
| **dispatch.yml** | Actions 页面手动触发 | **主入口**: 交互式选择平台/版本，一次触发多个并行编译 |
| **build.yml** | 被 dispatch 调用 / 独立手动触发 | 基础编译流程，支持工具链缓存 |
| **toolchain.yml** | 独立手动触发 | 预编译工具链，上传到 Releases 缓存 |
| **cache.yml** | 被其他工作流 workflow_call | 工具链缓存管理（可复用模块）|

---

## 快速开始

### 1. Fork 本仓库

### 2. 修改 acctl 地址（可选）

编辑 `scripts/build.sh`，修改以下变量：

```bash
ACCTL_REPO="https://github.com/你的用户名/acctl"
ACCTL_BRANCH="main"
```

### 3. 添加平台配置

每个平台需要一个 `.config` 文件（从现有 OpenWrt 编译环境导出）：

```bash
# 在本地 OpenWrt 编译环境中
make menuconfig  # 选择平台 + 软件包
./scripts/diffconfig > configs/ipq40xx.config
```

**平台对应配置文件名:**

| 平台 | 配置文件 |
|------|----------|
| ipq40xx | `configs/ipq40xx.config` |
| x86_64 | `configs/x86_64.config` |
| bcm2711 | `configs/bcm2711.config` |
| ramips-mt7621 | `configs/ramips-mt7621.config` |

### 4. 触发编译

**方式 A: 使用 dispatch 工作流（推荐）**

1. 进入本仓库 → **Actions** → **OpenWrt Dispatch**
2. 点击 **Run workflow**
3. 填写选项：
   - **Target platforms**: 输入平台名，多个用空格分隔（如 `ipq40xx x86_64`）
   - **OpenWrt source**: 源码版本（`master` / `v23.05.3` / commit hash）
   - **Build artifact**: 产物类型（firmware / packages / both）
   - **Toolchain strategy**: 工具链策略
   - 展开 **Advanced options** 可设置自定义仓库地址等
4. 点击 **Run workflow**

**方式 B: 直接触发 build 工作流**

1. **Actions** → **OpenWrt Build** → **Run workflow**
2. 选择单个平台和产物类型

### 5. 下载产物

编译完成后在 workflow run 页面下载：
- 固件: `openwrt-firmware-<平台>-*.zip`
- 软件包: `openwrt-packages-<平台>-*.zip`

---

## 交互选项详解

### dispatch.yml 选项

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `platforms` | 字符串（空格分隔） | `ipq40xx` | 目标平台，支持多选，如 `ipq40xx x86_64` |
| `openwrt_version` | 字符串 | `master` | 源码版本，支持分支/tag/commit hash |
| `artifact_type` | 选择 | `firmware` | 产物类型: firmware / packages / both |
| `toolchain_strategy` | 选择 | `use_cache` | 工具链策略（见下方说明）|
| `advanced_options` | 布尔 | `false` | 展开高级选项 |
| `custom_openwrt_repo` | 字符串 | 空 | 自定义 OpenWrt 仓库 URL |
| `custom_acctl_repo` | 字符串 | 空 | 自定义 acctl 仓库 URL |
| `custom_acctl_branch` | 字符串 | `main` | acctl 分支/tag |
| `custom_config_url` | 字符串 | 空 | 自定义 .config 的原始文件 URL |

### 工具链策略

| 策略 | 说明 |
|------|------|
| `use_cache` | 优先使用 Releases 中的缓存工具链，没有则从源码编译 |
| `force_rebuild` | 强制重新编译工具链，并更新 Releases 缓存 |
| `skip_toolchain` | 跳过工具链缓存，每次都从源码完整编译 |

---

## 工具链缓存机制

### 工作原理

```
首次编译:
┌─────────────┐    无缓存     ┌─────────────┐
│ build.yml   │ ────────────▶ │ 编译工具链   │
│             │               │ (30-60分钟)  │
└─────────────┘               └──────┬──────┘
                                     │
                              上传到 Releases
                                     │
                                     ▼
                              toolchain-{platform}-{commit}.tar.zst
                                     
第二次编译:
┌─────────────┐    有缓存     ┌─────────────┐
│ build.yml   │ ────────────▶ │ 下载+解压    │
│             │   (跳过)       │ (跳过)       │
└─────────────┘               └─────────────┘
```

### 缓存键格式

```
toolchain-{platform}-{commit-hash}
```

- `platform`: 平台名，如 `ipq40xx`
- `commit-hash`: OpenWrt 源码的 commit hash（前7位）

### 预热缓存

在正式编译前手动预热工具链缓存：

1. **Actions** → **Toolchain Build** → **Run workflow**
2. 选择平台和源码版本
3. 勾选 **Force rebuild** 确保重新编译
4. 编译完成后工具链会被上传到 Releases

---

## 平台说明

| 平台 | 架构 | 适用设备 |
|------|------|----------|
| `ipq40xx` | ARM Cortex-A7 | 小米 CR660x/AX1800/AX3600、TP-Link XDR/XE 系列等 |
| `x86_64` | x86_64 | 任意 x86_64 设备、软路由 |
| `bcm2711` | ARM Cortex-A72 | 树莓派 4B |
| `ramips-mt7621` | MIPS | 红米 AC2100、京东云系列等 |

---

## 目录结构

```
.
├── .github/
│   └── workflows/
│       ├── dispatch.yml     # 调度工作流（交互入口）★★★ 主入口
│       ├── build.yml         # 主编译工作流（基础流程）
│       ├── toolchain.yml     # 工具链编译（独立/预热用）
│       └── cache.yml         # 工具链缓存管理（可复用模块）
├── configs/
│   ├── feeds.conf           # 自定义 feeds 配置
│   ├── ipq40xx.config       # ipq40xx 平台配置
│   ├── x86_64.config        # x86_64 平台配置
│   ├── bcm2711.config       # bcm2711 平台配置
│   └── ramips-mt7621.config # ramips-mt7621 平台配置
├── scripts/
│   ├── build.sh             # 编译脚本（主逻辑）
│   └── setup.sh              # 本地环境初始化
└── README.md
```

---

## CI 环境

- **运行环境**: Ubuntu 22.04
- **编译线程**: 默认自动检测 CPU 核心数
- **超时时间**: 360 分钟（6小时）
- **产物保留**: 14 天
- **并发控制**: 相同平台+版本的任务会取消旧任务

---

## 常见问题

**Q: 编译失败怎么办？**  
A: 点击对应 workflow run → 查看日志，定位报错信息。常见问题：
- `.config` 缺少必要依赖
- feeds 失效
- 源码版本与配置不兼容

**Q: 如何加速编译？**  
A: 
1. 首次编译后工具链会被缓存，后续编译会自动使用
2. 使用 `force_rebuild` 策略可以更新到最新的工具链
3. 多平台并行：一次选择多个平台，GitHub 会并行编译

**Q: 如何自定义 OpenWrt 仓库？**  
A: 在 dispatch 工作流的 **Advanced options** 中填写 `Custom OpenWrt Repo URL`

**Q: 工具链缓存占用多少空间？**  
A: 每个平台的工具链约 500MB-1GB，存放在 Releases 中

**Q: 多个平台一起编译时如何查看进度？**  
A: 进入 **Actions** 页面，点击具体的 workflow run，每个平台是单独的 job

---

## 添加新平台

1. 在 `configs/` 创建 `<平台>.config`（从 menuconfig 导出）
2. 在 `scripts/build.sh` 的 `PLATFORM_TARGET` 关联数组添加映射
3. 在 `dispatch.yml` 和 `toolchain.yml` 的 `platform` 选项添加新平台
4. 提交即可

---

## 许可证

MIT
