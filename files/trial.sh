#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Login IP Position & Nav Icon FIX + Expiry Logic Update + Status FIX + PASSWORD EDIT FEATURE (MODAL UI UPDATE - Syntax Fixed + MAX-WIDTH Reduced)
# ================================== MODIFIED: USER COUNT + EXPIRES EDIT MODAL ==================================
# 💡 NEW MODIFICATION: Added User Limit Count Feature + ENFORCEMENT FIX
# 💡 MODIFICATION REQUEST: Shorten 'Edit Expires' and 'Edit Limit' buttons & make their Modals the same width as 'Password Edit' modal.
# 💡 HTTPS MODIFICATION: NGINX + CERTBOT ADDED for zivpn.web-panel.tak.today
set -euo pipefail

# ===== Pretty (CLEANED UP) =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Web UI (သက်တမ်းကုန်ဆုံးချိန် Logic နှင့် Status ပြင်ဆင်ပြီး) - (User Limit ထည့်သွင်းပြီး + ကန့်သတ်ချက် အမှန်တကယ် အလုပ်လုပ်စေရန် ပြင်ဆင်ပြီး)${Z}"
    echo -e "${C}🚨 Web Panel ကို Nginx/Certbot ဖြင့် HTTPS (https://zivpn.web-panel.tak.today) သို့ ပြောင်းလဲနေပါသည်။${Z}"
    echo -e "$LINE"
    echo -e "${C}သက်တမ်းကုန်ဆုံးသည့်နေ့ ည ၁၁:၅၉:၅၉ အထိ သုံးခွင့်ပေးပြီးမှ ဖျက်ပါမည်။${Z}\n"
}
say 

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
