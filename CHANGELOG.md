# Changelog

## v1.0.2

- 节点表格新增一键切换操作，点击后直接保存活动节点并重启 Bridge 与 PassWall。

## v1.0.1

- 修复旧版 LuCI 延后提交配置且不执行应用后钩子，导致节点切换不生效的问题。
- 节点管理改为紧凑表格，仅显示名称、服务器、端口、协议和混淆摘要。
- 新增独立节点编辑页，点击对应节点后才显示完整配置。

## v1.0.0

- 新增 LuCI PassWall Snell Bridge 配置页面。
- 支持 Snell v1 至 v5、ShadowTLS v1 至 v3。
- 支持添加、删除、排序和切换多个 Snell 节点。
- 自动将旧版单节点配置迁移到节点列表。
- 默认启用 Snell v4 UDP、连接复用和 TCP Fast Open。
- 将 Mihomo v1.19.28 下载到 RAM 并校验固定 SHA-256。
- 在 `127.0.0.1:17890` 提供本地 SOCKS5/mixed 入口。
- 新增 procd 托管、开机启动和配置变更重载。
- 新增 PassWall IPv6 TProxy 与 AAAA 过滤联动。
- 新增 LAN 本地服务 SOCKS5 接入及 WAN 阻断说明。
- 新增 OpenWrt Makefile、独立 IPK 构建脚本和 GitHub Actions 构建检查。
