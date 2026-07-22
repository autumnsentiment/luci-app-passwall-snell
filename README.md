# luci-app-passwall-snell

将 Mihomo 作为独立 Snell 客户端运行在 OpenWrt RAM 中，并在
`127.0.0.1:17890` 提供 SOCKS5/mixed 入口给 PassWall 使用。

该插件适用于 PassWall 本身不直接支持所需 Snell + ShadowTLS 组合的场景。
Mihomo 核心不会写入 Overlay，而是在每次启动时下载到 `/tmp`，通过固定
SHA-256 校验后运行。

## 功能

- Snell v1 至 v5 配置界面，推荐使用 Snell v4。
- 可添加、删除、排序多个 Snell 节点，并选择当前运行节点。
- ShadowTLS v1 至 v3、HTTP 和 TLS 混淆。
- Snell v4 UDP-over-TCP。
- 连接复用与 TCP Fast Open。
- LuCI 配置入口：`服务 -> PassWall Snell Bridge`。
- procd 进程托管、异常自动拉起和开机启动。
- 自动联动 PassWall IPv6 TProxy 与 AAAA 过滤设置。
- Mihomo 固定版本、固定下载地址和 SHA-256 校验。
- 配置文件在系统升级时保留。

## 数据流

```text
LAN 客户端
   -> PassWall REDIRECT/TPROXY
   -> V2Ray SOCKS 出站节点 SnV4Xray
   -> 127.0.0.1:17890
   -> Mihomo Snell v4 + ShadowTLS
   -> Snell 服务端
```

## 兼容性

`v1.0.3` 已验证环境：

- ImmortalWrt/OpenWrt 21.02 系列。
- 传统 Lua LuCI。
- PassWall 4.68。
- `aarch64/arm64`。
- Mihomo Meta `v1.19.28`。

当前 Release 仅内置 ARM64 Mihomo 下载地址和校验值。其他架构安装包虽然
可以被 `opkg` 接受，但服务会明确拒绝启动。

路由器建议至少有 128 MiB 可用 RAM。Mihomo 解压后约占用 43 MiB RAM，
但不会占用 Overlay。

## 依赖

- `luci-base`
- `luci-app-passwall`
- `curl`
- `ca-bundle`
- BusyBox `gzip`、`sha256sum`
- `/usr/share/libubox/jshn.sh`

Release IPK 会通过 `opkg` 检查前四项依赖。

## 从 Release 安装

从 Releases 下载：

```text
luci-app-passwall-snell_1.0.3-1_all.ipk
SHA256SUMS
```

校验并上传：

```sh
sha256sum -c SHA256SUMS
scp -O luci-app-passwall-snell_1.0.3-1_all.ipk root@192.168.1.1:/tmp/
```

安装：

```sh
ssh root@192.168.1.1
opkg install /tmp/luci-app-passwall-snell_1.0.3-1_all.ipk
```

安装脚本只启用开机启动，不会在配置为空时启动 Bridge。

如 LuCI 菜单没有立即出现：

```sh
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd restart
```

## LuCI 配置

打开：

```text
服务 -> PassWall Snell Bridge
```

或直接访问：

```text
http://路由器地址/cgi-bin/luci/admin/services/passwall_snell
```

填写：

- `Enable`：启用 Bridge。
- `Active node`：选择节点后点击同区域的 `Activate`，立即保存并重启 Bridge 与 PassWall。
- `Snell nodes`：以表格显示节点摘要，可添加、删除或排序节点。
- `Edit`：点击对应节点的编辑按钮后，才显示该节点的完整配置。
- `Name`：节点显示名称。
- `Server`：Snell 服务端 IP 或域名。
- `Port`：Snell 服务端端口。
- `PSK`：Snell 密钥。
- `Protocol version`：推荐 `Snell v4`。
- `UDP`：启用 UDP-over-TCP。
- `Connection reuse`：建议开启。
- `TCP Fast Open`：服务端和系统支持时开启。
- `Obfuscation`：ShadowTLS 节点选择 `ShadowTLS`。
- `ShadowTLS password`：ShadowTLS 密码。
- `ShadowTLS SNI`：伪装域名。
- `ShadowTLS version`：通常使用 v3。
- `IPv6 proxy`：仅在 Snell 服务端具备可用 IPv6 出口时开启。

先添加并保存节点，再在 `Active node` 中选择它并点击 `Save & Apply`。插件会在
配置应用完成后依次重启 Bridge 和 PassWall，确保所选节点立即生效。

## 使用 UCI 配置

以下示例中的值必须替换成自己的服务端参数：

```sh
uci set passwall_snell.main.enabled='1'
uci set passwall_snell.hk='node'
uci set passwall_snell.hk.remarks='Hong Kong'
uci set passwall_snell.hk.server='203.0.113.10'
uci set passwall_snell.hk.port='35802'
uci set passwall_snell.hk.psk='REPLACE_WITH_YOUR_PSK'
uci set passwall_snell.hk.version='4'
uci set passwall_snell.hk.udp='1'
uci set passwall_snell.hk.reuse='1'
uci set passwall_snell.hk.tfo='1'
uci set passwall_snell.hk.obfs='shadow-tls'
uci set passwall_snell.hk.shadow_tls_password='REPLACE_WITH_SHADOWTLS_PASSWORD'
uci set passwall_snell.hk.shadow_tls_sni='www.microsoft.com'
uci set passwall_snell.hk.shadow_tls_version='3'
uci set passwall_snell.main.active_node='hk'
uci commit passwall_snell
chmod 0600 /etc/config/passwall_snell

/etc/init.d/passwall-snell enable
/etc/init.d/passwall-snell restart
```

继续添加第二个节点时使用另一个 UCI 节名，例如 `us`。切换节点只需执行：

```sh
uci set passwall_snell.main.active_node='us'
uci commit passwall_snell
/etc/init.d/passwall-snell restart
```

查看节点列表和当前选择：

```sh
uci show passwall_snell | grep '=node'
uci get passwall_snell.main.active_node
```

查看启动日志：

```sh
logread | grep passwall-snell
```

首次启动会下载并解压 Mihomo，所需时间取决于路由器到 GitHub 的网络质量。

## 接入 PassWall

Bridge 启动后，在 PassWall 中创建一个 SOCKS 节点：

```sh
uci -q delete passwall.SnV4Xray 2>/dev/null || true
uci set passwall.SnV4Xray='nodes'
uci set passwall.SnV4Xray.remarks='Snell-v4-ShadowTLS-Mihomo-UoT-Xray'
uci set passwall.SnV4Xray.type='V2ray'
uci set passwall.SnV4Xray.protocol='socks'
uci set passwall.SnV4Xray.address='127.0.0.1'
uci set passwall.SnV4Xray.port='17890'
uci set passwall.SnV4Xray.tls='0'
uci set passwall.SnV4Xray.transport='tcp'
uci set passwall.SnV4Xray.mux='0'

uci set passwall.@global[0].tcp_node='SnV4Xray'
uci set passwall.@global[0].udp_node='tcp'

uci set passwall.@global[0].filter_proxy_ipv6='1'
uci set passwall.@global_forwarding[0].ipv6_tproxy='0'
uci set passwall.@global_forwarding[0].tcp_proxy_way='redirect'

uci commit passwall
/etc/init.d/passwall restart
```

`udp_node='tcp'` 表示 PassWall 的 UDP 流量使用当前 TCP 节点。Mihomo 接收到
SOCKS UDP 后，由 Snell v4 将 UDP 封装在 TCP 链路中。

确认节点已选中：

```sh
uci get passwall.@global[0].tcp_node
uci get passwall.@global[0].udp_node
cat /tmp/etc/passwall/id/TCP
```

确认无误后，可在 LuCI 开启 PassWall 主开关，或执行：

```sh
uci set passwall.@global[0].enabled='1'
uci commit passwall
/etc/init.d/passwall restart
```

## 给局域网本地服务使用

Bridge 的 `17890` 有意只监听 `127.0.0.1`，用于 PassWall 内部转发，不直接暴露给
局域网。需要让 NAS、容器或其他 LAN 服务显式使用 SOCKS5 时，开启 PassWall 自带的
本地 SOCKS 入口：

```sh
uci set passwall.@global[0].socks_enabled='1'
uci set passwall.@global[0].tcp_node_socks_port='1070'
uci commit passwall
/etc/init.d/passwall restart
```

客户端填写：

```text
协议：SOCKS5
地址：路由器 LAN 地址，例如 192.168.1.1
端口：1070
DNS：通过 SOCKS5 远程解析（socks5h）
```

路由器本机进程可以使用 `127.0.0.1:1070`；NAS、Docker 容器和其他 LAN 主机必须
使用路由器 LAN 地址，不能填写 `127.0.0.1`。例如：

```sh
export ALL_PROXY='socks5h://192.168.1.1:1070'
curl --socks5-hostname 192.168.1.1:1070 https://www.gstatic.com/generate_204
```

PassWall 的本地 SOCKS 默认不带认证。即使 WAN 区域通常为拒绝输入，也建议明确阻断
WAN 对该端口的访问：

```sh
uci -q delete firewall.passwall_socks_wan_block
uci set firewall.passwall_socks_wan_block='rule'
uci set firewall.passwall_socks_wan_block.name='Block-PassWall-SOCKS-from-WAN'
uci set firewall.passwall_socks_wan_block.src='wan'
uci set firewall.passwall_socks_wan_block.proto='tcp udp'
uci set firewall.passwall_socks_wan_block.dest_port='1070'
uci set firewall.passwall_socks_wan_block.target='REJECT'
uci commit firewall
/etc/init.d/firewall restart
```

## 验证

检查 Bridge 进程和端口：

```sh
ps w | grep /tmp/passwall-snell/mihomo | grep -v grep
netstat -lntup | grep 17890
```

验证 Mihomo 配置：

```sh
/tmp/passwall-snell/mihomo -t -f /tmp/passwall-snell/config.json
```

通过 Bridge 测试 HTTPS：

```sh
curl --socks5-hostname 127.0.0.1:17890 \
  --connect-timeout 15 --max-time 40 \
  https://www.gstatic.com/generate_204
```

检查 PassWall 透明代理：

```sh
netstat -lntup | grep -E '1041|15353|17890'
iptables-save | grep PSW
tail -n 100 /tmp/log/passwall.log
```

如安装了 `dig`，可使用临时 `dns2socks` 验证 UDP：

```sh
dns2socks /d 127.0.0.1:17890 1.1.1.1:53 127.0.0.1:15354 &
DNS_PID=$!
dig @127.0.0.1 -p 15354 www.google.com A
kill "$DNS_PID"
```

## Snell v4 与 v5

- 需要 UDP-over-TCP 时使用 Snell v4。
- 部分 Snell v5 实现会使用原生 UDP，行为与 UDP-over-TCP 需求不同。
- Snell v5 是否使用原生 UDP 取决于服务端和核心实现。

## IPv6

默认配置：

```text
ipv6_tproxy=0
tcp_proxy_way=redirect
filter_proxy_ipv6=1
```

这会过滤代理域名的 AAAA 结果，避免客户端绕过仅支持 IPv4 出口的 Snell
链路。只有服务端具备稳定 IPv6 出口时才应开启插件页面中的 IPv6 开关。

## 重启与存储

- 插件文件写入 Overlay，体积只有几 KiB。
- Mihomo 核心写入 `/tmp/passwall-snell/mihomo`，重启后消失。
- 每次冷启动会重新下载并校验核心。
- 配置文件 `/etc/config/passwall_snell` 以 `0600` 权限保存。
- sysupgrade 会通过 `/lib/upgrade/keep.d/luci-app-passwall-snell` 保留配置。

固定核心信息：

```text
Mihomo: v1.19.28
File: mihomo-linux-arm64-v1.19.28.gz
SHA-256: 2474450cd1c41dfa53036a54a4e85579f493d3af524d86c3d4b8e2b240b56cd2
```

## 升级

下载新版本 IPK 后直接安装：

```sh
cp /etc/config/passwall_snell /tmp/passwall_snell.backup
opkg install /tmp/luci-app-passwall-snell_NEW_VERSION_all.ipk
/etc/init.d/passwall-snell restart
```

`/etc/config/passwall_snell` 被声明为 conffile，正常升级会保留现有参数。
首次安装新版时，如果检测到旧版单节点字段且节点列表为空，安装脚本会复制旧参数到
一个名为 `Migrated node` 的列表项并自动选中。旧字段不会立即删除，可用于回滚。

## 卸载

```sh
opkg remove luci-app-passwall-snell
```

卸载脚本会停止并禁用服务，并清理 LuCI 缓存。根据 `opkg` 的 conffile
策略，修改过的 `/etc/config/passwall_snell` 可能会被保留。

如需彻底删除：

```sh
rm -f /etc/config/passwall_snell
rm -rf /tmp/passwall-snell
```

## 从源码构建

无需 OpenWrt SDK，使用 Python 3 构建 Release IPK：

```sh
python3 scripts/build-ipk.py --output dist
```

输出：

```text
dist/luci-app-passwall-snell_1.0.3-1_all.ipk
```

也可将仓库放入 OpenWrt 源码树：

```sh
git clone https://github.com/autumnsentiment/luci-app-passwall-snell.git \
  package/luci-app-passwall-snell
make menuconfig
make package/luci-app-passwall-snell/compile V=s
```

在 `LuCI -> 3. Applications` 中选择 `luci-app-passwall-snell`。

## 故障排查

### Bridge 一直处于停止状态

```sh
uci show passwall_snell
logread | grep passwall-snell
curl -I https://github.com/MetaCubeX/mihomo/releases/
```

确认 `active_node` 指向现有节点，并且该节点的 `server`、`port`、`psk` 已填写。
ShadowTLS 模式下还必须填写密码和 SNI。检查：

```sh
uci get passwall_snell.main.active_node
uci show passwall_snell | grep '=node'
```

### 启动时反复下载

通常是 GitHub 不可达、下载被截断或 SHA-256 不匹配。检查：

```sh
ls -lh /tmp/passwall-snell/
logread | grep passwall-snell
date
```

系统时间错误也可能造成 HTTPS 证书校验失败。

### Bridge 正常但 PassWall 无法联网

```sh
uci get passwall.@global[0].tcp_node
uci get passwall.@global[0].udp_node
netstat -lntup | grep -E '1041|15353|17890'
tail -n 100 /tmp/log/passwall.log
```

确保 `SnV4Xray` 节点地址为 `127.0.0.1`、端口为 `17890`，并且 PassWall
启动顺序晚于 Bridge。插件启动优先级为 `98`，PassWall 通常为 `99`。

### LuCI 菜单不显示

```sh
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd restart
```

## 安全说明

- 仓库、IPK 和示例配置不包含任何实际 PSK、订阅地址或 ShadowTLS 密码。
- Bridge 只监听 `127.0.0.1:17890`，不会直接暴露到 LAN。
- Mihomo 下载后必须通过固定 SHA-256 校验才会执行。
- 不建议将 `/etc/config/passwall_snell` 上传到公开仓库。
