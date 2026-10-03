# ربط الحسابات وبناء أول نسخة من ويندوز

بما أن عضوية Apple Developer وحساب GitHub مفعّلان، نبدأ بفحص التطبيق على جهاز Mac مستضاف. هذا الفحص لا يحتاج شهادات Apple، ويعطينا نتيجة بناء واختبارات حقيقية قبل تجهيز نسخة الآيفون الموقّعة.

## المرحلة الأولى: أول بناء عبر GitHub

1. حدّد حساب GitHub الذي سيملك المشروع ورابط مستودع جديد أو موجود. يُفضّل مستودع خاص؛ يجب أن تسمح إعداداته بتشغيل GitHub Actions وبناء macOS.
2. ضع محتويات مجلد المشروع في جذر المستودع، بما فيها `.github` و`project.yml`. لا ترفع ملفات التوقيع أو بيانات الشيكات.
3. شغّل **Build and test iPhone app** من تبويب Actions. يفحص المنطق الأساسي، ويبني تطبيق iPhone، ويشغّل اختبارات السجلات والتذكيرات وتجربة الإدخال على المحاكي.
4. نعالج أي خطأ فعلي في البناء أو الاختبارات، ثم ننتقل للتوقيع. نتيجة المحاكي لا تثبت عمل iCloud والكاميرا والبصمة والتنبيهات على هاتف مقفل.

المعلومة المطلوبة الآن: **اسم حساب GitHub ورابط المستودع**. إن كان الحساب غير مسجّل الدخول على الجهاز، أدخل كلمة المرور والتحقق بنفسك في صفحة GitHub. لا تُرسل كلمة المرور أو رمز التحقق في المحادثة.

## المرحلة الثانية: معرّفات التطبيق والتوقيع

من حساب Apple Developer نحتاج إلى:

| المعلومة | أين تُستخدم |
| --- | --- |
| Team ID المكوّن من عشرة محارف | توقيع التطبيق باسم فريقك |
| Bundle ID صريح وفريد ومسجّل لحسابك | هوية التطبيق؛ نستبدل `com.shekati.app` التجريبي |
| معرّف حاوية iCloud المسجّل للفريق | المزامنة الخاصة؛ نستبدل `iCloud.com.shekati.app` التجريبي |
| صلاحية Account Holder أو Admin | تسجيل المعرّفات والقدرات وملفات التوزيع |
| سجل تطبيق في App Store Connect بالـBundle ID نفسه | استقبال النسخة المرفوعة إلى TestFlight |

فعّل **iCloud مع CloudKit** و**Push Notifications** للمعرّف، واربط حاوية iCloud به قبل إنشاء ملف التوقيع. إذا تغيّرت القدرات لاحقًا، أعد إنشاء ملفات التوقيع. [تسجيل حاوية iCloud](https://developer.apple.com/help/account/identifiers/create-an-icloud-container)، [إعداد القدرات](https://developer.apple.com/help/account/identifiers/enable-app-capabilities).

التوزيع يحتاج **Apple Distribution certificate مع مفتاحها الخاص** بصيغة `.p12` وكلمة مرور، وملف **App Store Connect provisioning profile** مطابق للفريق والتطبيق والحاوية. ملف `.cer` وحده لا يحتوي المفتاح الخاص ولا يكفي للتوقيع. [ملف التوزيع لدى Apple](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).

يمكن تحضير المفتاح وطلب الشهادة CSR محليًا على ويندوز باستخدام OpenSSL المرفق مع Git for Windows. توجد أدوات مساعدة في `docs/windows/`، وهي لا تتصل بـApple أو GitHub:

```powershell
& .\docs\windows\New-SigningRequest.ps1 `
  -PrivateDirectory 'C:\Users\user\Documents\Shekati-Signing-Private' `
  -CommonName 'Shekati Distribution' -Email 'YOUR_ACTUAL_EMAIL'
```

تطلب الأداة كلمة مرور للمفتاح مباشرة داخل OpenSSL، وتحفظه مشفّرًا في مجلد خاص خارج المشروع. ارفع **CSR فقط** إلى صفحة إنشاء شهادة Apple Distribution، ثم نزّل شهادة `.cer`. لا تنشئ شهادة جديدة إذا كان لديك أصلًا `.p12` صالح مع مفتاحه الخاص.

لجمع الشهادة والمفتاح في `.p12`:

```powershell
& .\docs\windows\Export-SigningCertificate.ps1 `
  -PrivateKeyPath 'C:\Users\user\Documents\Shekati-Signing-Private\distribution.key.pem' `
  -CertificatePath 'C:\Users\user\Downloads\distribution.cer' `
  -OutputPath 'C:\Users\user\Documents\Shekati-Signing-Private\distribution.p12'
```

أدخل كلمة مرور المفتاح ثم كلمة مرور جديدة لتصدير `.p12` عند الطلب. الأداتان تحفظان الملفات محليًا فقط، وتمنعان استبدال الملفات الموجودة أو وضع الأسرار داخل مستودع التطبيق. تعليمات Apple الرسمية لإنشاء CSR تستخدم Keychain على Mac؛ الأدوات هنا بديل محلي يعتمد على [OpenSSL](https://docs.openssl.org/3.5/man1/openssl-genpkey/).

## المرحلة الثالثة: تهيئة iCloud ثم TestFlight

إنشاء الحاوية لا ينشئ مخطط سجلات التطبيق. قبل اختبار المزامنة في TestFlight نحتاج إلى تهيئة **Development schema** من النموذج الفعلي، ثم مراجعته واختيار **Deploy Schema Changes** في CloudKit Console. TestFlight يستخدم بيئة Production، التي لا تنشئ أنواع السجلات تلقائيًا. [تهيئة SwiftData لدى Apple](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices?changes=_8)، [نشر المخطط](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema).

مسار البناء الحالي لا يهيّئ هذا المخطط: المحاكي يعمل محليًا، ورفع TestFlight يستخدم Production. يلزم أولًا مسار تطوير موقّع على iPhone مسجّل أو جلسة Mac يمكن فيها تسجيل الدخول إلى iCloud وتشغيل تهيئة المخطط. هذا إجراء منفصل يُجهّز بعد نجاح أول بناء؛ لا نفترض أن شراء العضوية أو رفع نسخة أولى قد أنجزه.

عند اختيار مسار iPhone التطويري، نحتاج أيضًا إلى طراز الهاتف وإصدار iOS ومعرّف الجهاز **UDID** لتسجيله في فريقك، وشهادة Apple Development وملف تطوير يضم هذا الجهاز. هذه الملفات تختلف عن ملف App Store المستخدم في TestFlight. عند اختيار جلسة Mac، تسجّل الدخول إلى حساب iCloud بنفسك؛ لا نضع كلمة مرور Apple في GitHub Secrets.

بعد تجهيز المخطط، أضف أسرار التوقيع ومفتاح App Store Connect إلى بيئة GitHub باسم `testflight`. الأسماء الدقيقة والخطوات في [دليل البناء](BUILD.md). نحتاج أيضًا إلى **API Key ID وIssuer ID**؛ ملف `.p8` وكلمات المرور توضع مباشرة في GitHub Secrets، ولا تُرسل في المحادثة.

لنسخ ملف إلى الحافظة بصيغة base64 دون طباعته:

```powershell
& .\docs\windows\Copy-SigningFile.ps1 -Path 'C:\Users\user\Documents\Shekati-Signing-Private\distribution.p12'
```

الصقه مباشرة في الحقل المناسب في GitHub Secrets، ثم امسح الحافظة بالأداة نفسها مع `-Clear`. كرّر لملف `.mobileprovision` و`.p8`. لا ترسل ملفات التوقيع أو كلمات مرورها ولا تضفها إلى Git.

شغّل **Upload manually to TestFlight** بالمعرّفات الفعلية ورقم بناء جديد. يعيد فحص التطبيق قبل التوقيع والرفع. بعد معالجة Apple للنسخة، نختبرها على الآيفون. الرفع لا ينشر التطبيق للعامة؛ سعر التنزيل **9.99 دولار** وسياسة الخصوصية والدعم ومراجعة المتجر تُجهَّز في مرحلة الإطلاق.
