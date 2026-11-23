# تطبيق ERP المصنع — Flutter (ويندوز)

## التشغيل (على جهاز ويندوز عليه Flutter و Visual Studio بحزمة "Desktop development with C++")
```
flutter create --platforms=windows --org com.factory --project-name factory_erp .
flutter pub get
flutter run -d windows
```
> الأمر الأول يولّد مجلد `windows/` فقط ولا يمسّ `lib/` ولا `pubspec.yaml` (لو سألك عن استبدال pubspec.yaml اختر الإبقاء على الموجود).

عند أول تشغيل: اكتب عنوان السيرفر (مثال `http://192.168.1.10:8000` أو دومين المصنع) ثم بريد المستخدم وكلمة المرور.

## بناء نسخة للتسليم
```
flutter build windows --release
```
الناتج في `build/windows/x64/runner/Release/` (انسخ المجلد كله على جهاز المحاسب).

## ملاحظات
- التطبيق لا يحسب أي رقم مالي بنفسه؛ كل الحسابات من السيرفر (الأرقام المعروضة قبل الحفظ تقديرية فقط).
- الطباعة تفتح صفحة A4 عربية في المتصفح (طباعة أو «حفظ كـ PDF»).
- تصدير التقارير يحفظ ملف CSV في مجلد «التنزيلات» ويُفتح بـ Excel.
- الصلاحيات تُخفي الشاشات حسب دور المستخدم (محاسب / صاحب المصنع) والسيرفر يتحقق منها أيضًا.

## السرعة
- وضع التطوير (debug) على الويب بطيء بطبيعته. للتجربة السريعة استخدم: `flutter run -d chrome --release` (أو `flutter run -d macos --release`).
- السيرفر: `PHP_CLI_SERVER_WORKERS=4 php artisan serve --port=8000` يخليه يخدم أكتر من طلب في نفس الوقت.
- التقارير الكبيرة تعرض أول 300 صف في الشاشة؛ التصدير إلى Excel يحتوي كل الصفوف.

## التصميم
تصميم موحّد (ألوان، أزرار، حقول، جداول) في `lib/core/theme.dart` ومكوّنات في `lib/core/util.dart` (Panel, StatCard, Pill, EmptyState, PageHeader).
قائمة جانبية مجمّعة قابلة للتصغير، لوحة تحكم بمؤشرات ورسم مبيعات وتنبيهات قابلة للضغط، وشاشة دخول حديثة.
