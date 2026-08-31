<?php
// Copyright 2025 Carnegie Mellon University. All Rights Reserved.
// Released under a MIT (SEI)-style license. See LICENSE.md in the project root for license information.

// setup_environment.php — multi-function CLI for Moodle configuration
define('CLI_SCRIPT', true);
require('/var/www/html/config.php');

require_once($CFG->libdir . '/clilib.php');
require_once($CFG->dirroot . '/course/lib.php');

// Parse CLI options
list($options, $unrecognized) = cli_get_params([
    'step' => null,
    'file' => '',
    'secretsfile' => '',

    // OAuth2 options
    'id' => '',
    'baseurl' => '',
    'clientid' => '',
    'clientsecret' => '',
    'loginscopes' => '',
    'loginscopesoffline' => '',
    'loginparams' => '',
    'loginparamsoffline' => '',
    'name' => '',
    'showonloginpage' => true,
    'image' => '',
    'list' => false,
    'delete' => false,
    'delete-all' => false,
    'create-user-field' => false,
    'check-user-field' => false,
    'json' => false,
    'requireconfirmation' => false,
    'tokenendpoint' => '',
    'userinfoendpoint' => '',
    'externalfield' => '',
    'internalfield' => '',
    'prefix' => '',
]);

// Step dispatcher
switch ($options['step']) {
    case 'manage_oauth':
        manage_oauth($options);
        break;

    case 'enable_auth_oauth2':
        enable_auth_oauth2();
        break;

    case 'apply_preset':
        apply_preset($options);
        break;

    case 'set_configs':
        set_configs($options);
        break;

    case 'enable_plugins':
        enable_plugins($options);
        break;

    case 'set_cache_prefix':
        set_cache_prefix($options);
        break;

    default:
        cli_error("Unknown step");
}

function manage_oauth($options) {
    global $CFG;
    require_once("$CFG->libdir/clilib.php");
    require_once("$CFG->libdir/adminlib.php");
    require_once($CFG->dirroot . '/user/lib.php');
    \core\session\manager::set_user(get_admin());

    $api = new \core\oauth2\api();
    $issuer_settings = [
        'id', 'baseurl', 'clientid', 'clientsecret', 'loginscopes',
        'loginscopesoffline', 'name', 'image', 'showonloginpage',
        'requireconfirmation', 'loginparams', 'loginparamsoffline', 'alloweddomains',
    ];

    $results = ['success' => true, 'data' => []];

    if ($options['check-user-field']) {
        if (empty($options['id']) || $options['externalfield'] === '' || $options['internalfield'] === '') {
            cli_error("Missing required fields for user field mapping check.");
        }

        $results = ['success' => true, 'exists' => false];
        try {
            global $DB;
            $results['exists'] = $DB->record_exists('oauth2_user_field_mapping', [
                'issuerid' => $options['id'],
                'externalfield' => $options['externalfield'],
                'internalfield' => $options['internalfield'],
            ]);
        } catch (Exception $e) {
            $results['success'] = false;
            $results['error'] = $e->getMessage();
        }

        output_results($options, $results);
        return;
    }

    if ($options['create-user-field'] && $options['id'] && $options['json']) {
        $mapping_data = json_decode($options['json']);
        if (!$mapping_data || !isset($mapping_data->externalfieldname) || !isset($mapping_data->internalfieldname)) {
            cli_error("Invalid or missing JSON data for user field mapping.");
        }

        $data = new stdClass();
        $data->issuerid = $options['id'];
        $data->externalfield = $mapping_data->externalfieldname;
        $data->internalfield = $mapping_data->internalfieldname;

        try {
            \core\oauth2\api::create_user_field_mapping($data);
            cli_writeln("User field mapping created for provider ID {$options['id']}.");
        } catch (Exception $e) {
            cli_error("Error creating user field mapping: " . $e->getMessage());
        }
        return;
    }

    if ($options['list']) {
        if ($options['id']) {
            $issuer = $api->get_issuer($options['id']);
            if (!$issuer) {
                $results['success'] = false;
                $results['data'] = 'Provider not found.';
            } else {
                foreach ($issuer_settings as $key) {
                    $results['data'][$key] = $issuer->get($key);
                }
            }
        } else {
            foreach ($api->get_all_issuers() as $issuer) {
                $item = [];
                foreach ($issuer_settings as $key) {
                    $item[$key] = $issuer->get($key);
                }
                $results['data'][] = $item;
            }
        }
        output_results($options, $results);
        return;
    }

    if ($options['delete'] && $options['id']) {
        $issuer = $api->get_issuer($options['id']);
        if (!$issuer) {
            cli_error("Provider with ID {$options['id']} not found.");
        }
        $api->delete_issuer($options['id']);
        cli_writeln("Deleted provider with ID {$options['id']}");
        return;
    }

    if ($options['delete-all']) {
        foreach ($api->get_all_issuers() as $issuer) {
            $id = $issuer->get('id');
            if ($id) {
                $api->delete_issuer($id);
                cli_writeln("Deleted provider with ID {$id}");
            }
        }
        cli_writeln("Deleted all OAuth providers.");
        return;
    }

    $data = (object)[];
    foreach (['id', 'baseurl', 'clientid', 'clientsecret', 'loginscopes', 'loginscopesoffline', 'name', 'image', 'showonloginpage', 'requireconfirmation'] as $key) {
        if (isset($options[$key]) && $options[$key] !== '') {
            $data->$key = $options[$key];
        }
    }

    if (empty($data->id)) {
        if (empty($data->baseurl) || empty($data->clientid) || empty($data->clientsecret) || empty($data->name)) {
            cli_error("Missing required fields: baseurl, clientid, clientsecret, name.");
        }

        $discoveryurl = rtrim($data->baseurl, '/') . '/.well-known/openid-configuration';
        cli_writeln("OAuth2 baseurl: {$data->baseurl}");
        cli_writeln("OAuth2 discovery URL: {$discoveryurl}");
        if (!empty($options['tokenendpoint'])) {
            cli_writeln("OAuth2 token endpoint: {$options['tokenendpoint']}");
        }
        if (!empty($options['userinfoendpoint'])) {
            cli_writeln("OAuth2 userinfo endpoint: {$options['userinfoendpoint']}");
        }
    }

    if (empty($data->id)) {
        try {
            $issuer = $api->create_issuer($data);
            $issuerid = $issuer->get('id');
            if ($issuerid) {
                cli_writeln("Created provider with ID {$issuerid}");
            } else {
                cli_error("Failed to retrieve ID of new provider.");
            }
        } catch (Exception $e) {
            cli_error("Error creating OAuth2 issuer for baseurl {$data->baseurl}: " . $e->getMessage());
        }
    } else {
        try {
            $api->update_issuer($data);
            cli_writeln("Updated provider with ID {$data->id}");
        } catch (Exception $e) {
            cli_error("Error updating OAuth2 issuer: " . $e->getMessage());
        }
    }

    // Update endpoint
    $tokenurl    = $options['tokenendpoint'] ?? '';
    $userinfourl = $options['userinfoendpoint'] ?? '';

    if ($tokenurl !== '' || $userinfourl !== '') {
        // Get existing endpoints
        $existing = [];
        foreach (\core\oauth2\api::get_endpoints($issuer) as $endpoint) {
            $existing[$endpoint->get('name')] = $endpoint;
        }

        // Token endpoint.
        if ($tokenurl !== '') {
            $edata = new stdClass();
            $edata->issuerid = $issuerid;
            $edata->name     = 'token_endpoint';
            $edata->url      = $tokenurl;

            if (isset($existing['token_endpoint'])) {
                $edata->id = $existing['token_endpoint']->get('id');
                \core\oauth2\api::update_endpoint($edata);
                cli_writeln("Updated token_endpoint for issuer ID {$issuerid} to {$tokenurl}");
            } else {
                \core\oauth2\api::create_endpoint($edata);
                cli_writeln("Created token_endpoint for issuer ID {$issuerid} with URL {$tokenurl}");
            }
        }

        // Userinfo endpoint.
        if ($userinfourl !== '') {
            $edata = new stdClass();
            $edata->issuerid = $issuerid;
            $edata->name     = 'userinfo_endpoint';
            $edata->url      = $userinfourl;

            if (isset($existing['userinfo_endpoint'])) {
                $edata->id = $existing['userinfo_endpoint']->get('id');
                \core\oauth2\api::update_endpoint($edata);
                cli_writeln("Updated userinfo_endpoint for issuer ID {$issuerid} to {$userinfourl}");
            } else {
                \core\oauth2\api::create_endpoint($edata);
                cli_writeln("Created userinfo_endpoint for issuer ID {$issuerid} with URL {$userinfourl}");
            }
        }
    }
}

function enable_auth_oauth2() {
    // Ensure the class is available
    if (!class_exists('\auth_oauth2\api')) {
        throw new \moodle_exception('auth_oauth2 API class not found');
    }

    if (!\auth_oauth2\api::is_enabled()) {
        if (method_exists('\auth_oauth2\api', 'set_enabled')) {
            \auth_oauth2\api::set_enabled(true);
        } else {
            // Fallback for older versions where only config string is used
            $enabled = get_enabled_auth_plugins(true);
            $enabled[] = 'oauth2';
            set_config('auth', implode(',', array_unique($enabled)));
        }
    }
}

function load_json($file) {
    if (!is_readable($file)) {
        cli_error("Cannot read {$file}");
    }
    $data = json_decode(file_get_contents($file), true);
    if (!is_array($data)) {
        cli_error("Malformed JSON in {$file}");
    }
    return $data;
}

// cachestore_redis purges a definition by unlinking its whole hash, and that hash is
// md5("mode component area") with nothing site specific in it. Two Moodle sites on one Redis
// therefore share every definition hash, and a purge on either drops the other's entries.
// Moodle exposes a key prefix for exactly this; it permits at most 5 characters.
function set_cache_prefix($options) {
    $prefix = trim((string)$options['prefix']);
    if ($prefix === '') {
        cli_error('--prefix is required');
    }
    if (!preg_match('#^[a-zA-Z0-9\-_]+$#', $prefix)) {
        cli_error("Invalid cache prefix '{$prefix}': only a-z A-Z 0-9 - _ are allowed");
    }
    $writer = \core_cache\config_writer::instance();
    foreach ($writer->get_all_stores() as $name => $store) {
        if (($store['plugin'] ?? '') !== 'redis') {
            continue;
        }
        $configuration = $store['configuration'] ?? [];
        if (($configuration['prefix'] ?? '') === $prefix) {
            echo "Cache store {$name} already prefixed {$prefix}\n";
            continue;
        }
        $configuration['prefix'] = $prefix;
        $writer->edit_store_instance($name, $store['plugin'], $configuration);
        echo "Set cache store {$name} prefix to {$prefix}\n";
    }
}

function apply_preset($options) {
    global $CFG, $DB;
    require_once($CFG->libdir . '/adminlib.php');

    // The preset reads the admin settings tree through admin_get_root(), which is built
    // behind capability checks, so it comes back empty without an admin in session.
    \core\session\manager::set_user(get_admin());

    $file = $options['file'];
    $name = $options['name'];
    if ($file === '' && $name === '') {
        cli_error('apply_preset needs --file or --name');
    }

    $presetname = '';
    $requested = [];

    if ($file !== '') {
        if (!is_readable($file)) {
            cli_error("Preset file is not readable: {$file}");
        }
        $xml = simplexml_load_string(file_get_contents($file));
        if ($xml === false) {
            cli_error("Preset file is not valid XML: {$file}");
        }
        $presetname = trim((string)$xml->NAME);
        if ($presetname === '') {
            cli_error("Preset file has no <NAME>: {$file}");
        }
        // change_default_preset() imports every time it is handed a file, so a pod restart
        // would stack up rows. Drop the previous import first. iscore filters out Starter
        // and Full, which are core's own and must survive.
        $manager = new \core_adminpresets\manager();
        foreach ($DB->get_records('adminpresets', ['name' => $presetname, 'iscore' => 0]) as $old) {
            $manager->delete_preset($old->id);
        }
        $requested = preset_requested_settings($xml);
        $target = $file;
    } else {
        // Named presets are looked up, never imported, so there is nothing to dedupe.
        if (!preset_exists_by_name($name)) {
            cli_error("No preset named '{$name}' on this site");
        }
        $target = $name;
    }

    // The same call Moodle's own installer makes (lib/installlib.php, admin/index.php).
    $appliedid = \core_adminpresets\helper::change_default_preset($target);

    if ($file !== '') {
        $preset = $DB->get_record('adminpresets', ['name' => $presetname, 'iscore' => 0], '*', IGNORE_MULTIPLE);
        if (!$preset) {
            // Core deletes the record when the import recognised nothing at all.
            cli_error("Preset '{$presetname}' contained no setting or plugin this site knows");
        }
        // import_preset() discards unknown settings at DEBUG_DEVELOPER, where nobody sees them.
        // Compare what the file asked for against what was stored and say so.
        $stored = [];
        foreach ($DB->get_records('adminpresets_it', ['adminpresetid' => $preset->id]) as $item) {
            $stored[$item->plugin . '/' . $item->name] = true;
        }
        $dropped = array_diff_key($requested, $stored);
        foreach (array_keys($dropped) as $key) {
            echo "WARNING: preset setting {$key} is unknown to this site and was ignored\n";
        }
        if ($dropped) {
            echo 'WARNING: ' . count($dropped) . " preset setting(s) ignored - a plugin listed in the\n"
               . "         preset but missing from moodle.plugins is the usual cause\n";
        }
    }

    if (is_null($appliedid)) {
        echo "Preset already matches the site; nothing changed\n";
    } else {
        echo "Applied preset (id {$appliedid})\n";
    }
}

// Settings the file asks for, keyed the way import_preset() keys them.
function preset_requested_settings(SimpleXMLElement $xml) {
    $requested = [];
    if (!$xml->ADMIN_SETTINGS) {
        return $requested;
    }
    foreach ($xml->ADMIN_SETTINGS[0] as $plugin => $settings) {
        // Tags are upper case, and __ stands in for / in a component name.
        $plugin = str_replace('__', '/', strtolower($plugin));
        if (!$settings->SETTINGS) {
            continue;
        }
        foreach ($settings->SETTINGS[0]->children() as $setting => $value) {
            $requested[$plugin . '/' . strtolower($setting)] = true;
        }
    }
    return $requested;
}

// Mirrors the lookup in change_default_preset(): 'starter' resolves through a lang string.
function preset_exists_by_name($name) {
    global $DB;
    $stringmanager = get_string_manager();
    if ($stringmanager->string_exists($name . 'preset', 'core_adminpresets')) {
        $name = get_string($name . 'preset', 'core_adminpresets');
    }
    return $DB->record_exists('adminpresets', ['name' => $name]);
}

function set_configs($options) {
    // Settings whose value names a Secret arrive as environment variables. The manifest says
    // which variable carries which setting; the value is in no rendered manifest.
    $secretsfile = $options['secretsfile'] ?? '';
    if ($secretsfile !== '' && is_readable($secretsfile)) {
        foreach (load_json($secretsfile) as $ref) {
            $value = getenv($ref['env']);
            if ($value === false) {
                cli_error("{$ref['plugin']}/{$ref['name']} expects {$ref['env']}, which is not set");
            }
            $component = ($ref['plugin'] === 'core') ? null : $ref['plugin'];
            set_config($ref['name'], $value, $component);
            echo "Set {$ref['plugin']}/{$ref['name']} from secret {$ref['secret']}\n";
        }
    }
    if ($options['file'] === '' || !is_readable($options['file'])) {
        return;
    }
    foreach (load_json($options['file']) as $plugin => $settings) {
        $component = ($plugin === 'core') ? null : $plugin;
        foreach ($settings as $name => $value) {
            if (is_bool($value)) {
                $value = $value ? 1 : 0;
            }
            if (!is_scalar($value)) {
                cli_error("Value for {$plugin}/{$name} must be a scalar");
            }
            set_config($name, $value, $component);
            echo "Set {$plugin}/{$name}\n";
        }
    }
}

function enable_plugins($options) {
    foreach (load_json($options['file']) as $component => $enabled) {
        list($plugintype, $pluginname) = core_component::normalize_component($component);
        $class = core_plugin_manager::resolve_plugininfo_class($plugintype);
        $want = (bool)$enabled;
        $state = $want ? 'enabled' : 'disabled';

        $declaring = (new ReflectionMethod($class, 'enable_plugin'))->getDeclaringClass()->getName();
        if ($declaring === 'core\plugininfo\base') {
            cli_error("Plugin type '{$plugintype}' does not support enable/disable");
        }
        if (!core_plugin_manager::instance()->get_plugin_info($component)) {
            cli_error("Plugin {$component} is not installed");
        }

        if (plugin_enabled($component) === $want) {
            echo "Already {$state} {$component}\n";
            continue;
        }
        // Filters take a TEXTFILTER_ constant, and 0 is a context-level state filter_set_global_state rejects.
        $off = ($plugintype === 'filter') ? TEXTFILTER_DISABLED : 0;
        $changed = $class::enable_plugin($pluginname, $want ? 1 : $off);
        $after = plugin_enabled($component);
        // Every plugin type prefixes the short name itself except logstore, which stores whatever it is given.
        if ($after !== null && $after !== $want) {
            $changed = $class::enable_plugin($component, $want ? 1 : $off);
            $class::enable_plugin($pluginname, $off);
            if (plugin_enabled($component) !== $want) {
                cli_error("Could not leave {$component} {$state}.");
            }
        }
        echo $changed ? "Now {$state} {$component}\n" : "Already {$state} {$component}\n";
    }
}

function plugin_enabled($component) {
    core_plugin_manager::reset_caches();
    $enabled = core_plugin_manager::instance()->get_plugin_info($component)->is_enabled();
    return is_bool($enabled) ? $enabled : null;
}

function output_results($options, $results) {
    if ($options['json']) {
        echo json_encode($results, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    } else {
        print_r($results);
    }
}
?>
