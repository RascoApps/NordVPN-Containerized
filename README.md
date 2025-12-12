# NordVPN Docker Builder (WireGuard + OpenVPN P2P)

This project packages the official NordVPN Linux CLI inside an Ubuntu-based container and exposes the most commonly used configuration levers through environment variables. It targets two primary scenarios:

- **High-performance WireGuard (NordLynx)** sessions on the **P2P specialty servers** for torrenting workloads.
- **Compatibility-first OpenVPN** tunnels (UDP/TCP) for environments where WireGuard is blocked but P2P is still required.

The image follows NordVPN's official Docker build guidance, installs the native CLI from their Debian repository, and applies the Linux usage recommendations from NordVPN's docs. References:

- [How to build the NordVPN Docker image](https://support.nordvpn.com/hc/en-us/articles/20465811527057-How-to-build-the-NordVPN-Docker-image)
- [Installing & configuring NordVPN on Linux](https://support.nordvpn.com/hc/en-us/articles/20196094470929-Installing-NordVPN-on-Linux-distributions)
- [NordVPN provider specifics used by Gluetun](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/nordvpn.md)

## Features

- **Automated Test Suite**: Comprehensive tests for configuration functions and Docker setup
- **Reverse Proxy Integration**: Traefik reverse proxy with automatic service discovery
- **Custom Docker Network**: Isolated VPN network for all services
- **Example Service Stack**: Pre-configured media management services (qBittorrent, Prowlarr, Radarr, Sonarr)
- **Service URL Mapping**: Access services via path-based routing (e.g., `http://localhost/prowlarr`)

## Getting started

1. Export your NordVPN **service token** from the Nord Account portal (`Services → NordVPN → Manual setup`).
2. Copy `.env.example` to `.env` and fill in `NORDVPN_TOKEN`. Adjust other settings as needed.
3. Build and start the container:

```bash
# Build once
docker build -t nordvpn-cli .

# Run with docker compose (recommended)
docker compose --env-file .env up -d
```

> The container requires `NET_ADMIN`, the `/dev/net/tun` device, and IPv6 enabled (per NordVPN guidance) to avoid leaks.

### Network Architecture

The compose file creates a custom bridge network (`vpn_network`) that isolates all VPN-related traffic. Services can be configured in two ways:

1. **Using NordVPN's network** (`network_mode: "service:nordvpn"`): All traffic goes through the VPN
2. **On the shared network** (standard `networks` config): Can communicate with VPN services but doesn't route through VPN

### Accessing Services

Services using the VPN connection can be accessed via:

1. **Traefik Reverse Proxy** (recommended):
   - Access services via path-based routing at `http://localhost`:
     - qBittorrent: `http://localhost/qbittorrent`
     - Prowlarr: `http://localhost/prowlarr`
     - Radarr: `http://localhost/radarr`
     - Sonarr: `http://localhost/sonarr`
   - View Traefik dashboard at `http://localhost:8081/dashboard/`

2. **Direct Port Access**:
   - Services are also accessible via exposed ports on the nordvpn container
   - Note: Only BitTorrent ports (6881) are exposed by default in the updated config

### One-off `docker run`

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  --env-file .env \
  nordvpn-cli
```

### Persisting credentials

The compose file mounts `./data/nordvpn` to `/etc/nordvpn`, which stores the CLI credentials. After the first successful token login the session survives restarts.

## Configuration surface

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

Any variables omitted from `.env` keep NordVPN defaults, so you can start simple and layer adjustments later.

## Common scenarios

1. **WireGuard P2P (default)** – `.env` values from the example yield NordLynx + P2P with the best country server picked automatically.
2. **OpenVPN TCP for trackers** – set `NORDVPN_TECHNOLOGY=OpenVPN`, `NORDVPN_PROTOCOL=tcp`, keep `NORDVPN_GROUP=p2p` to stay on torrent-friendly exits.
3. **Location pinning** – specify `NORDVPN_COUNTRY=nl` or `NORDVPN_SERVER=us8045` to control exit nodes.
4. **Headless seedbox** – enable `NORDVPN_LAN_DISCOVERY=enable` and allowlist your LAN subnet (`NORDVPN_ALLOWLIST_SUBNETS=192.168.1.0/24`) so other containers can reach services on the VPN host.

## Adding New Services

To add a new service to the VPN network:

1. Add the service to `compose.yaml`:

```yaml
myservice:
  image: your/image:latest
  container_name: myservice
  environment:
    - YOUR_ENV=value
  volumes:
    - ./data/myservice:/config
  network_mode: "service:nordvpn"  # Route through VPN
  depends_on:
    - nordvpn
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.myservice.rule=PathPrefix(`/myservice`)"
    - "traefik.http.routers.myservice.entrypoints=web"
    - "traefik.http.routers.myservice.middlewares=myservice-stripprefix"
    - "traefik.http.middlewares.myservice-stripprefix.stripprefix.prefixes=/myservice"
    - "traefik.http.services.myservice.loadbalancer.server.port=8080"  # Your service port
```

2. Restart the stack:
```bash
docker compose up -d
```

3. Access your service at `http://localhost/myservice`

### Services Not Needing VPN

If a service doesn't need VPN routing, use regular networking:

```yaml
myservice:
  image: your/image:latest
  networks:
    - vpn_network
  ports:
    - "8080:8080"
  # ... rest of config
```

## Testing

Run the test suite to validate configuration:

```bash
# Run all tests
bash tests/test_entrypoint.sh

# Test compose file validity
docker compose config

# Run tests in CI
# Tests run automatically on push/PR via GitHub Actions
```

The test suite validates:
- Configuration normalization functions
- Docker Compose file syntax
- Dockerfile structure
- Service connectivity (when containers are running)

## Health & lifecycle

- The container ships with a `HEALTHCHECK` that marks it unhealthy if `nordvpn status` stops reporting a "Connected" state.
- Shutdown traps call `nordvpn disconnect` for a clean exit.
- When `NORDVPN_SKIP_CONNECT=true`, the daemon and CLI remain ready for manual connects via `docker exec -it nordvpn nordvpn connect --group p2p us`.

## Troubleshooting tips

- Use `docker logs nordvpn` to follow `/var/log/nordvpn/*` inside the container.
- If logins fail, regenerate the service token and update `.env`.
- Ensure the host kernel allows TUN devices and that no corporate firewall blocks UDP/51820 (WireGuard) or OpenVPN ports.
- **Service not accessible via path**: Verify Traefik is running (`docker ps`) and check service labels are correct
- **Service can't reach internet**: Verify the service uses `network_mode: "service:nordvpn"` and nordvpn is connected (`docker exec nordvpn nordvpn status`)
- **Traefik shows no routes**: Check service labels are correct and containers are running

## Reverse Proxy Details

The included Traefik reverse proxy provides:

- **Automatic Service Discovery**: Services with proper labels are automatically registered
- **Path-based Routing**: Access services via URL paths like `http://localhost/prowlarr`
- **Dashboard**: Monitor all routes at `http://localhost:8081/dashboard/`
- **No SSL by default**: Add your own certificate configuration if needed

### Traefik Configuration

The proxy is configured via Docker labels on each service:
- `traefik.enable=true`: Enable routing for this service
- `traefik.http.routers.<name>.rule=PathPrefix(...)`: Define the URL path
- `traefik.http.middlewares.<name>-stripprefix.stripprefix.prefixes=...`: Strip the path prefix before forwarding to the service
- `traefik.http.services.<name>.loadbalancer.server.port=<port>`: Specify the service port

Since services using `network_mode: "service:nordvpn"` share the nordvpn container's network stack, they are accessible through the nordvpn container's network namespace.

## Security notes

- Tokens grant full account access for manual configs—store `.env` securely.
- Consider running this container on dedicated hosts if other workloads depend on the routed traffic.

## Next steps

- Customize the service stack by adding or removing services from `compose.yaml`
- Configure Traefik with SSL certificates for HTTPS access
- Set up additional routing rules or middleware in Traefik
- Monitor your VPN connection health via `docker exec nordvpn nordvpn status`
- Explore other NordVPN specialty groups beyond P2P (see configuration options above)
