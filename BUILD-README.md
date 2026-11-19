# 京东云雅典娜 AX6600 定制固件构建记录

## 设备目标
- 京东云雅典娜 AX6600 / RE-CS-02
- OpenWrt target：`qualcommax/ipq60xx`
- 设备 profile：`jdcloud_re-cs-02`
- 上游构建项目：`https://github.com/ones20250/Openwrt-AX6600`

## 定制内容（PLUS）
- `dae`、`honk`、`luci-app-honk`、`nikki`、`luci-app-nikki`、`mihomo-meta`
- NaiLink 0.6.90 (`daed-router` / `luci-app-daed-router`) 取代旧 `daed` / `luci-app-daed`：两者上游包元数据明确互斥，NaiLink 是 Daed 后继并延用其服务及配置路径。
- Vantage、7dollar、Carbon 三款 LuCI 主题；7dollar 构建时保留 `.ut` 源模板，避免主机侧编译器解析其目标端模块 `luci.7dollar`。
- 原 PLUS 分区扩容工具 `luci-app-partexp`。
- Open-Box 通过单独的 `openbox-athena-install` 命令调用官方安装脚本；专有运行时由官方源在设备侧安装，不打包进固件。

NaiLink 官方只为 ARM64 发布 `daed-router` 运行包，LuCI 包没有单独发版（其 `build.py` 仅在 x86_64 目标下产出 LuCI 包）。因此构建时用官方 `daed-openwrt-source.tar.gz` 提供两个包的配方，运行所需的三个静态二进制（`daed`、`btf-probe`、`luci-proxy`）取自官方 `daed-router-0.6.90-aarch64_cortex-a53.ipk`，并按官方 `ipk-arm64.tsv` 校验 SHA256 后才使用。Open-Box 完整程序不由本固件重新分发。

## 分区空间说明
用户已将目标改为雅典娜 rootfs 2GB 方案。该容量由设备 eMMC GPT 分区布局决定，而不是编译选项；上游刷机文档列出 `gpt-JDC_AX6600_Athena_dual-boot_rootfs2048M_no-last-partition.bin`，并记录校验值 `9a921ca450e8a5aebd218b7fd1d1c5a8`。2GB rootfs 本身包括固件与 overlay，可用插件空间会扣除固件占用。固件编译与 GPT/刷分区表是两个独立步骤，本次工作流只构建固件，不会写设备分区表。使用 2048MB GPT 需确认设备 eMMC 容量与该布局相符；上游文档指出该布局总扇区数超过4GB，推荐8GB及以上 eMMC。

## 包集成说明
NaiLink 官方包要求 ARM64/Linux 5.17+、BPF/BTF 支持，并与 `daed`/`luci-app-daed` 冲突，因此本配置使用 NaiLink 后继包，而不是旧 Daed 包。Open-Box 上游以官方安装器/发行包提供核心程序；固件只集成官方安装器入口，不包含其专有运行时。首次部署 Open-Box 仍需路由器联网下载官方包。

## 构建环境与执行状态
本机 Windows/MSYS 不具备 Linux OpenWrt 构建环境，使用 GitHub Actions 云构建。固件镜像构建与 GPT 分区表刷写是两个步骤；此 workflow 只生成固件，不会刷写设备。
