import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

typedef Json = Map<String, dynamic>;

final NumberFormat _grouping = NumberFormat('#,##0', 'en_US');

/// مفتاح فريد لمنع تكرار الترحيل (يُنشأ مرة لكل نموذج)
String newKey() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

double toD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

/// تنسيق قيمة للعرض: أرقام عشرية بفواصل آلاف، وبوليان نعم/لا.
String fmtCell(dynamic v) {
  if (v == null) return '';
  if (v is bool) return v ? 'نعم' : 'لا';
  final s = v.toString();
  final m = RegExp(r'^(-?)(\d+)\.(\d+)$').firstMatch(s);
  if (m != null) {
    final intPart = _grouping.format(int.parse(m.group(2)!));
    var frac = m.group(3)!;
    // الكميات تأتي بأربع خانات (5.0000): نحذف الأصفار الزائدة لتُقرأ 5 وليس 5,000. المبالغ (خانتان) تبقى كما هي.
    if (frac.length > 2) {
      frac = frac.replaceFirst(RegExp(r'0+$'), '');
    }
    return frac.isEmpty ? '${m.group(1)}$intPart' : '${m.group(1)}$intPart.$frac';
  }
  return s;
}

/// كمية للعرض: 5.0000 → 5، 2.5000 → 2.5
String fmtQty(dynamic v) {
  if (v == null) return '0';
  final s = v.toString();
  final m = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(s);
  if (m == null) return s;
  final frac = (m.group(3) ?? '').replaceFirst(RegExp(r'0+$'), '');
  final intPart = _grouping.format(int.parse(m.group(2)!));
  return frac.isEmpty ? '${m.group(1)}$intPart' : '${m.group(1)}$intPart.$frac';
}

List<Json> asList(dynamic v) {
  if (v is Map && v['data'] is List) v = v['data']; // نتائج مقسّمة (paginate)
  if (v is! List) return <Json>[];
  return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Colors.red.shade700 : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

Future<bool> confirm(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم')),
      ],
    ),
  );
  return r ?? false;
}

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'تعذّر فتح الرابط.', error: true);
}

/// حفظ بيانات CSV في مجلد التنزيلات وإرجاع المسار.
Future<String> saveDownload(String name, List<int> bytes) async {
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

// ── اختيار عنصر من قائمة (مع بحث) ──────────────────────────────────────────

Future<Json?> pickOne(BuildContext context, String title, List<Json> options, String Function(Json) label) {
  return showDialog<Json>(
    context: context,
    builder: (ctx) {
      String q = '';
      return StatefulBuilder(builder: (ctx, setS) {
        final shown = options.where((o) => label(o).toLowerCase().contains(q.toLowerCase())).take(200).toList();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            height: 420,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث'),
                onChanged: (v) => setS(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('لا توجد نتائج'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => ListTile(dense: true, title: Text(label(shown[i])), onTap: () => Navigator.pop(ctx, shown[i])),
                      ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء'))],
        );
      });
    },
  );
}

/// حقل يعرض اختيارًا ويفتح قائمة بحث عند الضغط.
class PickerField extends StatelessWidget {
  final String label;
  final String? valueText;
  final VoidCallback onTap;
  const PickerField({super.key, required this.label, required this.valueText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
        child: Text(valueText ?? 'اختر...', style: TextStyle(color: valueText == null ? Colors.grey : null)),
      ),
    );
  }
}

// ── نموذج إدخال عام ───────────────────────────────────────────────────────

class FieldSpec {
  final String key;
  final String label;
  final String type; // text | number | date | picker | multiline
  final List<Json> options; // للـ picker: {'value':..., 'label':...}
  final String? initial;
  final bool required;
  const FieldSpec(this.key, this.label, {this.type = 'text', this.options = const [], this.initial, this.required = true});
}

Future<Map<String, String>?> showForm(BuildContext context, String title, List<FieldSpec> fields, {String submitLabel = 'حفظ'}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      final controllers = <String, TextEditingController>{};
      final picked = <String, String>{};
      final pickedLabel = <String, String>{};
      for (final f in fields) {
        controllers[f.key] = TextEditingController(text: f.type == 'date' ? (f.initial ?? today()) : (f.initial ?? ''));
        if (f.type == 'picker' && f.initial != null) {
          picked[f.key] = f.initial!;
          for (final o in f.options) {
            if (o['value'].toString() == f.initial) pickedLabel[f.key] = o['label'].toString();
          }
        }
      }
      String? error;
      return StatefulBuilder(builder: (ctx, setS) {
        Widget build(FieldSpec f) {
          switch (f.type) {
            case 'picker':
              return PickerField(
                label: f.label,
                valueText: pickedLabel[f.key],
                onTap: () async {
                  final r = await pickOne(ctx, f.label, f.options, (o) => o['label'].toString());
                  if (r != null) {
                    setS(() {
                      picked[f.key] = r['value'].toString();
                      pickedLabel[f.key] = r['label'].toString();
                    });
                  }
                },
              );
            case 'date':
              return TextField(
                controller: controllers[f.key],
                readOnly: true,
                decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.calendar_today)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.tryParse(controllers[f.key]!.text) ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) controllers[f.key]!.text = DateFormat('yyyy-MM-dd').format(d);
                },
              );
            case 'number':
              return TextField(
                controller: controllers[f.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: f.label),
              );
            case 'multiline':
              return TextField(
                controller: controllers[f.key],
                maxLines: 3,
                decoration: InputDecoration(labelText: f.label),
              );
            default:
              return TextField(controller: controllers[f.key], decoration: InputDecoration(labelText: f.label));
          }
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final f in fields) Padding(padding: const EdgeInsets.only(top: 10), child: build(f)),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final out = <String, String>{};
                for (final f in fields) {
                  final v = f.type == 'picker' ? (picked[f.key] ?? '') : controllers[f.key]!.text.trim();
                  if (f.required && v.isEmpty) {
                    setS(() => error = 'الحقل «${f.label}» مطلوب.');
                    return;
                  }
                  if (f.type == 'number' && v.isNotEmpty && double.tryParse(v) == null) {
                    setS(() => error = 'الحقل «${f.label}» يجب أن يكون رقمًا.');
                    return;
                  }
                  out[f.key] = v;
                }
                Navigator.pop(ctx, out);
              },
              child: Text(submitLabel),
            ),
          ],
        );
      });
    },
  );
}

// ── تحميل بيانات مع إعادة المحاولة ─────────────────────────────────────────

class Loader extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext context, dynamic data, Future<void> Function() reload) builder;
  const Loader({super.key, required this.load, required this.builder});

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late Future<dynamic> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  Future<void> reload() async {
    setState(() {
      _f = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off, size: 44, color: AppColors.danger),
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(s.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger))),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ]),
          );
        }
        return widget.builder(c, s.data, reload);
      },
    );
  }
}

// ── جدول تقرير بالشكل الموحّد {title, columns, rows, totals, meta} ─────────

const Map<String, String> _totalLabels = {
  'revenue': 'الإيرادات', 'expenses': 'المصروفات', 'net_profit': 'صافي الربح', 'assets': 'الأصول', 'liabilities': 'الالتزامات',
  'equity': 'حقوق الملكية', 'net_payable': 'صافي الضريبة (موجب = مستحقة للمصلحة)', 'closing': 'الرصيد الختامي', 'balance': 'الإجمالي',
  'value': 'القيمة', 'qty': 'الكمية', 'in': 'الوارد', 'out': 'المنصرف', 'remaining_qty': 'إجمالي المتبقي', 'remaining_value': 'إجمالي القيمة',
  'gross': 'الإجمالي', 'returns': 'المرتجعات', 'net': 'الصافي', 'tax': 'الضريبة', 'cogs': 'التكلفة', 'profit': 'الربح', 'total': 'الإجمالي',
  'current': 'غير مستحق', 'd1_30': '1-30', 'd31_60': '31-60', 'd61_90': '61-90', 'd90_plus': '+90',
};

class ReportTable extends StatelessWidget {
  final Json report;
  const ReportTable({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final cols = Map<String, dynamic>.from((report['columns'] as Map?) ?? {});
    final keys = cols.keys.toList();
    final allRows = asList(report['rows']);
    final rows = allRows.length > 300 ? allRows.sublist(0, 300) : allRows;
    final totals = report['totals'] is Map ? Map<String, dynamic>.from(report['totals'] as Map) : <String, dynamic>{};
    final meta = report['meta'] is Map ? Map<String, dynamic>.from(report['meta'] as Map) : <String, dynamic>{};

    final chips = <Widget>[];
    totals.forEach((k, v) {
      chips.add(Chip(label: Text('${cols[k] ?? _totalLabels[k] ?? k}: ${fmtCell(v)}')));
    });
    meta.forEach((k, v) {
      if (v is bool) {
        chips.add(Chip(
          avatar: Icon(v ? Icons.check_circle : Icons.error, color: v ? Colors.green : Colors.red, size: 18),
          label: Text(k == 'balanced' ? 'متوازن' : k == 'matches_gl' ? 'مطابق للأستاذ' : k),
        ));
      }
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Wrap(spacing: 8, runSpacing: 4, children: chips)),
      if (meta['note'] != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(meta['note'].toString(), style: const TextStyle(color: Colors.orange))),
      if (allRows.length > 300)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('معروض أول 300 صف من ${allRows.length}. استخدم «تصدير Excel» للباقي.', style: const TextStyle(color: Colors.orange))),
      if (rows.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد بيانات.'))
      else
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 22,
                columns: [for (final k in keys) DataColumn(label: Text(cols[k].toString()))],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [for (final k in keys) DataCell(Text(fmtCell(r[k])))]),
                ],
              ),
            ),
          ),
        ),
    ]);
  }
}

/// شريط عنوان صفحة مع أزرار
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Flexible(
          flex: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
          ]),
        ),
        const SizedBox(width: 16),
        Flexible(
          flex: 5,
          child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
        ),
      ]),
    );
  }
}

String partyTypeLabel(String t) => t == 'customer' ? 'عميل' : 'مورد';

const Map<String, String> invoiceTypeLabels = {
  'sales': 'فاتورة بيع', 'purchase': 'فاتورة شراء', 'sales_return': 'مرتجع مبيعات', 'purchase_return': 'مرتجع مشتريات',
};


// ── نظام التصميم ──────────────────────────────────────────────────────────

class AppColors {
  static const Color brand = Color(0xFF0E7C86);
  static const Color navy = Color(0xFF0F2A3D);
  static const Color bg = Color(0xFFF3F5F8);
  static const Color border = Color(0xFFE3E8EF);
  static const Color muted = Color(0xFF6B7785);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFED6C02);
  static const Color danger = Color(0xFFC62828);
}

String fmtMoney(dynamic v) => '${fmtCell(v ?? '0.00')} ج.م';

/// لوحة بيضاء بحواف ناعمة (بطاقة محتوى)
class Panel extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const Panel({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy))),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ]),
      ),
    );
  }
}

/// بطاقة مؤشر رقمي (قابلة للضغط للانتقال للشاشة المرتبطة)
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  final VoidCallback? onTap;
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color = AppColors.brand, this.hint, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(height: 3),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy)),
                if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, this.color = AppColors.brand});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: Colors.black26),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(color: AppColors.muted)),
      ]),
    );
  }
}

/// رسم أعمدة بسيط (بدون مكتبات) لعرض اتجاه شهري
class BarChartMini extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  const BarChartMini({super.key, required this.values, required this.labels, this.color = AppColors.brand});

  String _short(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}م';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}ك';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 200,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(_short(values[i]), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                const SizedBox(height: 4),
                Container(
                  height: maxV <= 0 ? 2 : (130 * values[i] / maxV).clamp(2.0, 130.0).toDouble(),
                  decoration: BoxDecoration(color: i == values.length - 1 ? color : color.withValues(alpha: 0.45), borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}
