# التحقق من جاهزية CloudKit واشتراك شيكاتي بلس

## نقطة الأساس

في 20 نوفمبر 2026 أعاد App Store Connect، بفحص GET لسجل التطبيق 6818852973، البناء المحدد 9 بحالة `VALID` والإصدار 1.0.0 بحالة `PENDING_DEVELOPER_RELEASE`. أعادت مجموعات الاشتراكات قائمة فارغة وHTTP 200. أعاد كل من سعر التطبيق والإتاحة HTTP 403 للحساب المستخدم، لذلك يلزم فحصهما من واجهة App Store Connect بصلاحية مناسبة. حالة اتفاقية التطبيقات المدفوعة والضرائب والحساب البنكي تحتاج تحققًا من صاحب الحساب.

مصدر بناء 9 الذي شُحن هو `7664b5d89d4212bb46b6a92ebeaca5b31cc2b5d0`. ثبّت ملف التشغيل ذلك الـcommit صراحةً. التغيير الوحيد بينه وبين `2e675efcb7e540df133d6ac9139f571f55a8f496` هو إضافة workflow الرفع. منطق الأرشيف ونموذج البيانات متطابقان بين المصدرين.

في فحص لاحق في اليوم نفسه، أظهرت واجهة App Store Connect أن تطبيق البناء 9 مسعّر بـ9.99 دولار أمريكي وأن 175 سوقًا مفعّلًا. أُنشئت مجموعة Shekati Plus برقم 22599559 والمنتجان الشهري 6837289550 والسنوي 6837290225. حُفظت أسعار الولايات المتحدة 4.99 و39.99 دولار ودرجات الأسعار المناظرة في 175 سوقًا، مع إتاحة الدفع السنوي مقدمًا. يُضبط التنزيل المجاني عند استبدال البناء وفق تسلسل الإصدار.

وأظهرت CloudKit Console في **Development وProduction** وجود `CD_AppConfiguration` مع 13 حقلًا و`CD_ChequeRecord` مع 47 حقلًا عند احتساب حقول النظام. لم تكن أنواع الحسابات والدفاتر والأحداث موجودة حينها.

## التغيير المتوقع في مخطط الحاوية

الحاوية الخاصة هي `iCloud.com.mf103871.shekati`. توثّق لقطة 4 أكتوبر إضافة `CD_deletedAt` وفهرسيه للمخطط التاريخي والتكافؤ يومها بين Development وProduction. قائمة الإنتاج الحية لهذا المرشح لم تُفحص هنا. يُقارن المصدر أدناه مع تصدير حي قبل اختبار TestFlight؛ قد تكون بعض الحقول موجودة أصلًا. يحتفظ `CD_AppConfiguration` بتعريفه السابق.

| نوع السجل | الحقول المطلوبة في المصدر |
|---|---|
| إضافة إلى `CD_ChequeRecord` | `bankAccountID` و`chequeBookID` و`replacesChequeID` من نوع UUID اختياري، و`ledgerBaselineStatusRaw` نص اختياري |
| `CD_BankAccountRecord` جديد | `id` UUID، و`name` و`currencyCode` نصان، و`openingMinor` Int64، و`createdAt` Date |
| `CD_ChequeBookRecord` جديد | `id` و`accountID` من نوع UUID، و`name` نص |
| `CD_LedgerEventRecord` جديد | `id` UUID، و`parentID` و`chequeID` و`accountID` و`relatedID` من نوع UUID اختياري، و`kindRaw` و`dayISO` و`party` و`currencyCode` نصوص، و`amountMinor` Int64 |

في تصدير CloudKit تبدأ أسماء الخصائص بـ`CD_`. ترسل طبقة Core Data حقولًا مساعدة وفهارس ونسخًا من بعض الحقول لتخزين الأصول. المرجع النهائي للتغييرات المادية هو نتيجة التهيئة من نموذج المرشح وفارق CloudKit Console. جدول المصدر يغطي 22 خاصية منطقية إضافية، ولا يُستخدم لاستيراد مخطط يدوي.

1. شغّل من جذر المستودع `python Tools/SchemaBootstrap/verify_ledger_schema.py` على نسخة Git تحتوي تاريخ بناء 9. يطابق الحقول القديمة والجديدة ويؤكد تسجيل الكيانات الخمسة في التطبيق وأداة التهيئة.
2. من Mac لديه صلاحية قراءة مخطط الحاوية عبر CloudKit Console أو cktool، صدّر schema لكل من development وproduction. ضع التصديرات خارج المستودع. لا يتطلب هذا الفحص قراءة سجل شيك من قاعدة مستخدم. مثال للقراءة باستخدام جلسة سبق تجهيزها:

   ```sh
   xcrun cktool export-schema --team-id "$TEAM_ID" --container-id iCloud.com.mf103871.shekati --environment development --output-file "$SCHEMA_DIR/development.ckdb"
   xcrun cktool export-schema --team-id "$TEAM_ID" --container-id iCloud.com.mf103871.shekati --environment production --output-file "$SCHEMA_DIR/production.ckdb"
   python3 Tools/SchemaBootstrap/verify_ledger_schema.py --export "$SCHEMA_DIR/development.ckdb"
   python3 Tools/SchemaBootstrap/verify_ledger_schema.py --export "$SCHEMA_DIR/production.ckdb"
   ```

3. إذا كانت حقول مرشح الاختبار ناقصة في Development، يبني مسؤول الإصدار هدف SchemaBootstrap من **نفس commit** على جهاز اختبار مسجّل، ثم يراجع نتيجة **Start setup**. تشغيلها ينشئ سجلات مؤقتة ويزيلها. إذا كانت حزمة الهدف المطوّر تطابق حزمة التطبيق، فتركيبها يستبدل التطبيق المثبّت على الجهاز. اختَر جهاز اختبار، أو هوية هدف إعداد مسجلة ومصرّحًا لها بالحاوية بشكل مستقل.
4. بعد نجاح اختبار Development، راجع في CloudKit Console أسماء الأنواع والحقول والفهارس الفعلية وسجل عدم حذف حقول تاريخية. إذا كانت Production تنقصها الإضافات، ينفّذ مسؤول يملك صلاحية الإنتاج **Deploy Schema Changes**، ثم يعيد تصديرها وفحصها. احتفظ برقم البناء ومراجع الدليل ووقت التحقق. توقيع الأرشيف أو نجاح رفعه إلى Apple لا ينفّذ هذه الخطوة.
5. افتح TestFlight على الجهاز بحساب iCloud اختباري وiCloud Drive مفعّل. تحقّق أن المزامنة تعمل وليست في الوضع المحلي الاحتياطي. سجّل حركة تجريبية، راقب تصديرها، ثم استوردها على عميل ثانٍ لإثبات الاتجاه المقابل وعدم تكرار الرصيد. إشارة «تمت المزامنة» على جهاز واحد دليل محدود على حالة ذلك الجهاز.

[تهيئة نماذج SwiftData](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) · [نشر مخطط CloudKit](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema) · [مرجع تصدير cktool](https://developer.apple.com/icloud/ck-tool/)

## مشتريات Apple

- يتأكد صاحب الحساب من سريان اتفاقية Paid Apps Agreement واكتمال المتطلبات المالية المطلوبة للحساب. يُراجع سعر تنزيل التطبيق العالمي المجاني ببيانات حساب مخوّل.
- يُنشئ مدير التطبيق مجموعة اشتراك واحدة للمنتجين `com.mf103871.shekati.plus.monthly` و`com.mf103871.shekati.plus.annual` بالترتيب الخدمي نفسه، مع 4.99 دولار شهريًا و39.99 دولار سنويًا كسعر أمريكي أساسي، وتحديد الأسواق والترجمات وبيانات المراجعة واللقطة المطلوبة ومن دون عروض تمهيدية.
- بعد انتشار الإعدادات، يجب أن يعيد StoreKit المنتجين وأسعارهما المحلية من App Store Connect على الهاتف. اختبار ملف StoreKit المحلي يفحص المنطق في بيئة Xcode. عبر TestFlight تتم عمليات الشراء والتجديد والاستعادة والانتهاء في **Sandbox من Apple** ببيانات المنتج الحقيقية ومن دون خصم أموال. الدفع المالي الحقيقي يتم من النسخة العامة فقط، بعد قبول المنتجات وتفعيلها في السوق المستهدف. يُرفق الاشتراكان ومجموعتهما مع أول نسخة للمراجعة.
- سجّل نتائج اشتراك فعّال، وتجديد أو استعادة، وانتهاء أو استرداد، ووصول المستخدم لبياناته بعد انتهاء الاشتراك. استخدم الحساب التجريبي وامنع ظهور أي إيصال أو معرف شخصي في الأدلة المشتركة.

[متطلبات الاتفاقية واختبار المشتريات](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases/) · [StoreKit Sandbox وTestFlight](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) · [إرسال أول اشتراك مع الإصدار](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)

## آيفون واحد ومحاكي Mac

يمكن لهاتف واحد معزول فحص استعادة الأرشيف، والتحديث الموضعي، والكاميرا، وقفل الشاشة، والتنبيهات، وشراء واستعادة اشتراك TestFlight التجريبي. إصدار المحاكي الحالي يستخدم `cloudKitDatabase: .none`، وكذلك مخزن اختبارات الواجهة. يمكن على Mac اختبار تبادل بيانات Development بين هاتف بناء تطوير ومحاكي فقط عند تجهيز نسخة Debug تسمح صراحةً بـCloudKit في المحاكي، وتسجيل الدخول لحساب iCloud الاختباري نفسه، والتأكد أن العميلين يتصلان بنفس حاوية وبيئة Development. يُفحص الاستيراد في الواجهة الأمامية مع مراعاة فروق إشعارات الخلفية في المحاكي وإصدار النظام. اختبار محاكي Development لا يطابق TestFlight الذي يستخدم Production. التحقق النهائي لمزامنة TestFlight وتعارض تعديلين على جهازين يستلزم عميلَي Production، ويفضَّل آيفونان فعليان على حساب الاختبار نفسه.

[تفعيل iCloud على جهاز أو محاكي](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)
