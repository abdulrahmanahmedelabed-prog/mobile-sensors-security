# mvscan: كاشف الثغرات البرمجية في تطبيقات الجوال

فحص ساكن (static analysis) لتطبيقات أندرويد وiOS وFlutter وReact Native. يعمل بـ Python 3.10+ دون أي مكتبات.

```bash
python3 -m mvscan TARGET... [--format text|json|html] [-o FILE] [--min-severity LEVEL] [--fail-on LEVEL]
python3 -m mvscan --adb [--package NAME]... [--include-system]
```

| الخيار | المعنى |
|---|---|
| `TARGET` | مجلد مشروع، أو `.apk` / `.xapk` / `.apks` / `.ipa` |
| `--adb` | يسحب ملفات APK للتطبيقات المثبتة في جوال متصل بـ USB ويفحصها (ثم يحذفها) |
| `--format` | `text` (الافتراضي، بالعربية)، أو `json` للأدوات، أو `html` تقرير للمشاركة |
| `--min-severity` | لا يعرض ما هو أقل من هذه الخطورة: `info` و`low` و`medium` و`high` و`critical` |
| `--fail-on` | يُرجع رمز 1 إن وُجدت ثغرة بهذه الخطورة أو أعلى (لإيقاف البناء في CI) |

لتجاهل نتيجة راجعتها وتأكدت أنها ليست ثغرة، أضف التعليق `mvscan:ignore` على السطر نفسه مع سبب التجاهل.

## القواعد

| الرمز | الخطورة | الثغرة |
|---|---|---|
| MV-SEC-001 | حرجة | مفتاح خاص (private key) داخل التطبيق |
| MV-SEC-002 | عالية | مفتاح وصول AWS |
| MV-SEC-003 | متوسطة | مفتاح Google API (يجب تقييده) |
| MV-SEC-004 | عالية | رموز Stripe/Slack/GitHub/GitLab/Twilio/SendGrid |
| MV-SEC-005 | عالية | كلمة مرور أو سرّ مكتوب في الكود |
| MV-NET-001 | متوسطة | رابط `http://` أو `ws://` غير مشفّر |
| MV-NET-002 | عالية | TrustManager يقبل كل الشهادات |
| MV-NET-003 | عالية | HostnameVerifier يقبل أي اسم خادم |
| MV-NET-004 | عالية | `badCertificateCallback` يُرجع true في Dart |
| MV-NET-005 | عالية | WebView يستدعي `proceed()` على أخطاء SSL |
| MV-NET-006 | عالية | `rejectUnauthorized: false` في JS |
| MV-NET-007 | عالية | تجاوز التحقق من الشهادة في iOS |
| MV-NSC-001 | متوسطة | `cleartextTrafficPermitted` في network_security_config |
| MV-NSC-002 | متوسطة | الثقة بشهادات المستخدم في الإصدار |
| MV-WEB-001…006 | منخفضة إلى عالية | JavaScript في WebView، و`addJavascriptInterface`، والوصول لملفات `file://`، وتصحيح WebView، و`UIWebView`، و`eval` |
| MV-CRY-001…005 | منخفضة إلى عالية | MD5/SHA-1، وDES/RC4/ECB، والمفاتيح وIV الثابتة، وبذرة SecureRandom الثابتة، والعشوائية غير الآمنة |
| MV-STO-001…004 | منخفضة إلى عالية | ملفات `MODE_WORLD_*`، والتخزين الخارجي، والأسرار في SharedPreferences/UserDefaults، والحافظة |
| MV-INJ-001…004 | منخفضة إلى عالية | حقن SQL، وتنفيذ الأوامر، وتحميل الكود الديناميكي، وتجاوز المسار |
| MV-IPC-001…003 | منخفضة إلى متوسطة | PendingIntent القابل للتعديل، والبث المثبّت، ومستقبِل البث المكشوف |
| MV-LOG-001 | متوسطة | طباعة الأسرار في السجل |
| MV-MAN-001 | عالية | `debuggable="true"` |
| MV-MAN-002 | منخفضة إلى متوسطة | النسخ الاحتياطي مفعّل |
| MV-MAN-003 | منخفضة إلى متوسطة | `usesCleartextTraffic` |
| MV-MAN-004 | منخفضة إلى متوسطة | Activity/Service/Receiver مكشوف دون إذن (ومنه الكشف الضمني بسبب intent-filter) |
| MV-MAN-005 | عالية | ContentProvider مكشوف دون إذن |
| MV-MAN-006 | منخفضة | minSdk أقل من 23 |
| MV-MAN-007 | منخفضة | `testOnly` |
| MV-MAN-008 | متوسطة | أذونات عالية الخطورة (`SYSTEM_ALERT_WINDOW` و`REQUEST_INSTALL_PACKAGES` وغيرها) |
| MV-MAN-009 | معلومة | أذونات تصل إلى بيانات خاصة |
| MV-MAN-011 | منخفضة | روابط عميقة بمخطط مخصّص، أو https دون `autoVerify` |
| MV-GRD-001…003 | متوسطة إلى عالية | debuggable في Gradle، والتوقيع بمفتاح debug، وكلمات مرور التوقيع في ملف البناء |
| MV-APK-001 | متوسطة | ملف APK غير موقّع |
| MV-IOS-001…006 | معلومة إلى متوسطة | تعطيل ATS، واستثناءات HTTP، ومشاركة الملفات، ومخططات URL، والأذونات |

## حدود الأداة

الفحص الساكن يجد الأنماط المعروفة بسرعة، لكنه لا يغني عن مراجعة بشرية واختبار ديناميكي (مثل MobSF أو Frida).
قد تظهر نتائج خاطئة، وقد تفوته ثغرات في المنطق. وفي ملفات APK المُعمّاة لا تتوفر أرقام الأسطر.
تنسيق AAB (Google Play) غير مدعوم؛ افحص ملف APK بدلًا منه.

## الاختبارات

```bash
pip install pytest && python3 -m pytest -q
```
