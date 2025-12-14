# NordVPN container with extensive CLI configuration support
# Builder stage for dependency installation
FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg

RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://repo.nordvpn.com/gpg/nordvpn_public.asc -o /etc/apt/keyrings/nordvpn_public.asc && \
    chmod 644 /etc/apt/keyrings/nordvpn_public.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/nordvpn_public.asc] https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list

RUN apt-get update && \
    apt-get install -y --no-install-recommends nordvpn && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Runtime stage
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=${TZ:-America/Denver}

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
    ca-certificates \
    iproute2 \
    iptables \
    iputils-ping \
    jq \
    openvpn \
    procps \
    wireguard-tools && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY --from=builder /opt/nordvpn /opt/nordvpn
COPY --from=builder /usr/bin/nordvpn /usr/bin/nordvpn
COPY --from=builder /etc/apt/sources.list.d/nordvpn.list /etc/apt/sources.list.d/
COPY --from=builder /etc/apt/keyrings/nordvpn_public.asc /etc/apt/keyrings/

HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD nordvpn status | grep -qi 'Connected'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
