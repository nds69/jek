#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Login IP Position & Nav Icon FIX
set -euo pipefail

# ===== Pretty (CLEANED UP) =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Web UI (Login IP Position & Nav Icon FIX)${Z}"
    echo -e "$LINE"
    echo -e "${C}Login စာမျက်နှာရှိ Server IP နေရာနှင့် Navigation Bar ရှိ Icon များကို ပြင်ဆင်ပြီးပါပြီ။${Z}\n"
}
say 

# --- (Skipping unchanged checks, package installation, and binary download for brevity. They are in the full script.) ---

# ===== Root check (unchanged) =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards (unchanged for brevity) =====
wait_for_apt() {
  echo -e "${Y}⏳ apt သင့်လျော်မှုကို စောင့်ပါ...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
  echo -e "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
  systemctl stop --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl stop --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
}

apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}
apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Packages (unchanged) =====
echo -e "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths and setup directories (unchanged) =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
TEMPLATES_DIR="/etc/zivpn/templates" 
mkdir -p /etc/zivpn "$TEMPLATES_DIR" 

# --- ZIVPN Binary, Config, Certs, Web Admin Login, VPN Passwords, config.json Update, systemd: ZIVPN (UNCHANGED SECTIONS) ---
echo -e "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

if [ ! -f "$CFG" ]; then
  echo -e "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  echo -e "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

echo -e "${Y}🔒 Web Admin Login UI ထည့်မလား? (လစ်: မဖိတ်)${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY'
import secrets;print(secrets.token_hex(32))
PY
)"
  fi
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
  } > "$ENVF"
  chmod 600 "$ENVF"
  echo -e "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  echo -e "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

echo -e "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: M-69P,tak,dtac69${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = (."cert" // "/etc/zivpn/zivpn.crt") |
    .key  = (."key" // "/etc/zivpn/zivpn.key") |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

echo -e "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}"
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 💡 Mobile Friendly: users_table.html (No Change)
echo -e "${Y}📄 Table HTML (users_table.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table.html" <<'TABLE_HTML'
<div class="table-container">
    <table>
      <thead>
          <tr>
            <th><i class="icon">👤</i> User</th>
            <th><i class="icon">🔑</i> Password</th>
            <th><i class="icon">⏰</i> Expires</th>
            <th><i class="icon">🚦</i> Status</th> 
            <th><i class="icon">❌</i> Action</th>
          </tr>
      </thead>
      <tbody>
          {% for u in users %}
          <tr class="{% if u.expires and u.expires < today %}expired{% elif u.expiring_soon %}expiring-soon{% endif %}">
            <td data-label="User">{% if u.expires and u.expires < today %}<s>{{u.user}}</s>{% else %}{{u.user}}{% endif %}</td>
            <td data-label="Password">{% if u.expires and u.expires < today %}<s>{{u.password}}</s>{% else %}{{u.password}}{% endif %}</td>
            <td data-label="Expires">{% if u.expires %}{% if u.expires < today %}<s>{{u.expires}} (Expired)</s>{% elif u.expiring_soon %}<span class="text-expiring">{{u.expires}}</span>{% else %}{{u.expires}}{% endif %}{% else %}<span class="muted">—</span>{% endif %}</td>
            <td data-label="Status">
              {% if u.expires and u.expires < today %}
                <span class="pill pill-expired"><i class="icon">🛑</i> Expired</span>
              {% elif u.expiring_soon %}
                <span class="pill pill-expiring"><i class="icon">⚠️</i> Expiring Soon</span>
              {% else %}
                {% if u.status == "Online" %}
                  <span class="pill ok"><i class="icon">🟢</i> Online</span>
                {% elif u.status == "Offline" %}
                  <span class="pill bad"><i class="icon">🔴</i> Offline</span>
                {% elif u.status == "Online (Shared)" %}
                  <span class="pill shared-online"><i class="icon">🟡</i> Online (Shared)</span>
                {% elif u.status == "Offline (Shared)" %}
                  <span class="pill shared-offline"><i class="icon">⚪</i> Offline (Shared)</span>
                {% else %}
                  <span class="pill unk"><i class="icon">⚫</i> {{ u.status }}</span>
                {% endif %}
              {% endif %}
            </td>
            <td data-label="Action">
              <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} ကို ဖျက်မလား?')">
                <input type="hidden" name="user" value="{{u.user}}">
                <button type="submit" class="btn-delete"><i class="icon">🗑️</i> Delete</button>
              </form>
            </td>
          </tr>
          {% endfor %}
      </tbody>
    </table>
</div>
TABLE_HTML

# 💡 Mobile Friendly: users_table_wrapper.html (Updated Nav Icons and Color)
echo -e "${Y}📄 Table Wrapper (users_table_wrapper.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table_wrapper.html" <<'WRAPPER_HTML'
<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel - Users</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
/* Global Styles for Mobile UI */
:root {
    --primary: #ff7f27; /* 💡 Color Change: Orange */
    --primary-dark: #cc661f; /* Darker shade for active/hover state */
    --secondary: #6c757d; --success: #28a745; --danger: #dc3545;
    --light: #f8f9fa; --dark: #343a40; 
    --bg-color: #f0f2f5; 
    --card-bg: #ffffff;
    --border-color: #dee2e6;
    --warning: #ffc107; /* New: Warning color for expiry */
    --warning-bg: #fff3cd;
}
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color);
    line-height: 1.6; color: var(--dark); margin: 0; padding: 0;
    padding-bottom: 70px; /* Space for fixed bottom navigation */
}
.icon { font-style: normal; margin-right: 5px; }

/* Header/Logo Only */
.main-header {
    display: flex; justify-content: space-between; align-items: center;
    background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
    margin-bottom: 15px; position: sticky; top: 0; z-index: 1000;
}
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none;}
.header-logo .highlight { color: var(--dark); }

/* 💡 Mobile Bottom Navigation (New) */
.bottom-nav {
    display: flex;
    justify-content: space-around;
    align-items: center;
    position: fixed;
    bottom: 0;
    left: 0;
    width: 100%;
    background-color: var(--card-bg);
    box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.1);
    z-index: 1000;
    padding: 5px 0;
}
.bottom-nav a {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-decoration: none;
    color: var(--secondary);
    font-size: 0.75em;
    padding: 8px;
    border-radius: 6px;
    transition: color 0.2s, background-color 0.2s;
    min-width: 80px;
}
.bottom-nav a:hover, .bottom-nav a.active {
    color: var(--primary); /* Hover and Active State use Primary Color (Orange) */
}
.bottom-nav a i.icon {
    font-size: 1.2em;
    margin-right: 0;
    margin-bottom: 3px;
    color: #ffd966; /* 💡 Nav Icon Color Change: Subtle Yellow */
}
.bottom-nav a:hover i.icon, .bottom-nav a.active i.icon {
    color: var(--primary); /* Active Icon uses Primary Color */
}


/* Table Styles (Mobile Responsiveness) */
.table-container { padding: 0 10px; margin: 0 auto; max-width: 100%; } 
table {
    width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 15px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05); border-radius: 8px; overflow: hidden;
}
th, td { padding: 10px; text-align: left; border-bottom: 1px solid var(--border-color); font-size: 0.9em; }
th { background-color: var(--primary); color: white; font-weight: 600; text-transform: uppercase; font-size: 0.8em; } /* 💡 Color Change */
tr:last-child td { border-bottom: none; }
tr:nth-child(even) { background-color: var(--light); }
tr:hover { background-color: #e9ecef; }

/* Mobile Table Stacked View (Crucial for mobile friendliness) */
@media (max-width: 768px) {
    .table-container { padding: 0 5px; }
    
    table, thead, tbody, th, td, tr { display: block; }
    thead { display: none; } /* Hide Header on Mobile */
    
    tr { 
        border: 1px solid var(--border-color); 
        margin-bottom: 15px; 
        border-radius: 8px; 
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
    }
    td {
        border: none;
        position: relative;
        padding-left: 45%; /* Space for label */
        text-align: right;
        border-bottom: 1px dashed #e0e0e0;
    }
    td:last-child { border-bottom: none; }
    
    td:before {
        content: attr(data-label);
        position: absolute;
        left: 0;
        width: 40%;
        padding-left: 10px;
        font-weight: bold;
        text-align: left;
        color: var(--secondary);
        font-size: 0.9em;
    }
    .pill { padding: 4px 8px; font-size: 0.8em; min-width: 70px; }
    .delform { display: block; text-align: right; }
    .btn-delete { width: 80px; padding: 6px 8px; font-size: 0.8em; margin-top: 5px;}
}
/* Desktop Navigation Hidden */
.main-nav { display: none; } 
@media (min-width: 769px) {
    .bottom-nav { display: none; } /* Hide bottom nav on desktop */
    body { padding-bottom: 0; }
}

/* Pill/Status & Buttons */
.pill { display: inline-flex; align-items: center; padding: 6px 10px; border-radius: 15px; font-size: 0.85em; font-weight: bold; min-width: 90px; justify-content: center;}
.ok { background-color: #d4edda; color: var(--success); } /* Green (Dedicated Online) */
.bad { background-color: #f8d7da; color: var(--danger); } /* Red (Dedicated Offline) */
.unk { background-color: #e2e3e5; color: var(--secondary); } /* Grey (Unknown / Shared Port) */
.shared-online { background-color: #fff3cd; color: var(--warning); } /* Yellow (Shared Port Active) */
.shared-offline { background-color: #f0f0f0; color: var(--secondary); } /* Light Grey (Shared Port Inactive) */

.pill-expired { background-color: #f0f0f0; color: var(--danger); }
.pill-expiring { background-color: var(--warning-bg); color: var(--warning); } 
.text-expiring { color: var(--warning); font-weight: bold; } 


/* Row Styles for Expiry */
tr.expired td { opacity: 0.6; text-decoration-color: var(--danger); }
tr.expiring-soon { border-left: 5px solid var(--warning); background-color: rgba(255, 193, 7, 0.1); } 


.btn-delete { background-color: var(--danger); color: white; border: none; padding: 8px 12px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s;}
.btn-delete:hover { background-color: #c82333; }

</style>
</head><body>
    
    <header class="main-header">
        <div class="header-logo">
            <a href="/">ZIVPN<span class="highlight"> Panel</span></a>
        </div>
    </header>

{% include 'users_table.html' %}

    <nav class="bottom-nav">
        <a href="/" class="active">
            <i class="icon">➕</i>
            <span>အကောင့်ထည့်ရန်</span>
        </a>
        <a href="/users">
            <i class="icon">📜</i>
            <span>အသုံးပြုသူ စာရင်း</span>
        </a>
        <a href="/logout">
            <i class="icon">➡️</i>
            <span>ထွက်ရန်</span>
        </a>
    </nav>

</body></html>
WRAPPER_HTML

# 💡 Web Panel (Flask - web.py) (Updated HTML Template String)
echo -e "${Y}🖥️ Web Panel (web.py) ကို Login IP Position Fix ဖြင့် ပြင်ဆင်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://zivpn-web.free.nf/zivpn-icon.png"

def get_server_ip():
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        ip = result.stdout.strip().split()[0]
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', ip):
            return ip
    except Exception:
        pass
    return "127.0.0.1" 

SERVER_IP_FALLBACK = get_server_ip()

# 💡 HTML Template အဓိကဖိုင် (Updated Colors, Login Error Display, UI Style, and IP Position)
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
/* Global Styles */
:root {
    --primary: #ff7f27; /* 💡 Color Change: Orange */
    --primary-dark: #cc661f; /* Darker shade for active/hover state */
    --secondary: #6c757d; --success: #28a745; --danger: #dc3545;
    --light: #f8f9fa; --dark: #343a40; --bg-color: #f0f2f5; --card-bg: #ffffff;
    --border-color: #dee2e6;
    --warning: #ffc107; 
}
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color);
    line-height: 1.6; color: var(--dark); margin: 0; padding: 0;
    padding-bottom: 70px; /* Space for fixed bottom navigation */
}
.icon { font-style: normal; margin-right: 5px; }

/* Header/Logo Only */
.main-header {
    display: flex; justify-content: space-between; align-items: center;
    background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
    margin-bottom: 15px; position: sticky; top: 0; z-index: 1000;
}
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none;} /* 💡 Color Change */
.header-logo .highlight { color: var(--dark); }

/* 💡 Mobile Bottom Navigation */
.bottom-nav {
    display: flex;
    justify-content: space-around;
    align-items: center;
    position: fixed;
    bottom: 0;
    left: 0;
    width: 100%;
    background-color: var(--card-bg);
    box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.1);
    z-index: 1000;
    padding: 5px 0;
}
.bottom-nav a {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-decoration: none;
    color: var(--secondary);
    font-size: 0.75em;
    padding: 8px;
    border-radius: 6px;
    transition: color 0.2s, background-color 0.2s;
    min-width: 80px;
}
.bottom-nav a:hover, .bottom-nav a.active {
    color: var(--primary); /* 💡 Color Change */
}
.bottom-nav a i.icon {
    font-size: 1.2em;
    margin-right: 0;
    margin-bottom: 3px;
    color: #ffd966; /* 💡 Nav Icon Color Change: Subtle Yellow */
}
.bottom-nav a:hover i.icon, .bottom-nav a.active i.icon {
    color: var(--primary); /* Active Icon uses Primary Color */
}
@media (min-width: 769px) {
    .bottom-nav { display: none; }
    body { padding-bottom: 0; }
}

/* Login/Form Styles - Enhanced UI */
.login-container, .boxa1 {
    background-color: var(--card-bg); 
    padding: 30px 20px; 
    border-radius: 12px;
    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15); /* Slightly stronger shadow */
    width: 90%; max-width: 400px;
    margin: 30px auto;
    text-align: center;
}
.boxa1 {
    max-width: 600px;
    margin-top: 15px;
    text-align: left;
}


/* New: Info Card for total users */
.info-card {
    background-color: #fcece3; 
    color: var(--primary-dark);
    padding: 15px 20px;
    border-radius: 8px;
    text-align: center;
    font-weight: bold;
    font-size: 1.0em; 
    margin-bottom: 15px;
    border: 1px solid var(--primary);
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}
/* 💡 ပြင်ဆင်ချက်: စုစုပေါင်းအရေအတွက် (Total Users) ကို စာလုံးသေးပေးလိုက်သည် */
.info-card span {
    font-size: 1.1em; /* 1.4em ကနေ 1.1em သို့ ပြောင်းလိုက်သည် */
    margin-right: 5px;
}

.profile-image-container {
    display: inline-block; margin-bottom: 15px; border-radius: 50%;
    overflow: hidden; border: 4px solid var(--primary); /* 💡 Color Change */
}
.profile-image { width: 70px; height: 70px; object-fit: cover; display: block; }
h1 { font-size: 22px; color: var(--dark); margin-bottom: 5px; }
.panel-title { font-size: 14px; color: var(--secondary); margin-bottom: 25px; }
/* 💡 New: Login IP Display Style */
.login-ip-display {
    font-size: 16px;
    color: var(--primary-dark);
    font-weight: bold;
    margin-top: -15px; /* Adjust margin to place it higher */
    margin-bottom: 25px; /* Ensure space below */
}

/* Input Fields with Icons/Design */
.input-group { 
    margin-bottom: 15px; 
    text-align: left;
}
.input-field-wrapper {
    display: flex;
    align-items: center;
    border: 1px solid var(--border-color);
    border-radius: 8px;
    margin-Top: 5px; 
    background-color: #fff;
    transition: border-color 0.3s, box-shadow 0.3s;
}
.input-field-wrapper:focus-within {
    border-color: var(--primary); /* 💡 Color Change */
    box-shadow: 0 0 0 3px rgba(255, 127, 39, 0.25); /* Focus effect with primary color */
}
.input-field-wrapper .icon {
    padding: 0 10px;
    color: var(--secondary);
    background: transparent; 
}
input[type="text"], input[type="password"], input[name="expires"], input[name="port"], input[name="ip"] {
    width: 100%;
    padding: 12px 10px;
    border: none; 
    border-radius: 0 8px 8px 0;
    font-size: 16px;
    outline: none;
    background: transparent; 
    appearance: none; 
    -webkit-appearance: none;
}
input[name="ip"] {
    background-color: var(--light);
    color: var(--secondary);
    cursor: pointer; 
}
/* 💡 Button Color and Hover/Active State */
.login-button, .save-btn {
    width: 100%; padding: 12px; 
    background-color: var(--primary); /* 💡 Color Change: Orange */
    color: white; border: none; border-radius: 8px; font-size: 16px;
    cursor: pointer; transition: background-color 0.3s; margin-top: 20px; font-weight: bold;
}
.login-button:hover, .save-btn:hover { background-color: var(--primary-dark); } /* 💡 Darken on hover */
.login-button:active, .save-btn:active { background-color: var(--primary-dark); transform: translateY(1px); } /* Pressed effect */


.section-title { font-size: 18px; font-weight: bold; color: var(--dark); margin-bottom: 15px; }
.row{display:flex;gap:15px;flex-wrap:wrap;margin-bottom: 5px;}
.row>div{flex:1 1 100%;}
@media (min-width: 600px) {
    .row>div{flex:1 1 220px;}
}
/* 💡 Error Message Style (For Login) */
.err{
    color: var(--danger); 
    background-color: #f8d7da;
    border: 1px solid #f5c6cb;
    padding: 10px;
    border-radius: 8px;
    margin-bottom: 15px; 
    font-weight: bold;
    text-align: center;
}

.user-info-card {
    /* 💡 ညာဘက်ယွန်းသော အလယ်နေရာသို့ ပြင်ဆင်လိုက်သော Properties များ */
    position: fixed; 
    top: 20px; 
    left: 50%; /* အလယ် (50%) ကနေ ညာဘက် (60%) ကို ရွှေ့ */
    transform: translateX(-50%); /* Card ရဲ့ ကိုယ်ပိုင်အကျယ်ရဲ့ တစ်ဝက်ကို ဘယ်ဘက်ပြန်ဆွဲ (Center နေရာမှစ၍ ညာဘက်ကို ချိန်ညှိရန်) */
    
    /* မူရင်း Styles များ */
    background-color: #d4edda;
    color: #155724; 
    border: 1px solid #c3e6cb; 
    border-radius: 8px;
    padding: 15px 20px; 
    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
    z-index: 2000; 
    max-width: 300px; 
    width: 90%; /* Mobile တွင် ကွက်တိဖြစ်စေရန် */
    text-align: left;
}


@keyframes fadein {
    from { opacity: 0; transform: translateY(-20px); }
    to { opacity: 1; transform: translateY(0); }
}

@keyframes fadeout {
    from { opacity: 1; }
    to { opacity: 0; visibility: hidden; }
}
/* New: Copy Success Message Style */
#copy-notification {
    position: fixed; top: 10px; right: 50%; transform: translateX(50%);
    background-color: var(--success); color: white; padding: 8px 15px;
    border-radius: 5px; z-index: 2000; font-size: 0.9em;
    opacity: 0; transition: opacity 0.5s;
}

text {
  
  font-size: 15px;
  margin-Top: 0px;
}

</style>
<script>
    // 💡 ULTIMATE FIX: JavaScript function for copy-to-clipboard with Fallback (Re-applied)
    function copyToClipboard(elementId) {
        const copyText = document.getElementById(elementId);
        if (!copyText) return;
        
        const notification = document.getElementById('copy-notification');
        const showNotification = () => {
            notification.innerText = 'Server IP ကို ကူးပြီးပါပြီ';
            notification.style.opacity = 1;
            setTimeout(() => {
                notification.style.opacity = 0;
            }, 2000);
        };
        
        // 1. New Clipboard API (Requires HTTPS or localhost)
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(copyText.value).then(showNotification).catch(err => {
                // If New API fails (e.g., due to HTTP), fall back
                fallbackCopy(copyText, showNotification);
            });
        } else {
            // 2. Fallback using execCommand (Works better on HTTP/older browsers)
            fallbackCopy(copyText, showNotification);
        }
    }

    function fallbackCopy(copyText, onSuccess) {
        let isCopied = false;
        try {
            // Select the text field
            copyText.select();
            // For mobile devices: ensure the selection range covers all text
            copyText.setSelectionRange(0, 99999); 
            
            // Copy the text inside the text field
            isCopied = document.execCommand('copy');

            if (isCopied) {
                onSuccess();
            } else {
                console.error('Copy failed using execCommand');
            }
        } catch (err) {
            console.error('Fallback copy failed: ', err);
        }
    }
</script>

</head><body>

{% if not authed %}
    <div class="login-container">
        <div class="profile-image-container">
            <img src="{{logo}}" alt="Profile" class="profile-image">
        </div>
        <h1>ZIVPN Panel</h1>
        <br>
        {% if IP %}
        <p class="login-ip-display">Server IP: {{ IP }}</p>
        {% endif %}
        
        <p class="panel-title">Login to Admin Dashboard</p>
        
        {% if err %}<div class="err">{{err}}</div>{% endif %} <form action="/login" method="POST" class="login-form">
            <div class="input-group">
                <label for="username" style="display:none;">Username</label>
                <div class="input-field-wrapper">
                    <i class="icon">🔑</i>
                    <input type="text" id="username" name="u" placeholder="Username" required>
                </div>
            </div>
            <div class="input-group">
                <label for="password" style="display:none;">Password</label>
                <div class="input-field-wrapper">
                    <i class="icon">🔒</i>
                    <input type="password" id="password" name="p" placeholder="Password" required>
                </div>
            </div>
            <button type="submit" class="login-button">Login</button>
        </form>
    </div>
{% else %}

   <header class="main-header">
        <div class="header-logo">
            <a href="/">ZIVPN<span class="highlight"> Panel</span></a>
        </div>
    </header>
    
    <div id="copy-notification"></div> <div class="boxa1">
        <div class="info-card">
            <i class="icon">💡</i> လက်ရှိ Member User စုစုပေါင်း<br><span>{{ total_users }}</span>ယောက်
        </div>
        
    <script>
        {% if msg and '{' in msg and '}' in msg %}
        try {
            const data = JSON.parse('{{ msg | safe }}');
            if (data.user) { 
                const card = document.createElement('div');
                card.className = 'user-info-card';
                card.innerHTML = `
                    <h4>✅ အကောင့်အသစ် ဖန်တီးပြီးပါပြီ</h4>
                    <p><i class="icon">🔥</i> Server IP: <b>${data.ip || '{{ IP }}'}</b></p>  
                    <p><i class="icon">👤</i> Username: <b>${data.user}</b></p>
                    <p><i class="icon">🔑</i> Password: <b>${data.password}</b></p>
                    <p><i class="icon">⏰</i> Expires: <b>${data.expires || 'N/A'}</b></p>                   
                `;
                document.body.appendChild(card);
                
                setTimeout(() => {
                    if (card.parentNode) {
                        card.parentNode.removeChild(card);
                    }
                }, 20000); 
            }
        } catch (e) {
            console.error("Error parsing message JSON:", e);
        }
        {% endif %}
    </script>


    <form method="post" action="/add" class="">
        <h2 class="section-title"><i class="icon">➕</i> Add new user</h2>
        {% if err %}<div class="err">{{err}}</div>{% endif %}
  
        <div class="input-group">
            <label for="username" style="display:none;">Username</label>
            <div class="input-field-wrapper">
                <i class="icon">👤</i>
                <input type="text" id="username" name="user" placeholder="Username" required>
            </div>
        </div>
        <div class="input-group">
            <label for="password" style="display:none;">Password</label>
            <div class="input-field-wrapper">
                <i class="icon">🔑</i>
                <input type="password" id="password" name="password" placeholder="Password" required>
            </div>
        </div>
        <div class="row">
            <div>
            <text> <label><i class="icon"></i>Add (expiration date)</label></text>
            <tak1>  <div class="input-field-wrapper">
                <i class="icon">🗓️</i>
                <input name="expires" required placeholder="Example : 2025-12-31 or 30">
            </div></tak1>
            </div>
        </div>
        <div class="input-group">
            <label><i class="icon"></i>Server IP (Click to Copy)</label> 
            <div class="input-field-wrapper">
                <i class="icon">📡</i>
                <input name="ip" id="server-ip-input" placeholder="ip" value="{{ IP }}" readonly onclick="copyToClipboard('server-ip-input')">
            </div>
        </div>

        <button class="save-btn" type="submit">Create Account</button>
    </form>
    </div> <nav class="bottom-nav">
        <a href="/">
            <i class="icon">➕</i>
            <span>အကောင့်ထည့်ရန်</span>
        </a>
        <a href="/users">
            <i class="icon">📜</i>
            <span>အသုံးပြုသူ စာရင်း</span>
        </a>
        <a href="/logout">
            <i class="icon">➡️</i>
            <span>ထွက်ရန်</span>
        </a>
    </nav>


{% endif %}
</body></html>"""

app = Flask(__name__, template_folder="/etc/zivpn/templates")

# Secret & Admin credentials (via env)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","M-69P").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","M-69P").strip()

# Flask Helper Functions 
def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except Exception:
    return default
def write_json_atomic(path, data):
  d=json.dumps(data, ensure_ascii=False, indent=2)
  dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
  try:
    with os.fdopen(fd,"w") as f: f.write(d)
    os.replace(tmp,path)
  finally:
    try: os.remove(tmp)
    except: pass
def load_users():
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v:
    out.append({"user":u.get("user",""),
                "password":u.get("password",""),
                "expires":u.get("expires",""),
                "port":str(u.get("port","")) if u.get("port","")!="" else ""})
  return out
def save_users(users): write_json_atomic(USERS_FILE, users)
def get_listen_port_from_config():
  cfg=read_json(CONFIG_FILE,{})
  listen=str(cfg.get("listen","")).strip()
  m=re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)
def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  return set(re.findall(r":(\d+)\s", out))
def pick_free_port():
  used={str(u.get("port","")) for u in load_users() if str(u.get("port",""))}
  used |= get_udp_listen_ports()
  for p in range(6000,20000):
    if str(p) not in used: return str(p)
  return ""
def has_recent_udp_activity(port):
  if not port: return False
  try:
    # Check for recent conntrack entries for the specific port
    out=subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b'",
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False
    
# Function to get the count of non-expired users
def get_total_active_users():
    users = load_users()
    today_date = datetime.now().date()
    active_count = 0
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError:
                # If date format is invalid, treat it as non-expiring (active)
                is_expired = False
        
        if not is_expired:
            active_count += 1
    return active_count

def status_for_user(u, active_ports, listen_port, all_users):
  port = str(u.get("port", "")).strip()
  
  is_sharing_main_port = (not port or port == listen_port)
  
  has_dedicated_users = any(str(user.get("port","")).strip() and str(user.get("port","")).strip() != listen_port for user in all_users)

  if is_sharing_main_port and not has_dedicated_users:
    if has_recent_udp_activity(listen_port):
      return "Online (Shared)" 
    return "Offline (Shared)"
  
  if is_sharing_main_port and has_dedicated_users:
    return "Shared Port"
    
  if port and port != listen_port:
    if has_recent_udp_activity(port):
      return "Online" # Green
    return "Offline" # Red
    
  return "Unknown" # Fallback

def is_expiring_soon(expires_str):
    if not expires_str: return False
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = datetime.now().date()
        two_days_out = today + timedelta(days=2)
        
        return expires_date >= today and expires_date <= two_days_out
    except ValueError:
        return False
    
def delete_user(user):
    users = load_users()
    remaining_users = [u for u in users if u.get("user").lower() != user.lower()]
    save_users(remaining_users)
    sync_config_passwords(mode="mirror")
def check_user_expiration():
    users = load_users()
    today_date = datetime.now().date()
    users_to_keep = []
    deleted_count = 0
    
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError:
                pass 

        if is_expired:
            deleted_count += 1
        else:
            users_to_keep.append(user)

    if deleted_count > 0:
        save_users(users_to_keep)
        sync_config_passwords(mode="mirror") 
        return True 
    return False 
def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  
  today_date = datetime.now().date()
  valid_passwords = set()
  for u in users:
      expires_str = u.get("expires")
      is_valid = True
      if expires_str:
          try:
              if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                  is_valid = False
          except ValueError:
              is_valid = True 

      if is_valid and u.get("password"):
          valid_passwords.add(str(u["password"]))

  users_pw=sorted(list(valid_passwords))
  
  if mode=="merge":
    old=[]
    if isinstance(cfg.get("auth",{}).get("config",None), list):
      old=list(map(str, cfg["auth"]["config"]))
    new_pw=sorted(set(old)|set(users_pw))
  else:
    new_pw=users_pw
    
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"
  cfg["auth"]["config"]=new_pw
  cfg["listen"]=cfg.get("listen") or ":5667"
  cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
  cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
  cfg["obfs"]=cfg.get("obfs") or "zivpn"
  write_json_atomic(CONFIG_FILE,cfg)
  subprocess.run("systemctl restart zivpn.service", shell=True)
def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
  if login_enabled() and not is_authed():
    return False
  return True
def prepare_user_data():
    all_users = load_users()
    check_user_expiration() 
    users = load_users() # Reload after expiration check
    active=get_udp_listen_ports()
    listen_port=get_listen_port_from_config()
    view=[]
    for u in users:
      view.append(type("U",(),{
        "user":u.get("user",""),
        "password":u.get("password",""),
        "expires":u.get("expires",""),
        "port":u.get("port",""),
        "status":status_for_user(u,active,listen_port, users), 
        "expiring_soon": is_expiring_soon(u.get("expires","")) 
      }))
    view.sort(key=lambda x:(x.user or "").lower())
    today=datetime.now().strftime("%Y-%m-%d")
    return view, today

# Flask Routes 
@app.route("/", methods=["GET"])
def index(): 
    server_ip = SERVER_IP_FALLBACK 
    if not require_login():
      return render_template_string(HTML, 
                                authed=False, 
                                logo=LOGO_URL, 
                                err=session.pop("login_err", None),
                                IP=server_ip) 
    
    # Run expiration check and get the total count
    check_user_expiration()
    total_users = get_total_active_users()

    return render_template_string(HTML, 
                                authed=True, 
                                logo=LOGO_URL, 
                                total_users=total_users, # Passed to template
                                msg=session.pop("msg", None), 
                                err=session.pop("err", None), 
                                today=datetime.now().strftime("%Y-%m-%d"),
                                IP=server_ip)

@app.route("/users", methods=["GET"])
def users_table_view():
    if not require_login(): return redirect(url_for('login'))
    
    view, today = prepare_user_data()
    
    return render_template("users_table_wrapper.html", 
                           users=view, 
                           today=today, 
                           logo=LOGO_URL, 
                           IP=SERVER_IP_FALLBACK)


@app.route("/login", methods=["GET","POST"])
def login():
  if not login_enabled():
    return redirect(url_for('index'))
  if request.method=="POST":
    u=(request.form.get("u") or "").strip()
    p=(request.form.get("p") or "").strip()
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
      session["auth"]=True
      return redirect(url_for('index'))
    else:
      session["auth"]=False
      session["login_err"]="❌ Username သို့မဟုတ် Password မှားယွင်းနေပါသည်။ ထပ်မံစစ်ဆေးပါ။" # Fixed Error Message
      return redirect(url_for('login'))
  # GET
  return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), IP=SERVER_IP_FALLBACK)

@app.route("/logout", methods=["GET"])
def logout():
  session.pop("auth", None)
  return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip() # This is now typically empty/unused by the form
  ip = (request.form.get("ip") or "").strip() or SERVER_IP_FALLBACK

  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    session["err"] = "User Name နှင့် Password များ မပါဝင်ပါ"
    return redirect(url_for('index')) 
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      session["err"] = "Expires ရက်စွဲ မမှန်ပါ"
      return redirect(url_for('index'))
  
  # Port logic remains generic, assuming empty 'port' means shared port (5667)
  # Dedicated ports (6000-19999) must be entered manually or via API
  if port:
    if not re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      session["err"] = "Port နံပါတ် (6000-19999) မမှန်ပါ"
      return redirect(url_for('index'))
  
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  
  save_users(users)
  sync_config_passwords()

  msg_dict = {
      "user": user,
      "password": password,
      "expires": expires,
      "ip": ip 
  }
  
  session["msg"] = json.dumps(msg_dict)
  return redirect(url_for('index'))

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    session["err"] = "User Name မပါဝင်ပါ"
    return redirect(url_for('users_table_view'))
  
  delete_user(user) 
  return redirect(url_for('users_table_view'))

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  
  delete_user(user) 
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  
  if request.method=="GET":
    all_users = load_users()
    check_user_expiration() 
    users = load_users() 
    active=get_udp_listen_ports(); listen_port=get_listen_port_from_config()
    for u in users: 
      u["status"]=status_for_user(u,active,listen_port, all_users)
      u["expiring_soon"]=is_expiring_soon(u.get("expires",""))
    return jsonify(users)
  
  if request.method=="POST":
    data=request.get_json(silent=True) or {}
    user=(data.get("user") or "").strip()
    password=(data.get("password") or "").strip()
    expires=(data.get("expires") or "").strip()
    port=str(data.get("port") or "").strip()
    if expires.isdigit():
      expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
    if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
    if port and (not re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
      return jsonify({"ok":False,"err":"invalid port"}),400
      
    users=load_users(); replaced=False
    for u in users:
      if u.get("user","").lower()==user.lower():
        u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
    if not replaced:
      users.append({"user":user,"password":password,"expires":expires,"port":port})
    save_users(users)
    sync_config_passwords()
    return jsonify({"ok":True})

@app.route("/favicon.ico", methods=["GET"])
def favicon(): return ("",204)

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8080)
PY
# ===== Web systemd (unchanged) =====
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
# Load optional web login credentials
EnvironmentFile=-/etc/zivpn/web.env
WorkingDirectory=/etc/zivpn 
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking: forwarding + DNAT + MASQ + UFW (unchanged) =====
echo -e "${Y}🌐 UDP/DNAT + UFW + sysctl အပြည့်ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '{print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0
# DNAT 6000:19999/udp -> :5667
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQ out
iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize (File တွေ အားလုံး ဖန်တီးပြီးမှ ရှင်းခြင်း) =====
echo -e "${Y}🧹 CRLF ရှင်းနေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table.html /etc/zivpn/templates/users_table_wrapper.html || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel (Add Users) :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}Web Panel (User List) :${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|systemctl restart zivpn  •  systemctl restart status|systemctl restart zivpn-web${Z}"
echo -e "$LINE"