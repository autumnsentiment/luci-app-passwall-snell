# Changelog

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
