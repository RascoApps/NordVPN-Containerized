# NordVPN container with extensive CLI configuration support
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    iproute2 \
    iptables \
    iputils-ping \
    jq \
    openvpn \
    procps \
    sudo \
    wireguard-tools && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://repo.nordvpn.com/gpg/nordvpn_public.asc -o /etc/apt/keyrings/nordvpn_public.asc && \
    chmod 644 /etc/apt/keyrings/nordvpn_public.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/nordvpn_public.asc] https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nordvpn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD nordvpn status | grep -qi 'Connected'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
