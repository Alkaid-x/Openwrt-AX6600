# 京东云雅典娜 AX6600 定制固件构建记录

## 设备目标
- 京东云雅典娜 AX6600 / RE-CS-02
- OpenWrt target：`qualcommax/ipq60xx`
- 设备 profile：`jdcloud_re-cs-02`
- 上游构建项目：`https://github.com/ones20250/Openwrt-AX6600`

## 本地配置内容
此构建配置已将 PLUS profile 增加以下包意图：
- `dae`、`daed`、`luci-app-daed`
- `honk`、`luci-app-honk`
- `nikki`、`luci-app-nikki`、`mihomo-meta`
- Vantage、7dollar、Carbon 三款 LuCI 主题
- 原项目 PLUS 默认的分区扩容工具 `luci-app-partexp`

其中 dae/honk、daed、Nikki 的源码入口已写入 `Scripts/Packages.sh`，按 feed 包目录提取。主题各自从用户指定仓库拉取。

## 分区空间说明
用户已将目标改为雅典娜 rootfs 2GB 方案。该容量由设备 eMMC GPT 分区布局决定，而不是编译选项；上游刷机文档列出 `gpt-JDC_AX6600_Athena_dual-boot_rootfs2048M_no-last-partition.bin`，并记录校验值 `9a921ca450e8a5aebd218b7fd1d1c5a8`。2GB rootfs 本身包括固件与 overlay，可用插件空间会扣除固件占用。固件编译与 GPT/刷分区表是两个独立步骤，本次工作流只构建固件，不会写设备分区表。使用 2048MB GPT 需确认设备 eMMC 容量与该布局相符；上游文档指出该布局总扇区数超过4GB，推荐8GB及以上 eMMC。

## 尚待处理的软件包
“openbox”当前检索到的对应项目是 Open-Box（程序发行包与安装器）；本地 GitHub Actions 工作流不会下载非源码发行物，也未集成该运行时包。
“Nailink”未检索到可确认的 OpenWrt 包仓库/包名，暂未配置为 Kconfig 包。

## 构建环境与执行状态
本机当前为 Windows/MSYS，未安装 WSL Linux 发行版，缺少 Linux OpenWrt 构建工具链。因此本地无法完成固件 make；待在 GitHub 上 fork/push 此项目并通过 GitHub Actions 编译。已修改的是工作区本地克隆，尚未推送到任何远端，也未启动任何云端 workflow。
