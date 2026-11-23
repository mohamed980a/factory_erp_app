import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const Map<String, String> _statusLabels = {'draft': 'مسودة', 'in_progress': 'قيد التنفيذ', 'completed': 'منتهي', 'cancelled': 'ملغي'};

class ProductionPage extends StatefulWidget {
  const ProductionPage({super.key});

  @override
  State<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends State<ProductionPage> {
  int _tick = 0;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('أوامر التصنيع', actions: [
        InputDecorator(
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _status,
              isDense: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('كل الحالات')),
                for (final e in _statusLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() {
                _status = v ?? '';
                _tick++;
              }),
            ),
          ),
        ),
        if (s.can('production.manage'))
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('أمر تصنيع جديد'),
            onPressed: () async {
              final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ProductionCreateScreen()));
              if (ok == true && mounted) setState(() => _tick++);
            },
          ),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_status'),
          load: () => s.api.get('/production', query: {'status': _status}),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد أوامر تصنيع.');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final o = rows[i];
                final outs = asList(o['outputs']).map((x) => '${x['item']?['name'] ?? ''} × ${fmtCell(x['planned_qty'])}').join('، ');
                return ListTile(
                  title: Text('${o['number']}  •  ${o['responsible'] ?? ''}'),
                  subtitle: Text(outs, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (o['status'] == 'in_progress') Text('تحت التشغيل: ${fmtCell(o['wip_balance'])}'),
                    const SizedBox(width: 12),
                    Chip(label: Text(_statusLabels[o['status']] ?? o['status'].toString())),
                  ]),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductionDetailScreen(id: o['id'] as int)));
                    if (mounted) setState(() => _tick++);
                  },
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _Out {
  final Json item;
  final String qty;
  final String mpp;
  final String other;
  _Out(this.item, this.qty, this.mpp, this.other);
}

class ProductionCreateScreen extends StatefulWidget {
  const ProductionCreateScreen({super.key});

  @override
  State<ProductionCreateScreen> createState() => _ProductionCreateScreenState();
}

class _ProductionCreateScreenState extends State<ProductionCreateScreen> {
  final _responsible = TextEditingController();
  final _start = TextEditingController(text: today());
  final _end = TextEditingController();
  final _notes = TextEditingController();
  Json? _raw;
  Json? _fin;
  final List<_Out> _outs = [];
  List<Json> _warehouses = [];
  List<Json> _finished = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta(refresh: true);
      _warehouses = asList(meta['warehouses']);
      _finished = asList(await s.api.get('/items', query: {'kind': 'finished', 'active': 1}));
      Json? firstOf(String type) => _warehouses.where((w) => w['type'] == type).isNotEmpty ? _warehouses.firstWhere((w) => w['type'] == type) : null;
      _raw = firstOf('raw');
      _fin = firstOf('finished');
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addOutput() async {
    final item = await pickOne(context, 'اختر المنتج التام (النوع - المقاس - اللون - القماش)', _finished, (i) => i['name'].toString());
    if (item == null || !mounted) return;
    final v = await showForm(context, item['name'].toString(), [
      const FieldSpec('qty', 'الكمية المستهدفة (قطعة)', type: 'number'),
      const FieldSpec('mpp', 'استهلاك القماش المتوقع للقطعة (متر)', type: 'number', initial: '0', required: false),
      const FieldSpec('other', 'تكلفة تقديرية أخرى للقطعة (أجور، خيوط، تعبئة...)', type: 'number', initial: '0', required: false),
    ]);
    if (v != null) setState(() => _outs.add(_Out(item, v['qty']!, v['mpp'] ?? '0', v['other'] ?? '0')));
  }

  Future<void> _date(TextEditingController c) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(c.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => c.text = d.toIso8601String().substring(0, 10));
  }

  Future<void> _submit() async {
    final s = context.read<Session>();
    if (_raw == null || _fin == null) return toast(context, 'اختر مخزن الخامات ومخزن المنتجات التامة.', error: true);
    if (_outs.isEmpty) return toast(context, 'أضف منتجًا واحدًا على الأقل.', error: true);
    setState(() => _busy = true);
    try {
      await s.api.post('/production', {
        'responsible': _responsible.text, 'start_date': _start.text, if (_end.text.isNotEmpty) 'end_date': _end.text, 'notes': _notes.text,
        'raw_warehouse_id': _raw!['id'], 'finished_warehouse_id': _fin!['id'],
        'outputs': [for (final o in _outs) {'item_id': o.item['id'], 'planned_qty': o.qty, 'meters_per_piece': o.mpp, 'est_other_cost': o.other}],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أمر تصنيع جديد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: TextField(controller: _responsible, decoration: const InputDecoration(labelText: 'المسؤول عن التشغيل'))),
                      const SizedBox(width: 12),
                      SizedBox(width: 160, child: TextField(controller: _start, readOnly: true, onTap: () => _date(_start), decoration: const InputDecoration(labelText: 'تاريخ البداية'))),
                      const SizedBox(width: 12),
                      SizedBox(width: 160, child: TextField(controller: _end, readOnly: true, onTap: () => _date(_end), decoration: const InputDecoration(labelText: 'تاريخ النهاية المتوقع'))),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: PickerField(label: 'مخزن الخامات', valueText: _raw?['name']?.toString(), onTap: () async {
                        final w = await pickOne(context, 'مخزن الخامات', _warehouses, (w) => w['name'].toString());
                        if (w != null) setState(() => _raw = w);
                      })),
                      const SizedBox(width: 12),
                      Expanded(child: PickerField(label: 'مخزن المنتجات التامة', valueText: _fin?['name']?.toString(), onTap: () async {
                        final w = await pickOne(context, 'مخزن المنتجات التامة', _warehouses, (w) => w['name'].toString());
                        if (w != null) setState(() => _fin = w);
                      })),
                    ]),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _addOutput, icon: const Icon(Icons.add), label: const Text('إضافة منتج'))),
                    Expanded(
                      child: Card(
                        child: _outs.isEmpty
                            ? const Center(child: Text('أضف المنتجات المطلوب تصنيعها'))
                            : ListView(children: [
                                for (var i = 0; i < _outs.length; i++)
                                  ListTile(
                                    title: Text(_outs[i].item['name'].toString()),
                                    subtitle: Text('الكمية ${_outs[i].qty}  •  ${_outs[i].mpp} م/قطعة  •  تكلفة أخرى تقديرية ${_outs[i].other}'),
                                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _outs.removeAt(i))),
                                  ),
                              ]),
                      ),
                    ),
                    TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ الأمر'))),
                  ]),
                ),
    );
  }
}

class ProductionDetailScreen extends StatefulWidget {
  final int id;
  const ProductionDetailScreen({super.key, required this.id});

  @override
  State<ProductionDetailScreen> createState() => _ProductionDetailScreenState();
}

class _ProductionDetailScreenState extends State<ProductionDetailScreen> {
  int _tick = 0;

  Future<void> _act(String path, Map<String, dynamic> body, {String? ok}) async {
    final s = context.read<Session>();
    try {
      await s.api.post('/production/${widget.id}$path', body);
      if (!mounted) return;
      if (ok != null) toast(context, ok);
      setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _issue() async {
    final s = context.read<Session>();
    try {
      final items = asList(await s.api.get('/items', query: {'active': 1})).where((i) => i['kind'] == 'raw' || i['kind'] == 'supply').toList();
      if (!mounted) return;
      final item = await pickOne(context, 'اختر الخامة / المستلزم', items, (i) => '${i['name']}  (${i['code']})');
      if (item == null || !mounted) return;
      int? rollId;
      var title = item['name'].toString();
      if (item['tracks_rolls'] == true) {
        final rolls = asList((await s.api.get('/reports/rolls', query: {'item_id': item['id']}))['rows']);
        if (rolls.isEmpty) return toast(context, 'لا توجد رولات متاحة لهذا القماش.', error: true);
        if (!mounted) return;
        final roll = await pickOne(context, 'اختر الرول', rolls, (r) => 'رول ${r['roll_no']} - متبقي ${r['remaining_qty']} (تكلفة المتر ${fmtCell(r['unit_cost'])})');
        if (roll == null || !mounted) return;
        rollId = roll['id'] as int;
        title += ' - رول ${roll['roll_no']} (متبقي ${roll['remaining_qty']})';
      }
      final v = await showForm(context, 'صرف: $title', [const FieldSpec('qty', 'الكمية', type: 'number'), const FieldSpec('date', 'التاريخ', type: 'date')]);
      if (v == null) return;
      await _act('/issue', {'item_id': item['id'], 'qty': v['qty'], 'date': v['date'], if (rollId != null) 'roll_id': rollId}, ok: 'تم صرف الخامة للأمر.');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _returnMaterial(Json order) async {
    final mats = asList(order['materials']).where((m) => toD(m['qty']) - toD(m['returned_qty']) > 0).toList();
    if (mats.isEmpty) return toast(context, 'لا توجد خامات قابلة للإرجاع.', error: true);
    final m = await pickOne(context, 'اختر الخامة المصروفة', mats, (m) => '${m['item']?['name']} - متاح للإرجاع ${(toD(m['qty']) - toD(m['returned_qty'])).toStringAsFixed(4)}');
    if (m == null || !mounted) return;
    final v = await showForm(context, 'إرجاع للمخزن', [const FieldSpec('qty', 'الكمية', type: 'number'), const FieldSpec('date', 'التاريخ', type: 'date')]);
    if (v == null) return;
    await _act('/return', {'material_id': m['id'], 'qty': v['qty'], 'date': v['date']}, ok: 'تم الإرجاع للمخزن.');
  }

  Future<void> _lossRecord(Json order, bool waste) async {
    final seen = <int>{};
    final fabrics = <Json>[];
    for (final m in asList(order['materials'])) {
      if (m['item']?['tracks_rolls'] == true && seen.add(m['item_id'] as int)) fabrics.add(m);
    }
    if (fabrics.isEmpty) return toast(context, 'لم يُصرف قماش لهذا الأمر.', error: true);
    final f = await pickOne(context, 'اختر القماش', fabrics, (m) => m['item']['name'].toString());
    if (f == null || !mounted) return;
    final v = await showForm(context, waste ? 'تسجيل هالك (غير قابل للاستخدام)' : 'تسجيل بواقي قابلة للاستخدام (ترجع المخزن)', [
      const FieldSpec('qty', 'الكمية (متر)', type: 'number'),
      FieldSpec('reason', waste ? 'سبب الهالك' : 'ملاحظة', required: waste),
      const FieldSpec('date', 'التاريخ', type: 'date'),
    ]);
    if (v == null) return;
    await _act(waste ? '/waste' : '/remnant', {'item_id': f['item_id'], 'qty': v['qty'], 'reason': v['reason'], 'date': v['date']}, ok: waste ? 'تم تسجيل الهالك.' : 'تم إرجاع البواقي للمخزن.');
  }

  Future<void> _cost() async {
    final s = context.read<Session>();
    final meta = await s.meta(refresh: true);
    final kinds = (meta['cost_kinds'] as Map).entries.map((e) => <String, dynamic>{'value': e.key, 'label': e.value}).toList();
    final List<Json> trs = [
      <String, dynamic>{'value': '', 'label': 'مستحقة (لم تُدفع بعد)'},
      ...asList(meta['treasuries']).map((t) => <String, dynamic>{'value': t['id'], 'label': 'تُدفع الآن من: ${t['name']}'}),
    ];
    if (!mounted) return;
    final v = await showForm(context, 'إضافة تكلفة على الأمر', [
      FieldSpec('kind', 'نوع التكلفة', type: 'picker', options: kinds),
      const FieldSpec('amount', 'المبلغ', type: 'number'),
      const FieldSpec('date', 'التاريخ', type: 'date'),
      FieldSpec('treasury_id', 'طريقة الدفع', type: 'picker', options: trs, initial: '', required: false),
      const FieldSpec('description', 'بيان', required: false),
    ]);
    if (v == null) return;
    await _act('/cost', {'kind': v['kind'], 'amount': v['amount'], 'date': v['date'], if ((v['treasury_id'] ?? '').isNotEmpty) 'treasury_id': int.parse(v['treasury_id']!), 'description': v['description']}, ok: 'تمت إضافة التكلفة.');
  }

  Future<void> _stage(Json order, Json stageLabels) async {
    final stages = asList(order['stages']);
    final st = await pickOne(context, 'اختر المرحلة', stages, (x) => '${stageLabels[x['stage']] ?? x['stage']}  (${x['status']})');
    if (st == null || !mounted) return;
    final v = await showForm(context, '${stageLabels[st['stage']] ?? st['stage']}', [
      const FieldSpec('status', 'الحالة', type: 'picker', initial: 'in_progress', options: [
        {'value': 'pending', 'label': 'لم تبدأ'}, {'value': 'in_progress', 'label': 'جارية'}, {'value': 'done', 'label': 'تمت'},
      ]),
      FieldSpec('done_qty', 'الكمية المنجزة', type: 'number', initial: st['done_qty']?.toString(), required: false),
      const FieldSpec('note', 'ملاحظة', required: false),
    ]);
    if (v == null) return;
    await _act('/stage', {'stage': st['stage'], 'status': v['status'], 'done_qty': v['done_qty'], 'note': v['note']});
  }

  Future<void> _receive(Json order) async {
    final outs = asList(order['outputs']);
    final v = await showForm(context, 'استلام منتج تام للمخزن', [
      for (final o in outs)
        FieldSpec('out_${o['id']}', '${o['item']?['name']}  (المستهدف ${fmtCell(o['planned_qty'])} • استُلم ${fmtCell(o['actual_qty'] ?? 0)})', type: 'number', initial: '0', required: false),
      const FieldSpec('final', 'نوع الاستلام', type: 'picker', initial: '0', options: [
        {'value': '0', 'label': 'دفعة جزئية (تُحمَّل حصتها من التكلفة)'},
        {'value': '1', 'label': 'الدفعة الأخيرة (تُحمَّل كل التكلفة المتبقية وينتهي الأمر)'},
      ]),
      const FieldSpec('date', 'تاريخ الاستلام', type: 'date'),
    ], submitLabel: 'استلام');
    if (v == null) return;
    final actuals = <String, String>{for (final o in outs) if (toD(v['out_${o['id']}']) > 0) '${o['id']}': v['out_${o['id']}']!};
    if (actuals.isEmpty) return toast(context, 'أدخل كمية لمنتج واحد على الأقل.', error: true);
    await _act('/receive', {'date': v['date'], 'final': v['final'] == '1', 'actuals': actuals}, ok: 'تم استلام المنتج التام في المخزن بتكلفته.');
  }

  Future<void> _reasonAction(String path, String title, {bool withDate = true}) async {
    final v = await showForm(context, title, [const FieldSpec('reason', 'السبب'), if (withDate) const FieldSpec('date', 'التاريخ', type: 'date')]);
    if (v == null) return;
    await _act(path, {'reason': v['reason'], if (withDate) 'date': v['date']}, ok: 'تم.');
  }

  Widget _section(String title, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
          ]),
        ),
      );

  DataTable _table(List<String> cols, List<List<String>> rows) => DataTable(
        columns: [for (final c in cols) DataColumn(label: Text(c))],
        rows: [for (final r in rows) DataRow(cells: [for (final c in r) DataCell(Text(c))])],
      );

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final canManage = s.can('production.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('أمر التصنيع')),
      body: Loader(
        key: ValueKey(_tick),
        load: () async {
          final meta = await s.meta();
          final d = await s.api.get('/production/${widget.id}');
          return {'meta': meta, 'data': d};
        },
        builder: (context, data, reload) {
          final meta = (data as Map)['meta'] as Json;
          final d = Map<String, dynamic>.from(data['data'] as Map);
          final order = Map<String, dynamic>.from(d['order'] as Map);
          final report = Map<String, dynamic>.from(d['report'] as Map);
          final meters = Map<String, dynamic>.from(report['meters'] as Map);
          final costs = Map<String, dynamic>.from(report['costs'] as Map);
          final stageLabels = Map<String, dynamic>.from(meta['production_stages'] as Map);
          final status = order['status'].toString();
          final byKind = costs['by_kind'] is Map ? Map<String, dynamic>.from(costs['by_kind'] as Map) : <String, dynamic>{};
          final costKinds = Map<String, dynamic>.from(meta['cost_kinds'] as Map);

          final actions = <Widget>[
            if (canManage && status == 'draft') FilledButton(onPressed: () => _act('/start', {}, ok: 'بدأ التنفيذ.'), child: const Text('بدء التنفيذ')),
            if (canManage && status == 'draft') OutlinedButton(onPressed: () => _reasonAction('/cancel', 'إلغاء الأمر', withDate: false), child: const Text('إلغاء الأمر')),
            if (canManage && status == 'in_progress') ...[
              FilledButton.icon(onPressed: _issue, icon: const Icon(Icons.output), label: const Text('صرف خامات')),
              OutlinedButton(onPressed: () => _returnMaterial(order), child: const Text('إرجاع خامات')),
              OutlinedButton(onPressed: () => _lossRecord(order, false), child: const Text('بواقي قابلة للاستخدام')),
              OutlinedButton(onPressed: () => _lossRecord(order, true), child: const Text('هالك')),
              OutlinedButton(onPressed: _cost, child: const Text('أجور / تكاليف')),
              OutlinedButton(onPressed: () => _stage(order, stageLabels), child: const Text('مراحل الإنتاج')),
              FilledButton.icon(onPressed: () => _receive(order), icon: const Icon(Icons.inventory), label: const Text('استلام منتج تام')),
              TextButton(onPressed: () => _reasonAction('/cancel', 'إلغاء الأمر', withDate: false), child: const Text('إلغاء')),
            ],
            if (canManage && (status == 'completed' || (status == 'in_progress' && asList(order['batches']).any((b) => b['status'] == 'posted'))))
              OutlinedButton(onPressed: () => _reasonAction('/reverse-batch', 'التراجع عن آخر دفعة'), child: const Text('التراجع عن آخر دفعة')),
          ];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(children: [
              Row(children: [
                Text(order['number'].toString(), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(width: 12),
                Chip(label: Text(_statusLabels[status] ?? status)),
                const SizedBox(width: 12),
                if (status == 'in_progress') Chip(label: Text('تحت التشغيل: ${fmtCell(costs['wip_balance'])}')),
                const Spacer(),
                IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
              ]),
              Text('المسؤول: ${order['responsible'] ?? '-'}    |    البداية: ${order['start_date'].toString().substring(0, 10)}    |    النهاية: ${order['end_date']?.toString().substring(0, 10) ?? '-'}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
              const SizedBox(height: 12),
              _section('المنتجات: التكلفة التقديرية مقابل الفعلية وهامش الربح', _table(
                ['المنتج', 'المستهدف', 'الفعلي', 'تكلفة تقديرية/قطعة', 'تكلفة فعلية/قطعة', 'الفرق', 'سعر البيع', 'الهامش', 'هامش %'],
                [
                  for (final o in asList(report['outputs']))
                    [o['item'].toString(), fmtCell(o['planned_qty']), fmtCell(o['actual_qty']), fmtCell(o['est_unit_cost']), fmtCell(o['actual_unit_cost']), fmtCell(o['cost_variance']), fmtCell(o['sale_price']), fmtCell(o['margin']), fmtCell(o['margin_pct'])],
                ],
              )),
              _section('تحليل استهلاك القماش (متر)', _table(
                ['المصروف صافي', 'بواقي مستخدمة', 'هالك مسجّل', 'المستهلك', 'المتوقع', 'فرق غير مفسَّر', 'هالك %', 'متر/قطعة فعلي'],
                [[fmtCell(meters['net_issued']), fmtCell(meters['usable_remnant']), fmtCell(meters['waste']), fmtCell(meters['consumed']), fmtCell(meters['expected']), fmtCell(meters['unexplained']), fmtCell(meters['waste_pct']), fmtCell(meters['actual_per_piece'])]],
              )),
              _section('ملخص التكلفة', _table(
                ['خامات (صافي)', 'بواقي راجعة', 'هالك (مصروف)', 'محمّل على المنتج التام', 'تحت التشغيل', ...byKind.keys.map((k) => costKinds[k]?.toString() ?? k)],
                [[fmtCell(costs['materials_net']), fmtCell(costs['remnant_value']), fmtCell(costs['waste_value']), fmtCell(costs['absorbed_into_finished']), fmtCell(costs['wip_balance']), ...byKind.values.map((v) => fmtCell(v))]],
              )),
              _section('دفعات المنتج التام', _table(
                ['الدفعة', 'التاريخ', 'النوع', 'التكلفة', 'الحالة'],
                [for (final b in asList(order['batches'])) ['${b['seq']}', b['batch_date'].toString().substring(0, 10), b['is_final'] == true ? 'أخيرة' : 'جزئية', fmtCell(b['cost_value']), b['status'] == 'posted' ? 'سارية' : 'ملغاة']],
              )),
              _section('الخامات المصروفة', _table(
                ['الخامة', 'الكمية', 'القيمة', 'المرتجع', 'التاريخ'],
                [for (final m in asList(order['materials'])) [m['item']?['name'].toString() ?? '', fmtCell(m['qty']), fmtCell(m['value']), fmtCell(m['returned_qty']), m['issue_date'].toString().substring(0, 10)]],
              )),
              _section('البواقي والهالك', _table(
                ['النوع', 'الخامة', 'الكمية', 'القيمة', 'السبب'],
                [for (final w in asList(order['waste'])) [w['kind'] == 'waste' ? 'هالك' : 'بواقي', w['item']?['name'].toString() ?? '', fmtCell(w['qty']), fmtCell(w['value']), w['reason']?.toString() ?? '']],
              )),
              _section('الأجور والتكاليف', _table(
                ['النوع', 'المبلغ', 'التاريخ', 'الدفع', 'بيان'],
                [for (final c in asList(order['costs'])) [costKinds[c['kind']]?.toString() ?? c['kind'].toString(), fmtCell(c['amount']), c['cost_date'].toString().substring(0, 10), c['treasury_id'] == null ? 'مستحقة' : 'من الخزينة', c['description']?.toString() ?? '']],
              )),
              _section('مراحل الإنتاج', _table(
                ['المرحلة', 'الحالة', 'المنجز', 'ملاحظة'],
                [for (final st in asList(order['stages'])) [stageLabels[st['stage']]?.toString() ?? st['stage'].toString(), {'pending': 'لم تبدأ', 'in_progress': 'جارية', 'done': 'تمت'}[st['status']] ?? st['status'].toString(), fmtCell(st['done_qty']), st['note']?.toString() ?? '']],
              )),
            ]),
          );
        },
      ),
    );
  }
}
