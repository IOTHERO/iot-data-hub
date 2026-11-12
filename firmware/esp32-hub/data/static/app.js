"use strict";
/* TiTi Hub portal. DOM built with textContent/createElement only (no innerHTML on data). */
const T={fa:{
loginSub:"برای ورود به تنظیمات هاب، رمز مدیر را وارد کنید",adminPass:"رمز مدیر",signIn:"ورود",wrongPass:"رمز نادرست است",locked:"چند بار رمز اشتباه وارد شد؛ یک دقیقه صبر کنید",
dash:"داشبورد",mods:"ماژول‌ها",scenes:"سناریوها",conn:"ارتباط",gsmNav:"پیامک و ساعت",sys:"سیستم",restart:"راه‌اندازی مجدد",cfgSwitch:"کلید کانفیگ",on:"روشن",off:"خاموش",live:"زنده",offline:"قطع",
hub:"هاب مرکزی",links:"وضعیت ارتباط‌ها",ethernet:"شبکهٔ LAN (W5500)",wifi:"وای‌فای",serverLink:"سرور (OPC / پلتفرم)",gsmLink:"مودم GSM",rtcLink:"ساعت RTC",connected:"متصل",notConnected:"قطع",notSet:"تنظیم نشده",disabled:"غیرفعال",
modOnline:"ماژول‌های آنلاین",clock:"ساعت",uptime:"زمان کارکرد",heap:"حافظهٔ آزاد",rtcTemp:"دمای RTC",resetReason:"علت آخرین ریست",sceneCount:"سناریوها",enrollment:"ثبت ماژول جدید",open:"باز",closed:"بسته",
alarms:"هشدارها",ack:"تأیید همه",noAlarms:"هشدار فعالی نیست",
enrollSub:"ماژولی که شناسه و رمزش در فهرست نیست فقط وقتی ثبت می‌شود که این پنجره باز باشد.",enrollOpen:"باز کردن ثبت (۲ دقیقه)",enrollOpenNow:"ثبت باز است",
registry:"فهرست ماژول‌ها",registrySub:"ماژول‌ها با شناسه و رمز خودشان (همان که در ماژول ثبت شده) به این هاب وصل می‌شوند. نام کوتاه برای فرمان پیامکی است (مثلاً m1).",
modId:"شناسه (Device ID)",modSecret:"رمز دستگاه",name:"نام",alias:"نام کوتاه",modRtu:"آدرس RS-485 (اگر روی باس است)",addModule:"افزودن ماژول",save:"ذخیره",saved:"ذخیره شد",invalid:"مقدار نامعتبر: ",secretKeep:"•••••• (ذخیره شده)",remove:"حذف",
noModules:"هنوز ماژولی ثبت نشده است.",lastSeen:"آخرین پیام",secAgo:"ثانیه پیش",noValues:"داده‌ای نرسیده",
scenesSub:"روی خود هاب اجرا می‌شوند؛ با قطع اینترنت هم کار می‌کنند",sceneEditor:"ویرایش سناریوها (JSON)",sceneHelp:"هر سناریو: ماشه (time، interval، value، event، manual)، شرط اختیاری و فهرست اقدام. ساعت‌ها به وقت محلی هاب‌اند؛ روزها از ۰=شنبه.",
addTemplate:"افزودن نمونه",saveScenes:"ذخیرهٔ سناریوها",run:"اجرا",running:"در حال اجرا",enabled:"فعال",noScenes:"سناریویی تعریف نشده است.",
tTime:"زمانی",tInterval:"تکرارشونده",tValue:"بر اساس مقدار",tEvent:"رویداد",tManual:"دستی",
tplEveningOn:"روشن شدن چراغ در ساعت مشخص",tplNightOff:"خاموش کردن همه در ساعت مشخص",tplPulse:"تکرار: ۲۰ ثانیه روشن، ۴۰ ثانیه خاموش",tplOfflineSms:"پیامک وقتی ماژول قطع شد",tplCloudLost:"اقدام هنگام قطع اینترنت",tplAllOff:"دستی: خاموش‌کردن چند رله",
lan:"شبکهٔ LAN (W5500)",netMode:"اولویت شبکه",nm0:"اول LAN، وای‌فای پشتیبان",nm1:"اول وای‌فای",nm2:"فقط LAN",nm3:"فقط وای‌فای",dhcp:"دریافت خودکار IP (DHCP)",subnet:"Subnet",gateway:"گیت‌وی",hostname:"نام میزبان",
wifiNet:"شبکهٔ وای‌فای",scan:"جستجو",scanning:"در حال جستجو…",noNets:"شبکه‌ای پیدا نشد",ssid:"نام شبکه (SSID)",password:"رمز",backupNet:"شبکهٔ پشتیبان (اختیاری)",savedPass:"•••••• (ذخیره شده — برای تغییر بنویسید)",
server:"سرور (OPC / پلتفرم)",serverSub:"هاب خودش را با این شناسه به سرور معرفی می‌کند و پیام ماژول‌ها را می‌رساند. خالی یا غیرفعال: هاب تنها در شبکهٔ محلی کار می‌کند.",srvEnabled:"اتصال به سرور فعال",smsLang:"زبان پیامک هشدار",smsLangEn:"انگلیسی (۱۶۰ نویسه)",smsLangFa:"فارسی (۷۰ نویسه)",holidays:"تعطیلات اضافه (قمری و خاص؛ هر خط یک تاریخ شمسی)",holidaysHelp:"تعطیلات ثابت شمسی (نوروز، ۱۲ و ۱۳ فروردین، ۱۴ و ۱۵ خرداد، ۲۲ بهمن، ۲۹ اسفند) داخل هاب هست. تعطیلات قمری هر سال را اینجا یا از سرور وارد کنید. سناریو با «calendar.holidays» آن‌ها را رد یا فقط همان روزها را اجرا می‌کند.",tplWorkdays:"فقط روزهای کاری (بدون تعطیلات)، ماه‌های مهر تا اسفند",tls:"اتصال امن (TLS، گواهی همیشه بررسی می‌شود)",caPem:"گواهی CA اختصاصی (PEM، اختیاری؛ خالی = CAهای عمومی داخلی)",clearCa:"پاک کردن گواهی",hubId:"شناسهٔ هاب (Hub ID)",hubSecret:"رمز هاب",host:"آدرس سرور",port:"پورت",prefix:"پیشوند تاپیک",keepalive:"Keepalive (ثانیه)",lostAlarm:"هشدار قطع سرور بعد از (ثانیه، ۰ = بدون هشدار)",
modBroker:"سرور محلی ماژول‌ها",modBrokerSub:"ماژول‌ها «سرور» خود را روی آدرس این هاب و همین پورت تنظیم می‌کنند.",offlineS:"قطع‌شدن ماژول بعد از (ثانیه)",
phoneApi:"کنترل از گوشی (شبکهٔ محلی)",phoneApiSub:"اپ فلاتر با کلید امضا مستقیم به هاب وصل می‌شود؛ بدون اینترنت هم کار می‌کند.",localEnabled:"کنترل محلی فعال",showKeys:"نمایش کلیدها",newKey:"کلید تازهٔ گوشی",keyNote:"کلید گوشی و کلید پیامک را فقط در اپ مدیر وارد کنید.",
ntp:"سرور زمان (NTP)",utcOffset:"اختلاف از UTC (دقیقه؛ ایران ۲۱۰)",
gsm:"مودم GSM",gsmEnabled:"مودم فعال",simPin:"PIN سیم‌کارت (اگر دارد)",smsEnabled:"فرمان و هشدار با پیامک",smsHelp:"فرمان پیامکی امضا دارد و فقط از شماره‌های مجاز پذیرفته می‌شود: HUB شمارنده نام.تگ=مقدار امضا. پیامک هشدار انگلیسی کوتاه است.",
contacts:"شمارهٔ مجاز",contactsSub:"تا ۱۰ شماره. «فرمان» یعنی می‌تواند پیامک فرمان بفرستد؛ «هشدار» یعنی هشدار را می‌گیرد.",phone:"شماره",cmds:"فرمان",alarmsShort:"هشدار",addContact:"افزودن شماره",
time:"زمان هاب (محلی)",source:"منبع ساعت",rtc:"ساعت RTC",setFromDevice:"تنظیم از ساعت این دستگاه",clockHelp:"ساعت RTC باتری‌دار است و با قطع برق هم زمان را نگه می‌دارد. اگر اینترنت نباشد، اپ گوشی هنگام وصل شدن ساعت را تنظیم می‌کند.",srcNone:"نامعتبر",srcRtc:"RTC",srcNtp:"NTP",srcServer:"سرور",srcPhone:"گوشی",srcPortal:"دستی",rtcLost:"باتری یا زمان از دست رفته",rtcNone:"نصب نیست",
general:"عمومی",devName:"نام هاب",newAdmin:"رمز جدید مدیر (خالی = بدون تغییر)",apPass:"رمز وای‌فای پیکربندی (خالی = بدون تغییر)",logLevel:"سطح گزارش",lvE:"فقط خطا",lvW:"هشدار",lvI:"اطلاعات",lvD:"اشکال‌زدایی",
firmware:"به‌روزرسانی Firmware",otaSub:"فایل .bin را انتخاب کنید. پس از نصب هاب خودش ریست می‌شود. تنظیمات، فهرست ماژول‌ها و سناریوها می‌مانند.",upload:"نصب",otaFs:"فایل رابط کاربری (LittleFS) است، نه Firmware",backup:"پشتیبان",download:"دریافت فایل",restore:"بازگردانی",factory:"بازگشت به تنظیمات کارخانه",liveLog:"گزارش زنده",pause:"توقف",resume:"ادامه",clear:"پاک کردن",
unsaved:"تغییرات ذخیره نشده",discard:"لغو",
rsTitle:"راه‌اندازی مجدد",rsText:"هاب دوباره راه‌اندازی می‌شود. ماژول‌ها چند ثانیه بعد دوباره وصل می‌شوند. اگر کلید کانفیگ روشن بماند، دوباره وارد حالت پیکربندی می‌شود.",rsGo:"ریست کن",cancel:"انصراف",restarting:"در حال راه‌اندازی مجدد…",
facTitle:"بازگشت به تنظیمات کارخانه",facText:"همهٔ تنظیمات، فهرست ماژول‌ها و سناریوها پاک می‌شود. برای تأیید RESET را بنویسید.",
adminDef:"رمز مدیر هنوز پیش‌فرض است. در صفحهٔ سیستم آن را تغییر دهید.",cfgStill:"کلید کانفیگ روشن است. پس از پایان تنظیمات آن را خاموش و هاب را ریست کنید.",rtcWarn:"ساعت RTC زمان را از دست داده است (باتری CR2032؟). تا رسیدن زمان درست، سناریوهای زمانی اجرا نمی‌شوند.",
al_rtc_lost:"ساعت RTC زمان را از دست داده است",al_no_time:"ساعت معتبر نیست؛ سناریوهای زمانی اجرا نمی‌شوند",al_gsm_down:"مودم GSM در شبکه ثبت نیست",al_no_link:"هیچ ارتباط شبکه‌ای نیست",al_config_on:"کلید کانفیگ هنوز روشن است",al_default_pass:"رمز مدیر پیش‌فرض است",al_cloud_lost:"ارتباط با سرور قطع است (هاب محلی کار می‌کند)",
sent:"ارسال شد",failed:"ناموفق",ok:"موفق",uploading:"در حال ارسال…",done:"انجام شد؛ هاب ریست می‌شود",
d:"روز",h:"ساعت",m:"دقیقه",addedRow:"ردیف اضافه شد"},
en:{
loginSub:"Enter the admin password to configure the hub",adminPass:"Admin password",signIn:"Sign in",wrongPass:"Wrong password",locked:"Too many wrong passwords; wait a minute",
dash:"Dashboard",mods:"Modules",scenes:"Scenes",conn:"Connection",gsmNav:"SMS & clock",sys:"System",restart:"Restart",cfgSwitch:"Config switch",on:"ON",off:"OFF",live:"Live",offline:"Offline",
hub:"Central hub",links:"Link status",ethernet:"LAN (W5500)",wifi:"Wi-Fi",serverLink:"Server (OPC / platform)",gsmLink:"GSM modem",rtcLink:"RTC clock",connected:"Connected",notConnected:"Down",notSet:"Not set",disabled:"Disabled",
modOnline:"Modules online",clock:"Clock",uptime:"Uptime",heap:"Free memory",rtcTemp:"RTC temperature",resetReason:"Last reset",sceneCount:"Scenes",enrollment:"Enroll new module",open:"Open",closed:"Closed",
alarms:"Alarms",ack:"Acknowledge all",noAlarms:"No active alarms",
enrollSub:"A module whose id and secret are not in the list can register only while this window is open.",enrollOpen:"Open enrollment (2 min)",enrollOpenNow:"Enrollment is open",
registry:"Module list",registrySub:"Modules connect to this hub with their own device id and secret (the ones stored in the module). The short name is used in SMS commands (for example m1).",
modId:"Device ID",modSecret:"Device secret",name:"Name",alias:"Short name",modRtu:"RS-485 address (if on the bus)",addModule:"Add module",save:"Save",saved:"Saved",invalid:"Invalid value: ",secretKeep:"•••••• (saved)",remove:"Remove",
noModules:"No module registered yet.",lastSeen:"Last message",secAgo:"s ago",noValues:"No data yet",
scenesSub:"They run on the hub itself, so they keep working with no internet",sceneEditor:"Edit scenes (JSON)",sceneHelp:"A scene has a trigger (time, interval, value, event, manual), optional conditions and a list of actions. Times are the hub's local time; weekdays: 0 = Saturday.",
addTemplate:"Add example",saveScenes:"Save scenes",run:"Run",running:"Running",enabled:"Enabled",noScenes:"No scenes defined.",
tTime:"Time",tInterval:"Repeating",tValue:"On value",tEvent:"Event",tManual:"Manual",
tplEveningOn:"Light on at a set time",tplNightOff:"Everything off at a set time",tplPulse:"Repeat: 20 s on, 40 s off",tplOfflineSms:"SMS when a module goes offline",tplCloudLost:"Action when the internet is lost",tplAllOff:"Manual: switch several relays off",
lan:"LAN (W5500)",netMode:"Network priority",nm0:"LAN first, Wi-Fi backup",nm1:"Wi-Fi first",nm2:"LAN only",nm3:"Wi-Fi only",dhcp:"Automatic IP (DHCP)",subnet:"Subnet",gateway:"Gateway",hostname:"Host name",
wifiNet:"Wi-Fi network",scan:"Scan",scanning:"Scanning…",noNets:"No networks found",ssid:"Network (SSID)",password:"Password",backupNet:"Backup network (optional)",savedPass:"•••••• (saved — type to change)",
server:"Server (OPC / platform)",serverSub:"The hub introduces itself to the server with this id and carries the modules' messages. Off or empty: the hub works on the local network only.",srvEnabled:"Server link enabled",smsLang:"Alarm SMS language",smsLangEn:"English (160 characters)",smsLangFa:"Persian (70 characters)",holidays:"Extra holidays (lunar and special; one Jalali date per line)",holidaysHelp:"The fixed solar holidays (Nowruz, 12-13 Farvardin, 14-15 Khordad, 22 Bahman, 29 Esfand) are built in. Add each year's lunar holidays here or from the server. A scene with calendar.holidays skips them, or runs only on them.",tplWorkdays:"Working days only (no holidays), Mehr to Esfand",tls:"Secure link (TLS, the certificate is always checked)",caPem:"Private CA certificate (PEM, optional; empty = built-in public CAs)",clearCa:"Clear certificate",hubId:"Hub ID",hubSecret:"Hub secret",host:"Server address",port:"Port",prefix:"Topic prefix",keepalive:"Keepalive (s)",lostAlarm:"Alarm when the server is lost for (s, 0 = none)",
modBroker:"Local server for modules",modBrokerSub:"Modules set their \"server\" to this hub's address and this port.",offlineS:"Module offline after (s)",
phoneApi:"Phone control (local network)",phoneApiSub:"The Flutter app reaches the hub directly with a signed key; it works with no internet.",localEnabled:"Local control enabled",showKeys:"Show keys",newKey:"New phone key",keyNote:"Enter the phone key and SMS key only in the admin app.",
ntp:"Time server (NTP)",utcOffset:"Offset from UTC (minutes; Iran 210)",
gsm:"GSM modem",gsmEnabled:"Modem enabled",simPin:"SIM PIN (if any)",smsEnabled:"SMS commands and alarms",smsHelp:"SMS commands are signed and accepted only from allowed numbers: HUB counter name.tag=value signature. Alarm SMS are short English texts.",
contacts:"Allowed numbers",contactsSub:"Up to 10. \"Commands\": may send SMS commands. \"Alarms\": receives alarms.",phone:"Number",cmds:"Commands",alarmsShort:"Alarms",addContact:"Add number",
time:"Hub time (local)",source:"Clock source",rtc:"RTC clock",setFromDevice:"Set from this device's clock",clockHelp:"The RTC has a battery and keeps the time through a power cut. With no internet the phone app sets the clock when it connects.",srcNone:"Invalid",srcRtc:"RTC",srcNtp:"NTP",srcServer:"Server",srcPhone:"Phone",srcPortal:"Manual",rtcLost:"Battery or time lost",rtcNone:"Not fitted",
general:"General",devName:"Hub name",newAdmin:"New admin password (empty = keep)",apPass:"Config Wi-Fi password (empty = keep)",logLevel:"Log level",lvE:"Errors only",lvW:"Warnings",lvI:"Info",lvD:"Debug",
firmware:"Firmware update",otaSub:"Pick the .bin. The hub restarts after installing it. Settings, the module list and scenes stay.",upload:"Install",otaFs:"This is the web UI image (LittleFS), not firmware",backup:"Backup",download:"Download",restore:"Restore",factory:"Factory reset",liveLog:"Live log",pause:"Pause",resume:"Resume",clear:"Clear",
unsaved:"Unsaved changes",discard:"Discard",
rsTitle:"Restart",rsText:"The hub restarts. Modules reconnect a few seconds later. If the config switch stays ON the hub comes back in config mode.",rsGo:"Restart",cancel:"Cancel",restarting:"Restarting…",
facTitle:"Factory reset",facText:"All settings, the module list and scenes are erased. Type RESET to confirm.",
adminDef:"The admin password is still the default. Change it on the System page.",cfgStill:"The config switch is ON. When done, turn it OFF and restart.",rtcWarn:"The RTC lost its time (CR2032 battery?). Time scenes do not run until a correct time arrives.",
al_rtc_lost:"RTC lost its time",al_no_time:"No valid clock: time scenes will not run",al_gsm_down:"GSM modem not registered",al_no_link:"No network link",al_config_on:"Config switch is still ON",al_default_pass:"Admin password is the default",al_cloud_lost:"Server link lost (the hub keeps working locally)",
sent:"Sent",failed:"Failed",ok:"OK",uploading:"Uploading…",done:"Done; the hub restarts",
d:"d",h:"h",m:"min",addedRow:"Row added"}};
let lang=(()=>{try{return localStorage.getItem("lang")||"fa"}catch(e){return"fa"}})();
const t=k=>(T[lang]&&T[lang][k])||T.en[k]||k;
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const el=(tag,cls,txt)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e};
let token=(()=>{try{return sessionStorage.getItem("tk")||""}catch(e){return""}})();
let S=null,S0="",ST=null,page="dash",REG=[],regDirty=false,SC=[],logSeq=0,logPaused=false,pollT=0,polling=false,scenesLoaded=false;
const PAGES=[["dash","i-dash"],["mods","i-mod"],["scenes","i-play"],["conn","i-link"],["gsmNav","i-gsm"],["sys","i-sys"]];
const PAGEID={dash:"dash",mods:"mods",scenes:"scenes",conn:"conn",gsmNav:"gsm",sys:"sys"};

function toast(msg,kind){const d=el("div","toast "+(kind||""),msg);$("#toasts").appendChild(d);setTimeout(()=>d.remove(),3500)}
async function api(path,body,method){
  const o={method:method||(body!==undefined?"POST":"GET"),headers:{"X-Auth":token}};
  if(body!==undefined){o.headers["Content-Type"]="application/json";o.body=typeof body==="string"?body:JSON.stringify(body)}
  const r=await fetch(path,o);let j={};try{j=await r.json()}catch(e){}
  if(r.status===401&&path!=="/api/login"){logout();throw new Error("login")}
  if(!r.ok){const e=new Error(j.error||r.status);e.field=j.field;throw e}
  return j;
}
function applyLang(){
  document.documentElement.lang=lang;document.documentElement.dir=lang==="fa"?"rtl":"ltr";
  $$("[data-t]").forEach(e=>{e.textContent=t(e.dataset.t)});
  $$("[data-lang]").forEach(b=>b.textContent=lang==="fa"?"English":"فارسی");
  buildNav();$("#ptitle").textContent=t(page);
  buildTemplates();
  if(S){fill();buildContacts()}
  if(ST)render();
  buildReg();renderScenes();
}
/* ---------- login ---------- */
async function login(){
  $("#lerr").textContent="";
  try{const j=await api("/api/login",{password:$("#lpass").value});token=j.token;try{sessionStorage.setItem("tk",token)}catch(e){}start()}
  catch(e){$("#lerr").textContent=t(e.message==="locked"?"locked":"wrongPass")}
}
function logout(){token="";try{sessionStorage.removeItem("tk")}catch(e){}clearInterval(pollT);$("#app").classList.add("hide");$("#login").classList.remove("hide")}
async function start(){
  try{S=await api("/api/settings")}catch(e){return}
  S0=JSON.stringify(S);
  $("#login").classList.add("hide");$("#app").classList.remove("hide");
  applyLang();go(page);await poll();clearInterval(pollT);pollT=setInterval(poll,2000);
}
/* ---------- nav ---------- */
function buildNav(){
  for(const box of [$("#navs"),$("#dock")]){box.innerHTML="";
    for(const [id,ic] of PAGES){const b=el("button","nav");b.dataset.go=id;
      const s=document.createElementNS("http://www.w3.org/2000/svg","svg"),u=document.createElementNS("http://www.w3.org/2000/svg","use");u.setAttribute("href","#"+ic);s.appendChild(u);
      b.appendChild(s);b.appendChild(el("span",null,t(id)));b.onclick=()=>go(id);box.appendChild(b)}}
  $$(".nav").forEach(b=>b.classList.toggle("on",b.dataset.go===page));
}
function go(p){page=p;$$(".page").forEach(e=>e.classList.toggle("on",e.id==="p-"+PAGEID[p]));$$(".nav").forEach(b=>b.classList.toggle("on",b.dataset.go===p));$("#ptitle").textContent=t(p);window.scrollTo({top:0,behavior:"smooth"});
  if(p==="scenes"&&!scenesLoaded)loadScenes();if(p==="sys")pollLog()}
/* ---------- helpers ---------- */
const getP=(o,p)=>p.split(".").reduce((a,k)=>a==null?a:a[k],o);
function setP(o,p,v){const ks=p.split(".");let a=o;for(let i=0;i<ks.length-1;i++){if(a[ks[i]]==null)a[ks[i]]={};a=a[ks[i]]}a[ks[ks.length-1]]=v}
function dur(s){const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return(d?d+"d ":"")+(d||h?h+"h ":"")+m+"m"}
function clockText(utc,off){if(!utc)return"—";const d=new Date((utc+off*60)*1000);const p=n=>String(n).padStart(2,"0");return d.getUTCFullYear()+"-"+p(d.getUTCMonth()+1)+"-"+p(d.getUTCDate())+" "+p(d.getUTCHours())+":"+p(d.getUTCMinutes())+":"+p(d.getUTCSeconds())}
function fill(){
  $$("[data-k]").forEach(e=>{const v=getP(S,e.dataset.k);
    if(e.type==="checkbox")e.checked=!!v;else if(e.dataset.secret)e.value="";else e.value=v==null?"":v});
  $$("[data-secret]").forEach(e=>{e.placeholder=getP(S,e.dataset.secret)?t("savedPass"):""});
  const hl=$("#holidays");if(hl)hl.value=(S.holidays||[]).join("\n");
  dirty();
}
function dirty(){const d=JSON.stringify(S)!==S0;$("#savebar").classList.toggle("show",d)}
document.addEventListener("input",e=>{
  const x=e.target,k=x.dataset&&x.dataset.k;if(!k||!S)return;
  let v;if(x.type==="checkbox")v=x.checked;else if(x.type==="number"||"num" in x.dataset)v=x.value===""?0:Number(x.value);else v=x.value;
  setP(S,k,v);dirty();
});
document.addEventListener("change",e=>{if(e.target.dataset&&e.target.dataset.k)e.target.dispatchEvent(new Event("input",{bubbles:true}))});
async function saveAll(){
  try{await api("/api/settings",S);toast(t("saved"),"ok");S=await api("/api/settings");S0=JSON.stringify(S);fill();buildContacts()}
  catch(e){toast(t("invalid")+(e.field||e.message),"bad")}
}
/* ---------- polling and render ---------- */
async function poll(){
  if(polling)return;polling=true;
  try{ST=await api("/api/state");$("#livedot").className="dot ok";$("#livetx").textContent=t("live");render()}
  catch(e){$("#livedot").className="dot bad";$("#livetx").textContent=t("offline")}
  polling=false;if(page==="sys"&&!logPaused)pollLog();
}
function linkRow(name,ok,detail,state){const d=el("div","link"),dot=el("span","dot "+(state||(ok?"ok":"bad")));d.append(dot,el("b",null,name),el("span",null,detail||""));return d}
function render(){
  if(!ST)return;const h=ST.hub;
  $("#bname").textContent=S?S.deviceName:"TiTi Hub";$("#bfw").textContent="v"+h.fw;$("#fwv").textContent="v"+h.fw;
  $("#dname").textContent=S?S.deviceName:"TiTi Hub";
  $("#dmode").textContent=h.config_mode?t("cfgStill"):"";
  $("#dfw").textContent="FW "+h.fw;$("#daddr").textContent=h.addr||"—";$("#did").textContent=h.hub_id||"—";
  $("#cfgdot").className="dot "+(h.config_switch?"warn":"ok");$("#cfgtx").textContent=h.config_switch?t("on"):t("off");
  const lb=$("#linkbox");lb.innerHTML="";
  lb.appendChild(linkRow(t("ethernet"),h.eth_up,(ST.net.eth.ip||"")));
  lb.appendChild(linkRow(t("wifi"),h.wifi_up,h.wifi_up?ST.net.wifi.ssid+" "+ST.net.wifi.rssi+" dBm":"",h.wifi_up?"ok":"warn"));
  lb.appendChild(linkRow(t("serverLink"),h.cloud_up,h.cloud_enabled?"":t("notSet"),h.cloud_enabled?(h.cloud_up?"ok":"warn"):"warn"));
  lb.appendChild(linkRow(t("gsmLink"),h.gsm_up,h.gsm_enabled?(h.gsm_up?(h.gsm_operator||"")+" CSQ "+h.gsm_csq:""):t("disabled"),h.gsm_enabled?(h.gsm_up?"ok":"bad"):"warn"));
  lb.appendChild(linkRow(t("rtcLink"),h.rtc&&!h.rtc_lost,h.rtc?(h.rtc_lost?t("rtcLost"):""):t("rtcNone"),h.rtc?(h.rtc_lost?"bad":"ok"):"warn"));
  $("#smo").textContent=h.modules_online+" / "+h.modules;
  $("#stm").textContent=h.clock_valid?clockText(h.time,h.utc_offset_min):"—";
  $("#sup").textContent=dur(h.uptime_s);$("#shp").textContent=Math.round(h.heap/1024)+" KB";
  $("#srt").textContent=h.rtc&&h.rtc_temp===h.rtc_temp?h.rtc_temp.toFixed(1)+" °C":"—";$("#srr").textContent=h.reset;
  $("#ssc").textContent=ST.scenes.length;$("#sen").textContent=h.enroll_left?t("open")+" ("+h.enroll_left+" s)":t("closed");
  $("#enrollBtn").textContent=h.enroll_left?t("enrollOpenNow")+" ("+h.enroll_left+" s)":t("enrollOpen");
  const al=$("#alerts");al.innerHTML="";
  if(S&&S.system&&S.system.adminPassDefault){const a=el("div","alert warn",t("adminDef"));al.appendChild(a)}
  const L=$("#alarmList");L.innerHTML="";
  if(!ST.alarms.length)L.appendChild(el("p",null,t("noAlarms")));
  for(const a of ST.alarms){const key="al_"+a.code;const txt=T[lang][key]||(a.code.startsWith("module_")?(lang==="fa"?"ماژول قطع شد: ":"Module offline: ")+a.code.slice(7):a.text);
    L.appendChild(el("div","alert "+(a.acked?"info":"bad"),txt+"  ("+clockText(a.at,h.utc_offset_min)+")"))}
  $("#gsmState").textContent=h.gsm_enabled?(h.gsm_up?(h.gsm_operator||"")+" · CSQ "+h.gsm_csq:t("notConnected")):t("disabled");
  $("#ckTime").textContent=h.clock_valid?clockText(h.time,h.utc_offset_min):"—";
  $("#ckSrc").textContent=t({none:"srcNone",rtc:"srcRtc",ntp:"srcNtp",server:"srcServer",phone:"srcPhone",portal:"srcPortal"}[h.clock_source]||"srcNone");
  $("#ckRtc").textContent=h.rtc?(h.rtc_lost?t("rtcLost"):(h.rtc_temp===h.rtc_temp?h.rtc_temp.toFixed(1)+" °C":"OK")):t("rtcNone");
  renderModules();renderScenes();
}
function renderModules(){
  const box=$("#modList");box.innerHTML="";
  if(!ST.modules.length){box.appendChild(el("p",null,t("noModules")))}
  for(const m of ST.modules){
    const c=el("div","mod"+(m.online?" on":""));const hd=el("div","hd");
    hd.append(el("span","dot "+(m.online?"ok":"bad")),el("b",null,m.name||m.id),el("small",null,(m.alias?m.alias+" · ":"")+m.id));
    if(m.addr)hd.appendChild(el("span","chip",m.addr));if(m.fw)hd.appendChild(el("span","chip","FW "+m.fw));
    hd.appendChild(el("span","chip",m.age_s>=0?m.age_s+" "+t("secAgo"):"—"));c.appendChild(hd);
    const v=el("div","vals");const tags=Object.keys(m.values||{});
    if(!tags.length)v.appendChild(el("span","vchip",t("noValues")));
    for(const tag of tags){const val=m.values[tag];
      if(/^relay_\d+$/.test(tag)){const b=el("button","rbtn"+(val?" on":""),tag.replace("relay_","K")+" "+(val?"ON":"OFF"));b.disabled=!m.online;
        b.onclick=async()=>{try{await api("/api/command",{target:m.id+":"+tag,value:!val});toast(t("sent"),"ok")}catch(e){toast(t("failed")+": "+e.message,"bad")}};v.appendChild(b)}
      else{const ch=el("span","vchip",tag);ch.appendChild(el("b",null,String(val)));v.appendChild(ch)}}
    c.appendChild(v);box.appendChild(c)}
  if(!regDirty){REG=ST.modules.map(m=>({id:m.id,name:m.name,alias:m.alias,rtu:m.rtu||"",secret:"",secretSet:m.secretSet,isNew:false}));buildReg()}
}
/* ---------- module registry ---------- */
function buildReg(){
  const b=$("#regBody");if(!b)return;b.innerHTML="";
  REG.forEach((r,i)=>{const tr=el("tr");
    const mk=(key,ltr,ph,type)=>{const td=el("td"),i2=el("input","in"+(ltr?" ltr":""));i2.value=r[key]||"";if(ph)i2.placeholder=ph;if(type)i2.type=type;
      i2.disabled=key==="id"&&!r.isNew;i2.oninput=()=>{r[key]=i2.value;regDirty=true};td.appendChild(i2);return td};
    tr.append(mk("id",true),mk("secret",true,r.secretSet?t("secretKeep"):"","password"),mk("name"),mk("alias",true),mk("rtu",true,"—","number"));
    const td=el("td"),del=el("button","btn sm red",t("remove"));del.onclick=()=>{REG.splice(i,1);regDirty=true;buildReg()};td.appendChild(del);tr.appendChild(td);b.appendChild(tr)});
}
async function saveReg(){
  const out=REG.map(r=>{const o={id:r.id.trim(),name:r.name||"",alias:r.alias||""};if(r.secret)o.secret=r.secret;if(+r.rtu>0)o.rtu=+r.rtu;return o});
  try{await api("/api/modules",out);regDirty=false;toast(t("saved"),"ok");await poll()}catch(e){toast(t("invalid")+(e.field||e.message),"bad")}
}
/* ---------- scenes ---------- */
const TPL={
tplEveningOn:{id:"evening",name:"Evening on",enabled:true,trigger:{type:"time",at:"18:30"},actions:[{type:"write",device:"m1",tag:"relay_1",value:true}]},
tplNightOff:{id:"night_off",name:"Night off",enabled:true,trigger:{type:"time",at:"23:30",weekdays:[0,1,2,3,4,5,6]},actions:[{type:"write",device:"m1",tag:"relay_1",value:false},{type:"write",device:"m1",tag:"relay_2",value:false}]},
tplPulse:{id:"blink",name:"20 s on, 40 s off",enabled:true,trigger:{type:"interval",every_s:60},actions:[{type:"write",device:"m1",tag:"relay_3",value:true},{type:"delay",s:20},{type:"write",device:"m1",tag:"relay_3",value:false}]},
tplOfflineSms:{id:"mod_lost",name:"Module offline",enabled:true,trigger:{type:"event",event:"module_offline"},actions:[{type:"sms",text:"Module offline"}]},
tplCloudLost:{id:"net_lost",name:"Internet lost",enabled:true,trigger:{type:"event",event:"cloud_lost"},actions:[{type:"alarm",text:"Internet lost"}]},
tplWorkdays:{id:"workdays",name:"Workdays 07:00",enabled:true,trigger:{type:"time",at:"07:00",weekdays:[0,1,2,3,4]},calendar:{months:[7,8,9,10,11,12],holidays:"skip"},actions:[{type:"write",device:"m1",tag:"relay_1",value:true}]},
tplAllOff:{id:"all_off",name:"All off",enabled:true,trigger:{type:"manual"},actions:[{type:"write",device:"m1",tag:"relay_1",value:false},{type:"write",device:"m1",tag:"relay_2",value:false},{type:"write",device:"m1",tag:"relay_3",value:false},{type:"write",device:"m1",tag:"relay_4",value:false}]}};
function buildTemplates(){const s=$("#tplSel");if(!s)return;s.innerHTML="";for(const k of Object.keys(TPL)){const o=el("option",null,t(k));o.value=k;s.appendChild(o)}}
async function loadScenes(){try{SC=await api("/api/scenes");scenesLoaded=true;$("#sceneJson").value=JSON.stringify(SC,null,1);renderScenes()}catch(e){}}
function renderScenes(){
  const box=$("#sceneList");if(!box)return;box.innerHTML="";
  if(!SC.length)box.appendChild(el("p",null,t("noScenes")));
  const live=ST?ST.scenes:[];
  SC.forEach((s,i)=>{const running=live.some(x=>x.id===s.id&&x.running);const d=el("div","sc"+(running?" run":""));
    const nm=el("b",null,s.name||s.id);nm.appendChild(el("small",null,t({time:"tTime",interval:"tInterval",value:"tValue",event:"tEvent",manual:"tManual"}[s.trigger&&s.trigger.type]||"tManual")+(s.trigger&&s.trigger.at?" · "+s.trigger.at:"")));
    const tg=el("label","tg"),cb=el("input");cb.type="checkbox";cb.checked=s.enabled!==false;tg.append(cb,el("i"));
    cb.onchange=async()=>{s.enabled=cb.checked;try{await api("/api/scenes",SC);$("#sceneJson").value=JSON.stringify(SC,null,1);toast(t("saved"),"ok")}catch(e){toast(t("invalid")+e.message,"bad")}};
    const run=el("button","btn sm",running?t("running"):t("run"));run.onclick=async()=>{try{await api("/api/scene/run",{id:s.id});toast(t("sent"),"ok")}catch(e){toast(t("failed")+": "+e.message,"bad")}};
    d.append(nm,tg,run);box.appendChild(d)});
}
async function saveScenes(){
  let j;try{j=JSON.parse($("#sceneJson").value||"[]")}catch(e){$("#sceneMsg").textContent="JSON: "+e.message;return}
  try{await api("/api/scenes",j);SC=j;$("#sceneMsg").textContent=t("saved");toast(t("saved"),"ok");renderScenes()}catch(e){$("#sceneMsg").textContent=t("invalid")+e.message}
}
/* ---------- contacts ---------- */
function buildContacts(){
  const b=$("#ctBody");if(!b||!S)return;b.innerHTML="";const list=S.gsm.contacts||(S.gsm.contacts=[]);
  list.forEach((c,i)=>{const tr=el("tr");
    const txt=(key,ltr)=>{const td=el("td"),x=el("input","in"+(ltr?" ltr":""));x.value=c[key]||"";x.oninput=()=>{c[key]=x.value;dirty()};td.appendChild(x);return td};
    const chk=key=>{const td=el("td"),x=el("input");x.type="checkbox";x.checked=!!c[key];x.onchange=()=>{c[key]=x.checked;dirty()};td.appendChild(x);return td};
    tr.append(txt("name"),txt("number",true),chk("commands"),chk("alarms"));
    const td=el("td"),del=el("button","btn sm red",t("remove"));del.onclick=()=>{list.splice(i,1);buildContacts();dirty()};td.appendChild(del);tr.appendChild(td);b.appendChild(tr)});
}
/* ---------- wifi scan ---------- */
async function scan(){
  const box=$("#nets");box.innerHTML="";box.appendChild(el("span","spin"));
  try{await api("/api/wifi/scan",{});for(let i=0;i<12;i++){await new Promise(r=>setTimeout(r,1000));const j=await api("/api/wifi/scan");if(!j.busy){box.innerHTML="";
    if(!j.nets.length)box.appendChild(el("p",null,t("noNets")));
    for(const n of j.nets){const d=el("div","net");d.append(el("b",null,n.ssid),el("span",null,n.rssi+" dBm"));d.onclick=()=>{S.net.wifiSsid=n.ssid;fill();dirty()};box.appendChild(d)}return}}}catch(e){}
  box.innerHTML=""}
/* ---------- log, ota, backup ---------- */
async function pollLog(){
  if(logPaused)return;try{const j=await api("/api/log?seq="+logSeq);logSeq=j.seq;const L=$("#log");
    j.lines.split("\n").filter(Boolean).forEach(x=>{const d=el("div",null,x);L.appendChild(d)});while(L.childNodes.length>200)L.removeChild(L.firstChild);L.scrollTop=L.scrollHeight}catch(e){}
}
function modal(title,text,okLabel,onOk,input){
  const m=$("#modal");m.innerHTML="";const w=el("div","modal"),b=el("div","box");b.append(el("h3",null,title),el("p",null,text));
  let inp=null;if(input){inp=el("input","in ltr");b.appendChild(inp)}
  const bar=el("div","bar");bar.style.marginTop="16px";const ok=el("button","btn pri",okLabel),no=el("button","btn",t("cancel"));
  no.onclick=()=>{m.innerHTML=""};ok.onclick=()=>{m.innerHTML="";onOk(inp?inp.value:"")};bar.append(ok,no);b.appendChild(bar);w.appendChild(b);m.appendChild(w)}
async function restart(){
  try{await api("/api/restart",{})}catch(e){}toast(t("restarting"));clearInterval(pollT);
  const wait=async()=>{try{const r=await fetch("/api/state");if(r.status===401||r.ok){location.reload();return}}catch(e){}setTimeout(wait,2000)};setTimeout(wait,4000)}
function uploadOta(){
  const f=$("#otaFile").files[0];if(!f)return;const fs=$("#otaFs").checked;
  const x=new XMLHttpRequest();x.open("POST","/api/ota?fs="+(fs?1:0));x.setRequestHeader("X-Auth",token);
  x.upload.onprogress=e=>{if(e.lengthComputable){$("#otaBar").style.width=Math.round(e.loaded/e.total*100)+"%"}};
  x.onload=()=>{let j={};try{j=JSON.parse(x.responseText)}catch(e){}$("#otaTx").textContent=x.status===200?t("done"):t("failed")+": "+(j.error||x.status);if(x.status===200)setTimeout(()=>location.reload(),9000)};
  x.onerror=()=>{$("#otaTx").textContent=t("failed")};$("#otaTx").textContent=t("uploading");
  const fd=new FormData();fd.append("file",f,f.name);x.send(fd)}
async function backup(){
  const r=await fetch("/api/backup",{headers:{"X-Auth":token}});const b=await r.blob();const a=el("a");a.href=URL.createObjectURL(b);a.download="titi-hub-backup.json";a.click();URL.revokeObjectURL(a.href)}
async function restoreFile(file){
  try{const txt=await file.text();await api("/api/restore",txt);toast(t("saved"),"ok");S=await api("/api/settings");S0=JSON.stringify(S);fill();buildContacts();scenesLoaded=false;regDirty=false;await poll()}
  catch(e){toast(t("invalid")+(e.field||e.message),"bad")}}
async function showKeys(){
  try{const k=await api("/api/keys");const b=$("#keyBox");b.innerHTML="";b.classList.remove("hide");
    for(const [lbl,val] of [["Hub ID",k.hub_id],["Phone key",k.local],["SMS key",k.sms]]){b.appendChild(el("div",null,lbl+": "+val))}
    b.appendChild(el("div",null,t("keyNote")))}catch(e){toast(t("failed")+": "+e.message,"bad")}}
async function newKey(){
  try{await api("/api/settings",{local:{newKey:true}});S=await api("/api/settings");S0=JSON.stringify(S);toast(t("saved"),"ok");showKeys()}catch(e){toast(t("failed"),"bad")}}
/* ---------- wiring ---------- */
document.addEventListener("click",e=>{
  const eye=e.target.closest("[data-eye]");if(eye){const i=document.getElementById(eye.dataset.eye);i.type=i.type==="password"?"text":"password"}
  if(e.target.closest("[data-lang]")){lang=lang==="fa"?"en":"fa";try{localStorage.setItem("lang",lang)}catch(x){}applyLang()}
  if(e.target.closest("[data-restart]"))modal(t("rsTitle"),t("rsText"),t("rsGo"),restart);
});
$("#lbtn").onclick=login;$("#lpass").addEventListener("keydown",e=>{if(e.key==="Enter")login()});
$("#save").onclick=saveAll;$("#discard").onclick=()=>{S=JSON.parse(S0);fill();buildContacts()};
$("#enrollBtn").onclick=async()=>{try{await api("/api/enroll",{});await poll()}catch(e){}};
$("#ackBtn").onclick=async()=>{try{await api("/api/alarms/ack",{});await poll()}catch(e){}};
$("#regAdd").onclick=()=>{REG.push({id:"",name:"",alias:"",rtu:"",secret:"",secretSet:false,isNew:true});regDirty=true;buildReg()};
$("#regSave").onclick=saveReg;
$("#tplAdd").onclick=()=>{let j=[];try{j=JSON.parse($("#sceneJson").value||"[]")}catch(e){}const k=$("#tplSel").value,tp=JSON.parse(JSON.stringify(TPL[k]));let n=1,id=tp.id;while(j.some(x=>x.id===id))id=tp.id+(++n);tp.id=id;j.push(tp);$("#sceneJson").value=JSON.stringify(j,null,1)};
$("#sceneSave").onclick=saveScenes;
$("#ctAdd").onclick=()=>{if(!S.gsm.contacts)S.gsm.contacts=[];if(S.gsm.contacts.length>=10)return;S.gsm.contacts.push({name:"",number:"",commands:true,alarms:true});buildContacts();dirty()};
$("#caClear").onclick=()=>{S.cloud.clearCa=true;S.cloud.ca="";dirty();toast(t("unsaved"))};
$("#holidays").addEventListener("input",e=>{S.holidays=e.target.value.split("\n").map(x=>x.trim()).filter(Boolean);dirty()});
$("#scanBtn").onclick=scan;$("#keyShow").onclick=showKeys;$("#keyNew").onclick=newKey;
$("#setTime").onclick=async()=>{try{await api("/api/time",{utc:Math.floor(Date.now()/1000)});toast(t("saved"),"ok");await poll()}catch(e){toast(t("failed"),"bad")}};
$("#otaBtn").onclick=uploadOta;$("#bkBtn").onclick=backup;$("#rsFile").onchange=e=>{if(e.target.files[0])restoreFile(e.target.files[0])};
$("#facBtn").onclick=()=>modal(t("facTitle"),t("facText"),t("factory"),async v=>{try{await api("/api/factory",{confirm:v});toast(t("restarting"));setTimeout(()=>location.reload(),6000)}catch(e){toast(t("failed"),"bad")}},true);
$("#logPause").onclick=e=>{logPaused=!logPaused;e.target.textContent=t(logPaused?"resume":"pause")};$("#logClear").onclick=()=>{$("#log").innerHTML=""};
buildNav();applyLang();
if(token){start()}
