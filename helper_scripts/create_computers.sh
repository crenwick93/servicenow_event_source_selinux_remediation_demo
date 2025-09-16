#!/usr/bin/env bash

set -euo pipefail

# Creates example computer CI records in ServiceNow for testing.
#
# Requirements (environment variables):
#   - SERVICENOW_INSTANCE_URL  e.g. https://dev12345.service-now.com
#   - SERVICENOW_USERNAME      e.g. admin
#   - SERVICENOW_PASSWORD      e.g. your-password or token
#
# Usage:
#   ./create_computers.sh               # create both DEV and PROD computers
#   ./create_computers.sh --dev-only    # create only the DEV computer
#   ./create_computers.sh --prod-only   # create only the PROD computer

if [[ "${SERVICENOW_INSTANCE_URL:-}" == "" || "${SERVICENOW_USERNAME:-}" == "" || "${SERVICENOW_PASSWORD:-}" == "" ]]; then
  echo "Error: Please set SERVICENOW_INSTANCE_URL, SERVICENOW_USERNAME, and SERVICENOW_PASSWORD." >&2
  exit 1
fi

MODE="both"
if [[ "${1:-}" == "--dev-only" ]]; then
  MODE="dev"
elif [[ "${1:-}" == "--prod-only" ]]; then
  MODE="prod"
elif [[ "${1:-}" != "" ]]; then
  echo "Unknown option: $1" >&2
  echo "Usage: $0 [--dev-only|--prod-only]" >&2
  exit 1
fi

INSTANCE_URL="${SERVICENOW_INSTANCE_URL%/}"
API_ENDPOINT="$INSTANCE_URL/api/now/table/cmdb_ci_computer"

DEV_HOST="ec2-16-16-233-77.eu-north-1.compute.amazonaws.com"
PROD_HOST="ec2-13-48-129-218.eu-north-1.compute.amazonaws.com"

have_jq() {
  command -v jq >/dev/null 2>&1
}

create_computer() {
  local name="$1"
  local host_name="$2"
  local environment="$3"

  # Build JSON payload. We keep it simple here since values are well-formed.
  local payload
  payload=$(cat <<JSON
{
  "name": "${name}",
  "host_name": "${host_name}",
  "environment": "${environment}"
}
JSON
)

  # Perform POST request
  # Capture body and status code separately to provide clearer feedback
  local response http_code
  response=$(curl -sS -u "${SERVICENOW_USERNAME}:${SERVICENOW_PASSWORD}" \
    -H "Content-Type: application/json" -X POST \
    "$API_ENDPOINT" \
    -d "$payload" \
    -w "\n%{http_code}") || {
      echo "Request failed for host $host_name" >&2
      return 1
    }

  http_code="${response##*$'\n'}"
  local body
  body="${response%$'\n'*}"

  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    echo "Failed to create computer ($host_name). HTTP $http_code" >&2
    if have_jq; then
      echo "$body" | jq . >&2 || true
    else
      echo "$body" >&2
    fi
    return 1
  fi

  if have_jq; then
    local sys_id display
    sys_id=$(echo "$body" | jq -r '.result.sys_id // empty') || true
    display=$(echo "$body" | jq -r '.result.display_value // empty') || true
    if [[ -n "$sys_id" ]]; then
      echo "Created: $host_name (env=$environment) sys_id=$sys_id${display:+ display=$display}"
    else
      echo "Created: $host_name (env=$environment)"
      echo "$body" | jq . || true
    fi
  else
    echo "Created: $host_name (env=$environment)"
    echo "$body"
  fi
}

main() {
  local rc=0

  if [[ "$MODE" == "both" || "$MODE" == "dev" ]]; then
    create_computer "$DEV_HOST" "$DEV_HOST" "development" || rc=1
  fi

  if [[ "$MODE" == "both" || "$MODE" == "prod" ]]; then
    create_computer "$PROD_HOST" "$PROD_HOST" "production" || rc=1
  fi

  exit "$rc"
}

main "$@"


