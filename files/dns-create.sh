#!/bin/bash
# FINAL FIX Script for index.php (HTTP 500 Error)

# =========================================================
# CONFIGURATION - API Token များသည် ယခု Script တွင် မပါဝင်ပါ။
# =========================================================
WEB_ROOT="/var/www/html"
# =========================================================

echo "========================================================"
echo "  Step 1: Rewriting index.php (FINAL SYNTAX FIX)      "
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
            <h3>Record အသစ်ဖန်တီး / Update လုပ်မည်</h3>
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

            <input type="submit" value="DNS Record ဖန်တီး / Update လုပ်မည်">
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
echo "  Step 2: Restarting Apache Server "
echo "========================================================"
sudo systemctl restart apache2

echo "========================================================"
echo "✅ index.php ၏ HTTP 500 Error ကို ဖြေရှင်းပြီးပါပြီ။"
echo "ယခု Browser Cache ကို ရှင်းလင်းပြီး http://185.84.161.211/index.php ကို ဖွင့်ပါ။"
echo "========================================================"
