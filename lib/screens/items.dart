import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const Map<String, String> kindLabels = {'raw': 'خامة', 'supply': 'مستلزم', 'finished': 'منتج تام', 'wip': 'تحت التشغيل', 'scrap': 'هالك/بواقي'};

List<String> _split(String x) => x.split(RegExp(r'[,،\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  String _q = '';
  String _kind = '';
  int _tick = 0;
  final Set<int> _sel = {};
  List<Json> _shown = [];

  List<Json> _opts(List<dynamic> list, String valueKey, String labelKey) =>
      list.map((e) => <String, dynamic>{'value': (e as Map)[valueKey], 'label': e[labelKey]}).toList();


  /// بعد إنشاء أصناف جديدة: يسأل عن الكمية الموجودة فعليًا ويسجّلها كرصيد افتتاحي (مخزون + قيد) في نفس الخطوة.
  Future<void> _askOpening(List<Json> items) async {
    if (items.isEmpty || !mounted) return;
    final s = context.read<Session>();
    if (!await confirm(context, 'تسجيل الكمية الموجودة فعليًا في المخزن لـ ${items.length} صنف دلوقتي؟\n\nلو اخترت «إلغاء» الرصيد هيفضل صفر، وفاتورة البيع هتعتبره غير متاح. تقدر تسجّله بعدين من «الأرصدة الافتتاحية».')) return;
    final meta = await s.meta();
    final whs = asList(meta['warehouses']);
    if (whs.isEmpty || !mounted) return;
    final wantType = items.first['kind'] == 'finished' ? 'finished' : 'raw';
    final def = whs.firstWhere((w) => w['type'] == wantType, orElse: () => whs.first);
    final head = await showForm(context, 'المخزن وتاريخ الرصيد', [
      FieldSpec('warehouse_id', 'المخزن', type: 'picker', initial: def['id'].toString(), options: [for (final w in whs) {'value': w['id'], 'label': w['name']}]),
      const FieldSpec('date', 'تاريخ الرصيد', type: 'date'),
    ]);
    if (head == null || !mounted) return;
    final lines = <Json>[];
    var skippedRolls = 0;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it['tracks_rolls'] == true) {
        skippedRolls++;
        continue;
      }
      final l = await showForm(context, '${it['name']}  (${i + 1} من ${items.length})', [
        const FieldSpec('qty', 'الكمية الموجودة (سيبها فاضية أو 0 للتخطي)', type: 'number', required: false),
        const FieldSpec('unit_cost', 'تكلفة الوحدة', type: 'number', required: false),
      ]);
      if (l == null) break; // إلغاء = توقف عن باقي الأصناف وسجّل اللي اتدخل
      final q = double.tryParse((l['qty'] ?? '').replaceAll(',', '')) ?? 0;
      if (q <= 0) continue;
      if ((double.tryParse((l['unit_cost'] ?? '').replaceAll(',', '')) ?? -1) < 0) {
        if (mounted) toast(context, 'اكتب تكلفة الوحدة لـ ${it['name']}. تم تخطيه.', error: true);
        continue;
      }
      lines.add({'item_id': it['id'], 'qty': l['qty'], 'unit_cost': l['unit_cost']});
    }
    if (!mounted) return;
    if (lines.isEmpty) {
      if (skippedRolls > 0) toast(context, 'الأقمشة بالرولات تُسجَّل من «الأرصدة الافتتاحية» (رقم وطول كل رول).');
      return;
    }
    try {
      await s.api.post('/stock-openings', {'warehouse_id': int.parse(head['warehouse_id']!), 'date': head['date'], 'notes': 'رصيد عند إضافة الصنف', 'lines': lines}, newKey());
      if (mounted) toast(context, 'تم تسجيل رصيد ${lines.length} صنف في المخزن.${skippedRolls > 0 ? '\nالأقمشة بالرولات: سجّلها من «الأرصدة الافتتاحية».' : ''}');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  /// يسجّل نفس الكمية والتكلفة لكل الأصناف المُنشأة في مخزن المنتجات التامة (الافتراضي) بتاريخ اليوم.
  Future<void> _postOpening(List<Json> items, String qty, String cost) async {
    final s = context.read<Session>();
    try {
      final whs = asList((await s.meta())['warehouses']);
      final wh = whs.firstWhere((w) => w['type'] == 'finished', orElse: () => whs.first);
      await s.api.post('/stock-openings', {
        'warehouse_id': wh['id'], 'date': today(), 'notes': 'رصيد عند إضافة الصنف',
        'lines': [for (final it in items) {'item_id': it['id'], 'qty': qty, 'unit_cost': cost}],
      }, newKey());
      if (mounted) {
        toast(context, 'تم تسجيل $qty قطعة لكل صنف (${items.length} صنف) في ${wh['name']}.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, 'تم إنشاء الأصناف لكن تعذّر تسجيل الرصيد: $e', error: true);
    }
  }

  Future<void> _addMaterial() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta();
      if (!mounted) return;
      final v = await showForm(context, 'خامة / مستلزم جديد', [
        const FieldSpec('name', 'الاسم (مثال: قماش قطن أزرق)'),
        const FieldSpec('kind', 'النوع', type: 'picker', options: [
          {'value': 'raw', 'label': 'خامة (قماش...)'},
          {'value': 'supply', 'label': 'مستلزم (خيط، زرار، ليبل...)'},
        ]),
        FieldSpec('unit_id', 'الوحدة', type: 'picker', options: _opts(meta['units'] as List, 'id', 'name')),
        const FieldSpec('tracks_rolls', 'يُدار بالرولات؟ (للأقمشة)', type: 'picker', initial: '0', options: [
          {'value': '1', 'label': 'نعم - بالرولات'},
          {'value': '0', 'label': 'لا'},
        ]),
        const FieldSpec('fabric_type', 'نوع القماش (للأقمشة)', required: false),
        const FieldSpec('color', 'اللون', required: false),
        const FieldSpec('reorder_level', 'حد إعادة الطلب', type: 'number', initial: '0', required: false),
        const FieldSpec('eta_item_code', 'كود الصنف للفاتورة الإلكترونية (فارغ = يُولَّد تلقائيًا)', required: false),
      ]);
      if (v == null) return;
      final made = await s.api.post('/items', {
        'eta_item_code': (v['eta_item_code'] ?? '').isEmpty ? null : v['eta_item_code'],
        'name': v['name'], 'kind': v['kind'], 'unit_id': int.parse(v['unit_id']!), 'tracks_rolls': v['tracks_rolls'] == '1',
        'fabric_type': v['fabric_type'], 'color': v['color'], 'reorder_level': v['reorder_level'],
      });
      if (mounted) setState(() => _tick++);
      if (made is Map) await _askOpening([Map<String, dynamic>.from(made)]);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  /// يضيف **فقط** ما تكتبه: كل (مقاس × لون × قماش) تدخله. لا مقاسات افتراضية.
  Future<void> _addFinished() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta();
      if (!mounted) return;
      final types = (meta['product_types'] as List).map((e) => <String, dynamic>{'value': e, 'label': e}).toList();
      final units = meta['units'] as List;
      final pcs = units.where((u) => (u as Map)['code'] == 'PCS').toList();
      final v = await showForm(context, 'إضافة منتج تام', [
        FieldSpec('product_type', 'نوع المنتج', type: 'picker', options: types),
        const FieldSpec('sizes', 'المقاس (واحد، أو أكتر مفصولة بفاصلة) مثال: M  أو  M,L'),
        const FieldSpec('colors', 'اللون (واحد أو أكتر مفصولة بفاصلة) مثال: أزرق'),
        const FieldSpec('fabrics', 'نوع القماش (واحد أو أكتر) مثال: قطن'),
        FieldSpec('unit_id', 'الوحدة', type: 'picker', options: _opts(units, 'id', 'name'), initial: pcs.isNotEmpty ? (pcs.first as Map)['id'].toString() : null),
        const FieldSpec('sale_price', 'سعر البيع (قطاعي)', type: 'number', initial: '0', required: false),
        const FieldSpec('wholesale_price', 'سعر الجملة', type: 'number', initial: '0', required: false),
        const FieldSpec('qty', 'الكمية الموجودة في المخزن (لكل صنف) — اختياري', type: 'number', required: false),
        const FieldSpec('unit_cost', 'تكلفة القطعة (مطلوبة لو كتبت كمية)', type: 'number', required: false),
      ]);
      if (v == null) return;
      final qtyNum = double.tryParse((v['qty'] ?? '').replaceAll(',', '')) ?? 0;
      if (qtyNum > 0 && (double.tryParse((v['unit_cost'] ?? '').replaceAll(',', '')) ?? -1) < 0) {
        return toast(context, 'اكتب تكلفة القطعة مع الكمية.', error: true);
      }
      final sizes = _split(v['sizes']!);
      final colors = _split(v['colors']!);
      final fabrics = _split(v['fabrics']!);
      final names = [for (final sz in sizes) for (final c in colors) for (final f in fabrics) '${v['product_type']} - $sz - $c - $f'];
      if (names.isEmpty) return toast(context, 'أدخل مقاسًا ولونًا ونوع قماش.', error: true);
      final preview = names.take(8).map((n) => '• $n').join('\n') + (names.length > 8 ? '\n... و${names.length - 8} أخرى' : '');
      if (!await confirm(context, 'سيتم إنشاء ${names.length} صنف فقط:\n$preview\n\nمتابعة؟')) return;
      final r = await s.api.post('/items/finished-variants', {
        'product_type': v['product_type'], 'sizes': sizes, 'colors': colors, 'fabrics': fabrics,
        'unit_id': int.parse(v['unit_id']!), 'sale_price': v['sale_price'], 'wholesale_price': v['wholesale_price'],
      });
      if (mounted) {
        toast(context, r['created'] == 0 ? 'الأصناف دي موجودة بالفعل.' : 'تم إنشاء ${r['created']} صنف.');
        setState(() => _tick++);
        final made = asList(r['items']).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (qtyNum > 0 && made.isNotEmpty) {
          await _postOpening(made, v['qty']!, v['unit_cost']!);
        } else {
          await _askOpening(made);
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _printLabels() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'طباعة ملصقات باركود (${_sel.length} صنف)', [
      const FieldSpec('copies', 'عدد النسخ لكل صنف', type: 'number', initial: '1'),
      const FieldSpec('size', 'المقاس', type: 'picker', initial: '50x30', options: [
        {'value': '50x30', 'label': 'ملصق حراري 50×30 مم'},
        {'value': '40x25', 'label': 'ملصق حراري 40×25 مم'},
        {'value': 'a4', 'label': 'ورق ملصقات A4 (3×7)'},
      ]),
    ], submitLabel: 'فتح للطباعة');
    if (v == null) return;
    try {
      final r = await s.api.get('/labels-url', query: {'type': 'items', 'ids': _sel.join(','), 'copies': (double.tryParse(v['copies']!) ?? 1).round().toString(), 'size': v['size']});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _export() async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/items/export-url', query: _kind.isEmpty ? null : {'kind': _kind});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _assignBarcodes() async {
    final s = context.read<Session>();
    try {
      final r = await s.api.post('/barcodes/assign-missing') as Map;
      if (mounted) {
        toast(context, r['assigned'] == 0 ? 'كل الأصناف لها باركود.' : 'تم توليد باركود لـ ${r['assigned']} صنف.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(Json it) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'تعديل ${it['name']}', [
      FieldSpec('sale_price', 'سعر البيع', type: 'number', initial: it['sale_price']?.toString()),
      FieldSpec('wholesale_price', 'سعر الجملة', type: 'number', initial: it['wholesale_price']?.toString()),
      FieldSpec('reorder_level', 'حد إعادة الطلب', type: 'number', initial: it['reorder_level']?.toString()),
      FieldSpec('eta_item_type', 'نوع كود الصنف الإلكتروني', type: 'picker', initial: it['eta_item_type']?.toString() ?? 'EGS', options: const [{'value': 'EGS', 'label': 'EGS (كود المنشأة)'}, {'value': 'GS1', 'label': 'GS1'}]),
      FieldSpec('eta_item_code', 'كود الصنف الإلكتروني (فارغ = يُولَّد تلقائيًا)', initial: it['eta_item_code']?.toString(), required: false),
      FieldSpec('is_active', 'الحالة', type: 'picker', initial: (it['is_active'] == true) ? '1' : '0', options: const [
        {'value': '1', 'label': 'مفعّل'},
        {'value': '0', 'label': 'موقوف'},
      ]),
    ]);
    if (v == null) return;
    try {
      await s.api.put('/items/${it['id']}', {
        'sale_price': v['sale_price'], 'wholesale_price': v['wholesale_price'], 'reorder_level': v['reorder_level'], 'is_active': v['is_active'] == '1',
        'eta_item_type': v['eta_item_type'], 'eta_item_code': (v['eta_item_code'] ?? '').isEmpty ? null : v['eta_item_code'],
      });
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _deleteSelected() async {
    final s = context.read<Session>();
    if (!await confirm(context, 'حذف ${_sel.length} صنف محدد؟\nالأصناف التي لها حركات أو فواتير لن تُحذف (يمكن إيقافها بدل ذلك).')) return;
    try {
      final r = await s.api.post('/items/bulk-delete', {'ids': _sel.toList()}) as Map;
      final kept = asList(r['kept']);
      if (!mounted) return;
      setState(() {
        _sel.clear();
        _tick++;
      });
      toast(context, 'تم حذف ${r['deleted']} صنف${kept.isEmpty ? '' : '، وتعذّر حذف ${kept.length}:\n${kept.take(5).map((k) => '${k['name']}: ${k['reason']}').join('\n')}'}', error: kept.isNotEmpty);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final canManage = s.can('items.manage');
    return Column(children: [
      PageHeader('الأصناف', actions: [
        SizedBox(
          width: 200,
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _kind,
                isDense: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('كل الأنواع')),
                  for (final e in kindLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() {
                  _kind = v ?? '';
                  _sel.clear();
                  _tick++;
                }),
              ),
            ),
          ),
        ),
        SizedBox(width: 220, child: TextField(decoration: const InputDecoration(hintText: 'بحث بالاسم أو الكود', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v))),
        if (_sel.isNotEmpty)
          OutlinedButton.icon(onPressed: _printLabels, icon: const Icon(Icons.qr_code_2), label: Text('ملصقات باركود (${_sel.length})')),
        PopupMenuButton<String>(
          tooltip: 'المزيد',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'export') _export();
            if (v == 'assign') _assignBarcodes();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'export', child: Text('تصدير الأصناف والأرصدة (Excel)')),
            if (canManage) const PopupMenuItem(value: 'assign', child: Text('توليد باركود للأصناف اللي ماعندهاش')),
          ],
        ),
        if (canManage && _sel.isNotEmpty)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete),
            label: Text('حذف المحدد (${_sel.length})'),
          ),
        if (canManage) ...[
          OutlinedButton.icon(onPressed: _addMaterial, icon: const Icon(Icons.add), label: const Text('خامة / مستلزم')),
          FilledButton.icon(onPressed: _addFinished, icon: const Icon(Icons.add), label: const Text('منتج تام')),
        ],
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_kind'),
          load: () => s.api.get('/items', query: {'kind': _kind}),
          builder: (context, data, reload) {
            final items = asList(data).where((i) => '${i['name']} ${i['code']}'.contains(_q)).toList();
            _shown = items;
            return Column(children: [
              if (canManage)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    TextButton(
                      onPressed: () => setState(() {
                        if (_sel.length == _shown.length) {
                          _sel.clear();
                        } else {
                          _sel
                            ..clear()
                            ..addAll(_shown.map((i) => i['id'] as int));
                        }
                      }),
                      child: Text(_sel.length == _shown.length && _shown.isNotEmpty ? 'إلغاء التحديد' : 'تحديد كل المعروض'),
                    ),
                    const Spacer(),
                    Text('${items.length} صنف'),
                  ]),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final id = it['id'] as int;
                    return ListTile(
                      dense: true,
                      leading: canManage
                          ? Checkbox(
                              value: _sel.contains(id),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _sel.add(id);
                                } else {
                                  _sel.remove(id);
                                }
                              }),
                            )
                          : null,
                      title: Text(it['name'].toString()),
                      subtitle: Text('${it['code']}  •  ${kindLabels[it['kind']] ?? it['kind']}  •  ${it['unit']?['name'] ?? ''}${it['tracks_rolls'] == true ? '  •  بالرولات' : ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('الرصيد: ${fmtQty(it['stock_total'])}', style: TextStyle(fontWeight: FontWeight.w600, color: (double.tryParse('${it['stock_total'] ?? 0}') ?? 0) <= 0 ? Colors.red : null))),
                        if (it['kind'] == 'finished') Text('بيع: ${fmtCell(it['sale_price'])}'),
                        if (it['is_active'] != true) const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Chip(label: Text('موقوف'))),
                        if (canManage) IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _edit(it)),
                      ]),
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}
