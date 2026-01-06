<?php
// Copyright 2025 Carnegie Mellon University. All Rights Reserved.
// Released under a MIT (SEI)-style license. See LICENSE.md in the project root for license information.

// setup_environment.php — multi-function CLI for Moodle OAuth2 configuration
define('CLI_SCRIPT', true);
require('/var/www/html/config.php');

require_once($CFG->libdir . '/clilib.php');
require_once($CFG->dirroot . '/course/lib.php');

// Parse CLI options
list($options, $unrecognized) = cli_get_params([
    'step' => null,

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
    'json' => false,
    'requireconfirmation' => false,
    'tokenendpoint' => '',
    'userinfoendpoint' => '',
]);

// Step dispatcher
switch ($options['step']) {
    case 'manage_oauth':
        manage_oauth($options);
        break;

    case 'enable_auth_oauth2':
        enable_auth_oauth2();
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

    if (empty($data->baseurl) || empty($data->clientid) || empty($data->clientsecret) || empty($data->name)) {
        cli_error("Missing required fields: baseurl, clientid, clientsecret, name.");
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
            cli_error("Error creating OAuth2 issuer: " . $e->getMessage());
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

function output_results($options, $results) {
    if ($options['json']) {
        echo json_encode($results, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    } else {
        print_r($results);
    }
}
?>
