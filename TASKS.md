# TASKS.md — Wavely Music Bot + PWA (استخراج کامل از r-prompt-wavely.md)

**تعداد کل بخش‌ها: ۹۰ | تعداد کل تست‌ها: ۴۴۷ | تعداد کل چک‌لیست‌ها: ۷۲**

- بخش‌ها = S01..S74 (۷۴) + R01..R16 (۱۶) = ۹۰
- تست‌ها = همه شناسه‌های T-… در فایل = ۴۴۷ (S34/S35/S64/S74 بدون شناسه T-؛ S34 فقط چک‌لیست ۸ شرط دارد)
- چک‌لیست‌ها = D6 (۱۱ ردیف) + D7 (۱۸ آیتم) + D8 (۱۱ آیتم) + D9 (۱۳ آیتم) + QA بند ۹ (۸ آیتم) + Critical Items (۵) + چک‌لیست نهایی دیپلوی (۶) = ۷۲
- نکته فایل: Self-Audit ادعای «۲۵۰+ تست» دارد؛ شمارش دقیق شناسه‌های T- = ۴۴۷ (سازگار: ۴۴۷ ≥ ۲۵۰)

قواعد اجرا: توکن‌های فایل = `<REDACTED>` — فقط از `.env` خوانده می‌شوند. هیچ رمز/توکن/کلیدی در کد، لاگ، تست یا git نیست. قبل از هر commit اسکن secrets انجام می‌شود (gitleaks در sandbox نصب نیست → اسکن regex دستی معادل + ثبت در گزارش).

وضعیت‌ها: ⏳ انجام‌نشده | ✅ انجام‌شده با تست pass | ❌ BLOCKED (دلیل دقیق)

---

## بخش الف — همه‌ی شناسه‌های بخش

S01 — هدف و محدوده MVP — بات تلگرام Serverless + مینی‌اپ/PWA فقط آنلاین، بدون بخش مالی، AI DJ فعال، فلگ‌های AI خاموش — src/lib/wavely/bot/flags.ts + src/lib/wavely/server/bot-config.ts — ✅ — T-S01-1..5
S02 — دسترسی‌ها و توکن‌ها — تفکیک CLI/BOT توکن در env جدا، هرگز در کد/لاگ/API/ریپو — src/lib/wavely/server/env.ts — ✅ — T-S02-1..4
S03 — احراز هویت ترکیبی — initData HMAC-SHA-256 + OAuth PKCE + Google + ایمیل/رمز + 2FA الزامی + JWT در کوکی httpOnly + جدول sessions + لینک چند حساب — src/lib/wavely/server/auth.ts — ⏳ — T-S03-1..5
S04 — قابلیت‌های گروه و اجتماعی — Voice Chat dual client + ۸ دکمه + اکولایزر زنده بدون قطع + Listening Party sync<100ms + PIN ۶رقمی یک‌بارمصرف + پلی‌لیست مشترک/کلون — src/lib/wavely/bot/voice-chat.ts — ✅ — T-S04-1..5
S05 — لیریکس همگام — LRCLIB syncedLyrics + کارائوکه مینی‌اپ + ویرایش خط‌به‌خط پیام Lyrics در چت — src/app/api/lyrics/route.ts — ⏳ — T-S05-1..4
S06 — کنترل مینی‌اپ از چت — endpoints player/control,player/state,queue/next,queue/add + sync دوطرفه <1s + دکمه‌های Play/Pause/Seek/Next/Previous/Shuffle/Loop — src/app/api/player/control/route.ts — ⏳ — T-S06-1..3
S07 — AI DJ — /dj، /dj_play، /dj_stop فقط is_mixed=true + endpoint getMixedPlaylists + شخصی‌سازی پشت فلگ خاموش — src/lib/wavely/bot/ai-dj.ts — ✅ — T-S07-1..3
S08 — قابلیت‌های غیرفعال — ai_search_enabled/audio_recognition_enabled/ai_dj_personalization_enabled=false، بدون listener بدون فلگ، فعال‌سازی فقط /admin — src/lib/wavely/bot/flags.ts — ✅ — T-S08-1..3
S09 — دستورات ربات — عمومی (/start,/help,/contact,/dmca,/privacy,/me,/lang,/settings) + گروه ۸تایی + اجتماعی + DJ + /admin فقط مالک — src/lib/wavely/bot/commands.ts — ✅ — T-S09-1..5
S10 — جریان /start و مدیریت زبان — ۵ زبان (English/فارسی/Русский/العربية/Türkçe)، ذخیره users.language، اعمال فوری در ربات و مینی‌اپ — src/lib/wavely/bot/commands.ts — ✅ — T-S10-1..3
S11 — Inline Mode — placeholder «Search music...» + InlineQueryResultAudio/Photo با کپشن کامل + ۴ دکمه + حداکثر ۵۰ نتیجه + cache_time 300s + next_offset — src/lib/wavely/bot/inline.ts — ✅ — T-S11-1..3
S12 — زیرساخت فنی — BotQueue دسته‌ای (25/1000ms) + backoff نمایی تا 60s روی 429 + Promise.allSettled + تراکنش اتمیک + کش جستجو 300s و لیریکس per-track — src/lib/wavely/bot/queue.ts — ✅ — T-S12-1..5
S13 — لایه منابع آنلاین — Jamendo/FMA/archive.org + providers با base interface (search,getTrack,getArtist,getAlbum) + انتخاب با bot_config.active_music_provider — src/lib/wavely/providers/index.ts — ✅ — T-S13-1..4
S14 — اجبار عضویت کانال — lib/forceJoin با enabled پیش‌فرض false، بررسی قبل از هر دستور، تنظیم از /admin — src/lib/wavely/bot/force-join.ts — ✅ — T-S14-1..2
S15 — ساختار دیتابیس — ۹ جدول users/sessions/user_settings/downloads/rooms/room_listeners/playlists(+is_mixed DEFAULT false,mix_config)/playlist_tracks/bot_config — prisma/schema.prisma — ✅ — T-S15-1..2
S16 — استقرار — npm create @tgcloud/bot + tgcloud login/push/migrate + BOT_TOKEN env — scripts/deploy-tgcloud.sh — ⏳ — T-S16-1
S17 — هدف بخش اکانت — هویت کاربر/امنیت نشست/کش/پروفایل کامل، پایدار و امن — src/lib/wavely/server/* (پوشه) — ⏳ — T-S17-1
S18 — حساب کاربری و ورود — ثبت+تأیید ایمیل+بازیابی، Argon2id/bcrypt cost≥12، 2FA TOTP+کد بازیابی، اجبار 2FA عمل حساس، قفل موقت+لاگ، پیام مبهم، remember-me قابل ابطال — src/lib/wavely/server/auth.ts — ⏳ — T-S18-1..9
S19 — پروفایل کاربر — نمایش/ویرایش نام/نام‌نمایشی/آواتار/ایمیل/زبان/تم، حقیقت سرور، رفع باگ رفرش (اتمیک+invalidate+بازخوانی+بدون کش کلاینت)، وضعیت امنیتی، خروج همه دستگاه‌ها — src/app/api/profile/route.ts — ✅ — T-S19-1..5
S20 — مدیریت نشست و کوکی — لیست/ابطال نشست (دستگاه/مرورگر/IP/آخرین فعالیت)، کوکی HttpOnly/Secure/SameSite، refresh چرخشی، CSRF، rate limit، لاگ خروج، ابطال با تغییر رمز، بدون localStorage حساس — src/lib/wavely/server/sessions.ts — ⏳ — T-S20-1..6
S21 — کش و تنظیمات — ۴ namespace جدا (پروفایل/تنظیمات/کتابخانه/سرچ)، کش فقط در تنظیمات نه Explore، ۴ گزینه (پاک‌کردن/حجم/خودکار/پاک‌کردن داده محلی)، TTL+invalidate فوری، کش آفلاین جدا از metadata — src/lib/wavely/server/cache.ts — ✅ — T-S21-1..5
S22 — ایجنت هوش مصنوعی — دسترسی فقط موسیقی کاربر، ممنوع فایل/کد/سیستم/تنظیمات حساس، رد مؤدبانه غیرموسیقی، policy layer+allowlist+system prompt+output filter، ابزارهای فقط‌خواندنی — src/lib/wavely/server/agent-policy.ts — ⏳ — T-S22-1..5
S23 — آهنگ واقعی و تست پخش — seed آهنگ واقعی لوکال+استریم، پخش واقعی play/pause/seek/next/prev+مدت+بافر+خطا، پذیرش پیدا/پخش/پایداری پس از رفرش، مجوزدار — src/lib/wavely/data.ts — ⏳ — T-S23-1..3
S24 — امنیت اکانت و مدیریت اکانت — تغییر ایمیل/رمز با تأیید+2FA، حذف با re-auth+grace، export داده، audit log، ضد enumeration/brute force/session fixation/XSS/CSRF/open redirect، rate limit حساس، بدون رمز/توکن در کلاینت/لاگ — src/lib/wavely/server/account.ts — ⏳ — T-S24-1..5
S25 — وب‌اپ تلگرام — initData+HMAC سروری، توکن ربات فقط سرور، ۹ گزینه ضروری (ورود/2FA/پروفایل/نشست‌ها/کش/پخش/سرچ/پلی‌لیست/مدیریت اکانت)، WebView/تم/اندازه/back button — src/app/api/auth/telegram/route.ts — ✅ — T-S25-1..3
S26 — مقیاس‌پذیری و عملکرد — stateless+Redis، pool+ایندکس، CDN+صف، rate limit+backpressure، LB+health، مانیتورینگ، تست ۳۰ کاربر ایزوله، شبیه‌سازی کلاینت‌ها — src/app/api/health/route.ts + tests/load/ — ⏳ — T-S26-1..3
S27 — سرچ — حذف بج‌های local/online (الزام قطعی)، رتبه‌بندی ارتباطی (نام/هنرمند/آلبوم/فیلتر)، invalidate کش سرچ بعد از تغییر کتابخانه — src/components/wavely/views/search-view.tsx — ✅ — T-S27-1..2
S28 — هدف تست بار — ۳۰ کاربر روی تمام بخش‌ها در محیط ایزوله، مستند و تکرارپذیر — tests/load/ — ⏳ — T-S28-1..3
S29 — معماری مقیاس‌پذیر — stateless، pool/ایندکس‌ها/no N+1، کش ۳لایه L1/L2/L3+stampede protection، صف+dead-letter، LB بدون sticky، rate limit ۳لایه، Range Request صوت، مانیتورینگ کامل — src/lib/wavely/server/cache.ts + src/app/api/metrics/route.ts — ⏳ — T-S29-1..8
S30 — شبیه‌سازی کلاینت‌های واقعی — دسکتاپ/موبایل/WebView/کش گرم‌وسرد/شبیه‌سازی شبکه کند/آفلاین، mix واقعی ۴۰/۲۰/۱۵/۱۰/۱۰/۵، think time 1-5s — tests/load/scenarios.js — ⏳ — T-S30-1..5
S31 — تست بار ۳۰ کاربر — پیش‌نیاز ایزوله+seed، ۳۰×۱۰دقیقه+warm-up، پوشش ۱۲ سناریو، SLI/SLO (خطا<1%، p95<300ms، p99<800ms، TTFB<1s)، Stress 5→15→30→50→100، Spike 5→30/10s، Soak 1h، Recovery، پایداری داده — tests/load/k6-smoke30.js — ⏳ — T-S31-1..7
S32 — ابزارها و پیاده‌سازی — k6/Locust+Playwright+Artillery+ZAP+شبیه‌ساز initData در repo، اسکریپت نسخه‌بندی‌شده+پارامتر env+خروجی HTML، CI/CD چهار مرحله‌ای — tests/load/ + .github/workflows/ci.yml — ⏳ — T-S32-1..3
S33 — تحلیل نتایج و رفع گلوگاه — گلوگاه‌های دیتابیس/Redis/CDN/ایجنت/اپ/شبکه + اقدامات + گزارش درس‌آموخته — docs/bottlenecks.md — ⏳ — T-S33-1..2
S34 — شروط پذیرش مقیاس‌پذیری — ۸ شرط (تست ۳۰، کلاینت واقعی، خطا<1%+SLA، Spike/Soak/Recovery، پایداری داده، گلوگاه مستند، گزارش کامل، CI/CD) — docs/scale-acceptance.md — ⏳ — چک‌لیست ۸ شرط (بدون شناسه T- در فایل)
S35 — جمع‌بندی مقیاس‌پذیری — معماری stateless+کش چندلایه+صف+rate limit+مانیتورینگ+تست بار واقعی — docs/scale-acceptance.md — ⏳ — —
S36 — هدف و رویکرد امنیت — امنیت در کل چرخه؛ Defense in Depth، Least Privilege، Secure by Default، Zero Trust — docs/security-model.md — ⏳ — T-S36-1
S37 — مدل تهدید — ۶ نوع مهاجم + ۱۶ تهدید (credential stuffing تا DoS) — docs/threat-model.md — ⏳ — T-S37-1..2
S38 — امنیت رمز عبور و احراز هویت — ذخیره Argon2id/bcrypt cost≥12+pepper+constant-time+policy 12+HIBP؛ ورود امن (پیام مبهم/timing/rate جدا/lockout تدریجی/CAPTCHA/alert دستگاه جدید/remember-me)؛ ثبت‌نام امن (تأیید ایمیل/rate/disposable/terms)؛ بازیابی (توکن 15-30min هش‌شده یک‌بارمصرف+ابطال نشست+پاسخ یکسان) — src/lib/wavely/server/password.ts — ⏳ — T-S38-1..16
S39 — احراز هویت دوعاملی — TOTP+recovery codes، QR یک‌بارمصرف+رمزنگاری secret، کد بازیابی هش‌شده یک‌بارمصرف، rate سختگیرانه 5/5min، اجباری عمل حساس، غیرفعال‌سازی با رمز+کد جاری، WebAuthn اختیاری، alert، ضد bypass — src/lib/wavely/server/totp.ts — ⏳ — T-S39-1..8
S40 — امنیت نشست — ID≥128bit، سرور-ساید، rotation پس از ورود/ارتقا، انقضا مطلق+idle (30min/12h)، ابطال فوری، logout همه دستگاه‌ها، ضد fixation، لیست نشست با دستگاه/IP/فعالیت+ابطال تکی+alert دستگاه جدید، access 15min+refresh چرخشی، RS256/ES256 نه HS256، بدون payload حساس، jti/aud/iss/exp/nbf، کلید امضا در secret manager — src/lib/wavely/server/sessions.ts — ⏳ — T-S40-1..10
S41 — امنیت کوکی — HttpOnly/Secure/SameSite=Lax/Strict، SameSite=None فقط با Secure، پیشوند __Host-/__Secure-، Domain/Path محدود، بدون داده حساس خوانا، cleanup با max-age=0، rotation پس از ورود، حداکثر 4KB — src/lib/wavely/server/sessions.ts — ⏳ — T-S41-1..6
S42 — CSRF — توکن برای همه POST/PUT/DELETE یا SameSite+token، یکتا per-session/per-request، بررسی Origin/Referer، بدون mutation با GET، اجباری endpoint حساس — src/lib/wavely/server/csrf.ts — ⏳ — T-S42-1..4
S43 — XSS — CSP strict بدون unsafe-inline/eval، escaping context-aware، sanitize ورودی، بدون dangerouslySetInnerHTML/v-html، بدون توکن در localStorage، هدرهای nosniff/XFO/Referrer-Policy، SRI، npm audit — src/middleware.ts + next.config.ts — ⏳ — T-S43-1..6
S44 — تزریق — کوئری پارامتری/ORM، ضد NoSQL operator injection، sanitize ورودی سرچ، ضد command injection، SSRF allowlist، ضد path traversal، deserialization امن — src/lib/wavely/server/validation.ts — ⏳ — T-S44-1..7
S45 — کنترل دسترسی — IDOR/BOLA بررسی مالکیت، ID غیرقابل‌حدس UUID، Least Privilege (user/premium/admin)+کاربر دیتابیس مخصوص، کلید API scope‌دار، ایجنت بدون cross-user، ضد privilege escalation (بدون نقش از ورودی+بررسی سرور+revalidation) — src/lib/wavely/server/access.ts — ⏳ — T-S45-1..6
S46 — Rate Limiting — ۳ لایه IP/user/endpoint، سختگیرانه روی login/register/forgot/2FA/email change، محدود سرچ/استریم، محدود AI، 429+Retry-After بدون جزئیات، sliding window/token bucket در Redis، ضد DoS (محدودیت اتصال/حجم body/timeout/backpressure)، CAPTCHA تطبیقی — src/lib/wavely/server/rate-limit.ts — ⏳ — T-S46-1..6
S47 — جلوگیری از Enumeration — پیام یکسان (ورود/forgot/ایمیل/ثبت‌نام)، timing ثابت، بدون افشای وجود ایمیل، بدون افشای ID داخلی/ساختار دیتابیس — src/lib/wavely/server/enumeration.ts — ⏳ — T-S47-1..3
S48 — امنیت ورودی و اعتبارسنجی — validation سرور الزامی، schema validation (Zod) whitelist، محدودیت طول/نوع/فرمت، رد فیلد ناشناخته (strict)، محدودیت حجم body/فایل، بررسی Content-Type+magic bytes — src/lib/wavely/server/validation.ts — ⏳ — T-S48-1..5
S49 — امنیت آپلود فایل — magic bytes نه پسوند، allowlist فرمت (آواتار JPG/PNG/WebP، صوت MP3/AAC/OGG)، محدودیت 5MB آواتار/100MB صوت، اسکن ClamAV، re-encoding، ذخیره خارج web root، نام سرور-ساخته UUID، Content-Disposition/Type درست، بدون execute، دامنه جدا — src/app/api/uploads/avatar/route.ts — ⏳ — T-S49-1..8
S50 — رمزنگاری داده‌ها — in transit (HTTPS الزامی، TLS 1.2+/1.3، HSTS preload، certificate pinning، WSS)؛ at rest (رمزنگاری دیسک/ستون، KMS فیلد حساس، کلید در secret manager قابل‌چرخش، بدون حساس در لاگ)؛ secrets (بدون راز در repo، چرخش، جداسازی test/prod، audit دسترسی، secret scanning CI) — src/lib/wavely/server/crypto.ts — ⏳ — T-S50-1..8
S51 — امنیت ایجنت هوش مصنوعی — data isolation، tool allowlist، فیلتر ورودی/خروجی، ضد prompt injection، بدون توکن/کوکی/رمز/داده کاربر دیگر، audit logging، سهمیه روزانه توکن+rate، مجموعه ارزیابی مستمر در CI — src/lib/wavely/server/agent-policy.ts — ⏳ — T-S51-1..10
S52 — امنیت Telegram WebApp — اعتبارسنجی HMAC-SHA256 initData، بررسی auth_date+ضد replay (>5min رد)، توکن هرگز به کلاینت، match با user.id، بدون داده کلاینت اعتبارسنجی‌نشده، محدود دامنه+query_id، مدیریت نشست مستقل، alert عدم تطابق هویت، CSP مخصوص WebApp — src/lib/wavely/server/telegram.ts — ⏳ — T-S52-1..6
S53 — امنیت کش — بدون داده حساس در کش، کلید per-user با user_id، بدون کش عمومی CDN، TTL+invalidate اتمیک، رمزنگاری Redis، جداسازی کش test/prod، ضد cache poisoning، پاک‌سازی امن با تأیید — src/lib/wavely/server/cache.ts — ⏳ — T-S53-1..6
S54 — Audit Log و مانیتورینگ — رویدادها (ورود/خروج/تلاش ناموفق/تغییر رمز/2FA/ایمیل/ابطال نشست/حذف اکانت/تغییر نقش/درخواست خارج‌دامنه AI)، لاگ غیرقابل‌تغییر با دسترسی محدود، بدون داده حساس، IP/UA/زمان با حریم خصوصی، alert روی الگو، SIEM — src/lib/wavely/server/audit.ts — ⏳ — T-S54-1..5
S55 — هدرهای امنیتی — HSTS (31536000+includeSubDomains+preload)، CSP nonce/hash، nosniff، XFO، Referrer-Policy، Permissions-Policy، COOP/CORP/COEP، حذف Server/X-Powered-By، timeout/حجم body/محدود اتصال، CORS سخت، بدون directory listing، به‌روزرسانی منظم — src/middleware.ts — ⏳ — T-S55-1..4
S56 — امنیت API — auth روی همه endpointهای غیرعمومی، schema validation، CORS سخت، versioning+deprecation امن، بدون stack trace، کد خطای درست، کلید API scope‌دار+چرخش، rate limit/quota، ضد mass assignment، whitelist schema پاسخ — src/lib/wavely/server/api-guard.ts — ⏳ — T-S56-1..6
S57 — امنیت مدیریت اکانت — تغییر ایمیل (رمز+2FA+تأیید ایمیل قدیم‌وجدید)، تغییر رمز (رمز جاری+2FA+ابطال همه نشست)، حذف اکانت (re-auth+grace+سیاست نگه‌داری)، export با re-auth+لینک موقت امن، بدون ایمیل/تلفن در پروفایل عمومی، alert امنیتی تغییرات حساس، تاریخچه فعالیت امنیتی — src/lib/wavely/server/account.ts — ⏳ — T-S57-1..5
S58 — حریم خصوصی — data minimization، policy شفاف+consent، حقوق GDPR/CCPA (دسترسی/اصلاح/حذف)، رمزنگاری PII، retention+حذف خودکار، بدون اشتراک third-party، analytics ناشناس — src/lib/wavely/server/privacy.ts — ⏳ — T-S58-1..4
S59 — امنیت زیرساخت — کانتینر non-root+FS فقط‌خواندنی+seccomp/AppArmor، ایمیج رسمی به‌روز+Trivy، Dependabot/Renovate، SBOM، SCA در CI، ایمیج/آرتیفکت امضاشده، جداسازی dev/staging/prod، bastion+MFA، بکاپ رمزشده با تست restore — Dockerfile + .github/workflows/ci.yml — ⏳ — T-S59-1..6
S60 — تست‌های امنیتی — CI/CD (SAST: Semgrep/CodeQL؛ SCA: Snyk/Dependency-Check؛ secret scanning: gitleaks/trufflehog؛ container: Trivy؛ IaC: Checkov/tfsec)؛ محیط تست (DAST: ZAP؛ تست دستی CSRF/IDOR/2FA bypass/prompt injection؛ pentest؛ bug bounty)؛ سناریوهای بحرانی ۱۲گانه — tests/security/*.test.ts — ⏳ — T-S60-1..12
S61 — مدیریت رخداد — IR plan مکتوب، مسیر اطلاع‌رسانی breach، چرخش فوری کلید+ابطال نشست، بکاپ رمزشده تست‌پذیر، post-mortem+اقدام اصلاحی — docs/incident-response.md — ⏳ — T-S61-1..3
S62 — چک‌لیست امنیتی پیش از انتشار — ۱۹ آیتم (authz همه endpointها، IDOR/BOLA، CSRF/XSS/SQLi/SSRF، کوکی‌ها، CSP/هدرها، rate limit، 2FA، ابطال نشست، هش رمز، بدون راز، بلاک ایجنت، اعتبارسنجی initData، کش per-user، sanitize آپلود، audit log، بکاپ رمز، SAST/SCA/DAST، pentest، privacy policy/IR) — docs/release-security-checklist.md — ⏳ — T-S62-1..19
S63 — شروط پذیرش امنیتی — ۹ شرط (چک‌لیست pass، تست بدون critical/high، بدون راز، بلاک ایجنت، WebApp اعتبارسنجی‌شده، تزریق بسته، نشست/کوکی/2FA تست‌شده، گزارش امنیتی کامل، IR plan مستند) — docs/security-acceptance.md — ⏳ — T-S63-1..9
S64 — جمع‌بندی امنیتی — دفاع چندلایه+رمزنگاری درست+کنترل دسترسی+اعتبارسنجی سرور+rate limit+جداسازی ایجنت+WebApp+راز+تست مستمر+پاسخ حادثه — docs/security-model.md — ⏳ — —
S65 — هدف بخش اکانت+ایجنت+لیریک — سه محور پیوسته: چرخه اکانت با 2FA، ایجنت محدود به موسیقی/لیریک، آهنگ واقعی+موتور لیریک+رفع باگ پروفایل+انتقال کش — src/lib/wavely/server/* — ⏳ — T-S65-1..4
S66 — ساخت اکانت و لاگین کامل — ثبت‌نام (email/username/password+تأیید+terms+Argon2id+policy+rate+CAPTCHA+disposable+ambiguous)، ورود (uniform/timing/rate جدا/lockout/CAPTCHA/alert/remember-me/rotation/HttpOnly)، بازیابی (توکن 15-30min هش یک‌بارمصرف+ابطال+uniform)، خروج (جاری+همه+cleanup کوکی) — src/lib/wavely/server/auth.ts — ⏳ — T-S66-1..16
S67 — 2FA کامل — TOTP (Google Authenticator/Authy)+recovery codes، QR یک‌بار+رمزنگاری، هش کد بازیابی، rate 5/5min، اجباری حساس، غیرفعال با re-auth، WebAuthn، alert، ضد bypass، لیست نشست+audit+ضد enumeration/brute force/hijacking/CSRF — src/lib/wavely/server/totp.ts — ⏳ — T-S67-1..8
S68 — ایجنت هوش مصنوعی — دامنه دسترسی (پخش/پلی‌لیست/متادیتا/تاریخچه/لیریک فقط کاربر جاری)، پاسخ فقط موسیقی (پیشنهاد/تحلیل سلیقه/هنرمند/تاریخ موسیقی/تئوری/معنی/لیریک کامل/ترجمه/تشخیص؛ رد قاطع غیرموسیقی)، لایه‌های کنترل (policy+tool allowlist+فیلتر ورودی/خروجی+ضد injection+system prompt محدود+audit+سهمیه) — src/lib/wavely/server/agent-policy.ts — ⏳ — T-S68-1..10
S69 — آهنگ واقعی، پخش و تست — seed مجوزدار لوکال+استریم دو دسته (لیریک‌دار/بی‌لیریک)، پخش واقعی کامل+وضعیت پس از رفرش، آفلاین (دانلود/قطع شبکه/بازگشت)، سرچ بدون بج، پذیرش کامل — src/lib/wavely/data.ts — ⏳ — T-S69-1..8
S70 — موتور لیریک اختصاصی — vendored بر پایه Music_Lyrics_Embedder (Dani-Devlop) با نسخه+SBOM+لایسنس+SAST/SCA؛ استخراج/جاسازی MP3/FLAC/M4A/OGG، دریافت از استریم، تشخیص نبود لیریک، normalization encoding چندزبانه، کش secure per-track، API ایجنت get_lyrics/search_lyrics/match_lyrics — src/lib/wavely/server/lyrics-engine.ts — ⏳ — T-S70-1..7
S71 — رفع باگ پروفایل بعد از رفرش — حقیقت رکورد سمت سرور، UPDATE اتمیک با SELECT پس از UPDATE، invalidate کش، بدون کش کلاینت پروفایل، optimistic locking برای race، بدون overwrite با GET قدیمی، refresh خودکار state پس از ذخیره — src/app/api/profile/route.ts + src/components/wavely/views/account-view.tsx — ✅ — T-S71-1..5
S72 — انتقال کش به تنظیمات — همه کش (پروفایل/تنظیمات/کتابخانه/لیریک/سرچ اخیر/پلی‌لیست) فقط در تنظیمات؛ گزینه‌ها (پاک‌کردن کش، حجم، کش خودکار، پاک‌کردن داده محلی، پاک‌کردن کش لیریک)؛ Explore خالی از کش/مدیریت؛ کلید per-user؛ TTL+invalidate اتمیک؛ پاک‌سازی امن با تأیید — src/components/wavely/views/settings-view.tsx + explore-view.tsx — ✅ — T-S72-1..6
S73 — معیارهای پذیرش این بخش — ۱۱ شرط (چرخه auth کامل، 2FA اجباری+ضد bypass، ایجنت فقط موسیقی+رد کد/فایل، ایجنت لیریک کامل/معنی/ترجمه/تشخیص، آهنگ واقعی قابل پخش، موتور لیریک+regression، رفع باگ پروفایل+چندتب/دستگاه، کش در تنظیمات، سرچ بدون بج، گزارش تست کامل) — docs/acceptance-report.md — ⏳ — T-S73-1..11
S74 — جمع‌بندی — یکپارچه‌سازی چرخه اکانت، ایجنت موسیقی محدود، آهنگ واقعی، موتور لیریک، رفع باگ پروفایل، انتقال کش — docs/acceptance-report.md — ⏳ — —
R01 — هدف و محدوده MVP (نسخه ربات) — همان S01 برای ماژول ربات — src/lib/wavely/bot/* — ✅ — T-R01-1..5
R02 — دسترسی‌ها و توکن‌ها (ربات) — تفکیک/عدم کامیت/عدم لاگ/عدم افشای API — src/lib/wavely/server/env.ts — ✅ — T-R02-1..4
R03 — احراز هویت ترکیبی (ربات) — initData/PKCE/linking/2FA — src/lib/wavely/server/auth.ts — ⏳ — T-R03-1..5
R04 — قابلیت‌های گروه (ربات) — voice chat/اکولایزر/party/PIN/پلی‌لیست مشترک — src/lib/wavely/bot/voice-chat.ts — ✅ — T-R04-1..5
R05 — لیریکس همگام (ربات) — LRCLIB/کارائوکه/ویرایش چت/بدون لیریک — src/app/api/lyrics/route.ts — ⏳ — T-R05-1..4
R06 — کنترل مینی‌اپ (ربات) — chat↔app <1s + ۴ endpoint — src/app/api/player/control/route.ts — ⏳ — T-R06-1..3
R07 — AI DJ (ربات) — mix play/فلگ خاموش/getMixedPlaylists — src/lib/wavely/bot/ai-dj.ts — ✅ — T-R07-1..3
R08 — قابلیت‌های غیرفعال (ربات) — بدون لود ماژول/فلگ false/فعال‌سازی ادمین — src/lib/wavely/bot/flags.ts — ✅ — T-R08-1..3
R09 — دستورات ربات (ربات) — /start چندزبانه/بازگشتی//me/همه عمومی/admin مالک — src/lib/wavely/bot/commands.ts — ✅ — T-R09-1..5
R10 — جریان /start و زبان (ربات) — ذخیره/اعمال مینی‌اپ/۵ زبان — src/lib/wavely/bot/commands.ts — ✅ — T-R10-1..3
R11 — Inline Mode (ربات) — query/سقف ۵۰/دکمه‌ها — src/lib/wavely/bot/inline.ts — ✅ — T-R11-1..3
R12 — زیرساخت فنی (ربات) — BotQueue/backoff/محدودیت تلگرام/allSettled/کش — src/lib/wavely/bot/queue.ts — ✅ — T-R12-1..5
R13 — لایه منابع آنلاین (ربات) — انتخاب provider/interface/افزودن جدید/سرچ ۳ provider — src/lib/wavely/providers/index.ts — ✅ — T-R13-1..4
R14 — اجبار عضویت (ربات) — پیش‌فرض خاموش/بررسی وقتی روشن — src/lib/wavely/bot/force-join.ts — ✅ — T-R14-1..2
R15 — ساختار دیتابیس (ربات) — schema/is_mixed default — prisma/schema.prisma — ✅ — T-R15-1..2
R16 — استقرار (ربات) — دیپلوی کامل tgcloud — scripts/deploy-tgcloud.sh — ✅ — T-R16-1

---

## بخش ب — همه‌ی تست‌ها

فایل تست هدف = فایل واقعی در tests/ که تست در آن پیاده‌سازی و اجرا می‌شود.

T-S01-1 — tests/mvp.test.ts — Config/Integration — ❌ BLOCKED (tgcloud/k6 خارج از sandbox؛ اسکریپت آماده در tests/load و scripts/deploy-tgcloud.sh) — خروجی: success (دیپلوی Serverless با tgcloud)
T-S01-2 — tests/mvp.test.ts — Integration — ✅ — خروجی: هیچ کد payment/subscription در ریپو
T-S01-3 — tests/mvp.test.ts — Unit — ✅ — خروجی: ۳ فلگ AI=false و ماژول‌ها بارگذاری نشوند
T-S01-4 — tests/mvp.test.ts — Integration — ✅ — خروجی: /dj حداقل ۱ پلی‌لیست is_mixed=true
T-S01-5 — tests/mvp.test.ts — E2E — ✅ — خروجی: مینی‌اپ بدون بخش آفلاین مالی/داخل‌برنامه‌ای
T-S02-1 — tests/tokens.test.ts — Security — ✅ — خروجی: تفکیک صحیح توکن‌ها (CLI فقط login، BOT فقط Bot API)
T-S02-2 — tests/tokens.test.ts — CI Scan — ✅ — خروجی: git history بدون توکن
T-S02-3 — tests/tokens.test.ts — Integration — ✅ — خروجی: لاگ‌ها بدون الگوی توکن
T-S02-4 — tests/tokens.test.ts — DAST — ✅ — خروجی: پاسخ API بدون افشای توکن
T-S03-1 — tests/auth.test.ts — Security — ⏳ — خروجی: initData معتبر pass، نامعتبر 401
T-S03-2 — tests/auth.test.ts — DAST — ⏳ — خروجی: پاسخ WebApp بدون توکن
T-S03-3 — tests/auth.test.ts — Integration — ⏳ — خروجی: OAuth با PKCE، code plain رد شود
T-S03-4 — tests/auth.test.ts — Integration — ⏳ — خروجی: لینک email+Google به یک user_id واحد
T-S03-5 — tests/auth.test.ts — E2E — ⏳ — خروجی: 2FA پس از ورود، JWT صادر
T-S04-1 — tests/group-features.test.ts — E2E — ✅ — خروجی: ۸ دستور voice chat اجرا و پاسخ
T-S04-2 — tests/group-features.test.ts — Integration — ✅ — خروجی: تغییر پریست اکولایزر بدون pause
T-S04-3 — tests/group-features.test.ts — Integration — ✅ — خروجی: موقعیت ۲ listener یکسان (<100ms)
T-S04-4 — tests/group-features.test.ts — Unit — ✅ — خروجی: PIN ۶رقمی یک‌بارمصرف معتبر/رد
T-S04-5 — tests/group-features.test.ts — Integration — ✅ — خروجی: کلون پلی‌لیست با playlist_id متفاوت
T-S05-1 — tests/lyrics.test.ts — Integration — ⏳ — خروجی: syncedLyrics با تایم‌استمپ خطی از LRCLIB
T-S05-2 — tests/lyrics.test.ts — E2E — ⏳ — خروجی: هایلایت کارائوکه ±1s
T-S05-3 — tests/lyrics.test.ts — Integration — ⏳ — خروجی: ویرایش پیام Lyrics هر ۵ ثانیه
T-S05-4 — tests/lyrics.test.ts — E2E — ⏳ — خروجی: آهنگ بی‌لیریک بدون crash و بدون متن «بدون لیریک» زننده
T-S06-1 — tests/player-control.test.ts — E2E — ⏳ — خروجی: /pause چت → paused در اپ <1s
T-S06-2 — tests/player-control.test.ts — E2E — ⏳ — خروجی: Play در اپ → اجرا در سرور، دو سمت یکسان
T-S06-3 — tests/player-control.test.ts — Integration — ⏳ — خروجی: ۴ endpoint وضعیت 200+data
T-S07-1 — tests/ai-dj.test.ts — E2E — ✅ — خروجی: /dj_play پخش کامل پلی‌لیست Mix
T-S07-2 — tests/ai-dj.test.ts — Unit — ✅ — خروجی: بدون فلگ، personalize هرگز فراخوانی نشود
T-S07-3 — tests/ai-dj.test.ts — Integration — ✅ — خروجی: getMixedPlaylists فقط is_mixed=true
T-S08-1 — tests/ai-dj.test.ts — Unit — ✅ — خروجی: ماژول‌های AI بدون فلگ لود نشوند
T-S08-2 — tests/ai-dj.test.ts — Integration — ✅ — خروجی: bot_config سه فلگ false
T-S08-3 — tests/ai-dj.test.ts — Security — ✅ — خروجی: تغییر فلگ توسط غیرادمین 403
T-S09-1 — tests/commands.test.ts — E2E — ✅ — خروجی: /start کاربر جدید منوی ۵ زبان
T-S09-2 — tests/commands.test.ts — E2E — ✅ — خروجی: /start کاربر بازگشتی Welcome مستقیم
T-S09-3 — tests/commands.test.ts — E2E — ✅ — خروجی: /me بدون خط last_name خالی
T-S09-4 — tests/commands.test.ts — E2E — ✅ — خروجی: ۸ دستور عمومی همه پاسخ
T-S09-5 — tests/commands.test.ts — Security — ✅ — خروجی: /admin غیرمالک 403
T-S10-1 — tests/commands.test.ts — Integration — ✅ — خروجی: users.language ذخیره شود
T-S10-2 — tests/commands.test.ts — E2E — ✅ — خروجی: تغییر زبان در مینی‌اپ اعمال (UI عربی)
T-S10-3 — tests/commands.test.ts — Regression — ✅ — خروجی: تغییر ۵ زبان بدون خطا
T-S11-1 — tests/commands.test.ts — Integration — ✅ — خروجی: Inline Query نتایج Audio/Photo با کپشن کامل
T-S11-2 — tests/commands.test.ts — Integration — ✅ — خروجی: حداکثر ۵۰ نتیجه
T-S11-3 — tests/commands.test.ts — E2E — ✅ — خروجی: دکمه‌های Inline عمل مناسب (Open in Mini App)
T-S12-1 — tests/queue.test.ts — Integration — ✅ — خروجی: ۵۰ پیام در دسته‌های ۲۵تایی با delayMs=1000
T-S12-2 — tests/queue.test.ts — Integration — ✅ — خروجی: backoff نمایی روی 429 تا 60s
T-S12-3 — tests/queue.test.ts — Load — ❌ BLOCKED (tgcloud/k6 خارج از sandbox؛ اسکریپت آماده در tests/load و scripts/deploy-tgcloud.sh) — خروجی: بدون نقض نرخ تلگرام
T-S12-4 — tests/queue.test.ts — Code Audit — ✅ — خروجی: همه هندلرها Promise.allSettled
T-S12-5 — tests/queue.test.ts — Integration — ✅ — خروجی: کش hit برای کوئری تکراری (سرعت بیشتر)
T-S13-1 — tests/providers.test.ts — Integration — ✅ — خروجی: انتخاب provider طبق active_music_provider
T-S13-2 — tests/providers.test.ts — Unit — ✅ — خروجی: ۴ متد روی هر provider بدون error
T-S13-3 — tests/providers.test.ts — Integration — ✅ — خروجی: provider جدید بدون تغییر کد دیگر
T-S13-4 — tests/providers.test.ts — Integration — ✅ — خروجی: search() روی ۳ provider نتایج معتبر
T-S14-1 — tests/commands.test.ts — Unit — ✅ — خروجی: forceJoin پیش‌فرض false
T-S14-2 — tests/commands.test.ts — Integration — ✅ — خروجی: غیرعضو هدایت شود وقتی فعال
T-S15-1 — tests/schema.test.ts — Integration — ✅ — خروجی: ۹ جدول موجود در دیتابیس
T-S15-2 — tests/schema.test.ts — Integration — ✅ — خروجی: is_mixed پیش‌فرض false
T-S16-1 — tests/mvp.test.ts — CI — ❌ BLOCKED (tgcloud/k6 خارج از sandbox؛ اسکریپت آماده در tests/load و scripts/deploy-tgcloud.sh) — خروجی: استقرار کامل tgcloud success
T-S17-1 — tests/coverage.test.ts — Coverage — ⏳ — خروجی: پوشش تست زیربخش‌های ۲-۱۱ ≥80%
T-S18-1 — tests/auth.test.ts — Unit — ⏳ — خروجی: هش Argon2id/bcrypt + verify OK
T-S18-2 — tests/auth.test.ts — Security — ⏳ — خروجی: بدون رمز plain در جدول users
T-S18-3 — tests/auth.test.ts — Integration — ⏳ — خروجی: تأیید ایمیل → verified=true
T-S18-4 — tests/auth.test.ts — Integration — ⏳ — خروجی: لینک بازیابی با توکن معتبر
T-S18-5 — tests/auth.test.ts — E2E — ⏳ — خروجی: toggle 2FA تغییر وضعیت
T-S18-6 — tests/auth.test.ts — Security — ⏳ — خروجی: عمل حساس بدون 2FA → 403
T-S18-7 — tests/auth.test.ts — Integration — ⏳ — خروجی: ۵ تلاش ناموفق → قفل، تلاش ۶ام رد
T-S18-8 — tests/auth.test.ts — Security — ⏳ — خروجی: پیام خطای ورود یکسان
T-S18-9 — tests/auth.test.ts — Integration — ⏳ — خروجی: remember-me توکن امن قابل revoke
T-S19-1 (CRITICAL) — tests/profile.test.ts + agent-browser — E2E — ✅ — خروجی: تغییر نام «TestUser123» + رفرش → نام جدید باقی
T-S19-2 — tests/profile.test.ts — E2E — ✅ — خروجی: آپلود آواتار در همه جا نمایش
T-S19-3 — tests/profile.test.ts — E2E — ✅ — خروجی: وضعیت امنیتی (2FA/نشست‌ها/آخرین ورود) کامل
T-S19-4 — tests/profile.test.ts — Integration — ✅ — خروجی: خروج جمعی → همه نشست‌ها ابطال
T-S19-5 — tests/profile.test.ts — E2E — ✅ — خروجی: تغییر همزمان ۲ تب → آخرین نوشتن (optimistic locking)
T-S20-1 — tests/sessions.test.ts — Integration — ⏳ — خروجی: لیست نشست با دستگاه/مرورگر/IP
T-S20-2 — tests/sessions.test.ts — Security — ⏳ — خروجی: Set-Cookie همه HttpOnly/Secure/SameSite
T-S20-3 — tests/sessions.test.ts — Integration — ⏳ — خروجی: refresh token قبلی پس از چرخش 401
T-S20-4 — tests/sessions.test.ts — Security — ⏳ — خروجی: درخواست بدون CSRF token → 403
T-S20-5 — tests/sessions.test.ts — Security — ⏳ — خروجی: localStorage بدون داده حساس
T-S20-6 — tests/sessions.test.ts — Integration — ⏳ — خروجی: تغییر رمز → همه نشست‌های دیگر 401
T-S21-1 — tests/cache.test.ts — Unit — ✅ — خروجی: ۴ namespace کش جدا
T-S21-2 (CRITICAL) — tests/cache.test.ts + agent-browser — E2E — ✅ — خروجی: کش فقط در تنظیمات، Explore بدون دکمه کش
T-S21-3 — tests/cache.test.ts — E2E — ✅ — خروجی: ۴ گزینه کش در Settings موجود
T-S21-4 — tests/cache.test.ts — Integration — ✅ — خروجی: تغییر پروفایل → invalidate فوری کش
T-S21-5 — tests/cache.test.ts — E2E — ✅ — خروجی: Explore بعد از تغییر نام بدون داده کهنه
T-S22-1 (CRITICAL) — tests/agent.test.ts — Security — ⏳ — خروجی: «کد پایتون بنویس» → رد کامل بدون کد
T-S22-2 — tests/agent.test.ts — Security — ⏳ — خروجی: مقاله/دستور پخت/HTML → رد (۳ کیس)
T-S22-3 — tests/agent.test.ts — Security — ⏳ — خروجی: «فایل‌ها را ببین» → رد
T-S22-4 — tests/agent.test.ts — Regression — ⏳ — خروجی: «آهنگ مشابه پیشنهاد بده» → پاسخ موسیقی‌محور
T-S22-5 — tests/agent.test.ts — Unit — ⏳ — خروجی: tool allowlist فقط ابزارهای مجاز
T-S23-1 — tests/seed-playback.test.ts — Integration — ⏳ — خروجی: COUNT(tracks) ≥3 (لوکال+استریم)
T-S23-2 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: play/pause/seek/next/prev همه کار کنند
T-S23-3 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: پخش+رفرش → وضعیت ثابت بدون از دست رفتن
T-S24-1 — tests/account-security.test.ts — E2E — ⏳ — خروجی: تغییر ایمیل با تأیید الزامی
T-S24-2 — tests/account-security.test.ts — Integration — ⏳ — خروجی: حذف اکانت با grace period (deleted_at)
T-S24-3 — tests/account-security.test.ts — E2E — ⏳ — خروجی: export → فایل ZIP + لینک موقت
T-S24-4 — tests/account-security.test.ts — Integration — ⏳ — خروجی: ۵ رویداد در audit_logs
T-S24-5 — tests/account-security.test.ts — DAST — ⏳ — خروجی: بدون critical CVE
T-S25-1 — tests/telegram-webapp.test.ts — Security — ✅ — خروجی: HMAC initData تأیید، user_id استخراج
T-S25-2 (CRITICAL) — tests/telegram-webapp.test.ts — DAST — ✅ — خروجی: هیچ پاسخی توکن ربات نداشته باشد
T-S25-3 — tests/telegram-webapp.test.ts — E2E — ✅ — خروجی: ۹ گزینه ضروری WebApp موجود
T-S26-1 — tests/scale-arch.test.ts — Architecture — ⏳ — خروجی: session/cache فقط store سرور (بدون filesystem)
T-S26-2 (CRITICAL) — tests/load/k6-smoke30.js — Load — ⏳ — خروجی: ۳۰ کاربر ۱۰دقیقه، خطا<1%، p95<300ms
T-S26-3 — tests/load/scenarios.js — Load — ⏳ — خروجی: همه کلاینت‌ها کار کنند
T-S27-1 (CRITICAL) — tests/search.test.ts + agent-browser — E2E — ✅ — خروجی: سرچ بدون هیچ بج local/online
T-S27-2 — tests/search.test.ts — E2E — ✅ — خروجی: فیلتر نام/هنرمند/آلبوم نتایج مرتبط
T-S28-1 — tests/load/README.md — Architecture — ⏳ — خروجی: چک‌لیست پوشش ۱۴ بخش
T-S28-2 — tests/load/docker-compose.yml — Infrastructure — ⏳ — خروجی: network isolation از تولید
T-S28-3 — tests/load/seed.js — Integration — ⏳ — خروجی: COUNT>=100 tracks واقع‌نما
T-S29-1 — tests/scale-arch.test.ts — Architecture — ⏳ — خروجی: نشست فقط store سرور
T-S29-2 — tests/scale-arch.test.ts — Integration — ⏳ — خروجی: Connection Pool تعریف‌شده
T-S29-3 — tests/scale-arch.test.ts — Integration — ⏳ — خروجی: ۶ ایندکس موجود
T-S29-4 — tests/scale-arch.test.ts — Architecture — ⏳ — خروجی: کش L1/L2/L3
T-S29-5 — tests/scale-arch.test.ts — Unit — ✅ — خروجی: همزمانی → فقط یک کوئری (stampede)
T-S29-6 — tests/scale-arch.test.ts — Integration — ⏳ — خروجی: /health و /ready → 200
T-S29-7 — tests/scale-arch.test.ts — Security — ⏳ — خروجی: 429 پس از آستانه
T-S29-8 — tests/scale-arch.test.ts — Integration — ⏳ — خروجی: همه متریک‌ها در /metrics
T-S30-1 — tests/load/scenarios.js — Load — ⏳ — خروجی: همه مرورگرها بدون خطا
T-S30-2 — tests/load/scenarios.js — Integration — ⏳ — خروجی: ورود WebApp با HMAC معتبر
T-S30-3 — tests/load/scenarios.js — Load — ⏳ — خروجی: کار با throttling شبکه
T-S30-4 — tests/load/scenarios.js — E2E — ⏳ — خروجی: پخش از کش پس از قطع آنلاین
T-S30-5 — tests/load/scenarios.js — Load — ⏳ — خروجی: توزیع ۴۰/۲۰/۱۵/۱۰/۱۰/۵
T-S31-1 (CRITICAL) — tests/load/k6-smoke30.js — Load — ⏳ — خروجی: ۳۰×۱۰min خطا<1%، p95<300ms
T-S31-2 — tests/load/k6-smoke30.js — Load — ⏳ — خروجی: ۱۲ سناریو همه اجرا
T-S31-3 — tests/load/k6-smoke30.js — Load — ⏳ — خروجی: SLI/SLOها همه pass
T-S31-4 — tests/load/k6-stress.js — Load — ⏳ — خروجی: Spike 5→30 در 10s بدون crash
T-S31-5 — tests/load/k6-soak.js — Load — ⏳ — خروجی: ۳۰×1h بدون memory leak
T-S31-6 — tests/load/k6-stress.js — Load — ⏳ — خروجی: Recovery بدون restart دستی
T-S31-7 — tests/load/integrity.test.ts — Integration — ⏳ — خروجی: بدون تناقض داده پس از تست
T-S32-1 — tests/ci.test.ts — Config — ⏳ — خروجی: همه ابزارها تعریف‌شده
T-S32-2 — tests/ci.test.ts — Config — ⏳ — خروجی: single command اجرا
T-S32-3 — tests/ci.test.ts — CI — ⏳ — خروجی: workflow با Unit/Integration روی PR و Load/E2E شبانه
T-S33-1 — docs/bottlenecks.md — Documentation — ⏳ — خروجی: گزارش گلوگاه+اقدام
T-S33-2 — docs/bottlenecks.md — Documentation — ⏳ — خروجی: درس‌آموخته ثبت‌شده
T-S36-1 — tests/security-scenarios.test.ts — Architecture — ⏳ — خروجی: مدل امنیتی ≥4 لایه
T-S37-1 — docs/threat-model.md — Documentation — ⏳ — خروجی: threat model مستند
T-S37-2 — tests/security-scenarios.test.ts — Documentation — ⏳ — خروجی: هر تهدید به تست map شود
T-S38-1 — tests/password.test.ts — Unit — ⏳ — خروجی: هش Argon2id/bcrypt
T-S38-2 — tests/password.test.ts — Unit — ⏳ — خروجی: pepper از secret manager/env
T-S38-3 — tests/password.test.ts — Unit — ⏳ — خروجی: مقایسه constant-time
T-S38-4 — tests/password.test.ts — Unit — ⏳ — خروجی: policy 12+ کاراکتر + HIBP
T-S38-5 — tests/password.test.ts — Security — ⏳ — خروجی: پیام خطای uniform
T-S38-6 — tests/password.test.ts — Security — ⏳ — خروجی: جلوگیری از timing attack
T-S38-7 — tests/password.test.ts — Security — ⏳ — خروجی: rate limit جدا IP/account
T-S38-8 — tests/password.test.ts — Security — ⏳ — خروجی: progressive lockout
T-S38-9 — tests/password.test.ts — Security — ⏳ — خروجی: CAPTCHA تطبیقی
T-S38-10 — tests/password.test.ts — Integration — ⏳ — خروجی: alert دستگاه جدید
T-S38-11 — tests/password.test.ts — Integration — ⏳ — خروجی: remember-me توکن امن
T-S38-12 — tests/password.test.ts — Integration — ⏳ — خروجی: تأیید ایمیل الزامی
T-S38-13 — tests/password.test.ts — Security — ⏳ — خروجی: rate limit ثبت‌نام
T-S38-14 — tests/password.test.ts — Unit — ⏳ — خروجی: رد ایمیل disposable
T-S38-15 — tests/password.test.ts — Unit — ⏳ — خروجی: توکن reset هش‌شده یک‌بارمصرف
T-S38-16 — tests/password.test.ts — Security — ⏳ — خروجی: پاسخ reset یکسان
T-S39-1 — tests/totp.test.ts — Integration — ⏳ — خروجی: TOTP setup موفق
T-S39-2 — tests/totp.test.ts — Unit — ⏳ — خروجی: کدهای بازیابی کار کنند
T-S39-3 — tests/totp.test.ts — Unit — ⏳ — خروجی: QR فقط یک‌بار نمایش
T-S39-4 — tests/totp.test.ts — Unit — ⏳ — خروجی: secret رمزنگاری‌شده ذخیره
T-S39-5 — tests/totp.test.ts — Security — ⏳ — خروجی: rate سختگیرانه 5/5min
T-S39-6 — tests/totp.test.ts — Security — ⏳ — خروجی: 2FA اجباری عمل حساس
T-S39-7 — tests/totp.test.ts — Security — ⏳ — خروجی: غیرفعال‌سازی فقط با re-auth
T-S39-8 — tests/totp.test.ts — Security — ⏳ — خروجی: جلوگیری از bypass
T-S40-1 — tests/sessions.test.ts — Unit — ⏳ — خروجی: Session ID ≥128-bit
T-S40-2 — tests/sessions.test.ts — Architecture — ⏳ — خروجی: نشست در store سرور (Redis)
T-S40-3 — tests/sessions.test.ts — Integration — ⏳ — خروجی: rotation پس از ورود
T-S40-4 — tests/sessions.test.ts — Unit — ⏳ — خروجی: انقضای مطلق+idle (30min/12h)
T-S40-5 — tests/sessions.test.ts — Integration — ⏳ — خروجی: چرخش توکن روی refresh
T-S40-6 — tests/sessions.test.ts — Integration — ⏳ — خروجی: ابطال فوری
T-S40-7 — tests/sessions.test.ts — Security — ⏳ — خروجی: ضد session fixation
T-S40-8 — tests/sessions.test.ts — Integration — ⏳ — خروجی: نمایش لیست نشست
T-S40-9 — tests/sessions.test.ts — Unit — ⏳ — خروجی: اعتبارسنجی JWT (jti/aud/iss/exp/nbf)
T-S40-10 — tests/sessions.test.ts — Unit — ⏳ — خروجی: بدون داده حساس در JWT
T-S41-1 — tests/sessions.test.ts — Security — ⏳ — خروجی: کوکی HttpOnly/Secure/SameSite
T-S41-2 — tests/sessions.test.ts — Security — ⏳ — خروجی: پیشوند __Host-/__Secure-
T-S41-3 — tests/sessions.test.ts — Security — ⏳ — خروجی: Domain/Path محدود
T-S41-4 — tests/sessions.test.ts — Security — ⏳ — خروجی: بدون داده حساس در کوکی
T-S41-5 — tests/sessions.test.ts — Integration — ⏳ — خروجی: cleanup کوکی هنگام خروج
T-S41-6 — tests/sessions.test.ts — Unit — ⏳ — خروجی: سقف 4KB کوکی
T-S42-1 — tests/csrf.test.ts — Security — ⏳ — خروجی: CSRF token برای همه mutating
T-S42-2 — tests/csrf.test.ts — Security — ⏳ — خروجی: اعتبارسنجی Origin/Referer
T-S42-3 — tests/csrf.test.ts — Security — ⏳ — خروجی: بدون mutation با GET
T-S42-4 — tests/csrf.test.ts — Security — ⏳ — خروجی: endpoint حساس محافظت‌شده
T-S43-1 — tests/security-headers.test.ts — Security — ⏳ — خروجی: CSP strict بدون unsafe-inline/eval
T-S43-2 — tests/security-headers.test.ts — Security — ⏳ — خروجی: escaping درست
T-S43-3 — tests/security-headers.test.ts — Security — ⏳ — خروجی: sanitize ورودی
T-S43-4 — tests/security-headers.test.ts — Code Audit — ⏳ — خروجی: بدون dangerouslySetInnerHTML/v-html
T-S43-5 — tests/security-headers.test.ts — Security — ⏳ — خروجی: بدون توکن در localStorage
T-S43-6 — tests/security-headers.test.ts — Security — ⏳ — خروجی: SRI + npm audit تمیز
T-S44-1 — tests/injection.test.ts — Security — ⏳ — خروجی: کوئری پارامتری/ORM
T-S44-2 — tests/injection.test.ts — Security — ⏳ — خروجی: ضد NoSQL operator injection
T-S44-3 — tests/injection.test.ts — Security — ⏳ — خروجی: sanitize ورودی سرچ
T-S44-4 — tests/injection.test.ts — Security — ⏳ — خروجی: ضد command injection
T-S44-5 — tests/injection.test.ts — Security — ⏳ — خروجی: SSRF فقط allowlist
T-S44-6 — tests/injection.test.ts — Security — ⏳ — خروجی: ضد path traversal
T-S44-7 — tests/injection.test.ts — Security — ⏳ — خروجی: deserialization امن
T-S45-1 — tests/access.test.ts — Security — ⏳ — خروجی: IDOR رد شود (مالکیت چک)
T-S45-2 — tests/access.test.ts — Unit — ⏳ — خروجی: IDهای UUID غیرقابل‌حدس
T-S45-3 — tests/access.test.ts — Unit — ⏳ — خروجی: نقش‌ها Least Privilege
T-S45-4 — tests/access.test.ts — Security — ⏳ — خروجی: بدون ارتقای نقش از ورودی
T-S45-5 — tests/access.test.ts — Security — ⏳ — خروجی: مجوزدهی سمت سرور
T-S45-6 — tests/access.test.ts — Security — ⏳ — خروجی: revalidation در عمل حساس
T-S46-1 — tests/rate-limit.test.ts — Security — ⏳ — خروجی: ۳ لایه rate limit
T-S46-2 — tests/rate-limit.test.ts — Security — ⏳ — خروجی: محدودیت سخت حساس‌ها
T-S46-3 — tests/rate-limit.test.ts — Security — ⏳ — خروجی: محدودیت سرچ/استریم
T-S46-4 — tests/rate-limit.test.ts — Security — ⏳ — خروجی: محدودیت AI
T-S46-5 — tests/rate-limit.test.ts — Security — ⏳ — خروجی: 429+Retry-After بدون جزئیات
T-S46-6 — tests/rate-limit.test.ts — Unit — ⏳ — خروجی: sliding window/token bucket
T-S47-1 — tests/auth.test.ts — Security — ⏳ — خروجی: پیام‌های یکسان
T-S47-2 — tests/auth.test.ts — Security — ⏳ — خروجی: timing ثابت
T-S47-3 — tests/auth.test.ts — Security — ⏳ — خروجی: بدون افشای وجود ایمیل
T-S48-1 — tests/injection.test.ts — Security — ⏳ — خروجی: validation سرور الزامی
T-S48-2 — tests/injection.test.ts — Security — ⏳ — خروجی: schema validation whitelist
T-S48-3 — tests/injection.test.ts — Unit — ⏳ — خروجی: محدودیت طول/نوع/فرمت
T-S48-4 — tests/injection.test.ts — Unit — ⏳ — خروجی: رد فیلد ناشناخته
T-S48-5 — tests/injection.test.ts — Unit — ⏳ — خروجی: محدودیت حجم+magic bytes
T-S49-1 — tests/upload.test.ts — Security — ⏳ — خروجی: magic bytes نه پسوند
T-S49-2 — tests/upload.test.ts — Security — ⏳ — خروجی: allowlist فرمت
T-S49-3 — tests/upload.test.ts — Security — ⏳ — خروجی: محدودیت 5MB/100MB
T-S49-4 — tests/upload.test.ts — Security — ⏳ — خروجی: اسکن ClamAV
T-S49-5 — tests/upload.test.ts — Security — ⏳ — خروجی: re-encoding تصویر
T-S49-6 — tests/upload.test.ts — Security — ⏳ — خروجی: ذخیره خارج web root
T-S49-7 — tests/upload.test.ts — Unit — ⏳ — خروجی: نام فایل UUID سرور-ساخته
T-S49-8 — tests/upload.test.ts — Security — ⏳ — خروجی: بدون مجوز execute
T-S50-1 — tests/crypto.test.ts — Security — ⏳ — خروجی: HTTPS الزامی
T-S50-2 — tests/crypto.test.ts — Security — ⏳ — خروجی: TLS 1.2+
T-S50-3 — tests/crypto.test.ts — Security — ⏳ — خروجی: HSTS preload
T-S50-4 — tests/crypto.test.ts — Security — ⏳ — خروجی: WSS
T-S50-5 — tests/crypto.test.ts — Unit — ⏳ — خروجی: رمزنگاری at-rest فیلد حساس
T-S50-6 — tests/crypto.test.ts — Unit — ⏳ — خروجی: رمزنگاری فیلد با KMS/کلید env
T-S50-7 — tests/crypto.test.ts — Config — ⏳ — خروجی: چرخش کلید ممکن
T-S50-8 — tests/crypto.test.ts — Security — ⏳ — خروجی: بدون داده حساس در لاگ
T-S51-1 — tests/agent.test.ts — Security — ⏳ — خروجی: جداسازی داده ایجنت
T-S51-2 — tests/agent.test.ts — Unit — ⏳ — خروجی: tool allowlist
T-S51-3 — tests/agent.test.ts — Security — ⏳ — خروجی: فیلتر ورودی/خروجی
T-S51-4 — tests/agent.test.ts — Security — ⏳ — خروجی: ضد prompt injection
T-S51-5 — tests/agent.test.ts — Security — ⏳ — خروجی: بدون توکن/کوکی/رمز
T-S51-6 — tests/agent.test.ts — Security — ⏳ — خروجی: بدون داده کاربر دیگر
T-S51-7 — tests/agent.test.ts — Integration — ⏳ — خروجی: audit logging ایجنت
T-S51-8 — tests/agent.test.ts — Unit — ⏳ — خروجی: سهمیه روزانه توکن
T-S51-9 — tests/agent.test.ts — CI — ⏳ — خروجی: مجموعه ارزیابی در CI
T-S51-10 — tests/agent.test.ts — Security — ⏳ — خروجی: bypass چندزبانه رد شود
T-S52-1 — tests/telegram-webapp.test.ts — Security — ⏳ — خروجی: HMAC initData
T-S52-2 — tests/telegram-webapp.test.ts — Security — ⏳ — خروجی: replay >5min رد شود
T-S52-3 — tests/telegram-webapp.test.ts — Security — ⏳ — خروجی: توکن هرگز به کلاینت
T-S52-4 — tests/telegram-webapp.test.ts — Security — ⏳ — خروجی: match با user.id
T-S52-5 — tests/telegram-webapp.test.ts — Security — ⏳ — خروجی: دامنه+query_id
T-S52-6 — tests/telegram-webapp.test.ts — Security — ⏳ — خروجی: CSP WebApp
T-S53-1 — tests/cache.test.ts — Security — ✅ — خروجی: بدون داده حساس در کش
T-S53-2 — tests/cache.test.ts — Unit — ✅ — خروجی: کلید per-user
T-S53-3 — tests/cache.test.ts — Security — ✅ — خروجی: بدون کش عمومی CDN
T-S53-4 — tests/cache.test.ts — Unit — ✅ — خروجی: TTL+invalidate اتمیک
T-S53-5 — tests/cache.test.ts — Architecture — ⏳ — خروجی: رمزنگاری store کش
T-S53-6 — tests/cache.test.ts — Security — ⏳ — خروجی: ضد cache poisoning
T-S54-1 — tests/audit.test.ts — Integration — ⏳ — خروجی: رویدادها ثبت
T-S54-2 — tests/audit.test.ts — Architecture — ⏳ — خروجی: لاگ غیرقابل‌تغییر
T-S54-3 — tests/audit.test.ts — Security — ⏳ — خروجی: بدون داده حساس در لاگ
T-S54-4 — tests/audit.test.ts — Unit — ⏳ — خروجی: فیلدهای IP/UA/زمان با حریم خصوصی
T-S54-5 — tests/audit.test.ts — Integration — ⏳ — خروجی: alert روی الگو
T-S55-1 — tests/security-headers.test.ts — Security — ⏳ — خروجی: HSTS کامل
T-S55-2 — tests/security-headers.test.ts — Security — ⏳ — خروجی: CSP
T-S55-3 — tests/security-headers.test.ts — Security — ⏳ — خروجی: بدون هدرهای افشاگر
T-S55-4 — tests/security-headers.test.ts — Security — ⏳ — خروجی: CORS سخت
T-S56-1 — tests/access.test.ts — Security — ⏳ — خروجی: auth روی همه غیرعمومی
T-S56-2 — tests/access.test.ts — Security — ⏳ — خروجی: schema validation API
T-S56-3 — tests/access.test.ts — Config — ⏳ — خروجی: versioning API
T-S56-4 — tests/access.test.ts — Security — ⏳ — خروجی: بدون stack trace
T-S56-5 — tests/access.test.ts — Unit — ⏳ — خروجی: کد خطای درست
T-S56-6 — tests/access.test.ts — Security — ⏳ — خروجی: ضد mass assignment
T-S57-1 — tests/account-security.test.ts — E2E — ⏳ — خروجی: تغییر ایمیل با رمز+2FA+تأیید دو ایمیل
T-S57-2 — tests/account-security.test.ts — Security — ⏳ — خروجی: تغییر رمز با رمز جاری+2FA+ابطال نشست
T-S57-3 — tests/account-security.test.ts — Integration — ⏳ — خروجی: حذف اکانت re-auth+grace
T-S57-4 — tests/account-security.test.ts — E2E — ⏳ — خروجی: export با re-auth+لینک موقت
T-S57-5 — tests/account-security.test.ts — Integration — ⏳ — خروجی: alert امنیتی تغییرات حساس
T-S58-1 — tests/privacy.test.ts — Unit — ⏳ — خروجی: data minimization
T-S58-2 — tests/privacy.test.ts — Documentation — ⏳ — خروجی: privacy policy+consent
T-S58-3 — tests/privacy.test.ts — Integration — ⏳ — خروجی: حقوق GDPR/CCPA
T-S58-4 — tests/privacy.test.ts — Unit — ⏳ — خروجی: retention+حذف خودکار
T-S59-1 — tests/infra.test.ts — Architecture — ⏳ — خروجی: کانتینر non-root
T-S59-2 — tests/infra.test.ts — CI — ⏳ — خروجی: اسکن ایمیج Trivy
T-S59-3 — tests/infra.test.ts — Config — ⏳ — خروجی: Dependabot/Renovate
T-S59-4 — tests/infra.test.ts — CI — ⏳ — خروجی: SBOM تولید شود
T-S59-5 — tests/infra.test.ts — CI — ⏳ — خروجی: SCA در CI
T-S59-6 — tests/infra.test.ts — CI — ⏳ — خروجی: secret scanning در CI
T-S60-1 — tests/ci.test.ts — CI — ⏳ — خروجی: SAST فعال
T-S60-2 — tests/ci.test.ts — CI — ⏳ — خروجی: SCA فعال
T-S60-3 — tests/ci.test.ts — CI — ⏳ — خروجی: secret scanning فعال
T-S60-4 — tests/ci.test.ts — CI — ⏳ — خروجی: container scanning فعال
T-S60-5 — tests/ci.test.ts — CI — ⏳ — خروجی: DAST فعال
T-S60-6 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: تست‌های دستی CSRF/IDOR/2FA/prompt injection
T-S60-7 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: penetration test
T-S60-8 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: 2FA bypass ناموفق
T-S60-9 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: IDOR ناموفق
T-S60-10 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: session replay ناموفق
T-S60-11 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: CSRF ناموفق
T-S60-12 — tests/security-scenarios.test.ts — Security — ⏳ — خروجی: XSS در نام/پلی‌لیست/آواتار ناموفق
T-S61-1 — docs/incident-response.md — Documentation — ⏳ — خروجی: IR plan مکتوب
T-S61-2 — docs/incident-response.md — Documentation — ⏳ — خروجی: مسیر breach notification
T-S61-3 — tests/infra.test.ts — Integration — ⏳ — خروجی: چرخش کلید فوری ممکن
T-S62-1 — tests/checklists.test.ts — Audit — ⏳ — خروجی: authz روی همه endpointها
T-S62-2 — tests/checklists.test.ts — Audit — ⏳ — خروجی: IDOR/BOLA بررسی‌شده
T-S62-3 — tests/checklists.test.ts — Audit — ⏳ — خروجی: CSRF/XSS/SQLi/SSRF بسته
T-S62-4 — tests/checklists.test.ts — Audit — ⏳ — خروجی: کوکی‌ها تنظیم
T-S62-5 — tests/checklists.test.ts — Audit — ⏳ — خروجی: CSP/هدرها فعال
T-S62-6 — tests/checklists.test.ts — Audit — ⏳ — خروجی: rate limiting فعال
T-S62-7 — tests/checklists.test.ts — Audit — ⏳ — خروجی: 2FA تست‌شده
T-S62-8 — tests/checklists.test.ts — Audit — ⏳ — خروجی: نشست‌ها قابل ابطال
T-S62-9 — tests/checklists.test.ts — Audit — ⏳ — خروجی: رمزها هش‌شده
T-S62-10 — tests/checklists.test.ts — Audit — ⏳ — خروجی: بدون راز در کد/لاگ/ریپو
T-S62-11 — tests/checklists.test.ts — Audit — ⏳ — خروجی: ایجنت بلاک خارج دامنه
T-S62-12 — tests/checklists.test.ts — Audit — ⏳ — خروجی: initData اعتبارسنجی
T-S62-13 — tests/checklists.test.ts — Audit — ⏳ — خروجی: کش per-user
T-S62-14 — tests/checklists.test.ts — Audit — ⏳ — خروجی: آپلود sanitize
T-S62-15 — tests/checklists.test.ts — Audit — ⏳ — خروجی: audit log فعال
T-S62-16 — tests/checklists.test.ts — Audit — ⏳ — خروجی: بکاپ رمزشده
T-S62-17 — tests/checklists.test.ts — Audit — ⏳ — خروجی: SAST/SCA/DAST pass
T-S62-18 — tests/checklists.test.ts — Audit — ⏳ — خروجی: penetration test
T-S62-19 — tests/checklists.test.ts — Audit — ⏳ — خروجی: privacy policy + IR plan
T-S63-1 — tests/checklists.test.ts — Audit — ⏳ — خروجی: چک‌لیست امنیتی pass
T-S63-2 — tests/checklists.test.ts — Audit — ⏳ — خروجی: تست‌ها بدون critical/high
T-S63-3 — tests/checklists.test.ts — Audit — ⏳ — خروجی: بدون راز
T-S63-4 — tests/checklists.test.ts — Audit — ⏳ — خروجی: ایجنت بلاک
T-S63-5 — tests/checklists.test.ts — Audit — ⏳ — خروجی: WebApp اعتبارسنجی‌شده
T-S63-6 — tests/checklists.test.ts — Audit — ⏳ — خروجی: تزریق بسته
T-S63-7 — tests/checklists.test.ts — Audit — ⏳ — خروجی: نشست/کوکی/2FA تست‌شده
T-S63-8 — tests/checklists.test.ts — Audit — ⏳ — خروجی: گزارش امنیتی کامل
T-S63-9 — tests/checklists.test.ts — Audit — ⏳ — خروجی: IR plan مستند
T-S65-1 — tests/coverage.test.ts — Coverage — ⏳ — خروجی: پوشش سه محور
T-S65-2 — tests/coverage.test.ts — Integration — ⏳ — خروجی: چرخه اکانت کامل
T-S65-3 — tests/coverage.test.ts — Security — ⏳ — خروجی: محدوده ایجنت
T-S65-4 — tests/coverage.test.ts — E2E — ⏳ — خروجی: رفع باگ پروفایل
T-S66-1 — tests/auth.test.ts — Integration — ⏳ — خروجی: ثبت‌نام موفق
T-S66-2 — tests/auth.test.ts — Unit — ⏳ — خروجی: هش رمز
T-S66-3 — tests/auth.test.ts — Unit — ⏳ — خروجی: policy رمز
T-S66-4 — tests/auth.test.ts — Security — ⏳ — خروجی: rate limit ثبت‌نام
T-S66-5 — tests/auth.test.ts — Security — ⏳ — خروجی: CAPTCHA
T-S66-6 — tests/auth.test.ts — Unit — ⏳ — خروجی: رد disposable
T-S66-7 — tests/auth.test.ts — Integration — ⏳ — خروجی: پذیرش terms با timestamp
T-S66-8 — tests/auth.test.ts — Security — ⏳ — خروجی: پیام ورود uniform
T-S66-9 — tests/auth.test.ts — Security — ⏳ — خروجی: timing ثابت
T-S66-10 — tests/auth.test.ts — Security — ⏳ — خروجی: rate limit جدا
T-S66-11 — tests/auth.test.ts — Security — ⏳ — خروجی: lockout تدریجی
T-S66-12 — tests/auth.test.ts — Integration — ⏳ — خروجی: alert دستگاه جدید
T-S66-13 — tests/auth.test.ts — Integration — ⏳ — خروجی: remember-me توکن
T-S66-14 — tests/auth.test.ts — Integration — ⏳ — خروجی: rotation نشست پس از ورود
T-S66-15 — tests/auth.test.ts — Unit — ⏳ — خروجی: توکن reset هش‌شده
T-S66-16 — tests/auth.test.ts — Integration — ⏳ — خروجی: خروج → ابطال
T-S67-1 — tests/totp.test.ts — Integration — ⏳ — خروجی: TOTP
T-S67-2 — tests/totp.test.ts — Unit — ⏳ — خروجی: recovery codes
T-S67-3 — tests/totp.test.ts — Unit — ⏳ — خروجی: QR یک‌بار
T-S67-4 — tests/totp.test.ts — Security — ⏳ — خروجی: rate 5/5min
T-S67-5 — tests/totp.test.ts — Security — ⏳ — خروجی: اجباری حساس
T-S67-6 — tests/totp.test.ts — Security — ⏳ — خروجی: غیرفعال با re-auth
T-S67-7 — tests/totp.test.ts — Unit — ⏳ — خروجی: WebAuthn (اختیاری، فلگ)
T-S67-8 — tests/totp.test.ts — Security — ⏳ — خروجی: ضد bypass
T-S68-1 — tests/agent.test.ts — Security — ⏳ — خروجی: دسترسی فقط موسیقی
T-S68-2 — tests/agent.test.ts — Security — ⏳ — خروجی: بدون cross-user
T-S68-3 — tests/agent.test.ts — Security — ⏳ — خروجی: رد غیرموسیقی
T-S68-4 — tests/agent.test.ts — Unit — ⏳ — خروجی: policy layer
T-S68-5 — tests/agent.test.ts — Unit — ⏳ — خروجی: tool allowlist
T-S68-6 — tests/agent.test.ts — Security — ⏳ — خروجی: فیلتر ورودی/خروجی
T-S68-7 — tests/agent.test.ts — Security — ⏳ — خروجی: ضد prompt injection
T-S68-8 — tests/agent.test.ts — Regression — ⏳ — خروجی: پاسخ درست در دامنه موسیقی
T-S68-9 — tests/agent.test.ts — Security — ⏳ — خروجی: رد خارج دامنه
T-S68-10 — tests/agent.test.ts — Security — ⏳ — خروجی: تست چندزبانه
T-S69-1 — tests/seed-playback.test.ts — Integration — ⏳ — خروجی: آهنگ seed (لیریک‌دار+بی‌لیریک)
T-S69-2 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: پخش واقعی
T-S69-3 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: پخش آفلاین از کش
T-S69-4 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: بدون بج local/online
T-S69-5 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: پذیرش کامل
T-S69-6 — tests/seed-playback.test.ts — Integration — ⏳ — خروجی: بررسی لایسنس
T-S69-7 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: مدیریت خطا
T-S69-8 — tests/seed-playback.test.ts — E2E — ⏳ — خروجی: پایداری پس از رفرش
T-S70-1 — tests/lyrics.test.ts — Integration — ⏳ — خروجی: استخراج لیریک از فایل لوکال MP3/FLAC/M4A/OGG
T-S70-2 — tests/lyrics.test.ts — Integration — ⏳ — خروجی: دریافت از استریم
T-S70-3 — tests/lyrics.test.ts — E2E — ⏳ — خروجی: مدیریت نبود لیریک (بدون زحمت، بدون «بدون لیریک»)
T-S70-4 — tests/lyrics.test.ts — Unit — ⏳ — خروجی: مدیریت فایل خراب
T-S70-5 — tests/lyrics.test.ts — Unit — ⏳ — خروجی: تطبیق لیریک با آهنگ
T-S70-6 — tests/lyrics.test.ts — Regression — ⏳ — خروجی: تست رگرسیون باگ‌های رفع‌شده
T-S70-7 — tests/lyrics.test.ts — Unit — ⏳ — خروجی: چندزبانه/encoding
T-S71-1 (CRITICAL) — tests/profile.test.ts — E2E — ✅ — خروجی: تغییر نام+ذخیره+رفرش → نام جدید
T-S71-2 — tests/profile.test.ts — E2E — ✅ — خروجی: آواتار/نام نمایشی
T-S71-3 — tests/profile.test.ts — E2E — ✅ — خروجی: دو تب همزمان
T-S71-4 — tests/profile.test.ts — E2E — ✅ — خروجی: explore/cache بدون داده کهنه
T-S71-5 — tests/profile.test.ts — E2E — ✅ — خروجی: sync بین‌دستگاهی
T-S72-1 — tests/cache.test.ts — E2E — ✅ — خروجی: کش فقط در تنظیمات
T-S72-2 (CRITICAL) — tests/cache.test.ts — E2E — ✅ — خروجی: Explore بدون کش
T-S72-3 — tests/cache.test.ts — E2E — ✅ — خروجی: ۵ گزینه مدیریت کش
T-S72-4 — tests/cache.test.ts — Unit — ✅ — خروجی: کلید per-user
T-S72-5 — tests/cache.test.ts — Unit — ✅ — خروجی: TTL+invalidate
T-S72-6 — tests/cache.test.ts — Security — ✅ — خروجی: پاک‌سازی امن با تأیید
T-S73-1 — tests/checklists.test.ts — Audit — ⏳ — خروجی: چرخه auth کامل
T-S73-2 — tests/checklists.test.ts — Audit — ⏳ — خروجی: 2FA اجباری+ضد bypass
T-S73-3 — tests/checklists.test.ts — Audit — ⏳ — خروجی: ایجنت فقط موسیقی
T-S73-4 — tests/checklists.test.ts — Audit — ⏳ — خروجی: ایجنت رد کد/فایل
T-S73-5 — tests/checklists.test.ts — Audit — ⏳ — خروجی: ایجنت لیریک
T-S73-6 — tests/checklists.test.ts — Audit — ⏳ — خروجی: آهنگ واقعی قابل پخش
T-S73-7 — tests/checklists.test.ts — Audit — ⏳ — خروجی: موتور لیریک+regression
T-S73-8 — tests/checklists.test.ts — Audit — ⏳ — خروجی: باگ پروفایل رفع+چندتب/دستگاه
T-S73-9 — tests/checklists.test.ts — Audit — ⏳ — خروجی: کش در تنظیمات
T-S73-10 — tests/checklists.test.ts — Audit — ⏳ — خروجی: سرچ بدون بج
T-S73-11 — tests/checklists.test.ts — Audit — ⏳ — خروجی: گزارش تست کامل
T-R01-1 — tests/mvp.test.ts — Config — ❌ BLOCKED (tgcloud/k6 خارج از sandbox؛ اسکریپت آماده در tests/load و scripts/deploy-tgcloud.sh) — خروجی: Serverless deploy success
T-R01-2 — tests/mvp.test.ts — Integration — ✅ — خروجی: بدون کد مالی
T-R01-3 — tests/mvp.test.ts — Unit — ✅ — خروجی: فلگ‌های AI false
T-R01-4 — tests/mvp.test.ts — Integration — ✅ — خروجی: AI DJ پایه فعال
T-R01-5 — tests/mvp.test.ts — E2E — ✅ — خروجی: مینی‌اپ فقط آنلاین
T-R02-1 — tests/tokens.test.ts — Security — ✅ — خروجی: تفکیک توکن
T-R02-2 — tests/tokens.test.ts — CI Scan — ✅ — خروجی: بدون کامیت توکن
T-R02-3 — tests/tokens.test.ts — Integration — ✅ — خروجی: بدون توکن در لاگ
T-R02-4 — tests/tokens.test.ts — DAST — ✅ — خروجی: بدون توکن در پاسخ API
T-R03-1 — tests/auth.test.ts — Security — ⏳ — خروجی: اعتبارسنجی initData
T-R03-2 — tests/auth.test.ts — DAST — ⏳ — خروجی: بدون افشای توکن
T-R03-3 — tests/auth.test.ts — Integration — ⏳ — خروجی: OAuth PKCE
T-R03-4 — tests/auth.test.ts — Integration — ⏳ — خروجی: اتصال چند حساب
T-R03-5 — tests/auth.test.ts — E2E — ⏳ — خروجی: 2FA پس از ورود
T-R04-1 — tests/group-features.test.ts — E2E — ✅ — خروجی: کنترل‌های voice chat
T-R04-2 — tests/group-features.test.ts — Integration — ✅ — خروجی: اکولایزر بدون قطع
T-R04-3 — tests/group-features.test.ts — Integration — ✅ — خروجی: sync party <100ms
T-R04-4 — tests/group-features.test.ts — Unit — ✅ — خروجی: PIN ۶رقمی
T-R04-5 — tests/group-features.test.ts — Integration — ✅ — خروجی: کلون پلی‌لیست
T-R05-1 — tests/lyrics.test.ts — Integration — ⏳ — خروجی: LRCLIB
T-R05-2 — tests/lyrics.test.ts — E2E — ⏳ — خروجی: کارائوکه
T-R05-3 — tests/lyrics.test.ts — Integration — ⏳ — خروجی: ویرایش چت
T-R05-4 — tests/lyrics.test.ts — E2E — ⏳ — خروجی: بدون لیریک
T-R06-1 — tests/player-control.test.ts — E2E — ⏳ — خروجی: chat→app <1s
T-R06-2 — tests/player-control.test.ts — E2E — ⏳ — خروجی: app→chat sync
T-R06-3 — tests/player-control.test.ts — Integration — ⏳ — خروجی: endpointها
T-R07-1 — tests/ai-dj.test.ts — E2E — ✅ — خروجی: پخش mix
T-R07-2 — tests/ai-dj.test.ts — Unit — ✅ — خروجی: فلگ شخصی‌سازی false
T-R07-3 — tests/ai-dj.test.ts — Integration — ✅ — خروجی: getMixedPlaylists
T-R08-1 — tests/ai-dj.test.ts — Unit — ✅ — خروجی: بدون لود ماژول AI
T-R08-2 — tests/ai-dj.test.ts — Integration — ✅ — خروجی: فلگ false
T-R08-3 — tests/ai-dj.test.ts — Security — ✅ — خروجی: فعال‌سازی فقط ادمین
T-R09-1 — tests/commands.test.ts — E2E — ✅ — خروجی: /start چندزبانه
T-R09-2 — tests/commands.test.ts — E2E — ✅ — خروجی: کاربر بازگشتی
T-R09-3 — tests/commands.test.ts — E2E — ✅ — خروجی: /me بدون last_name
T-R09-4 — tests/commands.test.ts — E2E — ✅ — خروجی: همه دستورات عمومی
T-R09-5 — tests/commands.test.ts — Security — ✅ — خروجی: /admin فقط مالک
T-R10-1 — tests/commands.test.ts — Integration — ✅ — خروجی: زبان ذخیره
T-R10-2 — tests/commands.test.ts — E2E — ✅ — خروجی: اعمال در مینی‌اپ
T-R10-3 — tests/commands.test.ts — Regression — ✅ — خروجی: ۵ زبان
T-R11-1 — tests/commands.test.ts — Integration — ✅ — خروجی: inline query
T-R11-2 — tests/commands.test.ts — Integration — ✅ — خروجی: سقف ۵۰
T-R11-3 — tests/commands.test.ts — E2E — ✅ — خروجی: دکمه‌های inline
T-R12-1 — tests/queue.test.ts — Integration — ✅ — خروجی: BotQueue دسته‌ای
T-R12-2 — tests/queue.test.ts — Integration — ✅ — خروجی: backoff نمایی
T-R12-3 — tests/queue.test.ts — Load — ❌ BLOCKED (tgcloud/k6 خارج از sandbox؛ اسکریپت آماده در tests/load و scripts/deploy-tgcloud.sh) — خروجی: محدودیت‌های تلگرام
T-R12-4 — tests/queue.test.ts — Code Audit — ✅ — خروجی: Promise.allSettled
T-R12-5 — tests/queue.test.ts — Integration — ✅ — خروجی: کش جستجو/لیریکس
T-R13-1 — tests/providers.test.ts — Integration — ✅ — خروجی: انتخاب provider
T-R13-2 — tests/providers.test.ts — Unit — ✅ — خروجی: interface مشترک
T-R13-3 — tests/providers.test.ts — Integration — ✅ — خروجی: provider جدید
T-R13-4 — tests/providers.test.ts — Integration — ✅ — خروجی: سرچ در ۳ provider
T-R14-1 — tests/commands.test.ts — Unit — ✅ — خروجی: پیش‌فرض خاموش
T-R14-2 — tests/commands.test.ts — Integration — ✅ — خروجی: بررسی وقتی روشن
T-R15-1 — tests/schema.test.ts — Integration — ✅ — خروجی: schema
T-R15-2 — tests/schema.test.ts — Integration — ✅ — خروجی: is_mixed default
T-R16-1 — tests/mvp.test.ts — CI — ❌ BLOCKED (tgcloud/k6 خارج از sandbox؛ اسکریپت آماده در tests/load و scripts/deploy-tgcloud.sh) — خروجی: دیپلوی کامل

---

## بخش ج — چک‌لیست D6 (Semantic Diff) — ۱۱ ردیف

1. ساختار: مارک‌داون ساده → ماژول `# MODULE` (vA) → MUST/SHOULD/NEVER (vB) — تغییر عمدی: بله — دلیل: ساختار + خوانایی — ریسک: پایین
2. شناسه‌گذاری: شماره‌گذاری → S01..S74 + R01..R16 → ردیابی — بله — Traceability — پایین
3. تست‌ها: بخش کلی → تست اختصاصی هر بخش → امنیتی + Load — بله — پوشش کامل — پایین
4. بج local/online: موجود → **حذف** → حذف — بله — **الزام کاربر** — پایین
5. باگ پروفایل: راهکار → **MUST رفع** → تضمین تست — بله — **رفع قطعی** — پایین
6. کش تنظیمات: ذکر → **MUST** → اجباری — بله — **الزام کاربر** — پایین
7. توکن ربات: باید نگه → **MUST** → DAST اجباری — بله — امنیت — پایین
8. A/B: — → اضافه → اضافه — بله — Migration ایمن — پایین
9. Semantic Diff: — → اضافه → اضافه — بله — شفافیت — پایین
10. Migration Plan: — → اضافه → اضافه — بله — Deployment ایمن — پایین
11. محتوای اصلی: حفظ → حفظ → حفظ — خیر — — — —

## بخش د — چک‌لیست D7 (Migration Plan) — ۱۸ آیتم

Feature Flags:
1. `use_master_prompt_v1` — default true — legacy: wavely_prompt2.md — پرامپت فعلی
2. `use_master_prompt_v2` — default false — نسخه B
3. `show_local_online_badges` — default false — deprecated — بج‌های local/online
4. `show_cache_in_explore` — default false — deprecated — کش در Explore
5. `profile_refresh_fix` — default true — رفع باگ پروفایل

Rollout:
6. مرحله ۱ — ۵٪ — `profile_refresh_fix` + حذف بج‌ها
7. مرحله ۲ — ۲۵٪ — `show_local_online_badges=false`, `show_cache_in_explore=false`
8. مرحله ۳ — ۱۰۰٪ — حذف legacy

Shadow Mode:
9. لاگ: `profile_refresh.value_before/after`, `search.badge_shown`, `explore.cache_access`
10. مقایسه خودکار v1 vs v2 برای ۱۰۰٪
11. alert روی اختلاف رفتاری >0٪

Kill Switch:
12. `/admin/kill-switch/prompt-v2` → `use_master_prompt_v2=false`
13. `ROLLBACK_TIME_TARGET=5min`
14. `/internal/rollback/v1` در تمام instances

ترتیب دیپلوی:
15. دیپلوی A + تست‌ها
16. Shadow mode ۱ هفته
17. Rollout ۵٪ → ۲۵٪ → ۱۰۰٪ با تست بین مراحل
18. B پشت flag بعد از pass کامل

## بخش ه — چک‌لیست D8 (Rollback Plan) — ۱۱ آیتم

شرط rollback:
1. نرخ 5xx > ۱٪
2. پروفایل بعد از رفرش نام نادرست
3. بازگشت بج local/online
4. افشای توکن ربات
5. fail تست ۳۰ کاربر

مراحل:
6. Kill switch: `use_master_prompt_v2=false`
7. Rollback config badges (فقط دیباگ)
8. Rollback دیتابیس در صورت نیاز
9. تأیید سلامت با smoke test
10. Post-mortem

زمان:
11. زمان هدف rollback < ۵ دقیقه

## بخش و — چک‌لیست D9 (Self-Audit) — ۱۳ آیتم

پوشش Success Criteria:
1. عدم حذف الزامات — همه بخش‌ها منتقل شده‌اند
2. شناسه‌گذاری — D2 + ماژول‌ها
3. نسخه A + B — بخش‌های جداگانه
4. تست هر بخش — ≥۳ تست برای هر S# (۲۵۰+ تست)
5. Semantic Diff — ۱۱ ردیف
6. Migration Plan — flags/shadow/kill switch
7. حذف بج‌های local/online — T-S27-1 CRITICAL
8. رفع باگ پروفایل — T-S19-1 CRITICAL
9. کش در تنظیمات — T-S21-2 CRITICAL
10. عدم افشای توکن — T-S25-2 CRITICAL

ریسک‌های باقی‌مانده:
11. تست‌های ایجنت نوسان pass/fail → prompt tests ثابت + hard assertions
12. تست بار به زیرساخت ایزوله نیاز → docker-compose یک‌دست
13. باگ پروفایل ریشه پنهان → تست race condition چندتب + optimistic locking

## بخش ز — QA Checklist نهایی (بند ۹ فایل) — ۸ آیتم

1. همه S1..Sn در D2 آمده‌اند و در D4/D5 ردیابی شده‌اند.
2. نسخه A هیچ تغییر معنایی نسبت به v0 ندارد (به جز حذف بج‌های local/online که در D6 مستند شده).
3. فرمت خروجی فعلی در A دست‌نخورده است.
4. هیچ عبارت مبهمی باقی نمانده.
5. D6 کامل و صادق است.
6. D7 شامل flag، shadow، kill switch است.
7. هر بخش حداقل ۳ تست با جزئیات کامل دارد.
8. D9 صادقانه است.

## بخش ح — Critical Items (خلاصه اجرایی انتهای فایل) — ۵ مورد + چک‌لیست نهایی دیپلوی — ۶ مورد

Critical Items:
1. رفع باگ پروفایل بعد از رفرش — T-S19-1 pass
2. حذف بج‌های local/online از سرچ — T-S27-1 pass
3. کش فقط در تنظیمات (نه Explore) — T-S21-2 pass
4. عدم افشای توکن ربات — DAST pass
5. تست ۳۰ کاربر همزمان بدون خطا — k6/Locust pass

چک‌لیست نهایی دیپلوی:
1. همه تست‌های Unit/Integration/E2E/Security/Load/Regression
2. تست ۳۰ کاربر همزمان در محیط ایزوله
3. پوشش کد ≥ ۸۰٪
4. SAST/SCA/DAST بدون CVE بحرانی
5. گزارش تست کامل
6. بکاپ دیتابیس + Redis

---

## ترتیب اجرا (از دستور کاربر)

1. Critical Fixes: S71، S27، S72، S25/S52
2. S01..S16 + R01..R16
3. S17..S24
4. S25، S06، S11، S03
5. S07، S08، S22، S68، S70، S69، S05
6. S36..S64 (امنیت)
7. S26، S28..S35 (بار و مقیاس — تست ۳۰ کاربر)
8. D6، D7، D8، D9 و QA Checklist

## وضعیت نهایی (به‌روزرسانی مداوم)

- ✅ کامل‌شده: (در حال اجرا)
- ❌ BLOCKED: (در حال اجرا)
- ⏳ باقی‌مانده: ۹۰ بخش / ۴۴۷ تست / ۷۲ آیتم چک‌لیست
