# NordVPN Docker Builder (WireGuard + OpenVPN P2P)

This project packages the official NordVPN Linux CLI inside an Ubuntu-based container and exposes the most commonly used configuration levers through environment variables. It targets two primary scenarios:

- **High-performance WireGuard (NordLynx)** sessions on the **P2P specialty servers** for torrenting workloads.
- **Compatibility-first OpenVPN** tunnels (UDP/TCP) for environments where WireGuard is blocked but P2P is still required.

The image follows NordVPN's official Docker build guidance, installs the native CLI from their Debian repository, and applies the Linux usage recommendations from NordVPN's docs. References:

- [How to build the NordVPN Docker image](https://support.nordvpn.com/hc/en-us/articles/20465811527057-How-to-build-the-NordVPN-Docker-image)
- [Installing & configuring NordVPN on Linux](https://support.nordvpn.com/hc/en-us/articles/20196094470929-Installing-NordVPN-on-Linux-distributions)
- [NordVPN provider specifics used by Gluetun](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/nordvpn.md)

## Getting started

1. Export your NordVPN **service token** from the Nord Account portal (`Services → NordVPN → Manual setup`).
2. Copy `.env.example` to `.env` and fill in `NORDVPN_TOKEN`. Adjust other settings as needed (PUID, PGID, TZ, storage paths, etc.).
3. Build and start the services:

```bash
# Run with docker compose (recommended)
docker compose up -d
```

> The NordVPN container requires `NET_ADMIN`, the `/dev/net/tun` device, and IPv6 enabled (per NordVPN guidance) to avoid leaks.

## Multi-Service Stack

The `compose.yaml` includes a complete media server stack with the following services:

### Services Routing Through VPN
- **qBittorrent** - BitTorrent client (port 8080)
- **Prowlarr** - Indexer manager (port 9696)
- **Lidarr** - Music collection manager (port 8686)
- **Radarr** - Movie collection manager (port 7878)
- **Sonarr** - TV show collection manager (port 8989)
- **Overseerr** - Request management (port 5055)
- **Whisparr** - Adult content manager (port 6969)

### Services Bypassing VPN
- **Traefik** - Reverse proxy (HTTP: port 100, Dashboard: port 8081)
- **Plex** - Media server (port 32400)

All VPN-routed services are accessible through Traefik at `http://your-host:100/<service-name>` or directly via their exposed ports on the nordvpn container.

### Persisting credentials

The compose file mounts `./data/nordvpn` to `/etc/nordvpn`, which stores the CLI credentials. After the first successful token login the session survives restarts.

## Configuration surface

### NordVPN Settings

| Variable | Purpose |
| --- | --- |
| `NORDVPN_TOKEN` | Non-interactive login token (required unless you exec into the container and run `nordvpn login`). |
| `NORDVPN_TECHNOLOGY` | `NordLynx` (WireGuard) or `OpenVPN`. Defaults to `NordLynx` for performance-oriented P2P. |
| `NORDVPN_PROTOCOL` | `udp` or `tcp`. Only applied when `NORDVPN_TECHNOLOGY=OpenVPN`. |
| `NORDVPN_GROUP` | Specialty group flag passed to `nordvpn connect --group`. Defaults to `p2p`. |
| `NORDVPN_COUNTRY` / `NORDVPN_SERVER` | Restrict connection to a country (`us`, `nl`, …) or a specific server ID (`us1234`). Server overrides country. |
| `NORDVPN_CONNECT` | Raw arguments appended to `nordvpn connect` (useful for edge cases). |
| `NORDVPN_SKIP_CONNECT` | `true` to skip auto-connect (container stays authenticated and ready). |
| `NORDVPN_KILLSWITCH`, `NORDVPN_THREAT_PROTECTION_LITE`, `NORDVPN_OBFUSCATE`, `NORDVPN_MESHNET`, `NORDVPN_ANALYTICS`, `NORDVPN_NOTIFY` | Toggle-able features exposed via `nordvpn set <feature> on/off`. |
| `NORDVPN_AUTOCONNECT_STATE` / `NORDVPN_AUTOCONNECT_TARGET` | Control NordVPN's native auto-connect (state = `on/off`, target = server identifier). |
| `NORDVPN_LAN_DISCOVERY` | `enable`/`disable` using `nordvpn set lan-discovery …`. |
| `NORDVPN_DNS` | Space/comma separated list of custom DNS servers applied through `nordvpn set dns`. |
| `NORDVPN_ALLOWLIST_PORTS` / `NORDVPN_ALLOWLIST_SUBNETS` | Lists passed to `nordvpn whitelist add port` / `nordvpn whitelist add subnet` so LAN services can bypass the tunnel. |

### Docker Environment Variables

| Variable | Purpose | Default |
| --- | --- | --- |
| `PUID` | User ID for file permissions | 1000 |
| `PGID` | Group ID for file permissions | 1000 |
| `TZ` | Timezone for containers | America/New_York |
| `DOCKERCONFDIR` | Path for application config directories | ./config |
| `DOCKERSTORAGEDIR` | Path for media/data storage | ./storage |
| `PLEX_CLAIM` | Plex claim token for initial setup | (empty) |
| `PLEX_PASS` | Whether Plex Pass features are enabled | no |

Any variables omitted from `.env` keep NordVPN defaults, so you can start simple and layer adjustments later.

## Common scenarios

1. **WireGuard P2P (default)** – `.env` values from the example yield NordLynx + P2P with the best country server picked automatically.
2. **OpenVPN TCP for trackers** – set `NORDVPN_TECHNOLOGY=OpenVPN`, `NORDVPN_PROTOCOL=tcp`, keep `NORDVPN_GROUP=p2p` to stay on torrent-friendly exits.
3. **Location pinning** – specify `NORDVPN_COUNTRY=nl` or `NORDVPN_SERVER=us8045` to control exit nodes.
4. **Headless seedbox** – enable `NORDVPN_LAN_DISCOVERY=enable` and allowlist your LAN subnet (`NORDVPN_ALLOWLIST_SUBNETS=192.168.1.0/24`) so other containers can reach services on the VPN host.

## Health & lifecycle

- The container ships with a `HEALTHCHECK` that marks it unhealthy if `nordvpn status` stops reporting a "Connected" state.
- Shutdown traps call `nordvpn disconnect` for a clean exit.
- When `NORDVPN_SKIP_CONNECT=true`, the daemon and CLI remain ready for manual connects via `docker exec -it nordvpn nordvpn connect --group p2p us`.

## Troubleshooting tips

- Use `docker logs nordvpn` to follow `/var/log/nordvpn/*` inside the container.
- If logins fail, regenerate the service token and update `.env`.
- Ensure the host kernel allows TUN devices and that no corporate firewall blocks UDP/51820 (WireGuard) or OpenVPN ports.

## Security notes

- Tokens grant full account access for manual configs—store `.env` securely.
- Consider running this container on dedicated hosts if other workloads depend on the routed traffic.
- All media service containers connect to the VPN through the shared `vpn_network` bridge network.
- Plex bypasses the VPN to allow direct streaming from your local network.

## Architecture

The docker-compose stack uses the following networking model:

- **vpn_network** (172.21.0.0/16): Bridge network shared by NordVPN and all media services (qBittorrent, *arr apps, etc.)
- **default network**: Used by Plex to bypass the VPN
- **Traefik**: Reverse proxy providing unified HTTP access at port 100, with service routing via path prefixes

All VPN-routed services depend on the `nordvpn` container and automatically use the VPN tunnel for external connections.
