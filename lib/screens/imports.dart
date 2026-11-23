import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// استيراد جماعي من Excel/CSV: انسخ الجدول من Excel والصقه هنا (أو اكتب مسار ملف CSV). معاينة ثم اعتماد.
/// الاستيراد كله أو لا شيء، وأي خطأ يظهر برقم السطر.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  static const _kinds = {
    'products': 'منتجات تامة + رصيدها',
    'materials': 'خامات ومستلزمات + رصيدها',
    'parties': 'عملاء وموردين + أرصدتهم',
  };
  static const _templates = {
    'products': 'product_type\tsize\tcolor\tfabric\tsale_price\twholesale_price\tqty\tunit_cost\nاسكراب\tM\tأزرق\tقطن\t300\t250\t10\t120',
    'materials': 'name\tkind\tunit\ttracks_rolls\tfabric_type\tcolor\trolls\tqty\tunit_cost\nقماش قطن أزرق\traw\tمتر\tنعم\tقطن\tأزرق\t101=120;102=95\t\t50\nزرار\tsupply\tقطعة\t\t\t\t\t500\t0.5',
    'parties': 'type\tname\tphone\taddress\tcredit_limit\tpayment_terms_days\tprice_level\topening_balance\nعميل\tمستشفى النور\t0100\t\t50000\t30\tجملة\t5000\nمورد\tمصنع الأقمشة\t0111\t\t\t\t\t2000',
  };
  static const _help = {
    'products': 'الأعمدة المطلوبة: product_type, size, color, fabric. اختيارية: sale_price, wholesale_price, qty, unit_cost (التكلفة مطلوبة لو في كمية). الصنف الموجود لا يتكرر ولا يُضاف له رصيد ثانٍ.',
    'materials': 'kind = raw أو supply. unit = متر/قطعة/كيلو. القماش بالرولات: tracks_rolls = نعم، وعمود rolls بصيغة 101=120;102=95 (رقم الرول=الطول).',
    'parties': 'type = عميل أو مورد. opening_balance موجب = مستحق لنا على العميل / مستحق للمورد علينا.',
  };

  String _kind = 'products';
  final _text = TextEditingController();
  final _path = TextEditingController();
  final _date = TextEditingController(text: today());
  Json? _wh;
  bool _createTypes = false;
  bool _busy = false;
  Json? _result;
  String? _error;
  String? _fileB64;
  String? _fileName;

  @override
  void dispose() {
    _text.dispose();
    _path.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      var p = _path.text.trim();
      if (p.length > 1 && (p.startsWith('"') || p.startsWith("'"))) p = p.substring(1, p.length - 1);
      final f = File(p);
      if (!await f.exists()) return toast(context, 'الملف غير موجود. اكتب المسار كاملًا (ملف Excel أو CSV).', error: true);
      final bytes = await f.readAsBytes();
      if (bytes.length > 12 * 1024 * 1024) return toast(context, 'الملف كبير (أكثر من 12 ميجا). قسّمه.', error: true);
      final isXlsx = bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;
      setState(() {
        _result = null;
        _error = null;
        if (isXlsx) {
          _fileB64 = base64Encode(bytes);
          _fileName = p.split(RegExp(r'[\\/]')).last;
          _text.clear();
        } else {
          _fileB64 = null;
          _fileName = null;
          _text.text = utf8.decode(bytes, allowMalformed: true);
        }
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذّرت قراءة الملف. احفظه CSV بترميز UTF-8 أو الصق محتواه مباشرة.', error: true);
    }
  }

  Future<void> _run(bool dry) async {
    final s = context.read<Session>();
    if (_fileB64 == null && _text.text.trim().isEmpty) return toast(context, 'الصق البيانات أو حمّل ملف Excel أولًا.', error: true);
    if (_kind != 'parties' && _wh == null) return toast(context, 'اختر المخزن.', error: true);
    if (!dry && !await confirm(context, 'سيتم الاعتماد وتسجيل الأرصدة في المحاسبة والمخزون. متأكد إنك عملت معاينة وراجعتها؟')) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await s.api.post('/import/$_kind', {
        if (_fileB64 != null) 'file_base64': _fileB64 else 'text': _text.text, 'dry_run': dry, 'date': _date.text, if (_kind != 'parties') 'warehouse_id': _wh!['id'], 'create_types': _createTypes,
      }) as Map<String, dynamic>;
      s.invalidateMeta();
      if (!mounted) return;
      setState(() => _result = r);
      if (!dry) {
        _text.clear();
        _fileB64 = null;
        _fileName = null;
        toast(context, 'تم الاستيراد والاعتماد.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _labels = {
    'items_created': 'أصناف جديدة', 'items_existing': 'أصناف موجودة من قبل', 'prices_updated': 'أسعار تم تحديثها', 'opening_skipped': 'أرصدة متجاهلة (الصنف له رصيد سابق)',
    'opening_lines': 'بنود رصيد افتتاحي', 'opening_qty': 'إجمالي الكمية', 'opening_value': 'إجمالي القيمة', 'opening_document': 'رقم مستند الرصيد',
    'parties_created': 'أطراف جديدة', 'parties_existing': 'أطراف موجودة من قبل', 'opening_total_receivable': 'إجمالي مستحق لنا على العملاء', 'opening_total_payable': 'إجمالي مستحق للموردين علينا',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return FutureBuilder<Map<String, dynamic>>(
      future: s.meta(),
      builder: (context, snap) {
        final whs = snap.hasData ? asList(snap.data!['warehouses']) : <Json>[];
        return ListView(padding: const EdgeInsets.all(16), children: [
          const PageHeader('استيراد جماعي', subtitle: 'انسخ جدول Excel والصقه — بدل إدخال الأصناف والأرصدة واحد واحد'),
          Panel(
            title: '1) نوع الاستيراد',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, children: [
                for (final e in _kinds.entries)
                  ChoiceChip(label: Text(e.value), selected: _kind == e.key, onSelected: (_) => setState(() {
                        _kind = e.key;
                        _result = null;
                        _error = null;
                        _wh = null;
                      })),
              ]),
              const SizedBox(height: 8),
              Text(_help[_kind]!, style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.download),
                label: const Text('تنزيل قالب Excel جاهز'),
                onPressed: () async {
                  try {
                    final r = await context.read<Session>().api.get('/import/$_kind/template-url');
                    if (mounted) await openUrl(context, r['url'].toString());
                  } catch (e) {
                    if (mounted) toast(context, e.toString(), error: true);
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('نسخ صف العناوين + مثال (الصقه في Excel)'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _templates[_kind]!));
                  if (mounted) toast(context, 'تم النسخ. الصقه في Excel في الخلية A1 ثم املأ الصفوف.');
                },
              ),
              ]),
            ]),
          ),
          Panel(
            title: '2) الإعدادات',
            child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (_kind != 'parties')
                SizedBox(
                  width: 260,
                  child: PickerField(
                    label: 'المخزن اللي يُسجَّل فيه الرصيد',
                    valueText: _wh?['name']?.toString(),
                    onTap: () async {
                      final r = await pickOne(context, 'المخزن', whs, (w) => w['name'].toString());
                      if (r != null) setState(() => _wh = r);
                    },
                  ),
                ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _date,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'تاريخ الرصيد الافتتاحي', suffixIcon: Icon(Icons.calendar_today)),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(_date.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setState(() => _date.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
                  },
                ),
              ),
              if (_kind == 'products')
                FilterChip(label: const Text('إنشاء أنواع المنتجات الناقصة تلقائيًا'), selected: _createTypes, onSelected: (v) => setState(() => _createTypes = v)),
            ]),
          ),
          Panel(
            title: '3) البيانات',
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(controller: _path, decoration: const InputDecoration(labelText: 'أو مسار ملف Excel/CSV  مثال: C:\\data\\items.xlsx'))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _loadFile, child: const Text('تحميل الملف')),
              ]),
              if (_fileName != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Chip(avatar: const Icon(Icons.table_chart, size: 18), label: Text('ملف Excel محمّل: $_fileName'), onDeleted: () => setState(() { _fileB64 = null; _fileName = null; _result = null; }))),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                onChanged: (_) {
                  if (_result != null && _result!['dry_run'] == true) setState(() => _result = null);
                },
                maxLines: 12,
                minLines: 8,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
                decoration: const InputDecoration(hintText: 'الصق هنا (Ctrl+V) الجدول المنسوخ من Excel، أول سطر = العناوين', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton.tonalIcon(onPressed: _busy ? null : () => _run(true), icon: const Icon(Icons.visibility), label: const Text('معاينة (بدون حفظ)')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: _busy || _result == null || _result!['dry_run'] != true ? null : () => _run(false), icon: const Icon(Icons.check), label: const Text('اعتماد الاستيراد')),
                if (_busy) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ]),
              const SizedBox(height: 4),
              const Text('زر الاعتماد يتفعّل بعد معاينة ناجحة. لو عدّلت البيانات بعد المعاينة اعمل معاينة تاني.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          if (_error != null)
            Panel(title: 'لم يُحفظ شيء — صحّح الأخطاء التالية', child: SelectableText(_error!, style: TextStyle(color: Colors.red.shade800))),
          if (_result != null)
            Panel(
              title: _result!['dry_run'] == true ? 'نتيجة المعاينة (لم يُحفظ شيء)' : 'تم الاعتماد',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in (_result!['summary'] as Map).entries) Text('${_labels[e.key] ?? e.key}:  ${fmtCell(e.value)}'),
              ]),
            ),
        ]);
      },
    );
  }
}
