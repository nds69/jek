#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Author mix: Zahid Islam (udp-zivpn) +  tweaks + KDEV AI UI polish
# Features: apt-guard, binary fetch fallback, UFW rules, DNAT+MASQ, sysctl forward,
#           Flask 1.x-compatible Web UI (auto-refresh 120s), users.json <-> config.json mirror sync,
#           per-user Online/Offline via conntrack, expires accepts "YYYY-MM-DD" OR days "30",
#           Web UI: Header logo + title + Messenger button, Delete button per user, clean styling,
#           Login UI (form-based session, logo included) with /etc/zivpn/web.env credentials.

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် chạy ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards =====
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

# ===== Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services to avoid text busy
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== Base config =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin (Login UI credentials) =====
say "${Y}🔒 Web Admin Login UI ထည့်မလား? (လစ်: မဖိတ်)${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  # strong secret for Flask session
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY'\nimport secrets;print(secrets.token_hex(32))\nPY\n)"
  fi
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
  } > "$ENVF"
  chmod 600 "$ENVF"
  say "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  say "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

# ===== Ask initial VPN passwords =====
say "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: kdev,tak,dtac69${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# ===== Update config.json =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = "/etc/zivpn/zivpn.crt" |
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== systemd: ZIVPN =====
say "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}"
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

# ===== Web Panel (Flask 1.x compatible, refresh 120s + Login UI) =====
say "${Y}🖥️ Web Panel (Flask) ကို ထည့်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'

from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120
LOGO_URL = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQWx88IHvB3mtrrcZdGzslZXj9pWsi1Xz_3tQqR5Zs-sw&s=10"


HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">

<meta http-equiv="refresh" content="120">
<style>
 :root{
  --bg:#ffffff; --fg:#111; --muted:#666; --card:#fafafa; --bd:#e5e5e5;
  --ok:#0a8a0a; --bad:#c0392b; --unk:#666; --btn:#fff; --btnbd:#ccc;
  --pill:#f5f5f5; --pill-bad:#ffecec; --pill-ok:#eaffe6; --pill-unk:#f0f0f0;
 }
 html,body{background:var(--bg);color:var(--fg)}
 body{font-family:system-ui,Segoe UI,Roboto,Arial;margin:18px}
 header{display:flex;align-items:center;gap:14px;margin-bottom:16px}
 h1{margin:0;font-size:1.8em;font-weight:600;line-height:1.2}
 .sub{color:var(--muted);font-size:.95em}
 .btn{
   padding:8px 14px;border-radius:999px;border:1px solid var(--btnbd);
   background:var(--btn);color:var(--fg);text-decoration:none;white-space:nowrap;cursor:pointer
 }
 table{border-collapse:collapse;width:100%;max-width:980px}
 th,td{border:1px solid var(--bd);padding:10px;text-align:left}
 th{background:var(--card)}
 .ok{color:var(--ok);background:var(--pill-ok)}
 .bad{color:var(--bad);background:var(--pill-bad)}
 .unk{color:var(--unk);background:var(--pill-unk)}
 .pill{display:inline-block;padding:4px 10px;border-radius:999px}
 form.box{margin:18px 0;padding:12px;border:1px solid var(--bd);border-radius:12px;background:var(--card);max-width:980px}
 label{display:block;margin:6px 0 2px}
 input{width:100%;max-width:420px;padding:9px 12px;border:1px solid var(--bd);border-radius:10px}
 .row{display:flex;gap:18px;flex-wrap:wrap}
 .row>div{flex:1 1 220px}
 .msg{margin:10px 0;color:var(--ok)}
 .err{margin:10px 0;color:var(--bad)}
 .muted{color:var(--muted)}
 .delform{display:inline}
 tr.expired td{opacity:.9; text-decoration-color: var(--bad);}
 .center{display:flex;align-items:center;justify-content:center}
 .login-card{max-width:auto;margin:70px auto;padding:24px;border:1px solid var(--bd);border-radius:14px;background:var(--card)}
 .login-card h3{margin:10px}
 .logo{height:64px;width:auto;border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,0.15)}

     /* ပုံမှန် စတိုင်များ Reset လုပ်ခြင်း */
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    font-family: sans-serif; /* သင့်တော်တဲ့ font ကို ပြောင်းနိုင်ပါတယ်။ */
}
sody {
    background-color: #f0f2f5; /* နောက်ခံ အရောင် အဖြူဘက်သမ်းသော မီးခိုးရောင် */
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
}
.boxa1 {
    background-color: #ffffff; /* Login Box ရဲ့ နောက်ခံ အဖြူရောင် */
    padding: 40px 30px;
    border-radius: 12px;
    box-shadow: 0 4px 10px rgba(0, 0, 0, 0.1); /* အရိပ်လေး ပေးခြင်း */
    width: 100%;
    max-width: 350px; /* အကျယ်ကို ကန့်သတ်ခြင်း */
   
}
.login-container {
    background-color: #ffffff; /* Login Box ရဲ့ နောက်ခံ အဖြူရောင် */
    padding: 40px 30px;
    border-radius: 12px;
    box-shadow: 0 4px 10px rgba(0, 0, 0, 0.1); /* အရိပ်လေး ပေးခြင်း */
    width: 100%;
    max-width: 350px; /* အကျယ်ကို ကန့်သတ်ခြင်း */
    text-align: center;
}

.profile-image-container {
    display: inline-block;
    margin-bottom: 20px;
    border-radius: 50%;
    overflow: hidden;
    border: 5px solid #f0f2f5; /* ပုံပတ်လည် ဘောင်လေး */
}

.profile-image {
    width: 80px; /* ပုံအရွယ်အစား */
    height: 80px;
    object-fit: cover;
    display: block;
}

h1 {
    font-size: 24px;
    color: #333333;
    margin-bottom: 5px;
}

.panel-title {
    font-size: 14px;
    color: #666666;
    margin-bottom: 30px;
}

.input-group {
    margin-bottom: 15px;
}

input[type="p"],
input[type="password"] {
    width: 100%;
    padding: 12px 15px;
    border: 1px solid #dddddd;
    border-radius: 8px;
    font-size: 16px;
    outline: none;
    transition: border-color 0.3s;
}

/* ပုံထဲကလို Password input မှာပဲ ဘောင်ထူထူလေး ထည့်ဖို့ */
input[type="p"] {
    border: 2px solid #5a5a5a; 
}

input:focus {
    border-color: #007bff; /* Focus လုပ်တဲ့အခါ အရောင်ပြောင်းဖို့ */
}

.login-button {
    width: 100%;
    padding: 12px;
    background-color: #007bff; /* ခလုတ်အရောင် (အပြာရောင်) */
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    cursor: pointer;
    transition: background-color 0.3s;
    margin-top: 20px;
}

.login-button:hover {
    background-color: #0056b3;
}

.save-btn {
    display: block;
    width: 100%;
    padding: 12px;
    background-color: #4CAF50; /* အစိမ်းရောင် */
    color: white;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    font-size: 1em;
    font-weight: bold;
    margin-top: 15px;
}

.save-btn:hover {
    background-color: #45a049;
}
.input-group label .icon {
    color: orange; /* သော့ပုံစံအတွက် */
    margin-right: 5px;
}
.input-group label:first-child .icon {
    color: royalblue; /* user ပုံစံအတွက် */
}
.input-group label:nth-child(3) .icon {
    color: crimson; /* နာရီပုံစံအတွက် */
}
.input-group label:nth-child(4) .icon {
    color: #4CAF50; /* port ပုံစံအတွက် */
}

.section-title {
    font-size: 18px;
    font-weight: bold;
    color: #333;
    margin-bottom: 15px;
}

.section-title .icon {
    font-size: 1.5em;
    margin-right: 5px;
    vertical-align: middle;
    color: #007bff; /* အပြာရောင် icon လေးတွေ */
}


/* အခြေခံ စတိုင်များ */
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: Arial, sans-serif;
    line-height: 1.6;
}

a {
    text-decoration: none;
    color: inherit; /* လင့်ခ်အရောင်ကို ပတ်ဝန်းကျင်အရောင်အတိုင်း သတ်မှတ် */
}

ul {
    list-style: none;
}

/* Header စတိုင် */
.main-header {
    /* Responsive Layout အတွက် Flexbox အသုံးပြုခြင်း */
    display: flex;
    justify-content: space-between; /* ဘယ်၊ ညာ မျှတအောင် ဖြန့်ခင်းခြင်း */
    align-items: center; /* ဒေါင်လိုက် အလယ်တည့်တည့် ထားရှိခြင်း */
    
    background-color: #ffffff;
    color: #333;
    padding: 15px 30px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); /* အရိပ်ပေးခြင်း */
    position: sticky; /* စခရင်ထိပ်မှာ ကပ်နေစေဖို့ */
    top: 0;
    z-index: 1000; /* တခြား အစိတ်အပိုင်းများအပေါ်တွင် ရှိနေစေရန် */
    sticky-top
}

/* Logo စတိုင် */
.header-logo a {
    font-size: 1.8em;
    font-weight: bold;
    color: #007bff; /* အမှတ်တံဆိပ် အရောင် */
}

.header-logo .highlight {
    color: #333; /* နာမည်ရှိ စာလုံးအချို့ကို အရောင်ပြောင်းခြင်း */
}

/* Navigation စတိုင် */
.main-nav .nav-list {
    display: flex; /* လင့်ခ်များကို ဘေးတိုက်ထားရှိခြင်း */
    gap: 25px; /* လင့်ခ်များကြား ခြားနားချက် */
}

.main-nav a {
    color: #333;
    font-size: 1.1em;
    padding: 5px 10px;
    transition: color 0.3s;
}

.main-nav a:hover {
    color: #007bff; /* မောက်စ်တင်ရင် အရောင်ပြောင်းခြင်း */
}

/* CTA ခလုတ် စတိုင် */
.cta-button {
    background-color: #007bff;
    color: white;
    padding: 10px 20px;
    border-radius: 5px;
    font-weight: bold;
    transition: background-color 0.3s;
}

.cta-button:hover {
    background-color: #0056b3;
}

/* Mobile Menu ခလုတ် (စစချင်း ဖျောက်ထားပါ) */
.menu-toggle {
    display: none;
    background: none;
    border: none;
    cursor: pointer;
    flex-direction: column;
    justify-content: space-around;
    width: 30px;
    height: 25px;
    padding: 0;
}

.menu-toggle .bar {
    width: 100%;
    height: 3px;
    background-color: #333;
    transition: all 0.3s ease;
    border-radius: 2px;
}

/* Responsive ဒီဇိုင်း (Mobile, Tablet အတွက်) */
@media (max-width: 768px) {
    /* Mobile မှာ Navigation ကို ဖျောက်ထားခြင်း */
    .main-nav {
        display: none;
        position: absolute;
        top: 60px; /* Header အောက်မှာ ထားခြင်း */
        left: 0;
        width: 100%;
        background-color: #f8f8f8;
        box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05);
        padding: 10px 0;
    }
    
    /* Menu ဖွင့်လိုက်ရင် ပြန်ပေါ်လာစေခြင်း (JavaScript ဖြင့် 'active' class ထည့်သွင်းရမည်) */
    .main-nav.active {
        display: block;
    }

    .main-nav .nav-list {
        flex-direction: column; /* ဒေါင်လိုက် စီစဉ်ခြင်း */
        align-items: center;
        gap: 10px;
    }

    .main-nav a {
        display: block;
        padding: 10px 20px;
        width: 100%;
        text-align: center;
        border-bottom: 1px solid #eee;
    }
    
    /* Mobile မှာ Menu ခလုတ်ကို ပြန်ပေါ်စေခြင်း */
    .menu-toggle {
        display: flex;
    }

    /* Mobile မှာ CTA ခလုတ်ကို လိုအပ်သလို နေရာချခြင်း (ဥပမာ- ဖျောက်ထားခြင်း သို့မဟုတ် Menu ထဲထည့်ခြင်း) */
    .header-cta {
        /* display: none; */ /* ဥပမာအနေဖြင့် ဖျောက်ထားနိုင်သည် */
        order: 3; /* Mobile Menu ဖွင့်/ပိတ်တဲ့ ခလုတ်နဲ့ မနီးစေဖို့ order ပြောင်းနိုင်တယ် */
    }

    .main-header {
        padding: 10px 20px;
    }
}

</style>

</head><bsody>

{% if not authed %}
<body>
    <div class="login-container">
        <div class="profile-image-container">
            <img src="https://raw.githubusercontent.com/tintaungkhaing2025/google/refs/heads/main/zivpn-icon.png" alt="KDEV Profile" class="profile-image">
        </div>
        <h1>KDEV</h1>
        <p class="panel-title">ZIVPN User Panel – Login</p>
<form action="/login" method="POST" class="login-form">
            <div class="input-group">
                <input type="text" id="username" name="u" placeholder="Username" required>
            </div>
            <div class="input-group">
                <input type="text" id="password" name="p" placeholder="Password" required>
            </div>
            <button type="submit" class="login-button">Login</button>
        </form>
    </div>
</body>
{% else %}

<!--   <header>
    <div class="sub">ZIVPN User Panel</div>
  </div>
  <div style="display:flex;gap:8px;align-items:center">
    <a class="btn" href="https://m.me/taknds69" target="_blank" rel="noopener">💬 Contact (Messenger)</a>
    <a class="btn" href="/logout">Logout</a>
  </div>
</header> -->


   <header class="main-header">
        <div class="header-logo">
            <a href="#">ZIVPN<span class="highlight"> User Panel</span></a>
        </div>

        <nav class="main-nav">
            <ul class="nav-list">
                <li><a href="#home">Home</a></li>
               
                <li><a href="/logout">Logout</a></li>
            </ul>
        </nav>

     <!--    <div class="header-cta">
            <a href="#signup" class="cta-button">Sign Up</a>
        </div> -->

        <button class="menu-toggle" aria-label="Toggle navigation">
            <span class="bar"></span>
            <span class="bar"></span>
            <span class="bar"></span>
        </button>
    </header>
    
    <script>
        // Responsive Menu အတွက် အခြေခံ JavaScript
        document.querySelector('.menu-toggle').addEventListener('click', function() {
            document.querySelector('.main-nav').classList.toggle('active');
            this.classList.toggle('active');
        });
    </script>

<form method="post" action="/add" class="boxa1">

    <h2 class="section-title"><span class="icon">+</span> အသုံးပြုသူ အသစ်ထည့်သွင်းရန်</h2>
  {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
  {% if err %}<div class="err">{{err}}</div>{% endif %}
  <div class="row">
    <div><label>👤 User</label><input name="user" required></div>
    <div><label>🔑 Password</label><input name="password" required></div>
  </div>
  <div class="row">
    <div><label>⏰ Expires (ထည့်သွင်းလိုသည့်ရက်)</label><input name="expires" required placeholder="2025-12-31 or 30"></div>
       <div class="input-group">
    <div><label><span class="icon">⚠</span> UDP Port (6000–19999)</label><input name="port" placeholder="auto"></div>
  </div></div>
  
    <div class="input-group">
    <div><label><span class="icon">🔥</span>Server IP</label><input name="copy" placeholder="ip copy" value="185.84.161.224"></div>
  </div></div>
  
  <button class="save-btn" type="submit">Save + Sync</button>
</form>
<br>
<table>
  <tr>
    <th>👤 User</th><th>🔑 Password</th><th>⏰ Expires</th>
<!--    <th>🔌 Port</th><th>🔎 Status</th><th>🗑️ Delete</th>
-->  </tr>
  {% for u in users %}
  <tr class="{% if u.expires and u.expires < today %}expired{% endif %}">
    <td class="usercell">{{u.user}}</td>
    <td>{{u.password}}</td>
    <td>{% if u.expires %}{{u.expires}}{% else %}<span class="muted">—</span>{% endif %}</td>
   <!-- <td>{% if u.port %}{{u.port}}{% else %}<span class="muted">—</span>{% endif %}</td>
    <td>
      {% if u.status == "Online" %}<span class="pill ok">Online</span>
      {% elif u.status == "Offline" %}<span class="pill bad">Offline</span>
      {% else %}<span class="pill unk">Unknown</span>
      {% endif %}
    </td>
    <td>
      <form class="delform" method="post" action="/delete" onsubmit="return confirm('ဖျက်မလား?')">
        <input type="hidden" name="user" value="{{u.user}}">
        <button type="submit" class="btn" style="border-color:transparent;background:#ffecec">Delete</button>
      </form>
    </td>-->
  </tr>
  {% endfor %}
</table>

{% endif %}
</body></html>"""

app = Flask(__name__)

# Secret & Admin credentials (via env)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","kdev").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","kdev").strip()

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
    out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False

def status_for_user(u, active_ports, listen_port):
  port=str(u.get("port",""))
  check_port=port if port else listen_port
  if has_recent_udp_activity(check_port): return "Online"
  if check_port in active_ports: return "Offline"
  return "Unknown"

# --- mirror sync: config.json(auth.config) = users.json passwords only
def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  users_pw=sorted({str(u["password"]) for u in users if u.get("password")})
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

# --- Login guard helpers
def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
  if login_enabled() and not is_authed():
    return False
  return True

def build_view(msg="", err=""):
  if not require_login():
    # render login UI
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))
  users=load_users()
  active=get_udp_listen_ports()
  listen_port=get_listen_port_from_config()
  view=[]
  for u in users:
    view.append(type("U",(),{
      "user":u.get("user",""),
      "password":u.get("password",""),
      "expires":u.get("expires",""),
      "port":u.get("port",""),
      "status":status_for_user(u,active,listen_port)
    }))
  view.sort(key=lambda x:(x.user or "").lower())
  today=datetime.now().strftime("%Y-%m-%d")
  return render_template_string(HTML, authed=True, logo=LOGO_URL, users=view, msg=msg, err=err, today=today)

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
      session["login_err"]="မှန်ကန်မှုမရှိပါ (username/password)"
      return redirect(url_for('login'))
  # GET
  return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
  session.pop("auth", None)
  return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip()

  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    return build_view(err="User နှင့် Password လိုအပ်သည်")
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
  if port:
    if not re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      return build_view(err="Port အကွာအဝေး 6000-19999")
  else:
    port=pick_free_port()

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return build_view(msg="Saved & Synced")

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    return build_view(err="User လိုအပ်သည်")
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return build_view(msg=f"Deleted: {user}")

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  if request.method=="GET":
    users=load_users(); active=get_udp_listen_ports(); listen_port=get_listen_port_from_config()
    for u in users: u["status"]=status_for_user(u,active,listen_port)
    return jsonify(users)
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
  if not port: port=pick_free_port()
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return jsonify({"ok":True})

@app.route("/favicon.ico", methods=["GET"])
def favicon(): return ("",204)

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8080)
PY

# ===== Web systemd =====
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
# Load optional web login credentials
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking: forwarding + DNAT + MASQ + UFW =====
echo -e "${Y}🌐 UDP/DNAT + UFW + sysctl အပြည့်ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
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

# ===== CRLF sanitize =====
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel   :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}users.json  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}config.json :${Z} ${Y}/etc/zivpn/config.json${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|restart zivpn  •  systemctl status|restart zivpn-web${Z}"
echo -e "$LINE"