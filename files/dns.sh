#!/bin/bash
# MASTER SCRIPT V3.0: Cloudflare DNS Manager Full Setup
# Includes:
# 1. Web Files (index.php, process.php, list.php) with A/CNAME/NS Support and Modern Design
# 2. NGINX + Certbot HTTPS Wildcard Subdomain Setup
# 3. Secure Config File Setup

# =========================================================
# ⚠️⚠️⚠️ CONFIGURATION - ဤနေရာတွင် မဖြစ်မနေ ပြင်ဆင်ပါ။ ⚠️⚠️⚠️
# =========================================================
# 1. သင်၏ အဓိက Domain
DOMAIN="zivpn-panel.cc" 
# 2. သင်၏ Cloudflare Email Address (Certbot မှ Cert ထုတ်ရန် လိုအပ်သည်)
CLOUDFLARE_EMAIL="tintaungkhaing66@gmail.com"
# 3. သင်၏ Cloudflare API Token (Global API Key သို့မဟုတ် DNS Zone Edit Token)
CLOUDFLARE_API_TOKEN="mKnsl9zrr7e-JV-wuD5nhaqeg1rm6O5d1xrzOow0" 
# 4. သင်၏ Cloudflare Zone ID (DNS Record စီမံခန့်ခွဲမည့် Zone ID)
CLOUDFLARE_ZONE_ID="9e9629822eadf8caf35ceaabbc588eac"
# 5. PHP Version (သင်၏ Server တွင် Install လုပ်ထားသော PHP FPM Version ကို ပြင်ပေးပါ)
PHP_VERSION="8.1"
# =========================================================
# File Paths
WEB_ROOT="/var/www/html"
CONFIG_DIR="/etc/app-config"
CONFIG_FILE="${CONFIG_DIR}/cloudflare_config.php"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
CRED_FILE="/root/.secrets/cloudflare_creds.ini"
CERTBOT_DNS_PLUGINS="python3-certbot-nginx python3-certbot-dns-cloudflare"
# =========================================================

echo "========================================================"
echo "  Step 0: Pre-flight Checks and Setup "
echo "========================================================"

# 0.1 Update & Install Core Dependencies
sudo apt update
sudo apt install -y nginx php${PHP_VERSION}-fpm php-curl php-json certbot $CERTBOT_DNS_PLUGINS python3-pip
sudo pip3 install dnspython # For Certbot DNS challenge

# 0.2 Stop and Disable Apache (Port Conflict ရှောင်ရန်)
if sudo systemctl is-active --quiet apache2; then
    echo "Apache service ကို ရပ်တန့်ပြီး Disable လုပ်ပါမည်။"
    sudo systemctl stop apache2
    sudo systemctl disable apache2
fi

# 0.3 Create Web Root and Config Directory
sudo mkdir -p "${WEB_ROOT}"
sudo mkdir -p "${CONFIG_DIR}"
sudo chown -R www-data:www-data "${WEB_ROOT}"


echo "========================================================"
echo "  PART 1: SECURE CONFIG FILE SETUP (PHP) "
echo "========================================================"

# 1.1 Create Secure Config File (Web Root အပြင်ဘက်)
echo "Creating secure config file at ${CONFIG_FILE}..."
cat << EOF_CONFIG_PHP | sudo tee "${CONFIG_FILE}" > /dev/null
<?php
// Secure Configuration File (Web Root အပြင်ဘက်တွင် သိမ်းဆည်းထားသည်)
return [
    'API_TOKEN' => '${CLOUDFLARE_API_TOKEN}',
    'ZONE_ID'   => '${CLOUDFLARE_ZONE_ID}',
    'DOMAIN'    => '${DOMAIN}',
];
?>
EOF_CONFIG_PHP
sudo chmod 640 "${CONFIG_FILE}"
sudo chown www-data:www-data "${CONFIG_FILE}"


echo "========================================================"
echo "  PART 2: WEB PANEL FILES (index, process, list) "
echo "========================================================"

# 2.1 index.php (Design & Multi-Record Type)
echo "Rewriting index.php..."
cat << EOF_INDEX_PHP | sudo tee "${WEB_ROOT}/index.php" > /dev/null
<?php 
// Error Debugging ကို ဖွင့်ထားဆဲ
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Base Domain ကို စနစ်တကျ ထုတ်ပြရန်
\$config_file = '${CONFIG_FILE}';
\$domain = 'zivpn-panel.cc'; // Default value

if (file_exists(\$config_file)) {
    \$config = require \$config_file;
    \$domain = \$config['DOMAIN'] ?? \$domain;
}
?>
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Manager - Record ဖန်တီး/ပြင်ဆင်</title>
    <style>
        /* Modern & Clean Design (Styles as provided in previous response) */
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #e9ecef; }
        .container { max-width: 650px; margin: auto; padding: 35px; background: #ffffff; border-radius: 15px; box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15); }
        h2 { color: #0056b3; border-bottom: 4px solid #0056b3; padding-bottom: 10px; margin-bottom: 30px; text-align: center; font-size: 1.8em; }
        label { display: block; margin-bottom: 8px; font-weight: 600; color: #343a40; }
        input[type="text"], select { width: 100%; padding: 12px; margin-bottom: 20px; border: 1px solid #ced4da; border-radius: 8px; box-sizing: border-box; font-size: 16px; transition: border-color 0.3s; }
        input[type="text"]:focus, select:focus { border-color: #007bff; box-shadow: 0 0 0 0.2rem rgba(0, 123, 255, 0.25); outline: none; }
        .btn-primary { width: 100%; padding: 15px; background-color: #007bff; color: white; cursor: pointer; font-size: 18px; font-weight: bold; border: none; border-radius: 8px; transition: background-color 0.3s, transform 0.1s; margin-top: 15px; }
        .btn-primary:hover { background-color: #0056b3; transform: translateY(-1px); }
        .domain-suffix { display: block; margin-top: -15px; margin-bottom: 25px; color: #6c757d; font-weight: normal; font-size: 0.9em; padding-left: 5px; }
        .list-btn { display: block; text-align: center; padding: 12px; margin-top: 15px; background-color: #6c757d; color: white; border-radius: 8px; text-decoration: none; font-weight: bold; transition: background-color 0.3s; }
        .list-btn:hover { background-color: #5a6268; }
        .result-box { padding: 20px; border-radius: 8px; margin-top: 30px; white-space: pre-wrap; font-size: 1em; }
        .result-success { background-color: #e6ffed; border: 2px solid #28a745; color: #155724; }
        .result-error { background-color: #f8d7da; border: 2px solid #dc3545; color: #721c24; }
        .result-info { background-color: #fcefd7; border: 2px solid #ffc107; color: #856404; }
        .result-title { font-size: 1.2em; font-weight: bold; margin-bottom: 10px; border-bottom: 1px dashed #ccc; padding-bottom: 5px; }
        .input-group { margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>🌐 Cloudflare DNS Record စီမံခန့်ခွဲမှု</h2>

        <form action="process.php?action=manage" method="POST">
            <h3>Record အသစ်ဖန်တီး / Update လုပ်မည်</h3>
            
            <div class="input-group">
                <label for="record_type">Record Type:</label>
                <select id="record_type" name="record_type" onchange="updateFormFields()">
                    <option value="A">A Record (IP Address)</option>
                    <option value="CNAME">CNAME Record (Host/Alias)</option>
                    <option value="NS">NS Record (Name Server)</option>
                </select>
            </div>

            <div class="input-group">
                <label for="subdomain">Subdomain Name:</label>
                <input type="text" id="subdomain" name="subdomain" placeholder="ဥပမာ: svp101" required>
                <span class="domain-suffix">.<?php echo htmlspecialchars(\$domain); ?></span>
            </div>

            <div class="input-group" id="dynamic_input_group">
                <label for="content_input" id="content_label">IP Address (A Record):</label>
                <input type="text" id="content_input" name="content_input" placeholder="ဥပမာ: 203.0.113.10 သို့မဟုတ် 'auto' ရိုက်ပါ" value="auto" required>
            </div>

            <div class="input-group" id="proxied_group">
                <label for="proxied">Cloudflare Proxy (Orange Cloud):</label>
                <select id="proxied" name="proxied">
                    <option value="false">Off (DNS Only) - Dynamic IP အတွက် အကြံပြု</option>
                    <option value="true">On (Proxied)</option>
                </select>
            </div>

            <button type="submit" class="btn-primary">DNS Record ဖန်တီး / Update လုပ်မည်</button>
        </form>

        <a href="list.php" class="list-btn">Record များ စာရင်းကြည့်ရန်</a>

        <?php 
        if (isset(\$_GET['result'])) {
            \$data = json_decode(base64_decode(\$_GET['result']), true);
            \$class = 'result-info'; 
            \$title = 'လုပ်ဆောင်ချက် ရလဒ်:';
            \$details = '';

            if (isset(\$data['status'])) {
                if (\$data['status'] === 'SUCCESS') {
                    \$class = 'result-success';
                    \$title = '✅ SUCCESS: Record ဖန်တီး/ပြင်ဆင်ခြင်း အောင်မြင်ပါသည်။';
                    \$details = "Record Type: " . htmlspecialchars(\$data['record_type']) . "\n";
                    \$details .= "Subdomain: <span style='font-weight: bold;'>" . htmlspecialchars(\$data['record_name']) . "</span>\n";
                    \$details .= "Content: " . htmlspecialchars(\$data['content']) . "\n";
                    if (isset(\$data['proxied'])) {
                        \$details .= "Proxy Status: " . (\$data['proxied'] ? "On (Proxied)" : "Off (DNS Only)") . "\n";
                    }
                    \$details .= "\nCloudflare တွင် အသက်ဝင်နေပါပြီ။";
                } elseif (\$data['status'] === 'DELETE_SUCCESS') {
                    \$class = 'result-success';
                    \$title = '🗑️ SUCCESS: Record ဖျက်ပစ်ခြင်း အောင်မြင်ပါသည်။';
                    \$details = "ဖျက်လိုက်သော Record: <span style='font-weight: bold;'>" . htmlspecialchars(\$data['record_name']) . "</span>\n";
                    \$details .= "Type: " . htmlspecialchars(\$data['record_type']) . "\n";
                } elseif (\$data['status'] === 'INFO') {
                    \$title = 'ℹ️ INFO: DNS Record သည် အမှန်အတိုင်းရှိနေပါသည်။';
                    \$details = "Record Type: " . htmlspecialchars(\$data['record_type']) . "\n";
                    \$details .= "Subdomain: <span style='font-weight: bold;'>" . htmlspecialchars(\$data['record_name']) . "</span>\n";
                    \$details .= "Content: " . htmlspecialchars(\$data['content']) . "\n";
                    if (isset(\$data['proxied'])) {
                        \$details .= "Proxy Status: " . (\$data['proxied'] ? "On (Proxied)" : "Off (DNS Only)") . "\n";
                    }
                } elseif (\$data['status'] === 'ERROR') {
                    \$class = 'result-error';
                    \$title = '❌ ERROR: လုပ်ဆောင်ချက် မအောင်မြင်ပါ။';
                    \$details = "Cloudflare Error: " . htmlspecialchars(\$data['cf_error']) . "\n";
                    \$details .= "HTTP Status: " . htmlspecialchars(\$data['http_code']) . "\n";
                    \$details .= "\nFull Response: " . print_r(\$data['full_response'] ?? [], true);
                }
            }
            
            echo "<div class='result-box {\$class}'>";
            echo "<div class='result-title'>{\$title}</div>";
            echo "<div class='result-details'>{\$details}</div>";
            echo "</div>";

            echo '<script>';
            echo 'if (history.replaceState) {';
            echo '  history.replaceState(null, document.title, window.location.pathname);';
            echo '}';
            echo '</script>';
        }
        ?>
    </div>
    
    <script>
        function updateFormFields() {
            const type = document.getElementById('record_type').value;
            const contentLabel = document.getElementById('content_label');
            const contentInput = document.getElementById('content_input');
            const proxiedGroup = document.getElementById('proxied_group');

            // Reset Input State
            contentInput.value = '';
            contentInput.placeholder = '';
            contentInput.setAttribute('type', 'text');
            
            // Update fields based on selected type
            if (type === 'A') {
                contentLabel.textContent = 'IP Address (A Record):';
                contentInput.placeholder = "ဥပမာ: 203.0.113.10 သို့မဟုတ် 'auto' ရိုက်ပါ";
                contentInput.value = 'auto';
                proxiedGroup.style.display = 'block';
            } else if (type === 'CNAME') {
                contentLabel.textContent = 'Target Hostname (CNAME Content):';
                contentInput.placeholder = 'ဥပမာ: www.othersite.com သို့မဟုတ် @';
                proxiedGroup.style.display = 'block';
            } else if (type === 'NS') {
                contentLabel.textContent = 'Name Server (NS Content):';
                contentInput.placeholder = 'ဥပမာ: ns1.mydnshost.com';
                proxiedGroup.style.display = 'none';
            }
        }

        document.addEventListener('DOMContentLoaded', updateFormFields);
    </script>
</body>
</html>
EOF_INDEX_PHP

# 2.2 process.php (A/CNAME/NS Logic)
echo "Rewriting process.php..."
cat << EOF_PROCESS_PHP | sudo tee "${WEB_ROOT}/process.php" > /dev/null
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

// Default TTL for all records (Auto: 1)
\$ttl = 1; 

// Helper function to redirect with JSON result
function redirect_with_result(\$status, \$message_data) {
    \$output_data = array_merge(['status' => \$status], \$message_data);
    \$encoded_result = base64_encode(json_encode(\$output_data));
    header("Location: index.php?result=" . \$encoded_result);
    exit();
}

// ACTION ROUTING
\$action = \$_GET['action'] ?? 'manage';
if (\$_SERVER['REQUEST_METHOD'] !== 'POST' && \$action !== 'delete') {
    if (\$action === 'manage') { header("Location: index.php"); exit(); }
}

if (\$action === 'manage') {
    handle_manage_record();
} elseif (\$action === 'delete') {
    handle_delete_record();
} else {
    header("Location: index.php"); exit();
}

// FUNCTION: MANAGE (CREATE/UPDATE) RECORD
function handle_manage_record() {
    global \$api_token, \$zone_id, \$domain, \$ttl;

    \$record_type = trim(\$_POST['record_type'] ?? 'A');
    \$subdomain = trim(\$_POST['subdomain'] ?? '');
    \$content_input = trim(\$_POST['content_input'] ?? '');
    \$proxied = (\$_POST['proxied'] === 'true') ? true : false;
    
    // NS Record များအတွက် Proxy ကို အမြဲ Off လုပ်ရန်
    if (\$record_type === 'NS') { \$proxied = false; }

    if (empty(\$subdomain) || empty(\$content_input)) {
        redirect_with_result('ERROR', ['cf_error' => 'Subdomain သို့မဟုတ် Content ကို ဖြည့်သွင်းရန် လိုအပ်ပါသည်။', 'http_code' => 400]);
    }

    \$record_name = (\$subdomain === '@' ? \$domain : \$subdomain . '.' . \$domain);
    \$content_value = \$content_input;

    // A Record အတွက် 'auto' IP ကိုင်တွယ်ခြင်း
    if (\$record_type === 'A') {
        if (strtolower(\$content_input) === 'auto') {
            \$content_value = @trim(file_get_contents('https://api.ipify.org'));
            if (empty(\$content_value)) {
                redirect_with_result('ERROR', ['cf_error' => 'IP Address ကို အလိုအလျောက် ရယူရာတွင် မအောင်မြင်ပါ။', 'http_code' => 500]);
            }
        } elseif (!filter_var(\$content_value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            redirect_with_result('ERROR', ['cf_error' => "A Record Content (\$content_value) သည် မှန်ကန်သော IPv4 ပုံစံမဟုတ်ပါ။", 'http_code' => 400]);
        }
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
    \$current_content = \$data['result'][0]['content'] ?? null;
    \$current_proxied = \$data['result'][0]['proxied'] ?? null; 
    \$action_url = '';
    \$method = '';

    // 2. စီမံခန့်ခွဲခြင်း (Create or Update)
    if (\$record_id) {
        if (\$current_content === \$content_value && (\$record_type === 'NS' || \$current_proxied == \$proxied)) {
            redirect_with_result('INFO', ['record_name' => \$record_name, 'content' => \$content_value, 'proxied' => \$proxied, 'record_type' => \$record_type]);
        }
        
        \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records/\$record_id";
        \$method = 'PUT';

    } else {
        \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records";
        \$method = 'POST';
    }

    // Final API Call (Create or Update)
    \$api_data_array = [
        'type' => \$record_type,
        'name' => \$subdomain, // Cloudflare API အတွက် name က subdomain ဖြစ်ရမည်
        'content' => \$content_value,
        'ttl' => \$ttl,
        'proxied' => \$proxied
    ];
    
    if (\$record_type === 'NS') {
        unset(\$api_data_array['proxied']);
        // NS record content is case-insensitive, but should be a valid hostname
    }

    \$api_data = json_encode(\$api_data_array);

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
        redirect_with_result('SUCCESS', ['record_name' => \$record_name, 'content' => \$content_value, 'proxied' => \$proxied, 'record_type' => \$record_type]);
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
    \$record_type = trim(\$_POST['record_type'] ?? 'A');

    if (empty(\$record_id) || empty(\$record_name)) {
        redirect_with_result('ERROR', ['cf_error' => 'Delete လုပ်ရန် Record ID မပြည့်စုံပါ။', 'http_code' => 400]);
    }
    
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
        redirect_with_result('DELETE_SUCCESS', ['record_name' => \$record_name, 'record_type' => \$record_type]);
    } else {
        \$cf_error = \$final_data['errors'][0]['message'] ?? 'Unknown API Error during delete';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$final_http_code, 'full_response' => \$final_data]);
    }
}
?>
EOF_PROCESS_PHP

# 2.3 list.php (All Record Types Listing)
echo "Rewriting list.php..."
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
    die("Error: Configuration file not found at " . \$config_file);
}

\$config = require \$config_file;

\$api_token = \$config['API_TOKEN']; 
\$zone_id = \$config['ZONE_ID']; 
\$domain = \$config['DOMAIN'];

// 1. Cloudflare မှ DNS Record အားလုံးကို ရယူခြင်း 
function fetch_records(\$api_token, \$zone_id) {
    // Type အားလုံးကို စာရင်းလုပ်ရန် type parameter ဖြုတ်ထားသည်
    \$url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records?per_page=100"; 
    
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

\$result = fetch_records(\$api_token, \$zone_id);
\$records = \$result['records'] ?? [];

// Filter: Root domain နှင့် Cloudflare Default Record များကို ချန်လှပ်ထားသည်
\$filtered_records = array_filter(\$records, function(\$record) use (\$domain) {
    \$valid_type = in_array(\$record['type'], ['A', 'CNAME', 'NS']);
    \$is_not_root = (\$record['name'] !== \$domain);
    return \$valid_type && \$is_not_root;
});

?>
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Records များစာရင်း</title>
    <style>
        /* Design based on index.php (Modern & Clean) */
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #e9ecef; }
        .container { max-width: 950px; margin: auto; padding: 35px; background: #ffffff; border-radius: 15px; box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15); }
        h2 { color: #0056b3; border-bottom: 4px solid #0056b3; padding-bottom: 10px; margin-bottom: 30px; text-align: center; font-size: 1.8em; }
        .back-btn { display: inline-block; padding: 10px 15px; margin-bottom: 25px; background-color: #6c757d; color: white; border-radius: 8px; text-decoration: none; font-weight: bold; transition: background-color 0.3s; }
        .back-btn:hover { background-color: #5a6268; }
        .info-box { padding: 15px; border-radius: 8px; margin-top: 20px; background-color: #fcefd7; border: 2px solid #ffc107; color: #856404; font-weight: bold; }
        .error-box { padding: 15px; border-radius: 8px; margin-top: 20px; background-color: #f8d7da; border: 2px solid #dc3545; color: #721c24; font-weight: bold; }
        .record-table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 0.9em; table-layout: fixed; }
        .record-table th, .record-table td { padding: 12px 10px; text-align: left; border-bottom: 1px solid #dee2e6; word-wrap: break-word; }
        .record-table th { background-color: #007bff; color: white; font-weight: 600; }
        .record-table tr:nth-child(even) { background-color: #f8f9fa; }
        .delete-btn { background-color: #dc3545; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; transition: background-color 0.3s; font-size: 0.9em; }
        .delete-btn:hover { background-color: #c82333; }
        .proxy-on { color: #ff9900; font-weight: bold; }
        .proxy-off { color: #28a745; font-weight: bold; }
        .type-badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 0.85em; }
        .type-A { background-color: #007bff; color: white; }
        .type-CNAME { background-color: #28a745; color: white; }
        .type-NS { background-color: #ffc107; color: #343a40; }
        .record-card-list { display: none; }
        @media (max-width: 768px) {
            .record-table { display: none; }
            .record-card-list { display: block; }
            .record-card { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 15px; margin-bottom: 15px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
            .card-item { padding: 5px 0; border-bottom: 1px dotted #eee; }
            .card-label { font-weight: bold; color: #555; display: inline-block; width: 35%; }
            .card-value { display: inline-block; width: 60%; text-align: right; }
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="index.php" class="back-btn">← Record ဖန်တီးရန် စာမျက်နှာသို့</a>
        <h2>📊 လက်ရှိ DNS Record များစာရင်း (<?php echo htmlspecialchars(\$domain); ?>)</h2>
        
        <?php if (\$result['error']): ?>
            <div class='error-box'>❌ ERROR: Record စာရင်းရယူရာတွင် မအောင်မြင်ပါ။ <?php echo htmlspecialchars(\$result['message']); ?></div>
        <?php elseif (empty(\$filtered_records)): ?>
            <div class='info-box'>ℹ️ လက်ရှိတွင် A, CNAME, NS Record များ မရှိသေးပါ သို့မဟုတ် Domain Root Record များသာ ရှိပါသည်။</div>
        <?php else: ?>
            
            <table class="record-table">
                <thead>
                    <tr>
                        <th style="width: 10%;">Type</th>
                        <th style="width: 30%;">Subdomain</th>
                        <th style="width: 40%;">Content (Value)</th>
                        <th style="width: 10%;">Proxy</th>
                        <th style="width: 10%;">Action</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach (\$filtered_records as \$record): 
                        \$subdomain_only = str_replace("." . \$domain, "", \$record['name']);
                        \$proxy_status = isset(\$record['proxied']) 
                            ? (\$record['proxied'] ? "<span class='proxy-on'>Proxied (On)</span>" : "<span class='proxy-off'>DNS Only (Off)</span>")
                            : "N/A";
                        
                        \$type_class = 'type-' . \$record['type'];
                    ?>
                        <tr>
                            <td><span class="type-badge <?php echo \$type_class; ?>"><?php echo htmlspecialchars(\$record['type']); ?></span></td>
                            <td><?php echo htmlspecialchars(\$subdomain_only); ?></td>
                            <td><?php echo htmlspecialchars(\$record['content']); ?></td>
                            <td><?php echo \$proxy_status; ?></td>
                            <td>
                                <form action='process.php?action=delete' method='POST' style='margin: 0;' onsubmit="return confirm('<?php echo htmlspecialchars(\$record['name']); ?> (<?php echo htmlspecialchars(\$record['type']); ?>) ကို ဖျက်တော့မှာ သေချာပါသလား?');">
                                    <input type='hidden' name='record_id' value='<?php echo htmlspecialchars(\$record['id']); ?>'>
                                    <input type='hidden' name='record_name' value='<?php echo htmlspecialchars(\$record['name']); ?>'>
                                    <input type='hidden' name='record_type' value='<?php echo htmlspecialchars(\$record['type']); ?>'>
                                    <button type='submit' class='delete-btn'>🗑️ ဖျက်မည်</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
            
            <div class="record-card-list">
                <?php foreach (\$filtered_records as \$record): 
                    \$subdomain_only = str_replace("." . \$domain, "", \$record['name']);
                    \$proxy_status = isset(\$record['proxied']) 
                        ? (\$record['proxied'] ? "<span class='proxy-on'>Proxied (On)</span>" : "<span class='proxy-off'>DNS Only (Off)</span>")
                        : "N/A";
                    \$type_class = 'type-' . \$record['type'];
                ?>
                    <div class="record-card">
                        <div class="card-item"><span class="card-label">Type:</span> <span class="card-value"><span class="type-badge <?php echo \$type_class; ?>"><?php echo htmlspecialchars(\$record['type']); ?></span></span></div>
                        <div class="card-item"><span class="card-label">Subdomain:</span> <span class="card-value"><?php echo htmlspecialchars(\$subdomain_only); ?></span></div>
                        <div class="card-item"><span class="card-label">Content:</span> <span class="card-value"><?php echo htmlspecialchars(\$record['content']); ?></span></div>
                        <div class="card-item"><span class="card-label">Proxy Status:</span> <span class="card-value"><?php echo \$proxy_status; ?></span></div>
                        <div style="margin-top: 10px; text-align: center;">
                            <form action='process.php?action=delete' method='POST' style='margin: 0;' onsubmit="return confirm('<?php echo htmlspecialchars(\$record['name']); ?> (<?php echo htmlspecialchars(\$record['type']); ?>) ကို ဖျက်တော့မှာ သေချာပါသလား?');">
                                <input type='hidden' name='record_id' value='<?php echo htmlspecialchars(\$record['id']); ?>'>
                                <input type='hidden' name='record_name' value='<?php echo htmlspecialchars(\$record['name']); ?>'>
                                <input type='hidden' name='record_type' value='<?php echo htmlspecialchars(\$record['type']); ?>'>
                                <button type='submit' class='delete-btn'>🗑️ ဖျက်မည်</button>
                            </form>
                        </div>
                    </div>
                <?php endforeach; ?>
            </div>

        <?php endif; ?>
    </div>
</body>
</html>
EOF_LIST_PHP

# 2.4 Final Web Permissions
sudo chown -R www-data:www-data "${WEB_ROOT}"


echo "========================================================"
echo "  PART 3: NGINX HTTPS WILDCARD SETUP "
echo "========================================================"

# 3.1 Certbot Cloudflare Credentials File
echo "Creating Certbot Cloudflare Credentials File..."
sudo mkdir -p /root/.secrets/
cat << EOF_CRED | sudo tee "${CRED_FILE}" > /dev/null
dns_cloudflare_email = ${CLOUDFLARE_EMAIL}
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF_CRED

sudo chmod 600 "${CRED_FILE}"

# 3.2 NGINX Config File Creation (Initial HTTP for Certbot)
echo "Creating initial NGINX config..."
cat << EOF_NGINX_CONF | sudo tee "${NGINX_CONF}" > /dev/null
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} *.$DOMAIN;
    root ${WEB_ROOT};

    location ~ /.well-known/acme-challenge {
        allow all;
        default_type "text/plain";
    }
    
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF_NGINX_CONF

# 3.3 Enable and Reload NGINX
sudo ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
echo "NGINX Config ကို စတင်အသုံးပြုရန် စစ်ဆေးပြီး Reload လုပ်ပါပြီ။"

# 3.4 Obtaining Wildcard SSL Certificate with Certbot
echo "Obtaining Wildcard SSL Certificate..."
sudo certbot certonly --dns-cloudflare \
    --dns-cloudflare-credentials "${CRED_FILE}" \
    --email ${CLOUDFLARE_EMAIL} \
    --agree-tos \
    --non-interactive \
    -d ${DOMAIN} -d *.$DOMAIN

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/"
if [ ! -d "$CERT_PATH" ]; then
    echo "❌ Wildcard Certificate ရယူခြင်း မအောင်မြင်ပါ။ Cloudflare API Token/Email ကို စစ်ဆေးပါ။"
    exit 1
fi

# 3.5 Final NGINX Config Adjustment (HTTPS Enable)
echo "Applying final NGINX config for HTTPS..."
cat << EOF_FINAL_NGINX_CONF | sudo tee "${NGINX_CONF}" > /dev/null
# NGINX Configuration for Cloudflare DNS Manager (Wildcard: *.$DOMAIN)

# HTTP Block: Redirect all traffic to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} *.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

# HTTPS Block: Main Application
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} *.$DOMAIN;
    root ${WEB_ROOT};
    index index.php index.html;

    # SSL Configuration
    ssl_certificate ${CERT_PATH}fullchain.pem;
    ssl_certificate_key ${CERT_PATH}privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;

    # PHP-FPM Processing
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }
}
EOF_FINAL_NGINX_CONF

# 3.6 Final NGINX Restart
sudo nginx -t && sudo systemctl restart nginx
echo "NGINX ကို HTTPS ဖြင့် ပြန်လည်စတင်ပါပြီ။"

echo "========================================================"
echo "🎉 MASTER SETUP ပြီးဆုံးပါပြီ။"
echo "သင်၏ Panel ကို HTTPS ဖြင့် မည်သည့် Subdomain မှမဆို ဝင်ရောက်နိုင်ပါပြီ။"
echo "ဥပမာ: https://dns.${DOMAIN}/ သို့မဟုတ် https://manager.${DOMAIN}/"
echo "========================================================"
