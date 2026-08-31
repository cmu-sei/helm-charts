# Copyright 2025 Carnegie Mellon University. All Rights Reserved.
# Released under a MIT (SEI)-style license. See LICENSE.md in the project root for license information.

# Moodle ships its libraries in-tree, so composer only adds an egress dependency.
composer() {
  echo "[OVERRIDE] composer install skipped";
  return 0;
}
# $CFG->alternative_component_cache names a file, and Moodle does not create its parent.
mkdir -p /var/www/moodledata/localcache || true;
rm -f /var/www/moodledata/localcache/core_component.php || true;
rm -f /var/www/moodledata/cache/core_component.php || true;
{{- if and .codeVolume .secretConfig.name }}
if ! grep -q alternative_component_cache /var/www/html/config.php; then
  echo "[ERROR] The config.php supplied through readOnlyDirroot.secret.name does not set" >&2;
  echo "[ERROR] \$CFG->alternative_component_cache, so every pod would share one component" >&2;
  echo "[ERROR] cache on the dataroot and a rolling pod carrying older code would overwrite it," >&2;
  echo "[ERROR] leaving the fleet blind to newly added plugin code while every pod stays Ready." >&2;
  echo "[ERROR] Add this line to your config.php:" >&2;
  echo "[ERROR]   \$CFG->alternative_component_cache = \"/var/www/moodledata/localcache/core_component.php\";" >&2;
  exit 1;
fi
{{- if .redis.host }}
if ! grep -q "session_handler_class" /var/www/html/config.php || ! grep -q "session_redis_host" /var/www/html/config.php; then
  echo "[ERROR] moodle.redis.host is set and the config.php supplied through" >&2;
  echo "[ERROR] readOnlyDirroot.secret.name does not set \$CFG->session_redis_host. The chart owns" >&2;
  echo "[ERROR] no config.php here and refuses the image's own write, so Moodle keeps sessions as" >&2;
  echo "[ERROR] files on the shared dataroot while every pod stays Ready and the site answers 200," >&2;
  echo "[ERROR] which is what moodle.redis.host was set to prevent." >&2;
  echo "[ERROR] Add these lines to your config.php:" >&2;
  echo "[ERROR]   \$CFG->session_handler_class = '\core\session\redis';" >&2;
  echo "[ERROR]   \$CFG->session_redis_host = \"$REDIS_HOST\";" >&2;
  echo "[ERROR]   \$CFG->session_redis_serializer_use_igbinary = true;" >&2;
{{- if or .redis.password .redis.existingSecret }}
  echo "[ERROR]   \$CFG->session_redis_auth = getenv(\"REDIS_PASSWORD\");" >&2;
{{- end }}
  exit 1;
fi
{{- end }}
{{- end }}
{{- if and (not .codeVolume) (or .redis.password .redis.existingSecret) }}
case "$REDIS_PASSWORD" in
  *\'*|*\\*|*\&*|*\|*|*\;*|\[*|true|false)
    echo "[ERROR] The Redis password contains a character the image cannot write into config.php." >&2;
    echo "[ERROR] It is written with sed here, so a quote breaks the file and a backslash, ampersand," >&2;
    echo "[ERROR] pipe or semicolon rewrites it; a leading [ or the words true and false change type." >&2;
    echo "[ERROR] Use a password without those, or set readOnlyDirroot.enabled=true where the chart" >&2;
    echo "[ERROR] writes it as getenv() and never through sed." >&2;
    exit 1 ;;
esac
{{- end }}
upgrade_verdict() {
  php -d max_input_vars=10000 -r 'define("CLI_SCRIPT", true); define("CACHE_DISABLE_ALL", true); require("/var/www/html/config.php"); $version = 0; require($CFG->dirroot . "/version.php"); echo ((int)$version < (int)$CFG->version) ? "downgrade" : (moodle_needs_upgrading() ? "yes" : "no");' 2>/dev/null | tail -n 1;
}
# Plugins whose code is older than the database, including subplugins carried inside a parent
# archive. Moodle aborts mid-upgrade on the first one; naming them all first is more useful.
plugin_downgrades() {
  php -d max_input_vars=10000 -r 'define("CLI_SCRIPT", true); define("CACHE_DISABLE_ALL", true); require("/var/www/html/config.php"); foreach (core_plugin_manager::instance()->get_plugins() as $plugins) { foreach ($plugins as $p) { if ($p->versiondb !== null && $p->versiondisk !== null && $p->versiondisk < $p->versiondb) { echo "  " . $p->component . ": database has " . $p->versiondb . ", disk has " . $p->versiondisk . "\n"; } } }' 2>/dev/null;
}
upgrade_moodle() {
  UPGRADE_MAX_WAIT={{ mul 300 .maxPods }};
  UPGRADE_LOCK_MARKER="/tmp/.moodle_upgrade.acquired";
  export UPGRADE_LOCK_MARKER UPGRADE_MAX_WAIT;
  rm -f "$UPGRADE_LOCK_MARKER" || true;
  echo "[UPGRADE] Acquiring Moodle's own upgrade lock, which the database releases by itself if this pod dies...";
  php -d max_input_vars=10000 -r 'define("CLI_SCRIPT", true); require("/var/www/html/config.php"); $factory = \core\lock\lock_config::get_lock_factory("core_upgrade"); $lock = $factory->get_lock("moodle_upgrade", (int)getenv("UPGRADE_MAX_WAIT")); if (!$lock) { fwrite(STDERR, "did not acquire\n"); exit(1); } fwrite(STDERR, "held by " . get_class($factory) . "\n"); file_put_contents(getenv("UPGRADE_LOCK_MARKER"), (string)getmypid()); while (true) { sleep(1); }' &
  UPGRADE_LOCK_PID=$!;
  until [ -f "$UPGRADE_LOCK_MARKER" ]; do
    if ! kill -0 "$UPGRADE_LOCK_PID" 2>/dev/null; then
      echo "[ERROR] Could not acquire Moodle's upgrade lock within ${UPGRADE_MAX_WAIT}s." >&2;
      echo "[ERROR] Another replica is upgrading and did not finish, or the database refused the lock." >&2;
      exit 1;
    fi
    sleep 1;
  done
  php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=outagelessupgrade --set=0 >/dev/null 2>&1 || true;
  if [ -f /var/www/moodledata/climaintenance.html ]; then
    echo "[UPGRADE] A replica died with CLI maintenance mode enabled, lifting it";
    php -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --disable || rm -f /var/www/moodledata/climaintenance.html || true;
  fi
  verdict=$(upgrade_verdict) || verdict=unknown;
  upgrade_rc=0;
  # Not gated on the verdict: moodle_needs_upgrading() answers no when code is OLDER than the
  # database, so a plugin downgrade reaches here reported as "nothing to upgrade".
  if [ "$verdict" != downgrade ]; then
    downgrades=$(plugin_downgrades) || downgrades="";
    if [ -n "$downgrades" ]; then
      echo "[ERROR] These plugins are older on disk than in the database, and Moodle refuses to" >&2;
      echo "[ERROR] downgrade a plugin, so the upgrade would abort partway:" >&2;
      printf '%s\n' "$downgrades" >&2;
      echo "[ERROR] A subplugin can differ even when its parent version matches, because the archive" >&2;
      echo "[ERROR] is the unit: a git checkout and a published release can share a parent version" >&2;
      echo "[ERROR] and carry different contents. Declare the plugin with a url pointing at an" >&2;
      echo "[ERROR] archive built from the tree this database came from." >&2;
      exit 1;
    fi
  fi
  if [ "$verdict" = no ]; then
    echo "[UPGRADE] Moodle and every plugin already match the database, nothing to upgrade";
  elif [ "$verdict" = downgrade ]; then
    echo "[ERROR] The database is newer than this image, and Moodle has no down-migration." >&2;
    echo "[ERROR] Roll image.tag forward, or restore the database from backup." >&2;
    upgrade_rc=1;
  elif [ "$verdict" != yes ]; then
    echo "[ERROR] Could not determine whether Moodle needs an upgrade, so this pod will not" >&2;
    echo "[ERROR] enable maintenance mode on the shared dataroot. Check the database is reachable." >&2;
    upgrade_rc=1;
  else
    set +e;
    php -d max_input_vars=10000 /var/www/html/admin/cli/upgrade.php --is-maintenance-required;
    maintenance_rc=$?;
    set -e;
    if [ "$maintenance_rc" -ne 2 ] && [ "$maintenance_rc" -ne 3 ]; then
      echo "[ERROR] admin/cli/upgrade.php --is-maintenance-required exited $maintenance_rc," >&2;
      echo "[ERROR] which is neither 2 nor 3, so this pod will not guess and will not enable" >&2;
      echo "[ERROR] maintenance mode on the shared dataroot." >&2;
      upgrade_rc="$maintenance_rc";
      [ "$upgrade_rc" -ne 0 ] || upgrade_rc=1;
    elif [ "$maintenance_rc" -eq 3 ]; then
      echo "Upgrading moodle without maintenance mode, no schema change is required...";
      php -d max_input_vars=10000 /var/www/html/admin/cli/upgrade.php --non-interactive --allow-unstable --no-maintenance || upgrade_rc=$?;
      if [ "$upgrade_rc" -eq 0 ]; then
        php -d max_input_vars=10000 /var/www/html/admin/cli/purge_caches.php || upgrade_rc=$?;
      fi
      if [ "$upgrade_rc" -ne 0 ]; then
        echo "[ERROR] The outageless upgrade failed and left outagelessupgrade set in the database," >&2;
        echo "[ERROR] which makes moodle_needs_upgrading() answer no on every later replica, so the site" >&2;
        echo "[ERROR] would run half upgraded with every pod Ready. Clearing it so the next replica retries." >&2;
        php -d max_input_vars=10000 /var/www/html/admin/cli/cfg.php --name=outagelessupgrade --set=0 || true;
      fi
    else
      echo "Upgrading moodle...";
      if php -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --enable; then
        php -d max_input_vars=10000 /var/www/html/admin/cli/upgrade.php --non-interactive --allow-unstable || upgrade_rc=$?;
        php -d max_input_vars=10000 /var/www/html/admin/cli/maintenance.php --disable || rm -f /var/www/moodledata/climaintenance.html || true;
      else
        upgrade_rc=$?;
        rm -f /var/www/moodledata/climaintenance.html || true;
        echo "[ERROR] Could not enable maintenance mode, so no upgrade was attempted" >&2;
      fi
    fi
  fi
  [ -z "$UPGRADE_LOCK_PID" ] || kill "$UPGRADE_LOCK_PID" 2>/dev/null || true;
  rm -f "$UPGRADE_LOCK_MARKER" || true;
  if [ "$upgrade_rc" -ne 0 ]; then
    echo "[ERROR] The upgrade step failed with $upgrade_rc; maintenance mode was lifted and the upgrade lock released" >&2;
    exit "$upgrade_rc";
  fi
}
{{- if and .moodle.plugins (not .codeVolume) }}
php /opt/sei/custom-scripts/place_plugins.php \
    --root=/var/www/html --file=/opt/sei/custom-scripts/plugins.json
{{- end }}
{{- if and .oidc.enabled (not .codeVolume) }}
cp /opt/sei/custom-scripts/key.svg {{ .webRoot }}/pix/key.svg
{{- end }}
{{- if .codeVolume }}
# Override functions that try modifying read-only dirroot
update_or_add_config_value() {
  setting=$(printf '%s' "$1" | sed 's/.*[^a-z0-9_]\([a-z0-9_][a-z0-9_]*\)[^a-z0-9_]*$/\1/');
  if [ -z "$2" ]; then
    echo "[OVERRIDE] $1 is deliberately absent";
  elif grep -q -e "\$CFG->$setting" -e "[\"']$setting[\"'] *=>" /var/www/html/config.php 2>/dev/null; then
    echo "[OVERRIDE] $1 is set by the chart";
  else
    echo "[OVERRIDE] Drift: the image would set $1 and the chart's config.php does not" >&2;
  fi
  return 0;
}
final_configurations() {
  echo "[OVERRIDE] final_configurations() skipped";
  return 0;
}
{{- end }}
install_database() {
  echo "Installing database...";
  {{- if .multiPod }}
  SCHEMA_INSTALLED=started;
  {{- end }}
  php -d max_input_vars=10000 /var/www/html/admin/cli/install_database.php \
    --lang="$MOODLE_LANGUAGE" --adminuser="$MOODLE_USERNAME" \
    --adminpass="$MOODLE_PASSWORD" --adminemail="$MOODLE_EMAIL" \
    --fullname="$MOODLE_SITENAME" --shortname=moodle --agree-license;
  {{- if .multiPod }}
  SCHEMA_INSTALLED=yes;
  {{- end }}
}

DONE_FILE="/var/www/moodledata/.moodle_install.done"
VERSION_FILE=/var/www/html/public/version.php
[ -f "$VERSION_FILE" ] || VERSION_FILE=/var/www/html/version.php
CODE_VERSION=$(sed -n 's/^\$version *= *\([0-9.]*\).*/\1/p' "$VERSION_FILE" | head -1)
if [ -z "$CODE_VERSION" ]; then
  echo "[ERROR] The code tree $VERSION_FILE declares no \$version" >&2
  exit 1
fi
DONE_VERSION=$(cat "$DONE_FILE" 2>/dev/null || true)
if [ -n "$DONE_VERSION" ] && [ "$DONE_VERSION" != "$CODE_VERSION" ] && \
   [ "$(printf '%s\n%s\n' "$DONE_VERSION" "$CODE_VERSION" | sort -n | tail -1)" = "$DONE_VERSION" ]; then
  echo "[ERROR] The dataroot records Moodle $DONE_VERSION and this image is $CODE_VERSION." >&2
  echo "[ERROR] Moodle has no down-migration, and the image enables maintenance mode on the" >&2
  echo "[ERROR] shared dataroot before it fails, taking every healthy replica offline with it." >&2
  echo "[ERROR] Roll image.tag forward, or restore the database from backup and delete $DONE_FILE." >&2
  exit 1
fi
{{- if .multiPod }}

# Leader election for multi-replica deployments
#
# The lock lives in the dataroot root, not in cachedir. Moodle's Server_cluster page says file
# locks belong in cachedir or muc, and moving it there was tried and measurably broke mutual
# exclusion: with the lock under cache/ several replicas won the election simultaneously and two
# ran install_database concurrently, reproducibly, where the dataroot-root placement is clean
# across the full matrix and nine consecutive cold starts. The mechanism was never identified,
# so do not move it again without replicating that result first. mkdir is an atomic namespace
# operation rather than a lock protocol, so it does not need the locking support that sentence
# is protecting.
LOCK_FILE="/var/www/moodledata/.moodle_install.lock"
FAILED_FILE="/var/www/moodledata/.moodle_install.failed"
STALE_FILE="/var/www/moodledata/.moodle_install.stale.$HOSTNAME"
CACHE_DIR="/var/www/moodledata/cache"
STALE_AFTER=60
SLEEP_INTERVAL=5
MAX_WAIT={{ mul 300 .maxPods }}

release_install_lock() {
  install_rc=$?;
  [ -z "$HEARTBEAT_PID" ] || kill "$HEARTBEAT_PID" 2>/dev/null || true;
  if [ "$install_rc" -eq 0 ] || [ "$SCHEMA_INSTALLED" = yes ]; then
    if printf '%s\n' "$CODE_VERSION" > "$LOCK_FILE/done" && mv "$LOCK_FILE/done" "$DONE_FILE"; then
      echo "[INIT] This replica finished installing Moodle $CODE_VERSION!";
    else
      install_rc=1;
      echo "[ERROR] This replica installed Moodle $CODE_VERSION and lost $LOCK_FILE before recording it" >&2;
    fi
  elif [ "$SCHEMA_INSTALLED" = started ]; then
    { printf '%s %s\n' "$CODE_VERSION" "$HOSTNAME" > "$LOCK_FILE/failed" && mv "$LOCK_FILE/failed" "$FAILED_FILE"; } || true;
    echo "[ERROR] This replica failed to install Moodle $CODE_VERSION (rc=$install_rc), no other replica may proceed" >&2;
  else
    echo "[ERROR] This replica stopped before the database was touched (rc=$install_rc), the next replica may try again" >&2;
  fi
  rm -rf "$LOCK_FILE" || true;
  return $install_rc;
}

HEARTBEAT_PID=""
SCHEMA_INSTALLED=no
elapsed=0
age=0
lastbeat=""
while :; do
  if [ "$(cat "$DONE_FILE" 2>/dev/null)" = "$CODE_VERSION" ]; then
    echo "[INIT] Moodle $CODE_VERSION is installed, joining as a cluster node"
    break
  fi
  if [ -f "$FAILED_FILE" ]; then
    echo "[ERROR] A previous replica failed to install Moodle $CODE_VERSION and left $FAILED_FILE" >&2
    echo "[ERROR] Moodle cannot recover a half finished install. Restore the database from backup," >&2
    echo "[ERROR] then delete $FAILED_FILE and $CACHE_DIR so a replica may install again." >&2
    exit 1
  fi
  if mkdirout=$(mkdir "$LOCK_FILE" 2>&1); then
    printf '%s\n' "$HOSTNAME" > "$LOCK_FILE/owner"
    printf 'start\n' > "$LOCK_FILE/heartbeat"
    ( n=0
      while [ "$(cat "$LOCK_FILE/owner" 2>/dev/null)" = "$HOSTNAME" ]; do
        n=$((n + 1))
        printf '%s %s\n' "$HOSTNAME" "$n" > "$LOCK_FILE/heartbeat" 2>/dev/null || exit 0
        sleep 10
      done ) &
    HEARTBEAT_PID=$!
    trap release_install_lock EXIT
    echo "[INIT] This replica won the election and will install Moodle $CODE_VERSION..."
    break
  fi
  if [ ! -d "$LOCK_FILE" ]; then
    echo "[ERROR] Cannot create $LOCK_FILE: $mkdirout" >&2
    exit 1
  fi
  beat=$(cat "$LOCK_FILE/heartbeat" 2>/dev/null || true)
  if [ "$beat" != "$lastbeat" ]; then
    lastbeat="$beat"
    age=0
  elif [ "$age" -ge "$STALE_AFTER" ]; then
    echo "[INIT] The replica holding $LOCK_FILE stopped answering ${age}s ago, taking it over..."
    rm -rf "$STALE_FILE" || true
    mv "$LOCK_FILE" "$STALE_FILE" 2>/dev/null && { rm -rf "$STALE_FILE" || true; }
    age=0
    continue
  fi
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "[ERROR] Waited ${elapsed}s for another replica to install Moodle $CODE_VERSION" >&2
    exit 1
  fi
  echo "[INIT] Another replica is installing Moodle $CODE_VERSION, waiting..."
  sleep ${SLEEP_INTERVAL}
  age=$((age + SLEEP_INTERVAL))
  elapsed=$((elapsed + SLEEP_INTERVAL))
done
{{- else }}

record_install_version() {
  install_rc=$?;
  [ "$install_rc" -eq 0 ] || return $install_rc;
  printf '%s\n' "$CODE_VERSION" > "$DONE_FILE.$HOSTNAME" && mv "$DONE_FILE.$HOSTNAME" "$DONE_FILE";
  return 0;
}
trap record_install_version EXIT
{{- end }}
{{- if and (not .codeVolume) .multiPod }}

# Serialise config.php generation across replicas.
#
# The image runs admin/cli/install.php from generate_config_file (02-configure-moodle.sh:145)
# at boot line 372, for every replica, because at readOnlyDirroot.enabled=false config.php
# lives on the container layer and never survives a pod. That call initialises the MUC cache
# config, and Moodle's own cache_config_writer::save_config()
# (public/cache/classes/config_writer.php:108) guards it with a cachelock_file lock.
# cachelock_file::lock() (public/cache/locks/file/lib.php:164) returns false even when its
# blocking retry loop DID acquire the lock, so any contention makes save_config() throw
# ex_configcannotsave, install.php aborts, and the container exits 1 and is restarted.
#
# The chart's install election below does not cover this: it gates who installs the schema at
# boot line 403, while this runs at 372, and replicas that break out of the election as cluster
# nodes reach 372 together. Recreate makes that likelier than RollingUpdate did, because every
# pod starts at once instead of being staggered by maxSurge.
#
# So take the lock here, in PRE_CONFIGURE (boot line 362), before the image reaches the window,
# and call the image's own function rather than reimplementing it. Once one replica has written
# the shared muc config, the others find it present and never call save_config() at all.
#
# This must run AFTER the election above, not before it. install.php bootstraps Moodle, and a
# replica installing the schema sets $CFG->upgraderunning, which makes every other bootstrap
# throw 'Site is being upgraded, please retry later.' (public/lib/setup.php:787). Generating
# config before the election put joiners on the wire during the winner's install and traded one
# race for another.
CONFIG_LOCK="/var/www/moodledata/.moodle_config.lock"
CONFIG_LOCK_STALE_AFTER=300
CONFIG_LOCK_MAX_WAIT={{ mul 120 .maxPods }}
if [ ! -f "$config_file" ]; then
  cfg_elapsed=0
  while :; do
    if mkdir "$CONFIG_LOCK" 2>/dev/null; then
      printf '%s\n' "$HOSTNAME" > "$CONFIG_LOCK/owner" 2>/dev/null || true
      # No EXIT trap here. This runs after the election, and the winner has already installed
      # 'trap release_install_lock EXIT'; setting our own would overwrite it and clearing it with
      # 'trap - EXIT' would drop it entirely, so the winner would never write .moodle_install.done
      # nor release the install lock, and every joiner would wait out MAX_WAIT and restart.
      # If this replica dies holding CONFIG_LOCK, the stale takeover below reclaims it.
      echo "[INIT] Generating config.php while holding $CONFIG_LOCK"
      generate_config_file
      set_extra_db_settings
      rm -rf "$CONFIG_LOCK" 2>/dev/null || true
      break
    fi
    if [ ! -d "$CONFIG_LOCK" ]; then
      echo "[ERROR] Cannot create $CONFIG_LOCK on the shared dataroot" >&2
      exit 1
    fi
    lock_mtime=$(stat -c %Y "$CONFIG_LOCK" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ "$lock_mtime" -gt 0 ] && [ $((now - lock_mtime)) -gt "$CONFIG_LOCK_STALE_AFTER" ]; then
      echo "[INIT] $CONFIG_LOCK is older than ${CONFIG_LOCK_STALE_AFTER}s, taking it over"
      rm -rf "$CONFIG_LOCK" 2>/dev/null || true
      continue
    fi
    if [ "$cfg_elapsed" -ge "$CONFIG_LOCK_MAX_WAIT" ]; then
      echo "[ERROR] Waited ${cfg_elapsed}s for another replica to generate config.php" >&2
      exit 1
    fi
    echo "[INIT] Another replica is generating config.php, waiting..."
    sleep 3
    cfg_elapsed=$((cfg_elapsed + 3))
  done
fi{{- end }}

{{- with .moodle.preConfigureCommands }}
# User: Custom pre-configure commands
{{ . | nindent 0 }}
{{- end }}
