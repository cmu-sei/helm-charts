#!/bin/sh
# Copyright 2025 Carnegie Mellon University. All Rights Reserved.
# Released under a MIT (SEI)-style license. See LICENSE.md in the project root for license information.

# Generic OIDC/OAuth2 configuration script for Moodle.
# Supports any OIDC-compliant provider (e.g. Keycloak, Okta, Azure AD, Auth0).
# Token and userinfo endpoints are automatically discovered via the OIDC discovery document.

# Global Variables
STATUS_FILE="/tmp/oidc_script_status.log"
LOG_FILE="/tmp/oidc_script.log"
MOODLE_DIR="/var/www/html"
OAUTH2_ISSUER_ID=""

PHP_CA_FLAGS=""
if [ -n "$OIDC_CA_CERT_PATH" ]; then
  PHP_CA_FLAGS="-d curl.cainfo=${OIDC_CA_CERT_PATH} -d openssl.cafile=${OIDC_CA_CERT_PATH}"
  export CURL_CA_BUNDLE="$OIDC_CA_CERT_PATH"
  export SSL_CERT_FILE="$OIDC_CA_CERT_PATH"
fi

php_exec() {
  php $PHP_CA_FLAGS "$@"
}

wait_for_oidc() {
  local url="$1"
  local timeout="${OIDC_WAIT_TIMEOUT:-300}"
  local interval="${OIDC_WAIT_INTERVAL:-5}"
  local start
  start=$(date +%s)
  local attempt=0

  while true; do
    attempt=$((attempt + 1))
    log "Waiting for OIDC discovery endpoint (attempt ${attempt}): ${url}"

    local output
    output=$(OIDC_CHECK_URL="$url" OIDC_CHECK_TIMEOUT="$interval" \
      php_exec -r '
        $url = getenv("OIDC_CHECK_URL");
        $timeout = (int)getenv("OIDC_CHECK_TIMEOUT");
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_NOBODY, true);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, $timeout);
        curl_exec($ch);
        $err = curl_error($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($err) {
          fwrite(STDERR, $err);
          exit(1);
        }
        if ($code < 200 || $code >= 400) {
          fwrite(STDERR, "HTTP " . $code);
          exit(1);
        }
        echo $code;
      ' 2>&1)
    local rc=$?

    if [ $rc -eq 0 ]; then
      log "OIDC discovery endpoint is ready (status: ${output})"
      return 0
    fi

    log "OIDC discovery not ready yet: ${output}"

    local now
    now=$(date +%s)
    if [ $now -ge $((start + timeout)) ]; then
      log "OIDC discovery endpoint did not become ready within ${timeout}s"
      return 1
    fi

    sleep "$interval"
  done
}

fetch_discovery_document() {
  local url="$1"
  OIDC_DOC_URL="$url" php_exec -r '
    $url = getenv("OIDC_DOC_URL");
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
    $body = curl_exec($ch);
    $err = curl_error($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($err) {
      fwrite(STDERR, $err);
      exit(1);
    }
    if ($code < 200 || $code >= 400) {
      fwrite(STDERR, "HTTP " . $code);
      exit(1);
    }
    echo $body;
  '
}

user_field_mapping_exists() {
  local issuer_id="$1"
  local external="$2"
  local internal="$3"

  local output
  output=$(php_exec /opt/sei/custom-scripts/setup_environment.php \
    --step=manage_oauth \
    --check-user-field \
    --id="$issuer_id" \
    --externalfield="$external" \
    --internalfield="$internal" \
    --json=1 2>&1)
  local rc=$?

  if [ $rc -ne 0 ]; then
    log "User field mapping check failed for $external -> $internal: $output"
    return 2
  fi

  printf '%s\n' "$output" | php -r '
    $data = json_decode(stream_get_contents(STDIN), true);
    if (!is_array($data)) {
        exit(2);
    }
    exit(!empty($data["exists"]) ? 0 : 1);
  '
  rc=$?
  if [ $rc -eq 0 ]; then
    return 0
  fi
  if [ $rc -eq 1 ]; then
    return 1
  fi

  log "User field mapping check returned unexpected output: $output"
  return 2
}

# Function to log messages
log() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

# Function to log errors
error() {
    section="$1"
    message="$2"
    echo "[ERROR] $message" | tee -a "$LOG_FILE"
    echo "$section = Failed" >> "$STATUS_FILE"
    exit 1
}

# Function to record status
record_status() {
    section="$1"
    status="$2"
    sed -i "/^$section =/d" "$STATUS_FILE" 2>/dev/null || true
    echo "$section = $status" >> "$STATUS_FILE"
}

# Function to check and execute a section
execute_section() {
    section="$1"
    func="$2"
    status=$(grep "^$section =" "$STATUS_FILE" 2>/dev/null | cut -d '=' -f2 | xargs)

    if [ "$status" != "Completed" ]; then
        log "Running section: $section"
        $func
        if [ $? -eq 0 ]; then
            record_status "$section" "Completed"
        else
            record_status "$section" "Failed"
            log "Section $section failed."
        fi
    else
        log "Skipping section: $section (already completed)"
    fi
}

configure_oauth2() {
  section="OAuth2 Configuration"
  log "Configuring OAuth2 settings..."

  # Verify required environment variables
  REQUIRED_KEYS="OIDC_DISCOVERY_URL OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_NAME"
  for key in $REQUIRED_KEYS; do
    eval val=\$$key
    if [ -z "$val" ]; then
      error "$section" "Missing required configuration: $key"
    fi
  done

  if ! wait_for_oidc "$OIDC_DISCOVERY_URL"; then
    error "$section" "OIDC discovery endpoint not ready at ${OIDC_DISCOVERY_URL}"
  fi

  # Fetch and parse the discovery document to obtain endpoints
  log "Fetching OIDC endpoints from discovery document..."
  DISCOVERY_JSON=$(fetch_discovery_document "$OIDC_DISCOVERY_URL")
  local fetch_rc=$?
  if [ $fetch_rc -ne 0 ] || [ -z "$DISCOVERY_JSON" ]; then
    error "$section" "Failed to fetch OIDC discovery document from ${OIDC_DISCOVERY_URL}"
  fi

  OIDC_ISSUER=$(printf '%s' "$DISCOVERY_JSON" | php -r '
    $data = json_decode(stream_get_contents(STDIN), true);
    echo isset($data["issuer"]) ? rtrim($data["issuer"], "/") . "/" : "";
  ')
  OIDC_TOKEN_ENDPOINT=$(printf '%s' "$DISCOVERY_JSON" | php -r '
    $data = json_decode(stream_get_contents(STDIN), true);
    echo $data["token_endpoint"] ?? "";
  ')
  OIDC_USERINFO_ENDPOINT=$(printf '%s' "$DISCOVERY_JSON" | php -r '
    $data = json_decode(stream_get_contents(STDIN), true);
    echo $data["userinfo_endpoint"] ?? "";
  ')

  if [ -z "$OIDC_TOKEN_ENDPOINT" ]; then
    error "$section" "Could not determine token_endpoint from OIDC discovery document"
  fi
  if [ -z "$OIDC_USERINFO_ENDPOINT" ]; then
    error "$section" "Could not determine userinfo_endpoint from OIDC discovery document"
  fi

  # Determine the base URL (issuer) to register in Moodle OAuth2
  if [ -n "$OIDC_ISSUER" ]; then
    PROVIDER_BASEURL="$OIDC_ISSUER"
  else
    PROVIDER_BASEURL=$(printf '%s' "$OIDC_DISCOVERY_URL" | sed 's|/\.well-known/.*$||')
    PROVIDER_BASEURL="${PROVIDER_BASEURL%/}/"
  fi

  # Derive provider icon URL from discovery URL host
  OIDC_ORIGIN=$(printf '%s' "$OIDC_DISCOVERY_URL" | php -r '
    $url = stream_get_contents(STDIN);
    $parsed = parse_url(trim($url));
    $scheme = $parsed["scheme"] ?? "https";
    $host = $parsed["host"] ?? "";
    $port = isset($parsed["port"]) ? ":" . $parsed["port"] : "";
    echo $scheme . "://" . $host . $port;
  ')
  OIDC_ICON_URL="${OIDC_ORIGIN}/favicon.svg"

  log "OIDC issuer: ${OIDC_ISSUER}"
  log "OIDC provider base URL: ${PROVIDER_BASEURL}"
  log "OIDC token endpoint: ${OIDC_TOKEN_ENDPOINT}"
  log "OIDC userinfo endpoint: ${OIDC_USERINFO_ENDPOINT}"
  log "CA cert path: ${OIDC_CA_CERT_PATH:-<not set>}"

  # Check if issuer already exists
  log "Checking for existing OAuth2 provider named '$OIDC_NAME'..."

  EXISTING_JSON=$(php_exec /opt/sei/custom-scripts/setup_environment.php \
      --step=manage_oauth \
      --list \
      --json=1 2>/dev/null)

  EXISTING_ID=$(printf '%s\n' "$EXISTING_JSON" | php -r '
    $name = "'"$OIDC_NAME"'";
    $data = json_decode(stream_get_contents(STDIN), true);
    if (!empty($data["data"])) {
        foreach ($data["data"] as $issuer) {
            if (isset($issuer["name"]) && $issuer["name"] === $name) {
                echo $issuer["id"];
                exit(0);
            }
        }
    }
    exit(1);
  ')

  if [ -n "$EXISTING_ID" ]; then
      log "OAuth2 provider already exists with ID: $EXISTING_ID"
      OAUTH2_ISSUER_ID="$EXISTING_ID"
      return 0
  fi

  log "No existing provider found. Creating a new one..."

  PROVIDER_OUTPUT=$(php_exec /opt/sei/custom-scripts/setup_environment.php \
    --step=manage_oauth \
    --baseurl="$PROVIDER_BASEURL" \
    --clientid="$OIDC_CLIENT_ID" \
    --clientsecret="$OIDC_CLIENT_SECRET" \
    --loginscopes="${OIDC_LOGIN_SCOPES:-openid profile email}" \
    --loginscopesoffline="${OIDC_LOGIN_SCOPES_OFFLINE:-openid profile email offline_access}" \
    --name="$OIDC_NAME" \
    --tokenendpoint="$OIDC_TOKEN_ENDPOINT" \
    --userinfoendpoint="$OIDC_USERINFO_ENDPOINT" \
    --image="$OIDC_ICON_URL" \
    --requireconfirmation="${OIDC_REQUIRE_CONFIRMATION:-0}" \
    --showonloginpage="$OIDC_SHOW_ON_LOGIN_PAGE" \
    2>&1)
  rc=$?
  log "Provider creation output: $PROVIDER_OUTPUT"
  if [ "$rc" -ne 0 ]; then
    error "$section" "Provider creation failed (rc=$rc)."
  fi

  NEW_ISSUER_ID=$(printf '%s\n' "$PROVIDER_OUTPUT" \
    | awk '/Created provider with ID[[:space:]][0-9]+/ {print $NF; exit}')
  if [ -z "$NEW_ISSUER_ID" ]; then
    error "$section" "Failed to retrieve the new provider ID; aborting mapping."
  fi
  log "OAuth2 Provider created successfully with ID: $NEW_ISSUER_ID"
  OAUTH2_ISSUER_ID="$NEW_ISSUER_ID"

  # ---- User field mappings ----
  log "Processing user field mappings: $OIDC_USER_FIELD_MAPPINGS"

  for m in $OIDC_USER_FIELD_MAPPINGS; do
    external=$(printf '%s' "$m" | cut -d':' -f1)
    internal=$(printf '%s' "$m" | cut -d':' -f2)
    json=$(printf '{"externalfieldname":"%s","internalfieldname":"%s"}' "$external" "$internal")

    if user_field_mapping_exists "$NEW_ISSUER_ID" "$external" "$internal"; then
      log "Mapping ($external -> $internal) already exists; continuing."
      continue
    fi

    local_attempt=1
    max_attempts="${OIDC_USERFIELD_RETRY_MAX:-5}"
    interval="${OIDC_USERFIELD_RETRY_INTERVAL:-5}"

    while true; do
      log "Creating user field mapping ($external -> $internal) for provider ID: $NEW_ISSUER_ID (attempt ${local_attempt}/${max_attempts})..."
      MAP_OUT=$(php_exec /opt/sei/custom-scripts/setup_environment.php \
        --step=manage_oauth \
        --create-user-field \
        --id="$NEW_ISSUER_ID" \
        --json="$json" 2>&1)
      rc=$?
      log "User field mapping output: $MAP_OUT"

      if [ "$rc" -eq 0 ]; then
        if printf '%s\n' "$MAP_OUT" | grep -q "User field mapping created"; then
          log "Mapping ($external -> $internal) created successfully."
        else
          log "Mapping ($external -> $internal) returned rc=0 but no success line; continuing."
        fi
        break
      fi

      if printf '%s\n' "$MAP_OUT" | grep -qi "already exists"; then
        log "Mapping ($external -> $internal) already exists; continuing."
        break
      fi

      if user_field_mapping_exists "$NEW_ISSUER_ID" "$external" "$internal"; then
        log "Mapping ($external -> $internal) detected after failure; continuing."
        break
      fi

      if [ "$local_attempt" -ge "$max_attempts" ]; then
        error "$section" "Failed to create mapping ($external -> $internal) (rc=$rc)."
      fi

      log "Retrying mapping ($external -> $internal) in ${interval}s..."
      sleep "$interval"
      local_attempt=$((local_attempt + 1))
    done
  done

  log "OAuth2 configuration completed successfully."
}

# Enable Oauth2 Plugin
enable_oauth2_plugin() {
  section="Enable OAuth2 Plugin"
  log "Enabling OAuth2 auth plugin..."
  out="$(php_exec /opt/sei/custom-scripts/setup_environment.php --step=enable_auth_oauth2 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    error "$section" "Failed to enable OAuth2 auth plugin: $out"
    return "$rc"
  fi
  log "$out"
}

configure_site() {
  section="Site Configuration"
  log "Configuring Site for OIDC provider communication..."

  # Extract the provider host from the discovery URL for CURL security
  OIDC_HOST=""
  if [ -n "$OIDC_DISCOVERY_URL" ]; then
    OIDC_HOST=$(echo "$OIDC_DISCOVERY_URL" | sed -e 's#^https\?://##' -e 's#/.*##')
  fi

  if [ "$OIDC_DISABLE_CURL_SECURITY" = "true" ]; then
    log "Disabling CURL security restrictions for internal OIDC provider communication..."

    php_exec /var/www/html/admin/cli/cfg.php --name=curlsecurityblockedhosts --set='' || error "$section" "Failed to set curlsecurityblockedhosts"
    php_exec /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedhosts --set='' || error "$section" "Failed to set curlsecurityallowedhosts"
    php_exec /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedport --set='' || error "$section" "Failed to set curlsecurityallowedport"

    log "CURL security restrictions disabled."
  else
    if [ -z "$OIDC_HOST" ]; then
      log "No OIDC provider host configured, skipping CURL security configuration."
      return 0
    fi

    log "Adding OIDC provider domain to allowed hosts..."

    CURRENT_ALLOWED=$(php_exec /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedhosts 2>/dev/null | grep -v "^$" | tail -1 || echo "")
    if [ -z "$CURRENT_ALLOWED" ] || [ "$CURRENT_ALLOWED" = "curlsecurityallowedhosts" ]; then
      NEW_ALLOWED="$OIDC_HOST"
    else
      if echo "$CURRENT_ALLOWED" | grep -q "$OIDC_HOST"; then
        NEW_ALLOWED="$CURRENT_ALLOWED"
      else
        NEW_ALLOWED=$(printf '%s\n%s' "$CURRENT_ALLOWED" "$OIDC_HOST")
      fi
    fi

    php_exec /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedhosts --set="$NEW_ALLOWED" || error "$section" "Failed to set curlsecurityallowedhosts"
    log "OIDC provider domain ($OIDC_HOST) added to allowed hosts."
  fi
}

# Main execution
log "Starting OIDC OAuth2 configuration script..."

# Create STATUS_FILE if it doesn't exist
touch "$STATUS_FILE"

# ALWAYS run Site Configuration (CURL security must be configured before OAuth2 operations)
log "Running section: Site Configuration"
configure_site
if [ $? -eq 0 ]; then
    record_status "Site Configuration" "Completed"
else
    record_status "Site Configuration" "Failed"
    error "Site Configuration" "Failed to configure site settings"
fi

# Execute sections based on status
execute_section "OAuth2 Configuration" configure_oauth2
execute_section "Enable OAuth2 Plugin" enable_oauth2_plugin

# On subsequent runs add admin user to the list of site admins
ADMINUSERID=$(moosh -n user-list 2>/dev/null | grep "$MOODLE_EMAIL" | sed -e "s/admin.*(\([0-9]\+\)),.*/\1/")
if [ -n "$ADMINUSERID" ]; then
    log "Found user $MOODLE_EMAIL with ID: $ADMINUSERID and resetting siteadmins list"
    php_exec /var/www/html/admin/cli/cfg.php --name=siteadmins --set="2,$ADMINUSERID"
fi

log "OIDC OAuth2 configuration script completed successfully!"
