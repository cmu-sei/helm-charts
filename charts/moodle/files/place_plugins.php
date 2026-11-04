<?php
// Copyright 2025 Carnegie Mellon University. All Rights Reserved.
// Released under a MIT (SEI)-style license. See LICENSE.md in the project root for license information.

// place_plugins.php: place declared plugin source trees into a Moodle code tree.

function fail($component, $message) {
    if ($component === '-') {
        fwrite(STDERR, "$message\n");
        exit(1);
    }
    fwrite(STDERR, "$component: $message\n");
    exit(1);
}

function info($message) {
    fwrite(STDOUT, "$message\n");
}

// A source could not be reached or did not answer with a usable archive. The caller decides
// whether a cached copy, an optional skip or a failed boot follows.
class fetch_failed extends Exception {
}

$options = getopt('', ['root:', 'file:', 'cache:']);
$root = rtrim($options['root'] ?? '', '/');
$file = $options['file'] ?? '';
$cache = rtrim($options['cache'] ?? '', '/');
if ($root === '' || $file === '') {
    fwrite(STDERR, "Usage: place_plugins.php --root=<moodle tree> --file=<plugins.json> [--cache=<dir>]\n");
    exit(1);
}
if (!is_dir($root)) {
    fail('-', "--root=$root is not a directory");
}
if (!is_readable($file)) {
    fail('-', "--file=$file is not readable");
}
$plugins = json_decode(file_get_contents($file), true);
if (!is_array($plugins)) {
    fail('-', "$file is not a JSON array");
}
if (count($plugins) === 0) {
    info('no plugins declared');
    exit(0);
}

// 5.1 and later keep version.php under public/, earlier releases at the tree root.
$versionfile = "$root/public/version.php";
if (!is_file($versionfile)) {
    $versionfile = "$root/version.php";
}
if (!is_file($versionfile)) {
    fail('-', "no version.php under $root - is this a Moodle tree?");
}
$versionsrc = file_get_contents($versionfile);
$branch = '';
if (preg_match('/^\$branch\s*=\s*[\'"]([^\'"]+)/m', $versionsrc, $m)) {
    $branch = $m[1];
}

// components.json paths are relative to the tree root and already carry any public prefix.
$componentsfile = "$root/lib/components.json";
if (!is_file($componentsfile)) {
    $componentsfile = "$root/public/lib/components.json";
}
if (!is_file($componentsfile)) {
    fail('-', "no lib/components.json under $root - cannot resolve plugin directories");
}
$components = json_decode(file_get_contents($componentsfile), true);
if (!is_array($components) || empty($components['plugintypes'])) {
    fail('-', "$componentsfile has no plugintypes map");
}
$types = [];
foreach ($components['plugintypes'] as $type => $relative) {
    if (is_string($relative) && $relative !== '') {
        $types[$type] = "$root/" . trim($relative, '/');
    }
}

// Subplugin types such as logstore are declared by their owning plugin, not by components.json.
function resolve_subplugin_type($type, $types) {
    foreach ($types as $typeroot) {
        foreach ((glob("$typeroot/*/db/subplugins.json") ?: []) as $declaration) {
            $decoded = json_decode(file_get_contents($declaration), true);
            $subtypes = $decoded['subplugintypes'] ?? [];
            if (!isset($subtypes[$type]) || !is_string($subtypes[$type])) {
                continue;
            }
            $ownerdir = dirname(dirname($declaration));
            return $ownerdir . '/' . trim($subtypes[$type], '/');
        }
    }
    return null;
}

// Read $plugin->version from a plugin's own version.php, or null.
function ondisk_version($dir) {
    $file = "$dir/version.php";
    if (!is_file($file)) {
        return null;
    }
    if (preg_match('/\$plugin->version\s*=\s*([0-9]+)/', file_get_contents($file), $m)) {
        return $m[1];
    }
    return null;
}

// Where a plugin came from, so a changed url is not masked by an unchanged version.
const SOURCE_MARKER = '.moodle-plugin-source';
function source_marker($dir) {
    $file = "$dir/" . SOURCE_MARKER;
    if (!is_file($file)) {
        return null;
    }
    $decoded = json_decode((string)file_get_contents($file), true);
    return is_array($decoded) ? $decoded : null;
}

// Read $plugin->component from a plugin's own version.php, or null.
function declared_component($dir) {
    $file = "$dir/version.php";
    if (!is_file($file)) {
        return null;
    }
    if (preg_match('/\$plugin->component\s*=\s*[\'"]([a-z0-9_]+)/', file_get_contents($file), $m)) {
        return $m[1];
    }
    return null;
}

// A User-Agent is always sent: download.moodle.org answers 403 without one.
function http_get($component, $url, $tofile = null) {
    $attempts = 3;
    for ($attempt = 1; ; $attempt++) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS      => 5,
            CURLOPT_USERAGENT      => 'moodle-helm-chart/1.0',
            CURLOPT_CONNECTTIMEOUT => 30,
            CURLOPT_TIMEOUT        => 300,
            CURLOPT_FAILONERROR    => true,
        ]);
        $handle = null;
        if ($tofile !== null) {
            $handle = fopen($tofile, 'wb');
            if ($handle === false) {
                fail($component, "cannot open $tofile for writing");
            }
            curl_setopt($ch, CURLOPT_FILE, $handle);
        } else {
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        }
        $result = curl_exec($ch);
        $error  = curl_error($ch);
        $status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        if ($handle !== null) {
            fclose($handle);
        }
        if ($result !== false) {
            return $result;
        }
        if ($attempt >= $attempts) {
            throw new fetch_failed("GET $url failed (HTTP $status): $error");
        }
        info("$component: GET $url failed (HTTP $status): $error, retrying");
        sleep(5 * $attempt);
    }
}

// Convert the branch version.php carries into the form the plugins API filters on.
function branch_to_api_format($branch) {
    if (strpos($branch, '.') !== false) {
        return $branch;
    }
    $numeric = (int)$branch;
    if ($numeric <= 0) {
        return $branch;
    }
    if ($numeric >= 310) {
        $major = (int)floor($numeric / 100);
        return $major . '.' . ($numeric - 100 * $major);
    }
    return substr($branch, 0, -1) . '.' . substr($branch, -1);
}

// Ask download.moodle.org for a download URL and md5.
function query_pluginfo($component, $query) {
    $url = 'https://download.moodle.org/api/1.3/pluginfo.php?' . $query;
    $decoded = json_decode(http_get($component, $url), true);
    if (!is_array($decoded) || ($decoded['status'] ?? '') !== 'OK') {
        throw new fetch_failed("pluginfo API did not return OK for $url");
    }
    $version = $decoded['pluginfo']['version'] ?? null;
    if (empty($version['downloadurl'])) {
        throw new fetch_failed("pluginfo API returned no downloadurl for $url");
    }
    return [
        'downloadurl' => $version['downloadurl'],
        'downloadmd5' => $version['downloadmd5'] ?? null,
        'version'     => (string)($version['version'] ?? ''),
    ];
}

// The cache holds the last archive placed for each declaration, so a source that is down
// at boot does not stop the pod. It is best effort: nothing here fails the run.
function cache_key($component, $url, $version, $branch) {
    return $component . '-' . substr(hash('sha256', json_encode([$url, $version, $branch])), 0, 16);
}

function cache_lookup($cache, $component, $key) {
    if ($cache === '') {
        return null;
    }
    $zip = "$cache/$key.zip";
    $meta = json_decode((string)@file_get_contents("$cache/$key.json"), true);
    if (!is_array($meta) || !is_file($zip)) {
        return null;
    }
    if (hash_file('sha256', $zip) !== ($meta['sha256'] ?? '')) {
        info("$component: cached copy $zip does not match its checksum, ignoring it");
        return null;
    }
    return $zip;
}

function cache_store($cache, $component, $key, $zip, $meta) {
    if ($cache === '') {
        return;
    }
    if (!is_dir($cache) && !@mkdir($cache, 0755, true)) {
        info("$component: warning: cannot create plugin cache $cache, not caching");
        return;
    }
    // Written under a private name and renamed, so a pod sharing the dataroot never reads half a file.
    $tmp = "$cache/.$key." . getmypid() . '.tmp';
    $meta['sha256'] = hash_file('sha256', $zip);
    if (!@copy($zip, $tmp) || @file_put_contents("$tmp.json", json_encode($meta) . "\n") === false
            || !@rename($tmp, "$cache/$key.zip") || !@rename("$tmp.json", "$cache/$key.json")) {
        @unlink($tmp);
        @unlink("$tmp.json");
        info("$component: warning: cannot write to plugin cache $cache, not caching");
        return;
    }
    info("$component cached as $cache/$key.zip");
}

// Drop entries no current declaration uses, and temp files a killed run left behind.
function cache_prune($cache, $keep) {
    if ($cache === '' || !is_dir($cache)) {
        return;
    }
    foreach ((glob("$cache/*.{zip,json}", GLOB_BRACE) ?: []) as $path) {
        if (!in_array(pathinfo($path, PATHINFO_FILENAME), $keep, true)) {
            @unlink($path);
        }
    }
    foreach ((glob("$cache/.*.tmp*") ?: []) as $path) {
        if (filemtime($path) < time() - 3600) {
            @unlink($path);
        }
    }
}

function rm_rf($path) {
    if (is_link($path) || (file_exists($path) && !is_dir($path))) {
        @unlink($path);
        return;
    }
    if (!is_dir($path)) {
        return;
    }
    foreach (scandir($path) as $entry) {
        if ($entry === '.' || $entry === '..') {
            continue;
        }
        rm_rf("$path/$entry");
    }
    @rmdir($path);
}

// A plugin type directory the tree does not ship has no realpath, so containment resolves against the nearest ancestor.
function nearest_existing($path) {
    while ($path !== '' && $path !== '/' && $path !== '.' && !file_exists($path)) {
        $path = dirname($path);
    }
    return realpath($path);
}

// The staging directory lives inside --root so that rename() never crosses a mount.
$staging = "$root/.chart-plugin-staging";
rm_rf($staging);
if (!@mkdir($staging, 0755, true)) {
    fail('-', "cannot create staging directory $staging");
}
register_shutdown_function(function () use ($staging) {
    rm_rf($staging);
});

$realroot = realpath($root);
$apibranch = $branch === '' ? '' : branch_to_api_format($branch);
$keep = [];
$skipped = [];

foreach ($plugins as $index => $entry) {
    if (!is_array($entry) || empty($entry['name'])) {
        fail('-', "moodle.plugins[$index] has no name");
    }
    $component = (string)$entry['name'];
    $url       = isset($entry['url']) ? trim((string)$entry['url']) : '';
    $version   = isset($entry['version']) ? trim((string)$entry['version']) : '';
    $optional  = $entry['optional'] ?? false;
    if (!is_bool($optional)) {
        fail($component, 'optional must be true or false');
    }
    $floats = ($url === '' && $version === '');
    // A floating plugin follows the Moodle branch, so a cached copy for another branch is not reused.
    $key = cache_key($component, $url, $version, $floats ? $apibranch : '');
    $keep[] = $key;

    if (!preg_match('/^([a-z][a-z0-9]*)_([a-z][a-z0-9_]*)$/', $component, $split)) {
        fail($component, 'name must be <plugintype>_<pluginname>, lowercase');
    }
    [, $type, $shortname] = $split;

    $typeroot = $types[$type] ?? resolve_subplugin_type($type, $types);
    if ($typeroot === null) {
        fail($component, "unknown plugin type '$type': not in lib/components.json and not declared as a subplugin type by any installed plugin");
    }
    $target = "$typeroot/$shortname";

    $parent = nearest_existing(dirname($target));
    if ($parent === false || strpos($parent . '/', $realroot . '/') !== 0) {
        fail($component, "resolved target $target is outside --root=$root");
    }

    // An explicit pin the disk already satisfies needs no network at all, but only when it
    // came from the same place: a changed url with an unchanged version must still be fetched.
    $disk = ondisk_version($target);
    if ($version !== '' && $disk !== null && bccomp_str($disk, $version) === 0) {
        $marker = source_marker($target);
        if ($marker === null || ($marker['url'] ?? '') === $url) {
            info("$component already on disk at $version, skipping");
            continue;
        }
        info("$component is on disk at $version but its url changed, replacing");
    }

    if ($floats && $branch === '') {
        fail($component, "no version pinned and \$branch could not be read from $versionfile");
    }

    $zip = "$staging/$component.zip";
    $fromcache = false;
    try {
        if ($url !== '') {
            $downloadurl = $url;
            $md5 = null;
        } else if ($version !== '') {
            $resolved = query_pluginfo($component, 'plugin=' . rawurlencode("$component@$version"));
            $downloadurl = $resolved['downloadurl'];
            $md5 = $resolved['downloadmd5'];
        } else {
            $resolved = query_pluginfo($component, 'plugin=' . rawurlencode($component) . '&branch=' . rawurlencode($apibranch) . '&minversion=0');
            if ($disk !== null && bccomp_str($disk, $resolved['version']) === 0) {
                info("$component floats and the disk already holds {$resolved['version']} on branch $apibranch, skipping");
                continue;
            }
            $downloadurl = $resolved['downloadurl'];
            $md5 = $resolved['downloadmd5'];
            info("$component floats: resolved to version {$resolved['version']} on branch $apibranch");
        }

        info("$component <- $downloadurl");
        http_get($component, $downloadurl, $zip);

        if ($md5 !== null && $md5 !== '') {
            $actual = md5_file($zip);
            if ($actual !== $md5) {
                throw new fetch_failed("checksum mismatch: expected $md5, got $actual");
            }
        }
    } catch (fetch_failed $e) {
        if ($floats && $disk !== null) {
            // Any version satisfies a floating declaration, so the tree already there serves.
            info("$component: warning: {$e->getMessage()}; keeping version $disk already on disk");
            continue;
        }
        $cached = cache_lookup($cache, $component, $key);
        if ($cached !== null) {
            info("$component: warning: {$e->getMessage()}; placing the cached copy $cached");
            if (!@copy($cached, $zip)) {
                fail($component, "cannot copy the cached copy $cached into $zip");
            }
            $fromcache = true;
        } else if ($optional) {
            info("$component: warning: {$e->getMessage()}; optional and not cached, so it is skipped this boot");
            $skipped[] = $component;
            continue;
        } else {
            fail($component, $e->getMessage() . ($cache === '' ? '' : ', and there is no cached copy in ' . $cache));
        }
    }

    $extract = "$staging/$component.d";
    rm_rf($extract);
    if (!@mkdir($extract, 0755, true)) {
        fail($component, "cannot create $extract");
    }
    $archive = new ZipArchive();
    if ($archive->open($zip) !== true) {
        fail($component, "cannot open the " . ($fromcache ? 'cached' : 'downloaded') . " archive as a zip");
    }
    if (!$archive->extractTo($extract)) {
        $archive->close();
        fail($component, "cannot extract the archive into $extract");
    }
    $archive->close();

    $tops = array_values(array_diff(scandir($extract), ['.', '..']));
    if (count($tops) !== 1 || !is_dir("$extract/$tops[0]")) {
        fail($component, 'the archive must contain exactly one top-level directory, found: ' . implode(', ', $tops));
    }
    $topdir = "$extract/$tops[0]";
    // The archive's own version.php is authoritative about the component, its directory name is not.
    $declared = declared_component($topdir);
    if ($declared !== null) {
        if ($declared !== $component) {
            fail($component, "the archive declares component '$declared'");
        }
    } else if (ondisk_version($topdir) === null) {
        fail($component, "the archive's top-level directory '$tops[0]' has no readable version.php");
    } else if ($tops[0] !== $shortname) {
        fail($component, "the archive declares no \$plugin->component and its top-level directory is '$tops[0]', not '$shortname'");
    }

    if (!is_dir(dirname($target)) && !@mkdir(dirname($target), 0755, true)) {
        fail($component, 'cannot create ' . dirname($target));
    }
    rm_rf($target);
    if (!@rename($topdir, $target)) {
        fail($component, "cannot move the plugin into $target");
    }
    rm_rf($extract);

    $placed = ondisk_version($target) ?? 'unknown';
    if ($version !== '' && bccomp_str($placed, $version) !== 0) {
        fail($component, "moodle.plugins declares version $version and the archive is $placed");
    }
    @file_put_contents("$target/" . SOURCE_MARKER, json_encode(['url' => $url, 'version' => $placed]) . "\n");
    info("$component placed at $target (version $placed" . ($fromcache ? ', from the cache' : '') . ')');
    if (!$fromcache) {
        cache_store($cache, $component, $key, $zip, ['component' => $component, 'url' => $url, 'version' => $placed]);
    }
    @unlink($zip);
}

cache_prune($cache, $keep);

// setup_environment.php reads this so enabledPlugins does not fail on a plugin skipped above.
$skippedfile = "$root/.chart-plugins-skipped.json";
if (@file_put_contents($skippedfile, json_encode($skipped) . "\n") === false && $skipped) {
    fail('-', "cannot write $skippedfile");
}
if ($skipped) {
    info('declared plugins are on disk except optional ' . implode(', ', $skipped));
} else {
    info('all declared plugins are on disk');
}
exit(0);

// Compare two Moodle version stamps as numeric strings of possibly unequal length.
function bccomp_str($a, $b) {
    $length = max(strlen($a), strlen($b));
    $a = str_pad($a, $length, '0', STR_PAD_LEFT);
    $b = str_pad($b, $length, '0', STR_PAD_LEFT);
    return strcmp($a, $b);
}
?>
