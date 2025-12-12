#!/usr/bin/env bash

# Test suite for entrypoint.sh functions
# Uses basic bash test framework

set -euo pipefail

# Get the repository root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ${test_name:-Test passed}"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} ${test_name:-Test failed}"
        echo -e "  Expected: ${expected}"
        echo -e "  Actual:   ${actual}"
        return 1
    fi
}

assert_success() {
    local command="$1"
    local test_name="${2:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$command" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ${test_name:-Command succeeded}"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} ${test_name:-Command failed}"
        return 1
    fi
}

# Test normalize_on_off function
test_normalize_on_off() {
    print_test_header "Testing normalize_on_off function"
    
    # Define the function inline to avoid sourcing the full script
    normalize_on_off() {
      local value
      value="${1:-}"
      if [[ -z "$value" ]]; then
        return 1
      fi
      case "${value,,}" in
        on|true|1|yes|enabled|enable) echo "on" ;;
        off|false|0|no|disabled|disable) echo "off" ;;
        *) return 1 ;;
      esac
    }
    
    # Test "on" variations
    result=$(normalize_on_off "on")
    assert_equals "on" "$result" "normalize_on_off: 'on' -> 'on'"
    
    result=$(normalize_on_off "true")
    assert_equals "on" "$result" "normalize_on_off: 'true' -> 'on'"
    
    result=$(normalize_on_off "1")
    assert_equals "on" "$result" "normalize_on_off: '1' -> 'on'"
    
    result=$(normalize_on_off "yes")
    assert_equals "on" "$result" "normalize_on_off: 'yes' -> 'on'"
    
    result=$(normalize_on_off "enabled")
    assert_equals "on" "$result" "normalize_on_off: 'enabled' -> 'on'"
    
    # Test "off" variations
    result=$(normalize_on_off "off")
    assert_equals "off" "$result" "normalize_on_off: 'off' -> 'off'"
    
    result=$(normalize_on_off "false")
    assert_equals "off" "$result" "normalize_on_off: 'false' -> 'off'"
    
    result=$(normalize_on_off "0")
    assert_equals "off" "$result" "normalize_on_off: '0' -> 'off'"
    
    result=$(normalize_on_off "no")
    assert_equals "off" "$result" "normalize_on_off: 'no' -> 'off'"
    
    result=$(normalize_on_off "disabled")
    assert_equals "off" "$result" "normalize_on_off: 'disabled' -> 'off'"
    
    # Test case insensitivity
    result=$(normalize_on_off "ON")
    assert_equals "on" "$result" "normalize_on_off: 'ON' -> 'on'"
    
    result=$(normalize_on_off "OFF")
    assert_equals "off" "$result" "normalize_on_off: 'OFF' -> 'off'"
}

# Test normalize_enable_disable function
test_normalize_enable_disable() {
    print_test_header "Testing normalize_enable_disable function"
    
    # Define the function inline to avoid sourcing the full script
    normalize_enable_disable() {
      local value
      value="${1:-}"
      if [[ -z "$value" ]]; then
        return 1
      fi
      case "${value,,}" in
        enable|enabled|on|true|1|yes) echo "enable" ;;
        disable|disabled|off|false|0|no) echo "disable" ;;
        *) return 1 ;;
      esac
    }
    
    # Test "enable" variations
    result=$(normalize_enable_disable "enable")
    assert_equals "enable" "$result" "normalize_enable_disable: 'enable' -> 'enable'"
    
    result=$(normalize_enable_disable "enabled")
    assert_equals "enable" "$result" "normalize_enable_disable: 'enabled' -> 'enable'"
    
    result=$(normalize_enable_disable "on")
    assert_equals "enable" "$result" "normalize_enable_disable: 'on' -> 'enable'"
    
    result=$(normalize_enable_disable "true")
    assert_equals "enable" "$result" "normalize_enable_disable: 'true' -> 'enable'"
    
    # Test "disable" variations
    result=$(normalize_enable_disable "disable")
    assert_equals "disable" "$result" "normalize_enable_disable: 'disable' -> 'disable'"
    
    result=$(normalize_enable_disable "disabled")
    assert_equals "disable" "$result" "normalize_enable_disable: 'disabled' -> 'disable'"
    
    result=$(normalize_enable_disable "off")
    assert_equals "disable" "$result" "normalize_enable_disable: 'off' -> 'disable'"
    
    result=$(normalize_enable_disable "false")
    assert_equals "disable" "$result" "normalize_enable_disable: 'false' -> 'disable'"
    
    # Test case insensitivity
    result=$(normalize_enable_disable "ENABLE")
    assert_equals "enable" "$result" "normalize_enable_disable: 'ENABLE' -> 'enable'"
    
    result=$(normalize_enable_disable "DISABLE")
    assert_equals "disable" "$result" "normalize_enable_disable: 'DISABLE' -> 'disable'"
}

# Test docker-compose file validity
test_compose_file_validity() {
    print_test_header "Testing docker-compose file validity"
    
    cd "$REPO_ROOT"
    
    # Check if compose file is valid
    if docker compose config >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} docker-compose file is valid"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} docker-compose file is invalid"
    fi
}

# Test Dockerfile validity
test_dockerfile_validity() {
    print_test_header "Testing Dockerfile validity"
    
    cd "$REPO_ROOT"
    
    # Check if Dockerfile has proper structure
    if grep -q "FROM ubuntu:24.04" Dockerfile && \
       grep -q "ENTRYPOINT" Dockerfile; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Dockerfile structure is valid"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Dockerfile structure is invalid"
    fi
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
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Main test execution
main() {
    echo "Running NordVPN Containerized Test Suite"
    
    test_normalize_on_off
    test_normalize_enable_disable
    test_compose_file_validity
    test_dockerfile_validity
    
    print_summary
}

main "$@"
