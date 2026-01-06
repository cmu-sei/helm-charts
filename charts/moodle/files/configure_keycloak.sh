#!/bin/sh
# Copyright 2025 Carnegie Mellon University. All Rights Reserved.
# Released under a MIT (SEI)-style license. See LICENSE.md in the project root for license information.

# Global Variables
STATUS_FILE="/tmp/keycloak_script_status.log"
LOG_FILE="/tmp/keycloak_script.log"
MOODLE_DIR="/var/www/html"
OAUTH2_ISSUER_ID=""

if [ -z "$KEYCLOAK_URL" ] && [ -n "$KEYCLOAK_DOMAIN" ]; then
  KEYCLOAK_URL="$KEYCLOAK_DOMAIN"
fi

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
    # Delete existing line for this section
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

  # Build URLs from environment variables
  if printf '%s' "$KEYCLOAK_URL" | grep -qE '^https?://'; then
    KEYCLOAK_BASE="$KEYCLOAK_URL"
  else
    KEYCLOAK_BASE="https://${KEYCLOAK_URL}"
  fi
  KEYCLOAK_REALM_URL="${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/"
  KEYCLOAK_TOKEN_ENDPOINT="${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token"
  KEYCLOAK_USERINFO_ENDPOINT="${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/userinfo"
  if [ -z "$KEYCLOAK_IMAGE" ]; then
    KEYCLOAK_IMAGE="${KEYCLOAK_BASE}/favicon.svg"
  fi

  # Verify required keys
  REQUIRED_KEYS="KEYCLOAK_URL KEYCLOAK_REALM KEYCLOAK_CLIENTID KEYCLOAK_CLIENTSECRET KEYCLOAK_LOGINSCOPES KEYCLOAK_LOGINSCOPESOFFLINE KEYCLOAK_NAME"
  for key in $REQUIRED_KEYS; do
    eval val=\$$key
    if [ -z "$val" ]; then
      error "$section" "Missing required configuration: $key"
    fi
  done

  # Check if issuer already exists
  log "Checking for existing OAuth2 provider named '$KEYCLOAK_NAME'..."

  EXISTING_JSON=$(php /opt/sei/custom-scripts/setup_environment.php \
      --step=manage_oauth \
      --list \
      --json=1 2>/dev/null)

  EXISTING_ID=$(printf '%s\n' "$EXISTING_JSON" | php -r '
    $name = "'"$KEYCLOAK_NAME"'";
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

  log "Creating a new OAuth2 provider..."
  PROVIDER_OUTPUT=$(php /opt/sei/custom-scripts/setup_environment.php \
    --step=manage_oauth \
    --baseurl="$KEYCLOAK_REALM_URL" \
    --clientid="$KEYCLOAK_CLIENTID" \
    --clientsecret="$KEYCLOAK_CLIENTSECRET" \
    --loginscopes="$KEYCLOAK_LOGINSCOPES" \
    --loginscopesoffline="$KEYCLOAK_LOGINSCOPESOFFLINE" \
    --name="$KEYCLOAK_NAME" \
    --tokenendpoint="$KEYCLOAK_TOKEN_ENDPOINT" \
    --userinfoendpoint="$KEYCLOAK_USERINFO_ENDPOINT" \
    --image="$KEYCLOAK_IMAGE" \
    --requireconfirmation="$KEYCLOAK_REQUIRECONFIRMATION" \
    --showonloginpage="$KEYCLOAK_SHOWONLOGINPAGE" \
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
  log "Processing user field mappings: $KEYCLOAK_USERFIELDMAPPINGS"

  for m in $KEYCLOAK_USERFIELDMAPPINGS; do
    external=$(printf '%s' "$m" | cut -d':' -f1)
    internal=$(printf '%s' "$m" | cut -d':' -f2)
    json=$(printf '{"externalfieldname":"%s","internalfieldname":"%s"}' "$external" "$internal")

    log "Creating user field mapping ($external -> $internal) for provider ID: $NEW_ISSUER_ID..."
    MAP_OUT=$(php /opt/sei/custom-scripts/setup_environment.php \
      --step=manage_oauth \
      --create-user-field \
      --id="$NEW_ISSUER_ID" \
      --json="$json" 2>&1)
    rc=$?
    log "User field mapping output: $MAP_OUT"

    if [ "$rc" -ne 0 ]; then
      if printf '%s\n' "$MAP_OUT" | grep -qi "already exists"; then
        log "Mapping ($external -> $internal) already exists; continuing."
      else
        error "$section" "Failed to create mapping ($external -> $internal) (rc=$rc)."
      fi
    else
      if printf '%s\n' "$MAP_OUT" | grep -q "User field mapping created"; then
        log "Mapping ($external -> $internal) created successfully."
      else
        log "Mapping ($external -> $internal) returned rc=0 but no success line; continuing."
      fi
    fi
  done

  log "OAuth2 configuration completed successfully."
}

# Enable Oauth2 Plugin
enable_oauth2_plugin() {
  section="Enable OAuth2 Plugin"
  log "Enabling OAuth2 auth plugin..."
  out="$(php /opt/sei/custom-scripts/setup_environment.php --step=enable_auth_oauth2 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    error "$section" "Failed to enable OAuth2 auth plugin: $out"
    return "$rc"
  fi
  log "$out"
}

configure_site() {
  section="Site Configuration"
  log "Configuring Site for Keycloak communication..."

  if [ "$KEYCLOAK_DISABLE_CURL_SECURITY" = "true" ]; then
    log "Disabling CURL security restrictions for internal Keycloak communication..."

    # Allow all hosts by setting an empty blocklist and empty allowlist
    php /var/www/html/admin/cli/cfg.php --name=curlsecurityblockedhosts --set='' || error "$section" "Failed to set curlsecurityblockedhosts"
    php /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedhosts --set='' || error "$section" "Failed to set curlsecurityallowedhosts"
    php /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedport --set='' || error "$section" "Failed to set curlsecurityallowedport"

    log "CURL security restrictions disabled."
  else
    log "Adding Keycloak domain to allowed hosts..."

    # Extract base host from KEYCLOAK_URL (remove scheme/path if present)
    KEYCLOAK_HOST=$(echo "$KEYCLOAK_URL" | sed -e 's#^https\\?://##' -e 's#/.*##')

    # Get current allowed hosts and add Keycloak host
    CURRENT_ALLOWED=$(php /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedhosts 2>/dev/null | grep -v "^$" | tail -1 || echo "")
    if [ -z "$CURRENT_ALLOWED" ] || [ "$CURRENT_ALLOWED" = "curlsecurityallowedhosts" ]; then
      NEW_ALLOWED="$KEYCLOAK_HOST"
    else
      # Append if not already present
      if echo "$CURRENT_ALLOWED" | grep -q "$KEYCLOAK_HOST"; then
        NEW_ALLOWED="$CURRENT_ALLOWED"
      else
        NEW_ALLOWED=$(printf '%s\n%s' "$CURRENT_ALLOWED" "$KEYCLOAK_HOST")
      fi
    fi

    php /var/www/html/admin/cli/cfg.php --name=curlsecurityallowedhosts --set="$NEW_ALLOWED" || error "$section" "Failed to set curlsecurityallowedhosts"
    log "Keycloak domain ($KEYCLOAK_HOST) added to allowed hosts."
  fi
}

# Main execution
log "Starting Keycloak OAuth2 configuration script..."

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
    php /var/www/html/admin/cli/cfg.php --name=siteadmins --set="2,$ADMINUSERID"
fi

log "Keycloak OAuth2 configuration script completed successfully!"
