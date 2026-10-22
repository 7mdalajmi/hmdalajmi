# ‫قائمة التجهيز للنشر — لقطة ⁦1.0⁩‬

‫كل بند هنا يحتاج حسابك أو جهازك، ولا يمكن إنجازه في المحاكي. الترتيب مهم: القسم 1، ثم 3، ثم 4، ثم 5.‬

## ‫1. أول تشغيل على الآيفون (ينشئ مخطط ⁦CloudKit⁩)‬

1. ‫وصّل الآيفون ⁦Hmdalajmi⁩ بالماك واختره من أعلى ⁦Xcode⁩، ثم ⁦Run⁩. يضيف ⁦Xcode⁩ صلاحيات ⁦iCloud⁩ و⁦Push⁩ إلى ملف التوقيع تلقائيًا.‬
2. ‫تأكد أن الآيفون مسجّل في ⁦iCloud⁩ وأن ⁦iCloud Drive⁩ مفعّل.‬
3. ‫في لقطة افتح ⁦Settings⁩، وفعّل ⁦iCloud Sync⁩، ثم ⁦Turn On⁩.‬
4. ‫انتظر في ⁦Console⁩ داخل ⁦Xcode⁩ سطر ⁦`cloud: development schema initialized`⁩. بهذا تنشئ نسخة ⁦Debug⁩ مخطط ⁦CloudKit⁩ كاملًا (كل أنواع السجلات وحقولها) في بيئة ⁦Development⁩، مرة واحدة لكل تغيير في النموذج.‬
5. ‫إذا ظهر ⁦`cloud: schema initialization failed`⁩، تأكد من الإنترنت وحساب ⁦iCloud⁩، ثم أوقف التطبيق وشغّله من ⁦Xcode⁩ مرة أخرى.‬

## ‫2. اختبارات على الجهاز‬

1. ‫مزامنة ⁦iCloud⁩ بين جهازين: فعّلها، أضف عنصرًا ومجلدًا على الأول وتأكد من ظهورهما على الثاني، ثم احذف وقفل مجلدًا وراقب التغيير.‬
2. ‫إيقاف المزامنة: تأكد أن الملفات تُنزّل قبل الإيقاف، وأن زر الإلغاء يعمل.‬
3. ‫النسخ الاحتياطي في ⁦iCloud: Back Up Now⁩، ثم استرجع على جهاز آخر، وجرّب الحذف والاحتفاظ بعدد النسخ.‬
4. ‫ملف النسخة الاحتياطية: احفظه في الملفات، وافتحه من تطبيق الملفات على جهاز آخر.‬
5. ‫العمل في الخلفية: اترك التطبيق مغلقًا ليلة كاملة والجهاز على الشاحن، وتأكد أن تاريخ آخر نسخة تحدّث، وأن النسخة الطويلة تعرض شريط التقدم من النظام.‬
6. ‫نص الكلام في الفيديو بالعربية والإنجليزية (⁦SpeechAnalyzer⁩ لا يعمل في المحاكي).‬
7. ‫حذف الأصل من الصور: صورة، وفيديو، وتسجيل شاشة، وصورة مكررة؛ وتأكد أن ⁦iOS⁩ يطلب التأكيد.‬
8. ‫⁦YouTube⁩: فيديو عادي، وفيديو خاص أو محذوف، ورابط قناة. ثم احفظ رابط فيديو بدون إنترنت، وتأكد أن العنوان والقناة والصورة تكتمل بعد عودة الاتصال.‬
9. ‫إضافة المشاركة مع 30 صورة دفعة واحدة، ومع فيديو كبير (حد الذاكرة 120 ميغابايت).‬
10. ‫⁦Face ID⁩: قفل المجلد وفتحه، وإخفاء المحتوى في مبدّل التطبيقات.‬
11. ‫إمكانية الوصول على الجهاز: ⁦VoiceOver⁩، وتكبير النص، والنص العريض، وتقليل الحركة والشفافية، وزيادة التباين.‬
12. ‫الآيباد: الشريط الجانبي، والسحب من الصور والملفات إلى المجلدات، واختصارات لوحة المفاتيح، وأحجام ⁦Stage Manager⁩.‬
13. ‫مساحة تخزين قليلة، وبدون إنترنت.‬

## ‫3. صفحات الخصوصية والدعم (منشورة)‬

‫نُشرت من مستودع ⁦laqta⁩ العام على ⁦GitHub Pages⁩، والملفات الأصلية في مجلد ⁦`AppStore/web`⁩، وبريد الدعم فيها ⁦`7mdalajmi@gmail.com`⁩.‬

```text
https://7mdalajmi.github.io/laqta/
https://7mdalajmi.github.io/laqta/privacy.html
https://7mdalajmi.github.io/laqta/support.html
```

‫الرابطان موضوعان في ⁦`Config/Laqta.xcconfig`⁩، فيظهر صف ⁦Support⁩ في الإعدادات وزر ⁦Open on the Web⁩ في شاشة الخصوصية.‬

‫يبقى عليك وضعهما في ⁦App Store Connect⁩: رابط الخصوصية في ⁦App Privacy⁩، ورابط الدعم في صفحة الإصدار.‬

‫لتحديث الصفحات لاحقًا: عدّل الملفات في ⁦`AppStore/web`⁩، ثم في صفحة المستودع اضغط ⁦Add file⁩ ثم ⁦Upload files⁩، وارفعها فوق القديمة.‬

## ‫4. مخطط ⁦CloudKit⁩ (منشور في ⁦Production⁩)‬

> ‫نُشر مرة ثانية في ⁦2026-09-18⁩ بعد إضافة ⁦`parentID`⁩: الحوار عرض «تعديل حقل واحد في ⁦CD_Folder⁩ وإنشاء 3 فهارس»، وبعد ⁦Deploy⁩ ظهر «⁦Changes Deployed⁩». تأكدنا أن ⁦`CD_parentID`⁩ موجود الآن في ⁦Production⁩.‬


‫نُشر في ⁦2026-09-18⁩ من لوحة ⁦CloudKit⁩ للحاوية ⁦`iCloud.Hmdalajmi.Laqta`⁩: النوعان ⁦`CD_Folder`⁩ (27 حقلًا بعد ⁦`parentID`⁩) و⁦`CD_Shot`⁩ (82 حقلًا) موجودان في ⁦Development⁩ و⁦Production⁩ بعد ⁦Deploy Schema Changes⁩، فالمزامنة تعمل في ⁦TestFlight⁩ و⁦App Store⁩.‬

‫بعد أي تغيير في النموذج: شغّل نسخة ⁦Debug⁩ على الآيفون مع ⁦iCloud Sync⁩ (ينشئ ⁦`CloudSchema`⁩ الحقول الجديدة في ⁦Development⁩)، ثم ⁦Deploy Schema Changes⁩ من جديد قبل رفع النسخة. مخطط ⁦Production⁩ إضافة فقط: لا يُحذف حقل ولا يتغير نوعه.‬

## ‫5. قبل الإرسال إلى ⁦App Store⁩‬

‫سجل التطبيق جاهز في ⁦App Store Connect⁩ باسم ⁦`The Laqta`⁩ (اسم ⁦Laqta⁩ وحده محجوز في المتجر)، ومعرّفه ⁦`Hmdalajmi.Laqta`⁩، ورابطا الخصوصية والدعم موضوعان فيه.‬

1. ‫وافق على ⁦Apple Developer Program License Agreement⁩ المحدّث من حساب ⁦Account Holder⁩، وأدخل حالة التاجر (⁦Trader Status⁩) المطلوبة للاتحاد الأوروبي، وإلا لا يقبل المتجر الإرسال.‬
2. ‫✅ الإصدار موحّد الآن: المشروع و⁦App Store Connect⁩ كلاهما ⁦1.0⁩ والبناء ⁦1⁩.‬
3. ‫أكمل صفحة الإصدار: الوصف والكلمات المفتاحية والنص الترويجي من ⁦`AppStore/Listing-en.md`⁩، والتصنيفان، وصور المتجر، وملاحظات المراجعة من ⁦`AppStore/ReviewNotes.md`⁩.‬
4. ‫من ⁦App Privacy⁩ اضغط ⁦Get Started⁩ واختر ⁦Data Not Collected⁩.‬
5. ‫أضف اللغة العربية في ⁦App Store Connect⁩ وانسخ نصوص ⁦`AppStore/Listing-ar.md`⁩، واسم التطبيق فيها لقطة.‬
6. ‫ارفع ⁦`CURRENT_PROJECT_VERSION`⁩ مع كل رفع، وارفع ⁦`MARKETING_VERSION`⁩ خطوة واحدة مع كل تحديث للمتجر: ⁦1.0⁩ ثم ⁦1.1⁩ ثم ⁦1.2⁩ وهكذا.‬
7. ‫من ⁦Xcode⁩ اختر ⁦Any iOS Device⁩ ثم ⁦Product → Archive⁩، وبعدها ⁦Distribute App → App Store Connect → Upload⁩.‬
8. ‫جرّب البناء عبر ⁦TestFlight⁩ داخليًا قبل طلب المراجعة، وتأكد أن المزامنة تعمل فيه.‬

## ‫6. الصور المطلوبة للمتجر‬

‫الصور جاهزة في مجلد ⁦AppStore/Screenshots⁩ بمقاس ⁦iPhone 6.9⁩ إنش (1320 × 2868) ومقاس ⁦iPad⁩ 13 إنش (2064 × 2752)، بالإنجليزية والعربية. ترتيب الرفع وملاحظاته في ملف ⁦README⁩ داخل المجلد.‬

‫قبل النشر يُفضَّل إعادة التصوير بصورك أنت بدل صور العينة التي تأتي مع المحاكي، وأجهّز لك الإطارات والعناوين من الصور الجديدة بنفس التصميم.‬

## ‫تحديث ⁦2026-09-18⁩‬

- ‫صور متجر جديدة ثنائية اللغة (إنجليزي + عربي في نفس الصورة) في ⁦`AppStore/Screenshots/Bilingual/`: `iPhone-6.7/01..10.png`⁩ بمقاس 1284×2778، و⁦`iPad-13/01..10.png`⁩ بمقاس 2048×2732. نفس المجموعة تصلح للوصف الإنجليزي والعربي.‬
- ‫أسماء المجلدات الافتراضية صارت إنجليزية: ⁦Travel · Perfume · Cities · Private⁩.‬

## ‫بيانات المتجر (أُدخلت في ⁦2026-09-18⁩)‬

- ‫⁦App Information⁩: الاسم ⁦The Laqta⁩، العنوان الفرعي ⁦`Shots, links & PDFs in folders`⁩، التصنيف ⁦Photo & Video⁩ ثم ⁦Productivity⁩، ⁦Content Rights⁩ «نعم مع الحقوق» (بسبب عناوين وصور ⁦YouTube⁩ ومعاينات الروابط)، ⁦Age Rating⁩ 4+ بعد الإجابة بلا على الأسئلة السبع.‬
- ‫الإصدار ⁦1.0⁩: النص الترويجي (159 حرفًا)، الوصف (2109 حرفًا، ويذكر المجلدات الفرعية وشريط الأيام)، الكلمات المفتاحية (97 حرفًا)، ⁦Support URL⁩ و ⁦Marketing URL⁩، حقوق النشر ⁦`2026 Hamad Alajmi`⁩. صور الآيفون ⁦6.5⁩ بوصة مرفوعة (10 من 10).‬
- App Privacy: Data Not Collected، ومنشور.
- ‫⁦Pricing and Availability⁩: مجاني ($⁦0.00⁩) في 175 دولة، والتوفر مضبوط على كل الدول.‬


## ‫التجربة والشراء (⁦2026-09-20⁩)‬

‫التطبيق مجاني التحميل، ويعمل كاملًا ⁦30⁩ يومًا. بعدها يبقى كل شيء محفوظًا ويُقرأ ويُصدَّر، ويتوقف إدخال الجديد (الحفظ من قائمة المشاركة، و⁦Import⁩، والمجلدات الجديدة) حتى يُشترى التطبيق مرة واحدة. هذا هو النمط الذي تقبله آبل: التطبيق لا يصبح معطّلًا بالكامل.‬

### ‫ما يجب إنشاؤه في ⁦App Store Connect⁩‬

‫**تم في ⁦2026-09-20⁩:** وقّع حمد ⁦Paid Apps Agreement⁩ من ⁦Business → Agreements⁩ وأضاف الحساب البنكي (⁦KWD⁩، قيد المعالجة ⁦24⁩ ساعة) وأكمل إقرار ⁦Digital Services Act⁩. حالة الاتفاقية الآن ⁦Pending User Info⁩ ولا تصير ⁦Active⁩ حتى يكتمل **نموذج الضرائب الأمريكي** (⁦U.S. Tax Questionnaire⁩ — حالته ⁦Missing Tax Info⁩، الزر ⁦Add Tax Info⁩ في نفس الصفحة) وتنتهي معالجة البنك.‬

‫ويُنصح بالتسجيل في ⁦App Store Small Business Program⁩ (حصتك ⁦85%⁩ بدل ⁦70%⁩).‬

‫**المنتج المطلوب واحد فقط** (⁦Apps → The Laqta → Distribution → Monetization → In-App Purchases⁩):‬

| ‫المعرّف‬ | ‫الاسم المرجعي‬ | ‫السعر‬ |
|---|---|---|
| ⁦Hmdalajmi.Laqta.unlock⁩ | ⁦Laqta (full app)⁩ | ⁦$0.99⁩ |

‫منتج التجربة ⁦Hmdalajmi.Laqta.trial30⁩ لم يعد مستخدمًا ولا يُرسل للمراجعة: الثلاثون يومًا تُحسب الآن من ⁦AppTransaction.originalPurchaseDate⁩، أي يوم أول تنزيل للتطبيق على حساب ⁦Apple⁩ نفسه، فلا نافذة شراء على تجربة مجانية ولا منتج بـ⁦$0.00⁩ في القائمة. إن كان المنتج موجودًا في ⁦App Store Connect⁩ فاتركه ⁦Prepare for Submission⁩ بلا إرسال، أو احذفه؛ والتطبيق يقرأ تاريخه إن وُجد لمن جرّب نسخة ⁦TestFlight⁩ سابقة.‬

‫المُدخل للمنتج: التوفّر (⁦175⁩ دولة)، والسعر، و⁦Display Name⁩ و⁦Description⁩ بالإنجليزية (⁦Laqta, Yours for Good — “One payment. Keep saving, forever.”⁩)، و⁦Review Notes⁩ تشرح نموذج التجربة.‬

‫**الناقص:** ⁦Review Screenshot⁩ للمنتج — لقطة لشاشة الشراء داخل التطبيق، تُؤخذ بعد أول تشغيل للنسخة الجديدة. بدونها لا يقبل الموقع الإرسال.‬

‫يُرسل مع أول ⁦Build⁩ من صفحة الإصدار (⁦In-App Purchases and Subscriptions → Select⁩) وإلا رُفض.‬

### ‫ملاحظات المراجعة (تُضاف إلى ⁦App Review Information⁩)‬

```
Laqta is free to download and fully functional for 30 days.
The 30 days are counted from the date this Apple Account first downloaded
the app (StoreKit's AppTransaction.originalPurchaseDate), so deleting and
reinstalling the app does not restart them. There is no trial in-app
purchase and nothing is charged during the trial.
After 30 days nothing is deleted: browsing, search, viewing and export all
keep working. Only adding new items pauses until the one-time $0.99
purchase. Restore Purchase is in Settings > Laqta and on the purchase screen.
```

### ‫الاختبار قبل الرفع‬

- ‫في المحاكي: ملف ⁦Config/Laqta.storekit⁩ مربوط بالمخطط (⁦Edit Scheme → Run → Options → StoreKit Configuration⁩). إن لم يظهر مربوطًا، اختره مرة واحدة من القائمة.‬
- ‫لتجربة انتهاء المدة: ⁦Debug → StoreKit → Manage Transactions⁩ لتغيير تاريخ ⁦App Transaction⁩، أو غيّر تاريخ المحاكي.‬
- ‫على جهاز حقيقي قبل النشر: ⁦Sandbox Apple Account⁩ من ⁦Users and Access → Sandbox Testers⁩.‬

### ‫ما زال مطلوبًا من حمد‬
- ‫⁦App Review Information⁩: خانة الاتصال والملاحظات ترفض الحفظ حاليًا (الخادم يرد 409 على ⁦POST⁩). غير مطلوبة لـ ⁦TestFlight⁩، وتُملأ بعد رفع أول ⁦Build⁩. ينقص أيضًا رقم الهاتف.‬
- ‫إكمال ⁦U.S. Tax Questionnaire⁩ من ⁦Business → Agreements → Tax Forms → Add Tax Info⁩ — آخر ما ينقص لتصير اتفاقية ⁦Paid Apps⁩ فعّالة.‬
- Digital Services Act (Trader Status) وقبول اتفاقية Apple Developer Program المحدَّثة — من حساب Account Holder.
- ‫رفع ⁦Build⁩ من ⁦Xcode (Archive → Upload⁩)، ثم اختيار البناء في صفحة الإصدار.‬
- ‫صور الآيباد (2048×2732) وصور ⁦6.9⁩ بوصة إن طلبها المتجر — جاهزة في ⁦`AppStore/Screenshots/Bilingual/`⁩.‬
- ‫الترجمة العربية للقائمة (لقطة) — النصوص جاهزة في ⁦`Listing-ar.md`⁩.‬
