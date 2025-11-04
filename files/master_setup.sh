#!/bin/bash
# Master Script for Cloudflare DNS Manager Fix, Installation, and Security Enhancement

# =========================================================
# CONFIGURATION - ဤနေရာတွင် သင်၏ Config ကို စစ်ဆေးပါ။
# =========================================================
# သင်၏ မှန်ကန်သော API Token
API_TOKEN="0472OKcWxrte69C5tyasX7la9OPwW_5QXaycDdUF" 

# သင်၏ Cloudflare Zone ID
ZONE_ID="9e9629822eadf8caf35ceaabbc588eac" 

# သင်၏ အဓိက Domain
DOMAIN="zivpn-panel.cc" 

WEB_ROOT="/var/www/html"
CONFIG_DIR="/etc/app-config"
CONFIG_FILE="${CONFIG_DIR}/cloudflare_config.php"
# =========================================================

echo "========================================================"
echo "  Step 1: Security Setup - Creating Config File (Out of Web Root) "
echo "========================================================"

# 1.1. Web Root အပြင်ဘက်တွင် Directory ဖန်တီးခြင်း
sudo mkdir -p "${CONFIG_DIR}"
echo "Config Directory: ${CONFIG_DIR} ကို ဖန်တီးပြီးပါပြီ။"

# 1.2. Config File ကို မှန်ကန်သော Token များဖြင့် ရေးသားခြင်း
cat << EOF_CONFIG | sudo tee "${CONFIG_FILE}" > /dev/null
<?php
// ${CONFIG_FILE} - Cloudflare API Token ကို Web Root အပြင်ဘက်တွင် လုံခြုံစွာ သိမ်းဆည်းသည်။
return [
    'API_TOKEN' => '${API_TOKEN}',
    'ZONE_ID' => '${ZONE_ID}',
    'DOMAIN' => '${DOMAIN}',
];
EOF_CONFIG

echo "Config File: ${CONFIG_FILE} ကို ဖန်တီးပြီးပါပြီ။"

# 1.3. Config File Permissions ကို www-data (Apache User) သာ ဖတ်နိုင်အောင် ပြင်ဆင်ခြင်း
sudo chown www-data:www-data "${CONFIG_FILE}"
sudo chmod 400 "${CONFIG_FILE}"
echo "Config File Permissions ကို www-data ကသာ ဖတ်နိုင်အောင် ပြင်ဆင်ပြီးပါပြီ။"

echo "========================================================"
echo "  Step 2: Rewriting index.php (Final Syntax Fix) "
echo "========================================================"

# index.php ၏ PHP Syntax Error ကို ဖြေရှင်းပြီး HTML ကို ပြန်လည်ရေးသားသည်။
cat << 'EOF_INDEX_PHP' | sudo tee "${WEB_ROOT}/index.php" > /dev/null
<?php 
// Error Debugging ကို ဖွင့်ထားဆဲ
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Base Domain ကို စနစ်တကျ ထုတ်ပြရန်
$domain = "zivpn-panel.cc"; 
// မှတ်ချက်: Domain ကို Config File မှ ခေါ်ယူစရာမလိုဘဲ တိုက်ရိုက် သတ်မှတ်နိုင်သည်။
?>
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Manager - Record ဖန်တီး/ပြင်ဆင်</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f7f6; }
        .container { max-width: 600px; margin: auto; padding: 30px; background: #fff; border-radius: 12px; box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1); }
        h2 { color: #007bff; border-bottom: 3px solid #007bff; padding-bottom: 10px; margin-bottom: 25px; text-align: center; }
        label { display: block; margin-bottom: 5px; font-weight: bold; color: #333; }
        input[type="text"], select { width: 100%; padding: 12px; margin-bottom: 20px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 16px; }
        input[type="submit"] { width: 100%; padding: 15px; background-color: #28a745; color: white; cursor: pointer; font-size: 18px; font-weight: bold; border: none; border-radius: 6px; transition: background-color 0.3s; }
        input[type="submit"]:hover { background-color: #218838; }
        .domain-suffix { display: block; margin-top: -15px; margin-bottom: 25px; color: #6c757d; font-weight: normal; font-size: 0.9em; padding-left: 2px; }
        
        /* Navigation Button */
        .list-btn { display: block; text-align: center; padding: 12px; margin-top: 15px; background-color: #007bff; color: white; border-radius: 6px; text-decoration: none; font-weight: bold; transition: background-color 0.3s; }
        .list-btn:hover { background-color: #0056b3; }

        /* Result Styles */
        .result-box { padding: 20px; border-radius: 8px; margin-top: 30px; white-space: pre-wrap; font-size: 1em; }
        .result-success { background-color: #e6ffed; border: 2px solid #28a745; color: #155724; }
        .result-error { background-color: #f8d7da; border: 2px solid #dc3545; color: #721c24; }
        .result-info { background-color: #fcefd7; border: 2px solid #ffc107; color: #856404; }
        .result-title { font-size: 1.2em; font-weight: bold; margin-bottom: 10px; border-bottom: 1px dashed #ccc; padding-bottom: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Cloudflare DNS Record စီမံခန့်ခွဲမှု</h2>

        <form action="process.php?action=manage" method="POST">
            <h3>Create</h3>
            <label for="subdomain">Subdomain Name:</label>
            <input type="text" id="subdomain" name="subdomain" placeholder="ဥပမာ: svp101" required>
            <span class="domain-suffix">.<?php echo htmlspecialchars($domain); ?></span>

            <label for="ip_address">IP Address (A Record):</label>
            <input type="text" id="ip_address" name="ip_address" placeholder="ဥပမာ: 203.0.113.10 သို့မဟုတ် 'auto' ရိုက်ပါ" value="auto" required>

            <label for="proxied">Cloudflare Proxy (Orange Cloud):</label>
            <select id="proxied" name="proxied">
                <option value="false">Off (DNS Only) - Dynamic IP အတွက် အကြံပြု</option>
                <option value="true">On (Proxied)</option>
            </select>

            <input type="submit" value="DNS Create ">
        </form>

        <a href="list.php" class="list-btn">Record များ စာရင်းကြည့်ရန်</a>

        <?php 
        if (isset($_GET['result'])) {
            $data = json_decode(base64_decode($_GET['result']), true);
            $class = 'result-info'; 
            $title = 'လုပ်ဆောင်ချက် ရလဒ်:';
            $details = '';

            if (isset($data['status'])) {
                if ($data['status'] === 'SUCCESS') {
                    $class = 'result-success';
                    $title = '✅ SUCCESS: Record ဖန်တီး/ပြင်ဆင်ခြင်း အောင်မြင်ပါသည်။';
                    $details = "Subdomain: <span style='font-weight: bold;'>" . htmlspecialchars($data['record_name']) . "</span>\n";
                    $details .= "IP Address: " . htmlspecialchars($data['vps_ip']) . "\n";
                    $details .= "Proxy Status: " . ($data['proxied'] ? "On (Proxied)" : "Off (DNS Only)") . "\n";
                    $details .= "\nCloudflare တွင် အသက်ဝင်နေပါပြီ။";
                } elseif ($data['status'] === 'DELETE_SUCCESS') {
                    $class = 'result-success';
                    $title = '🗑️ SUCCESS: Record ဖျက်ပစ်ခြင်း အောင်မြင်ပါသည်။';
                    $details = "ဖျက်လိုက်သော Record: <span style='font-weight: bold;'>" . htmlspecialchars($data['record_name']) . "</span>\n";
                } elseif ($data['status'] === 'INFO') {
                    $title = 'ℹ️ INFO: DNS Record သည် အမှန်အတိုင်းရှိနေပါသည်။';
                    $details = "Subdomain: <span style='font-weight: bold;'>" . htmlspecialchars($data['record_name']) . "</span>\n";
                    $details .= "IP Address: " . htmlspecialchars($data['vps_ip']) . "\n";
                    $details .= "Proxy Status: " . ($data['proxied'] ? "On (Proxied)" : "Off (DNS Only)") . "\n";
                } elseif ($data['status'] === 'ERROR') {
                    $class = 'result-error';
                    $title = '❌ ERROR: လုပ်ဆောင်ချက် မအောင်မြင်ပါ။';
                    $details = "Cloudflare Error: " . htmlspecialchars($data['cf_error']) . "\n";
                    $details .= "HTTP Status: " . htmlspecialchars($data['http_code']) . "\n";
                    $details .= "\nFull Response: " . print_r($data['full_response'] ?? [], true);
                }
            }
            
            echo "<div class='result-box {$class}'>";
            echo "<div class='result-title'>{$title}</div>";
            echo "<div class='result-details'>{$details}</div>";
            echo "</div>";

            // JavaScript to clean the URL bar
            echo '<script>';
            echo 'if (history.replaceState) {';
            echo '  history.replaceState(null, document.title, window.location.pathname);';
            echo '}';
            echo '</script>';
        }
        ?>
    </div>
</body>
</html>
EOF_INDEX_PHP


echo "========================================================"
echo "  Step 3: Rewriting process.php (Config File Integration) "
echo "========================================================"

# process.php ၏ Configuration အပိုင်းကို Config File မှ ခေါ်ယူသုံးစွဲရန် ပြင်ဆင်ခြင်း
cat << EOF_PHP | sudo tee "${WEB_ROOT}/process.php" > /dev/null
<?php
// Error Debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// =========================================================
// CONFIGURATION (Secure Config File မှ ခေါ်ယူခြင်း)
// =========================================================
\$config_file = '${CONFIG_FILE}';
if (!file_exists(\$config_file)) {
    die("Error: Configuration file not found at " . \$config_file);
}

\$config = require \$config_file;

\$api_token = \$config['API_TOKEN']; 
\$zone_id = \$config['ZONE_ID']; 
\$domain = \$config['DOMAIN'];

\$record_type = "A";
\$ttl = 1; 

// Helper function to redirect with JSON result
function redirect_with_result(\$status, \$message_data) {
    \$output_data = array_merge(['status' => \$status], \$message_data);
    \$encoded_result = base64_encode(json_encode(\$output_data));
    // Always redirect back to index.php after any action
    header("Location: index.php?result=" . \$encoded_result);
    exit();
}

// =========================================================
// ACTION ROUTING
// =========================================================
\$action = \$_GET['action'] ?? 'manage';

if (\$_SERVER['REQUEST_METHOD'] !== 'POST' && \$action !== 'delete') {
    if (\$action === 'manage') {
        header("Location: index.php"); 
        exit();
    }
}

if (\$action === 'manage') {
    handle_manage_record();
} elseif (\$action === 'delete') {
    handle_delete_record();
} else {
    header("Location: index.php"); 
    exit();
}

// FUNCTION: MANAGE (CREATE/UPDATE) RECORD
function handle_manage_record() {
    global \$api_token, \$zone_id, \$domain, \$record_type, \$ttl;

    \$subdomain = trim(\$_POST['subdomain'] ?? '');
    \$input_ip = trim(\$_POST['ip_address'] ?? '');
    \$proxied = (\$_POST['proxied'] === 'true') ? true : false;

    if (empty(\$subdomain)) {
        redirect_with_result('ERROR', ['cf_error' => 'Subdomain Name ကို ဖြည့်သွင်းရန် လိုအပ်ပါသည်။', 'http_code' => 400]);
    }

    \$record_name = \$subdomain . '.' . \$domain;

    \$vps_ip = '';
    if (strtolower(\$input_ip) === 'auto' || empty(\$input_ip)) {
        \$vps_ip = @trim(file_get_contents('https://api.ipify.org'));
    } else {
        if (!filter_var(\$input_ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            redirect_with_result('ERROR', ['cf_error' => "ထည့်သွင်းထားသော IP Address (\$input_ip) သည် မှန်ကန်သော IPv4 ပုံစံမဟုတ်ပါ။", 'http_code' => 400]);
        }
        \$vps_ip = \$input_ip;
    }

    if (empty(\$vps_ip)) {
        redirect_with_result('ERROR', ['cf_error' => 'IP Address ကို အလိုအလျောက် ရယူရာတွင် မအောင်မြင်ပါ။', 'http_code' => 500]);
    }

    // 1. လက်ရှိ DNS Record ကို ရှာဖွေခြင်း
    \$ch = curl_init("https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records?type=\$record_type&name=\$record_name");
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json"
    ));
    \$response = curl_exec(\$ch);
    \$http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$data = json_decode(\$response, true);

    if (\$http_code !== 200 || !(\$data['success'] ?? false)) {
        \$cf_error = \$data['errors'][0]['message'] ?? 'Unknown API Query Error (Search)';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$http_code, 'full_response' => \$data]);
    }

    \$record_id = \$data['result'][0]['id'] ?? null;
    \$current_ip = \$data['result'][0]['content'] ?? null;
    \$current_proxied = \$data['result'][0]['proxied'] ?? null; 
    \$action_url = '';
    \$method = '';

    // 2. စီမံခန့်ခွဲခြင်း (Create or Update)
    if (\$record_id) {
        if (\$current_ip === \$vps_ip && \$current_proxied == \$proxied) {
            redirect_with_result('INFO', ['record_name' => \$record_name, 'vps_ip' => \$vps_ip, 'proxied' => \$proxied]);
        }
        
        \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records/\$record_id";
        \$method = 'PUT';

    } else {
        \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records";
        \$method = 'POST';
    }

    // Final API Call (Create or Update)
    \$api_data = json_encode([
        'type' => \$record_type,
        'name' => \$subdomain,
        'content' => \$vps_ip,
        'ttl' => \$ttl,
        'proxied' => \$proxied
    ]);

    \$ch = curl_init(\$action_url);
    curl_setopt(\$ch, CURLOPT_CUSTOMREQUEST, \$method);
    curl_setopt(\$ch, CURLOPT_POSTFIELDS, \$api_data);
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json",
        'Content-Length: ' . strlen(\$api_data)
    ));
    \$final_response = curl_exec(\$ch);
    \$final_http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$final_data = json_decode(\$final_response, true);

    if (\$final_http_code >= 200 && \$final_http_code < 300 && (\$final_data['success'] ?? false)) {
        redirect_with_result('SUCCESS', ['record_name' => \$record_name, 'vps_ip' => \$vps_ip, 'proxied' => \$proxied]);
    } else {
        \$cf_error = \$final_data['errors'][0]['message'] ?? 'Unknown API Error (Create/Update)';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$final_http_code, 'full_response' => \$final_data]);
    }
}


// FUNCTION: DELETE RECORD
function handle_delete_record() {
    global \$api_token, \$zone_id;

    \$record_id = trim(\$_POST['record_id'] ?? '');
    \$record_name = trim(\$_POST['record_name'] ?? '');

    if (empty(\$record_id) || empty(\$record_name)) {
        redirect_with_result('ERROR', ['cf_error' => 'Delete လုပ်ရန် Record ID မပြည့်စုံပါ။', 'http_code' => 400]);
    }
    
    // API Call: DELETE
    \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records/\$record_id";

    \$ch = curl_init(\$action_url);
    curl_setopt(\$ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json"
    ));
    \$final_response = curl_exec(\$ch);
    \$final_http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$final_data = json_decode(\$final_response, true);

    if (\$final_http_code === 200 && (\$final_data['success'] ?? false)) {
        redirect_with_result('DELETE_SUCCESS', ['record_name' => \$record_name]);
    } else {
        \$cf_error = \$final_data['errors'][0]['message'] ?? 'Unknown API Error during delete';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$final_http_code, 'full_response' => \$final_data]);
    }
}
?>
EOF_PHP


echo "========================================================"
echo "  Step 4: Rewriting list.php (Config File Integration) "
echo "========================================================"

# list.php ၏ Configuration အပိုင်းကို Config File မှ ခေါ်ယူသုံးစွဲရန် ပြင်ဆင်ခြင်း
cat << EOF_LIST_PHP | sudo tee "${WEB_ROOT}/list.php" > /dev/null
<?php
// Error Debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// =========================================================
// CONFIGURATION (Secure Config File မှ ခေါ်ယူခြင်း)
// =========================================================
\$config_file = '${CONFIG_FILE}';
if (!file_exists(\$config_file)) {
    // Configuration Error ပြခြင်း
    die("Error: Configuration file not found at " . \$config_file);
}

\$config = require \$config_file;

\$api_token = \$config['API_TOKEN']; 
\$zone_id = \$config['ZONE_ID']; 
\$domain = \$config['DOMAIN'];

\$record_type = "A";

// 1. Cloudflare မှ DNS Record အားလုံးကို ရယူခြင်း
function fetch_records(\$api_token, \$zone_id, \$record_type) {
    \$url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records?type=\$record_type&per_page=100";
    
    \$ch = curl_init(\$url);
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json"
    ));
    \$response = curl_exec(\$ch);
    \$http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$data = json_decode(\$response, true);

    if (\$http_code !== 200 || !(\$data['success'] ?? false)) {
        \$error_message = \$data['errors'][0]['message'] ?? 'Unknown API Query Error';
        return ['error' => true, 'message' => \$error_message, 'full_response' => \$data];
    }
    return ['error' => false, 'records' => \$data['result'] ?? []];
}

\$result = fetch_records(\$api_token, \$zone_id, \$record_type);
\$records = \$result['records'] ?? [];

// Filter only records that belong to the main domain
\$filtered_records = array_filter(\$records, function(\$record) use (\$domain) {
    return strpos(\$record['name'], \$domain) !== false && \$record['name'] !== \$domain;
});

?>
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Records များစာရင်း</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f7f6; }
        .container { max-width: 900px; margin: auto; padding: 30px; background: #fff; border-radius: 12px; box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1); }
        h2 { color: #007bff; border-bottom: 3px solid #007bff; padding-bottom: 10px; margin-bottom: 25px; text-align: center; }
        
        /* Navigation Button */
        .back-btn { display: inline-block; padding: 10px 15px; margin-bottom: 20px; background-color: #6c757d; color: white; border-radius: 6px; text-decoration: none; font-weight: bold; transition: background-color 0.3s; }
        .back-btn:hover { background-color: #5a6268; }

        /* Error/Info Box */
        .info-box { padding: 15px; border-radius: 8px; margin-top: 20px; background-color: #fcefd7; border: 2px solid #ffc107; color: #856404; font-weight: bold; }
        .error-box { padding: 15px; border-radius: 8px; margin-top: 20px; background-color: #f8d7da; border: 2px solid #dc3545; color: #721c24; font-weight: bold; }

        /* Mobile-First Responsive List (Default: Card View) */
        .record-card {
            background: #fff;
            border: 1px solid #ddd;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
        }
        .card-item { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px dotted #eee; }
        .card-item:last-child { border-bottom: none; }
        .card-label { font-weight: bold; color: #555; width: 40%; }
        .card-value { text-align: right; width: 60%; }
        .delete-form { margin: 15px 0 0; text-align: center; }
        .delete-btn { background-color: #dc3545; color: white; border: none; padding: 8px 15px; border-radius: 4px; cursor: pointer; transition: background-color 0.3s; width: 100%; font-size: 1em; }
        .delete-btn:hover { background-color: #c82333; }
        .proxy-on { color: #ff9900; font-weight: bold; }
        .proxy-off { color: #28a745; font-weight: bold; }


        /* Desktop View (Table View for larger screens) */
        .record-table { display: none; }
        @media (min-width: 768px) {
            .record-card-list { display: none; }
            .record-table { display: table; width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 0.9em; }
            .record-table th, .record-table td { padding: 12px 8px; text-align: left; border-bottom: 1px solid #ddd; }
            .record-table th { background-color: #007bff; color: white; font-weight: bold; }
            .record-table tr:nth-child(even) { background-color: #f8f8f8; }
            .record-table .delete-form { margin: 0; text-align: left; }
            .record-table .delete-btn { width: auto; padding: 6px 10px; font-size: 0.9em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="index.php" class="back-btn">← Record ဖန်တီးရန် စာမျက်နှာသို့</a>
        <h2>လက်ရှိ DNS Record များစာရင်း (<?php echo htmlspecialchars(\$domain); ?>)</h2>
        
        <?php if (\$result['error']): ?>
            <div class='error-box'>❌ ERROR: Record စာရင်းရယူရာတွင် မအောင်မြင်ပါ။ <?php echo htmlspecialchars(\$result['message']); ?>
                <?php if (isset(\$result['full_response'])): ?>
                    <pre style="white-space: pre-wrap; word-wrap: break-word; font-size: 0.8em; margin-top: 10px; border-top: 1px solid #ccc; padding-top: 5px;">
                        API Response Details: <?php print_r(\$result['full_response']); ?>
                    </pre>
                <?php endif; ?>
            </div>
        <?php elseif (empty(\$filtered_records)): ?>
            <div class='info-box'>ℹ️ လက်ရှိတွင် A Record များ မရှိသေးပါ သို့မဟုတ် Domain Root Record များသာ ရှိပါသည်။</div>
        <?php else: ?>
            
            <div class="record-card-list">
                <?php foreach (\$filtered_records as \$record): 
                    \$subdomain_only = str_replace("." . \$domain, "", \$record['name']);
                    \$proxy_status = \$record['proxied'] ? "<span class='proxy-on'>On (Proxied)</span>" : "<span class='proxy-off'>Off (DNS Only)</span>";
                ?>
                    <div class="record-card">
                        <div class="card-item"><span class="card-label">Subdomain:</span> <span class="card-value"><?php echo htmlspecialchars(\$subdomain_only); ?></span></div>
                        <div class="card-item"><span class="card-label">IP Address:</span> <span class="card-value"><?php echo htmlspecialchars(\$record['content']); ?></span></div>
                        <div class="card-item"><span class="card-label">Proxy Status:</span> <span class="card-value"><?php echo \$proxy_status; ?></span></div>
                        <div class="delete-form">
                            <form action='process.php?action=delete' method='POST' style='margin: 0;' onsubmit="return confirm('သေချာပါသလား? <?php echo htmlspecialchars(\$subdomain_only); ?> ကို ဖျက်တော့မှာပါ။');">
                                <input type='hidden' name='record_id' value='<?php echo htmlspecialchars(\$record['id']); ?>'>
                                <input type='hidden' name='record_name' value='<?php echo htmlspecialchars(\$record['name']); ?>'>
                                <button type='submit' class='delete-btn'>🗑️ ဖျက်မည်</button>
                            </form>
                        </div>
                    </div>
                <?php endforeach; ?>
            </div>

            <table class="record-table">
                <thead>
                    <tr>
                        <th>Subdomain</th>
                        <th>IP Address</th>
                        <th>Proxy</th>
                        <th>လုပ်ဆောင်ချက်</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach (\$filtered_records as \$record): 
                        \$subdomain_only = str_replace("." . \$domain, "", \$record['name']);
                        \$proxy_status = \$record['proxied'] ? "<span class='proxy-on'>On (Proxied)</span>" : "<span class='proxy-off'>Off (DNS Only)</span>";
                    ?>
                        <tr>
                            <td><?php echo htmlspecialchars(\$subdomain_only); ?></td>
                            <td><?php echo htmlspecialchars(\$record['content']); ?></td>
                            <td><?php echo \$proxy_status; ?></td>
                            <td>
                                <form action='process.php?action=delete' method='POST' style='margin: 0;' onsubmit="return confirm('သေချာပါသလား? <?php echo htmlspecialchars(\$subdomain_only); ?> ကို ဖျက်တော့မှာပါ။');">
                                    <input type='hidden' name='record_id' value='<?php echo htmlspecialchars(\$record['id']); ?>'>
                                    <input type='hidden' name='record_name' value='<?php echo htmlspecialchars(\$record['name']); ?>'>
                                    <button type='submit' class='delete-btn'>🗑️ ဖျက်မည်</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>

        <?php endif; ?>
    </div>
</body>
</html>
EOF_LIST_PHP


echo "========================================================"
echo "  Step 5: Setting File Permissions and Restarting Apache"
echo "========================================================"

# Web Server File များကို Apache အတွက် ခွင့်ပြုချက် ပြင်ဆင်ခြင်း
sudo chown -R www-data:www-data "${WEB_ROOT}"
sudo chmod -R 755 "${WEB_ROOT}"

# Apache ကို Restart ပြန်လုပ်ရန်
echo "Restarting Apache..."
sudo systemctl restart apache2

echo "========================================================"
echo "✅ Master Setup ပြီးဆုံးပါပြီ။ Panel သည် လုံခြုံစွာ အလုပ်လုပ်နေပါပြီ။"
echo "Browser Cache ကို ရှင်းလင်းပြီး http://185.84.161.85/index.php ကို ဖွင့်ပါ။"
echo "========================================================"
