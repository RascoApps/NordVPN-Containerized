#!/usr/bin/env bash

# Integration tests for docker-compose networking and service configuration

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

assert_true() {
    local condition="$1"
    local test_name="${2:-Test}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$condition"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ${test_name}"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} ${test_name}"
        return 1
    fi
}

# Test network configuration
test_network_config() {
    print_test_header "Testing Network Configuration"
    
    cd /home/runner/work/NordVPN-Containerized/NordVPN-Containerized
    
    # Check if vpn_network is defined
    assert_true "docker compose config | grep -q 'vpn_network'" \
        "vpn_network is defined in compose file"
    
    # Check if network has custom subnet
    assert_true "docker compose config | grep -A 5 'vpn_network' | grep -q '172.20.0.0'" \
        "vpn_network has custom subnet configured"
}

# Test service network modes
test_service_network_modes() {
    print_test_header "Testing Service Network Modes"
    
    cd /home/runner/work/NordVPN-Containerized/NordVPN-Containerized
    
    # Check if qbittorrent uses nordvpn network mode
    assert_true "docker compose config | grep -A 10 'qbittorrent:' | grep -q 'network_mode:.*service:nordvpn'" \
        "qbittorrent uses nordvpn network mode"
    
    # Check if traefik is on vpn_network
    assert_true "docker compose config | grep -A 20 'traefik:' | grep -q 'vpn_network'" \
        "traefik is on vpn_network"
    
    # Check if nordvpn is on vpn_network
    assert_true "docker compose config 2>&1 | sed -n '/^  nordvpn:/,/^  [a-z]/p' | grep -q 'vpn_network'" \
        "nordvpn is on vpn_network"
}

# Test Traefik labels
test_traefik_labels() {
    print_test_header "Testing Traefik Labels"
    
    cd /home/runner/work/NordVPN-Containerized/NordVPN-Containerized
    
    # Check if traefik service has enable label
    assert_true "docker compose config | grep -A 30 'traefik:' | grep -q 'traefik.enable.*true'" \
        "traefik has enable label"
    
    # Check if qbittorrent has traefik labels
    assert_true "docker compose config | grep -A 20 'qbittorrent:' | grep -q 'traefik.http.routers.qbittorrent'" \
        "qbittorrent has traefik router configuration"
    
    # Check if services have host rules
    assert_true "docker compose config | grep -q 'Host.*qbittorrent.local'" \
        "qbittorrent has host rule configured"
    
    assert_true "docker compose config | grep -q 'Host.*prowlarr.local'" \
        "prowlarr has host rule configured"
}

# Test service dependencies
test_service_dependencies() {
    print_test_header "Testing Service Dependencies"
    
    cd /home/runner/work/NordVPN-Containerized/NordVPN-Containerized
    
    # Check if services depend on nordvpn
    assert_true "docker compose config | grep -A 10 'qbittorrent:' | grep -q 'depends_on'" \
        "qbittorrent has dependency configuration"
    
    # Check if all *arr services are defined
    assert_true "docker compose config | grep -q 'prowlarr:'" \
        "prowlarr service is defined"
    
    assert_true "docker compose config | grep -q 'radarr:'" \
        "radarr service is defined"
    
    assert_true "docker compose config | grep -q 'sonarr:'" \
        "sonarr service is defined"
}

# Test exposed ports
test_exposed_ports() {
    print_test_header "Testing Exposed Ports"
    
    cd /home/runner/work/NordVPN-Containerized/NordVPN-Containerized
    
    # Check traefik ports
    assert_true "docker compose config 2>&1 | sed -n '/^  traefik:/,/^  [a-z]/p' | grep -A 5 'ports:' | grep -q 'target: 80'" \
        "traefik exposes port 80 for HTTP"
    
    assert_true "docker compose config 2>&1 | sed -n '/^  traefik:/,/^  [a-z]/p' | grep -A 10 'ports:' | grep -q 'target: 8080'" \
        "traefik exposes port 8081 for dashboard"
    
    # Check nordvpn ports
    assert_true "docker compose config 2>&1 | sed -n '/^  nordvpn:/,/^  [a-z]/p' | grep -A 5 'ports:' | grep -q 'target: 6881'" \
        "nordvpn exposes port 6881 for BitTorrent"
}

# Print summary
print_summary() {
    echo -e "\n${YELLOW}=== Test Summary ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "\n${GREEN}All integration tests passed!${NC}"
        exit 0
    fi
}

# Main test execution
main() {
    echo "Running NordVPN Docker Compose Integration Tests"
    
    test_network_config
    test_service_network_modes
    test_traefik_labels
    test_service_dependencies
    test_exposed_ports
    
    print_summary
}

main "$@"
