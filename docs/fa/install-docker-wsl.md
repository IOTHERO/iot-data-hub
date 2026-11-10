# نصب و اجرای تولیدی با Docker روی WSL (ویندوز)

این راهنما کل سامانه را روی WSL 2 در ویندوز (یا هر سرور لینوکس) با Docker بالا می‌آورد: داشبورد مهندسی، وب‌اپ مشتری، پنل سازنده، API، بروکر MQTT دستگاه‌ها و پایگاه داده. اپ فلاتر و اپ اندروید جدا ساخته می‌شوند و فقط به همین سرور وصل می‌شوند.

> فایل‌ها: `Dockerfile` در ریشهٔ پروژه و پوشهٔ `deploy/`. مرجع فنی انگلیسی: `docs/backend.md` و `docs/platform.md`.

---

## ۱. چه چیزهایی اجرا می‌شود

```
           اینترنت / شبکهٔ محلی
                  │
   ┌──────────────┼───────────────────────────────┐
   │  ۸۰ و ۴۴۳     │  ۸۸۸۳ (MQTT+TLS)     ۷۰۰۰ (TCP+TLS)
   ▼              ▼                       ▼
 caddy ──────►  hub  ◄──── emqx ◄──── ماژول‌های تی‌تی‌سویچ
 (HTTPS)     (API، داشبوردها،          (بروکر دستگاه‌ها)
              درایورها، هشدار،
              اتوماسیون)
                  │  شبکهٔ داخلی (بدون راه به بیرون)
                  ▼
                 db (PostgreSQL 17 + TimescaleDB)
```

| سرویس | کار | درگاه روی میزبان |
|---|---|---|
| `caddy` | HTTPS جلوی همه‌چیز | `80`، `443` |
| `hub` | API، داشبورد مهندسی `/`، وب‌اپ `/app/`، پنل سازنده `/maker/`، درایورهای صنعتی، درگاه TCP دستگاه‌ها | `7000` |
| `emqx` | بروکر MQTT دستگاه‌ها (فقط TLS) | `8883`؛ داشبورد EMQX فقط روی خود سیستم: `127.0.0.1:18083` |
| `db` | پایگاه داده | هیچ (فقط داخلی) |
| `emqx-init` | پیش از هر شروع EMQX، پیکربندی آن را با رمز hook و حساب hub از `.env` می‌نویسد و تمام می‌شود | — |

داده‌ها در volumeهای Docker می‌مانند و با خاموش و روشن شدن یا به‌روزرسانی پاک نمی‌شوند:
* `db-data`: پایگاه داده
* `hub-backups`: پشتیبان‌های شبانه
* `hub-spool`: پیام‌های در صف
* `emqx-data`: داده‌های بروکر
* `caddy-data`: گواهی‌ها

---

## ۲. پیش‌نیازها

* ویندوز ۱۰ (22H2) یا ۱۱ با WSL 2 و Ubuntu. روی همین سیستم Ubuntu 26.04 نصب و systemd روشن است.
* دست‌کم ۴ گیگ RAM آزاد برای WSL و ۲۰ گیگ دیسک.
* برای دسترسی از اینترنت: یک دامنه و باز بودن درگاه‌ها روی مودم یا فایروال. برای شبکهٔ محلی لازم نیست.

### ۲-۱. نصب Docker داخل WSL

در ترمینال Ubuntu (نه PowerShell):

```bash
sudo apt update
sudo apt install -y ca-certificates curl openssl git
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

یک بار از WSL بیرون بیایید (`exit`) و دوباره وارد شوید، بعد امتحان کنید:

```bash
docker run --rm hello-world
docker compose version
```

> اگر مخزن Docker برای نسخهٔ Ubuntu شما هنوز بستهٔ آماده ندارد، `sudo apt install -y docker.io docker-compose-v2` از مخزن خود Ubuntu هم کار می‌کند.
> راه دیگر Docker Desktop روی ویندوز است (با گزینهٔ WSL integration). یکی از این دو کافی است، نه هر دو.
> اگر دسترسی به `download.docker.com` یا Docker Hub از ایران بسته باشد، یک mirror برای Docker تنظیم کنید (`/etc/docker/daemon.json` → `registry-mirrors`).

### ۲-۲. شبکهٔ WSL: دیده شدن از شبکهٔ محلی (برای سخت‌افزار مهم است)

WSL به‌طور پیش‌فرض در حالت **NAT** است: یک IP داخلی جدا دارد (مثلاً `172.19.x.x`) و دستگاه‌های روی شبکهٔ محلی مستقیم به آن نمی‌رسند. یکی از دو راه زیر لازم است.

**راه پیشنهادی: حالت mirrored** (ویندوز ۱۱ 22H2 به بعد). WSL همان IP ویندوز را می‌گیرد.

فایل `C:\Users\<نام کاربر>\.wslconfig` را بسازید یا ویرایش کنید:

```ini
[wsl2]
networkingMode=mirrored
memory=6GB

[experimental]
hostAddressLoopback=true
```

بعد در PowerShell با دسترسی Administrator:

```powershell
wsl --shutdown
# اجازهٔ ورود به WSL از شبکه (فایروال Hyper-V)
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
# فایروال ویندوز: درگاه‌های سامانه
New-NetFirewallRule -DisplayName "TiTiSwitch web" -Direction Inbound -Protocol TCP -LocalPort 80,443 -Action Allow
New-NetFirewallRule -DisplayName "TiTiSwitch devices" -Direction Inbound -Protocol TCP -LocalPort 7000,8883 -Action Allow
```

> **فقط یکی از این دو راه را به کار ببرید.** اگر mirrored روشن است، قانون‌های `portproxy` راه دوم را حتماً پاک کنید. وگرنه همان درگاه‌ها را می‌گیرند و Docker خطای `address already in use` می‌دهد (پاک کردن در بخش ۸).

**راه دیگر: ماندن در NAT و فرستادن درگاه‌ها** (ویندوز ۱۰). IP داخلی WSL با هر بار روشن شدن عوض می‌شود، پس این دستورها باید پس از هر راه‌اندازی دوباره اجرا شوند (مثلاً با Task Scheduler). در PowerShell Administrator:

```powershell
$ip = (wsl -d Ubuntu hostname -I).Split(" ")[0]
foreach ($p in 80,443,7000,8883) {
  netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>$null
  netsh interface portproxy add v4tov4 listenport=$p listenaddress=0.0.0.0 connectport=$p connectaddress=$ip
}
New-NetFirewallRule -DisplayName "TiTiSwitch" -Direction Inbound -Protocol TCP -LocalPort 80,443,7000,8883 -Action Allow
```

IP ویندوز روی شبکهٔ محلی را با `ipconfig` پیدا کنید (مثلاً `192.168.1.20`). همین نشانی را در گام بعد به `setup.sh` می‌دهید. بهتر است در مودم برای این کامپیوتر IP ثابت (DHCP reservation) بگذارید.

### ۲-۳. اینترنت از راه proxy (مثلاً v2rayN)

اگر ویندوز از راه یک proxy محلی (مثلاً v2rayN روی `127.0.0.1:10808`) به اینترنت می‌رود، WSL در حالت NAT به آن دسترسی ندارد. هنگام ساخت image، نصب بسته‌های Python با خطای `Temporary failure in name resolution` متوقف می‌شود. راه حل:

1. حالت **mirrored** بخش ۲-۲ را روشن کنید. WSL خودش proxy ویندوز را می‌بیند و `127.0.0.1:10808` داخل WSL هم کار می‌کند.
2. در `deploy/.env` بنویسید:
   ```
   BUILD_PROXY=http://127.0.0.1:10808
   ```
   ساخت image بسته‌های Python را از این راه می‌گیرد. بسته‌های سیستمی (apt) مستقیم دانلود می‌شوند، چون بعضی proxyها (مثل xray) آن‌ها را خراب می‌کنند. برنامهٔ در حال اجرا به این proxy نیازی ندارد.
3. اگر دانلود image‌ها از Docker Hub هم کند یا بسته است، برای خود Docker هم proxy بگذارید:
   ```bash
   sudo mkdir -p /etc/systemd/system/docker.service.d
   printf '[Service]\nEnvironment="HTTP_PROXY=http://127.0.0.1:10808" "HTTPS_PROXY=http://127.0.0.1:10808" "NO_PROXY=localhost,127.0.0.1"\n' | sudo tee /etc/systemd/system/docker.service.d/proxy.conf
   sudo systemctl daemon-reload && sudo systemctl restart docker
   ```

### ۲-۴. روشن ماندن پس از راه‌اندازی دوبارهٔ ویندوز

کانتینرها `restart: unless-stopped` دارند و با روشن شدن Docker خودشان بالا می‌آیند. فقط باید خود WSL پس از روشن شدن ویندوز اجرا شود:

* Task Scheduler ← Create Task
  * Trigger: «At startup»
  * Action: `wsl.exe -d Ubuntu --exec /bin/sh -c "sleep infinity"`
  * گزینهٔ «Run whether user is logged on or not» را بزنید.

---

## ۳. نصب پروژه

پروژه را **داخل خود WSL** بگذارید (مثلاً `~/titiswitch`)، نه روی `/mnt/d/...`. روی دیسک ویندوز هم سرعت فایل‌ها کم است و هم دسترسی‌ها درست کار نمی‌کند.

```bash
cd ~
git clone https://github.com/cmuiran/iot-data-hub.git titiswitch
cd titiswitch
git checkout master
```

(اگر گیت‌هاب در دسترس نیست، پوشهٔ پروژه را از ویندوز کپی کنید: `cp -r "/mnt/d/Peyman Project/1405/Yaser Mahdiyan - IOT/14050729 opc" ~/titiswitch`)

### ۳-۱. رمزها و گواهی‌ها: یک بار

```bash
cd ~/titiswitch/deploy
./setup.sh 192.168.1.20                 # IP ویندوز روی شبکهٔ محلی
# یا چند نام با هم:   ./setup.sh 192.168.1.20 titiswitch.local
# یا روی سرور ابری با دامنه:   ./setup.sh hub.example.com
```

این اسکریپت سه کار می‌کند:
* **`deploy/.env`** را با رمزهای تصادفی و بلند می‌سازد. اگر از قبل باشد، دست نمی‌خورد.
* یک **مرجع گواهی (CA)** برای دستگاه‌ها در `deploy/ca/` می‌سازد:
  * `ca.crt` داخل Firmware قرار می‌گیرد و روی کامپیوترها و گوشی‌ها هم نصب می‌شود.
  * `ca.key` را بیرون از سرور، جای امن نگه دارید.
* **گواهی سرور** را برای همان نام‌ها و IPها در `deploy/certs/` می‌سازد. همین گواهی برای HTTPS، MQTT و TCP به کار می‌رود.

اگر نام دامنه بدهید، ایمیل می‌پرسد تا گواهی رایگان Let's Encrypt بگیرد. در آن حالت درگاه‌های ۸۰ و ۴۴۳ باید از اینترنت باز باشند.

بعد `deploy/.env` را باز کنید و در صورت نیاز این‌ها را پر کنید:
* SMTP: برای ایمیل‌های ثبت‌نام و فراموشی رمز
* پنل پیامک: `HUB_SMS_PROVIDER`
* `HUB_SIGNUP_ENABLED`: ثبت‌نام آزاد

### ۳-۲. ساخت و اجرا

```bash
cd ~/titiswitch/deploy
docker compose up -d --build            # بار اول چند دقیقه طول می‌کشد
docker compose ps                       # همه باید running یا healthy باشند
docker compose logs -f hub              # گزارش hub (با Ctrl+C بیرون بیایید)
```

### ۳-۳. اولین مدیر

```bash
docker compose exec hub hub-admin create-admin --username admin
```

رمزی که می‌پرسد را وارد کنید. با این حساب در داشبورد مهندسی (`https://<IP>/`):
1. سازمان سازنده را بسازید.
2. حساب پنل سازنده را تعریف کنید.
3. محصول‌ها و دستگاه‌ها را در پنل سازنده ثبت کنید.

### ۳-۴. اعتماد به گواهی (شبکهٔ محلی)

فایل `deploy/ca/ca.crt` را روی هر کامپیوتر یا گوشی که به سامانه وصل می‌شود نصب کنید تا مرورگر هشدار ندهد:
* **ویندوز:** دو بار کلیک روی فایل ← Install Certificate ← Local Machine ← «Trusted Root Certification Authorities»
* **اندروید:** تنظیمات ← امنیت ← نصب گواهی ← گواهی CA
* **آیفون:** فایل را باز کنید ← نصب پروفایل؛ بعد تنظیمات ← عمومی ← درباره ← Certificate Trust Settings ← روشن کنید

با دامنه و Let's Encrypt این کار لازم نیست.

### ۳-۵. نشانی‌ها

| بخش | نشانی |
|---|---|
| داشبورد مهندسی | `https://192.168.1.20/` |
| وب‌اپ مشتری (و اپ آیفون از راه «Add to Home Screen») | `https://192.168.1.20/app/` |
| پنل سازنده | `https://192.168.1.20/maker/` |
| اپ فلاتر و اپ اندروید | در صفحهٔ ورود ← «تغییر نشانی سرور» ← `https://192.168.1.20` |
| داشبورد EMQX (فقط روی همین کامپیوتر) | `http://127.0.0.1:18083`؛ رمزش `EMQX_DASHBOARD_PASSWORD` در `.env` |

---

### ۳-۶. شروع آزمون: حساب‌ها، اپ اندروید، ایمیل

**۱. حساب‌ها**

* مدیر سامانه (داشبورد مهندسی و ساخت سازنده): بخش ۳-۳.
* **مشتری بدون ایمیل** (برای آزمون، یا جایی که سرور ایمیل ندارد). حساب فوراً فعال است و خانهٔ خودش را دارد؛ رمز را خود دستور می‌پرسد:
  ```bash
  docker compose exec hub hub-admin create-customer --email ali@example.com --display-name "علی"
  ```
  با همین ایمیل و رمز در وب‌اپ یا اپ اندروید وارد شوید.
* **ثبت‌نام خود مشتری‌ها، فراموشی رمز و دعوت‌نامه** به ایمیل نیاز دارند. در `deploy/.env` بخش SMTP را پر کنید و `HUB_SIGNUP_ENABLED=true` بگذارید. بعد `docker compose up -d`. برای آزمون، در وب‌اپ «فراموشی رمز» را برای یک حساب مشتری بزنید: ایمیل باید برسد. اگر نرسید، `docker compose logs hub | grep -i mail` علت را نشان می‌دهد.
  با Gmail: «App password» بسازید و `HUB_SMTP_HOST=smtp.gmail.com`، `HUB_SMTP_PORT=587`، `HUB_SMTP_USERNAME=<ایمیل>`، `HUB_SMTP_PASSWORD=<App password>`.

**۲. سازنده و محصول.** شرکت سازنده و مدیر پنل سازنده را بسازید. این حساب هم فوراً فعال است و رمز را خود دستور می‌پرسد:
  ```bash
  docker compose exec hub hub-admin create-maker --org-id kish_smart --name "کیش هوشمند" --email maker@example.com --display-name "مدیر محصول"
  ```
  با همین ایمیل در `https://192.168.1.173/maker/` وارد شوید. در پنل سازنده (`/maker/`) محصول (مثلاً TiTiRelay8 با قالب `platform/product-template.json` مخزن Firmware) را تعریف کنید، دستگاه‌ها را ثبت کنید و خروجی CSV با رمزها بگیرید (بخش ۵-۱).

**۳. اپ اندروید**

* فایل `app-release.apk` را روی گوشی کپی کنید و باز کنید. اگر اندروید اجازه خواست، «نصب از منابع ناشناخته» را برای همان برنامه روشن کنید.
* در اولین اجرا، نشانی سرور را بزنید: `https://192.168.1.173`. گوشی باید روی همان شبکهٔ Wi-Fi باشد.
* چون گواهی سرور را CA خصوصی خود شما امضا کرده (نه یک مرجع عمومی)، اپ پنجرهٔ **«تأیید گواهی سرور»** را نشان می‌دهد. اثر انگشت SHA-256 آن را با خطی که `setup.sh` چاپ کرد مقایسه کنید. اگر آن خط را ندارید، در WSL بزنید:
  ```bash
  openssl x509 -in ~/titiswitch/deploy/certs/server.crt -noout -fingerprint -sha256
  ```
  اگر یکی بود «یکی است، اعتماد کن» را بزنید. اپ از آن به بعد فقط همین گواهی را برای همین سرور می‌پذیرد. با ساختن دوبارهٔ گواهی (`setup.sh`)، اپ دوباره می‌پرسد.
* APK فعلی با کلید آزمایشی (debug) امضا شده و برای آزمون کافی است. برای نسخهٔ نهایی، یک کلید امضای دائمی بسازید و آن را در GitHub ← Settings ← Secrets ← Actions با نام‌های `ANDROID_KEYSTORE_BASE64`، `ANDROID_KEYSTORE_PASSWORD`، `ANDROID_KEY_ALIAS` و `ANDROID_KEY_PASSWORD` بگذارید (`mobile/README.md`). نسخهٔ امضاشده با کلید دائمی روی نسخهٔ آزمایشی نصب نمی‌شود: یک بار اپ آزمایشی را پاک کنید. آن کلید را جای امن نگه دارید؛ بدون آن به‌روزرسانی اپ ممکن نیست.

## ۴. درگاه‌ها (Port)

| درگاه | پروتکل | چه کسی وصل می‌شود | باز روی |
|---|---|---|---|
| `443` | HTTPS | مرورگرها، اپ‌ها، دستگاه‌هایی که HTTP می‌زنند (`/ingest/v1/...`) | شبکه / اینترنت |
| `80` | HTTP | فقط برای گرفتن گواهی Let's Encrypt و فرستادن خودکار به HTTPS | شبکه / اینترنت |
| `8883` | MQTT روی TLS | ماژول‌های تی‌تی‌سویچ (پیشنهاد برای تعداد زیاد) | شبکه / اینترنت |
| `7000` | TCP روی TLS (JSON خط‌به‌خط) | ماژول‌های تی‌تی‌سویچ | شبکه / اینترنت |
| `18083` | HTTP | داشبورد EMQX | فقط `127.0.0.1` |
| `8000` | HTTP | خود hub؛ فقط Caddy به آن وصل می‌شود | بسته (داخلی) |
| `1883` | MQTT بدون TLS | فقط hub به EMQX | بسته (داخلی) |
| `5432` | PostgreSQL | فقط hub | بسته (داخلی) |

اگر خروجی‌های اختیاری را روشن کنید، درگاهشان را هم در `docker-compose.yml` زیر `hub` ← `ports` اضافه کنید:
* سرور OPC UA (`HUB_OPCUA_SERVER_PORT`، پیش‌فرض `4840`)
* سرور Modbus TCP (`config/modbus_server.yaml`)

---

## ۵. ارتباط با سخت‌افزار

### ۵-۱. ماژول‌های تی‌تی‌سویچ (دستگاه‌های native)

دستگاه خودش به سرور وصل می‌شود. سرور هیچ‌وقت سراغ دستگاه نمی‌رود، پس IP دستگاه مهم نیست و پشت مودم خانه هم کار می‌کند.

**در خط تولید (یک بار برای هر برد):**
1. پنل سازنده ← برچسب‌ها یا تولید ← خروجی CSV **با رمزها**.
2. روی یک کامپیوتر ویندوزی که برد با USB به آن وصل است:
   ```bash
   hub-provision --csv codes.csv --port COM5 --broker 192.168.1.173:8883 --api https://192.168.1.173 --repeat
   ```
   شناسه و رمز هر برد از راه کنسول سریال خود برد، در حافظهٔ امن آن نوشته می‌شود. جزئیات در `docs/fa/platform/firmware-checklist.md`.
3. برد باید `deploy/ca/ca.crt` را داشته باشد تا به گواهی سرور اعتماد کند. آن را در پورتال راه‌اندازی برد وارد کنید.

**یکی از سه راه اتصال دستگاه:**

| راه | نشانی | ورود |
|---|---|---|
| MQTT | `mqtts://<IP یا دامنه>:8883` | نام کاربری = `device_id`، رمز = `device_secret`. Topicها: `d/<device_id>/telemetry`، `state`، `ack`. فرمان‌ها روی `d/<device_id>/cmd` می‌آیند. |
| TCP | `<IP یا دامنه>:7000` با TLS | خط اول: `{"device_id": "…", "secret": "…"}`. بعد پیام‌های JSON، هر کدام در یک خط. |
| HTTP | `https://<IP یا دامنه>/ingest/v1/devices/<device_id>/telemetry` | سرآیند `Authorization: Bearer <device_secret>` |

شکل پیام‌ها (telemetry، state، command، ack) روی هر سه راه یکی است: `docs/platform.md` ← «Messages».

**مشتری:** QR روی دستگاه را در اپ اسکن می‌کند و دستگاه به خانه‌اش اضافه می‌شود.

**بدون اینترنت:** اپ روی Wi-Fi خانه مستقیم با ماژول حرف می‌زند (کنترل محلی، بدون سرور). اگر خانه هاب محلی دارد، سناریوها روی همان اجرا می‌شوند.

### ۵-۲. تجهیزات صنعتی (Modbus TCP، OPC UA، S7، SNMP، HTTP، MQTT دیگران)

این بار سرور سراغ دستگاه می‌رود. هر دستگاه یک فایل YAML در `deploy/config/devices/` دارد. ساده‌ترین راه، مهارت `add-device` در Claude Code یا قالب Excel است. بعد:

```bash
docker compose exec hub python -m hub.validate_config --config-dir /app/config
docker compose restart hub
```

* کانتینر hub از راه شبکهٔ WSL و ویندوز به IPهای شبکهٔ محلی (مثلاً PLC روی `192.168.10.50:502`) دسترسی دارد. لازم نیست درگاهی باز کنید.
* اگر دستگاه روی یک شبکهٔ صنعتی جداست، ویندوز باید به آن شبکه راه داشته باشد (کارت شبکهٔ دوم یا route).
* **بدون تأیید، هیچ نوشتنی روی دستگاه انجام نمی‌شود.** هر برچسب پیش‌فرض فقط‌خواندنی است. برای نوشتن، `access: read_write` با `min` و `max` روی آن برچسب لازم است، به‌اضافهٔ نقشی که اجازهٔ نوشتن دارد. `HUB_CONTROL_ENABLED=true` هم در `.env` باید باشد.

### ۵-۳. Modbus RTU با مبدل USB به سریال (RS-485)

WSL به‌طور پیش‌فرض USB را نمی‌بیند. با **usbipd-win** وصلش کنید.

در PowerShell Administrator (یک بار نصب):

```powershell
winget install --exact dorssel.usbipd-win
usbipd list                          # BUSID مبدل را پیدا کنید، مثلاً 2-3
usbipd bind --busid 2-3
usbipd attach --wsl --busid 2-3      # پس از هر بار وصل کردن USB یا روشن شدن ویندوز
```

در WSL باید `ls /dev/ttyUSB*` آن را نشان دهد. بعد در `deploy/docker-compose.yml` زیر `hub` خط‌های `devices:` را از حالت توضیح بیرون بیاورید و `docker compose up -d` را اجرا کنید. در فایل YAML دستگاه، پورت را `/dev/ttyUSB0` بگذارید.

### ۵-۴. ابزار خط تولید روی ویندوز

`hub-provision` به درگاه COM ویندوز نیاز دارد، پس آن را **روی خود ویندوز** اجرا کنید، نه داخل Docker. همان محیط Python پروژه کافی است:

```powershell
.venv\Scripts\python.exe -m hub.provision --csv codes.csv --port COM5 --broker 192.168.1.173:8883 --api https://192.168.1.173 --repeat
```

---

## ۶. کارهای روزمره

| کار | دستور (در `~/titiswitch/deploy`) |
|---|---|
| وضعیت | `docker compose ps` |
| گزارش‌ها | `docker compose logs -f hub` (یا `emqx`، `caddy`، `db`) |
| توقف / شروع | `docker compose stop` / `docker compose start` |
| به‌روزرسانی برنامه | `git pull && docker compose up -d --build` (migrationها خودکار اجرا می‌شوند) |
| پشتیبان دستی | `docker compose exec hub hub-admin backup` |
| برداشتن پشتیبان‌ها | `docker compose cp hub:/app/backups ./backups-copy` |
| بازیابی | `docker compose exec hub hub-admin restore-backup /app/backups/<file> --yes` |
| بازنشانی رمز کاربر | `docker compose exec hub hub-admin reset-password <نام>` |
| فهرست کاربران | `docker compose exec hub hub-admin list-users` |
| تمدید گواهی دستگاه‌ها (همان CA) | `./setup.sh <همان نام‌ها> && docker compose restart hub emqx caddy` |

* پشتیبان شبانه ساعت `HUB_BACKUP_TIME` (پیش‌فرض ۲:۳۰) گرفته و با `HUB_DATA_KEY` رمزگذاری می‌شود. **`deploy/.env` را جای امن نگه دارید.** بدون `HUB_DATA_KEY` پشتیبان‌ها باز نمی‌شوند.
* پشتیبان‌ها را مرتب به دیسک یا جای دیگری کپی کنید و هر چند وقت یک بار بازیابی را آزمایش کنید (`docs/fa/admin-guide.md`).
* **`docker compose down -v` همهٔ داده‌ها را پاک می‌کند.** برای توقف فقط `stop` یا `down` بدون `-v` را بزنید.

---

## ۷. فهرست امنیتی پیش از استفادهٔ واقعی

- [ ] `deploy/.env`، `deploy/ca/ca.key` و پشتیبان‌ها جای امن و بیرون از گیت باشند (`.gitignore` آن‌ها را کنار می‌گذارد).
- [ ] پایگاه داده و درگاه 8000 روی میزبان منتشر نشده باشند (همین‌طور است؛ تغییرش ندهید).
- [ ] MQTT بدون TLS (1883) فقط داخلی باشد (همین‌طور است).
- [ ] داشبورد EMQX فقط روی `127.0.0.1` باز باشد.
- [ ] برای مدیرها ورود دومرحله‌ای (MFA) روشن شود.
- [ ] `HUB_SIGNUP_ENABLED` فقط اگر واقعاً ثبت‌نام آزاد می‌خواهید روشن شود.
- [ ] روی اینترنت فقط ۴۴۳، ۸۰، ۸۸۸۳ و ۷۰۰۰ باز باشند.

---

## ۸. رفع اشکال

| نشانه | علت محتمل و راه |
|---|---|
| `failed to bind host port ... address already in use` | قانون‌های `portproxy` روش NAT با حالت mirrored تداخل دارند. در PowerShell Administrator: `foreach ($p in 80,443,7000,8883) { netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 }`، بعد `docker compose up -d`. اگر برنامهٔ دیگری درگاه را گرفته باشد: `Get-NetTCPConnection -LocalPort 443 -State Listen` |
| `Temporary failure in name resolution` هنگام ساخت | روی WSL: اینترنت ویندوز از راه proxy است و WSL به آن دسترسی ندارد (بخش ۲-۳). روی سرور لینوکس: DNS سرور `files.pythonhosted.org` را پیدا نمی‌کند (بخش ۸-۰) |
| `Input/output error` و `command not found` برای دستورهای ساده | دیسک مجازی WSL هنگام نوشتن آسیب دیده. در PowerShell: `wsl --shutdown`، بعد دوباره Ubuntu را باز کنید (سیستم فایل خودش تعمیر می‌شود). اگر بعدش دانلود image با `failed to stat parent` شکست خورد، بخش ۸-۱ |
| `setup.sh: bad interpreter` یا `^M` | فایل با پایان خط ویندوزی کپی شده؛ پروژه را داخل WSL با `git clone` بگیرید، یا `sed -i 's/\r$//' deploy/setup.sh` |
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER` و یک بار خروج و ورود دوباره به WSL |
| سایت از کامپیوتر دیگر باز نمی‌شود | حالت mirrored یا portproxy و فایروال ویندوز (بخش ۲-۲)؛ `docker compose ps` |
| مرورگر هشدار گواهی می‌دهد | `ca.crt` روی آن دستگاه نصب نشده (۳-۴)، یا نشانی با نام‌هایی که به `setup.sh` دادید یکی نیست |
| دستگاه به 8883 یا 7000 وصل نمی‌شود | ساعت دستگاه درست نیست (TLS به ساعت نیاز دارد)، `ca.crt` در Firmware نیست، یا درگاه در فایروال بسته است؛ `docker compose logs emqx hub` |
| hub بالا نمی‌آید | `docker compose logs hub`؛ معمولاً یک مقدار در `.env` یا خطا در YAML دستگاه‌ها: `docker compose run --rm hub python -m hub.validate_config --config-dir /app/config` |
| پس از روشن شدن ویندوز چیزی بالا نیست | WSL اجرا نشده (۲-۴). در NAT، IP عوض شده و portproxy باید دوباره اجرا شود |

### ۸-۰. ساخت image در `pip install` با `Temporary failure in name resolution` می‌ماند

اگر `Collecting ...` می‌آید ولی دانلود از `files.pythonhosted.org` شکست می‌خورد، یعنی خود سرور نمی‌تواند نام آن را پیدا کند. این را روی خود سرور (نه داخل Docker) امتحان کنید:

```bash
resolvectl query files.pythonhosted.org
dig +short files.pythonhosted.org @1.1.1.1
dig +short files.pythonhosted.org @8.8.8.8
```

یکی از سه راه را انتخاب کنید:

1. **درست کردن DNS سرور.** اگر یکی از `dig`های بالا جواب داد، همان DNS را برای سرور بگذارید. در `/etc/systemd/resolved.conf` بنویسید:
   ```
   [Resolve]
   DNS=1.1.1.1 8.8.8.8
   ```
   بعد `sudo systemctl restart systemd-resolved` را بزنید. اگر هیچ DNS خارجی جواب نداد (فیلتر)، یک DNS ضدتحریم یا DNS سرویس‌دهندهٔ سرور را بگذارید.
2. **proxy فقط برای ساخت.** اگر روی سرور یا شبکه proxy دارید، آن را در `deploy/.env` بنویسید:
   ```
   BUILD_PROXY=http://<آدرس proxy>:<درگاه>
   ```
3. **mirror بسته‌های Python.** بسیاری از سرویس‌دهنده‌های ابری داخل ایران mirror خود PyPI را دارند. نشانی «simple» آن را از راهنمای سرویس‌دهنده بگیرید و در `deploy/.env` بنویسید:
   ```
   BUILD_PIP_INDEX=https://<mirror>/simple
   BUILD_PIP_TRUSTED_HOST=<نام mirror>     # فقط اگر گواهی HTTPS آن معتبر نیست
   ```
   فقط از mirrorی استفاده کنید که به آن اعتماد دارید، چون بسته‌های برنامه از آن نصب می‌شوند. نسخهٔ هر بسته در `requirements.lock` ثابت است.

بعد از هر کدام، دوباره `docker compose up -d --build` را بزنید. این تنظیم‌ها فقط هنگام ساخت image به کار می‌روند و در image یا برنامهٔ در حال اجرا نمی‌مانند.

### ۸-۱. لایهٔ خراب image پس از خطای دیسک

اگر `docker pull` یا `docker compose up` بگوید `failed to stat parent: stat /var/lib/containerd/.../snapshots/<n>/fs: no such file or directory`، یکی از لایه‌های دانلودشده با خطای دیسک از بین رفته است. لایه‌ای که به آن پوشه اشاره می‌کند را پاک کنید. Docker همان لایه را دوباره دانلود می‌کند:

```bash
sudo ctr -n moby snapshots ls | grep -v Committed      # لایهٔ نیمه‌کاره و پدرش (ستون PARENT)
sudo ctr -n moby snapshots rm sha256:<شناسهٔ پدر>
docker compose up -d --build
```

اگر چند لایه خراب بود، راه سریع‌تر این است. همهٔ image‌ها دوباره دانلود می‌شوند؛ تا وقتی سامانه هنوز داده‌ای ندارد بی‌خطر است:

```bash
sudo systemctl stop docker containerd
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo systemctl start containerd docker
```

برای کم کردن احتمال تکرار، دیسک WSL را به درایوی با جای بیشتر ببرید (در PowerShell): `wsl --shutdown` و بعد `wsl --manage Ubuntu --move D:\WSL\Ubuntu`.

