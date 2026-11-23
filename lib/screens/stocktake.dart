import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const _stStatus = {'draft': 'مسودة (جارٍ العد)', 'counted': 'تم العدّ — بانتظار المراجعة', 'posted': 'مرحَّل', 'cancelled': 'ملغى'};

Color _stColor(String s) => s == 'posted' ? Colors.green.shade700 : (s == 'cancelled' ? Colors.grey : Colors.orange.shade800);

/// الجرد: كشوف العد الفعلي ومقارنتها بالرصيد الدفتري وترحيل العجز والزيادة.
class StocktakePage extends StatefulWidget {
  const StocktakePage({super.key});

  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  int _tick = 0;

  Future<void> _new() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final v = await showForm(context, 'كشف جرد جديد', [
        FieldSpec('warehouse_id', 'المخزن', type: 'picker', options: asList(meta['warehouses']).map((w) => <String, dynamic>{'value': w['id'], 'label': w['name']}).toList()),
        const FieldSpec('date', 'تاريخ الجرد', type: 'date'),
        const FieldSpec('mode', 'نطاق الجرد', type: 'picker', initial: 'all', options: [
          {'value': 'all', 'label': 'كل أصناف المخزن'},
          {'value': 'top_value', 'label': 'جزئي: الأعلى قيمة'},
          {'value': 'not_counted', 'label': 'جزئي: الأقدم جردًا / لم يُجرَد'},
        ]),
        const FieldSpec('limit', 'عدد الأصناف (للجرد الجزئي)', type: 'number', required: false, initial: '20'),
        const FieldSpec('days', 'لم تُجرَد منذ كم يوم (للأقدم جردًا)', type: 'number', required: false, initial: '30'),
        const FieldSpec('blind', 'طريقة العد', type: 'picker', initial: '0', options: [
          {'value': '0', 'label': 'عادي (الرصيد الدفتري ظاهر)'},
          {'value': '1', 'label': 'أعمى (العدّاد لا يرى الدفتري)'},
        ]),
        const FieldSpec('notes', 'ملاحظات', required: false),
      ], submitLabel: 'إنشاء الكشف');
      if (v == null) return;
      final st = await s.api.post('/stocktakes', {
        'warehouse_id': int.parse(v['warehouse_id']!), 'date': v['date'], 'notes': v['notes'], 'mode': v['mode'],
        if ((v['limit'] ?? '').isNotEmpty) 'limit': int.parse(v['limit']!), if ((v['days'] ?? '').isNotEmpty) 'days': int.parse(v['days']!), 'blind': v['blind'] == '1',
      }) as Map<String, dynamic>;
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => StocktakeDetailScreen(id: st['id'] as int)));
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('الجرد', subtitle: 'اطبع ورقة العد، أدخل الكميات الفعلية، ثم رحّل الفروق', actions: [
        FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('كشف جرد جديد')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/stocktakes'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد كشوف جرد.');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final r = rows[i];
                final st = r['status'].toString();
                final total = r['lines_count'] ?? 0;
                final done = r['counted_count'] ?? 0;
                return Card(
                  child: ListTile(
                    title: Text('${r['number']}  •  ${r['warehouse']?['name'] ?? ''}'),
                    subtitle: Text('${r['count_date'].toString().substring(0, 10)}${st == 'draft' ? '  •  تم عدّ $done من $total بند' : ''}${r['blind'] == true || r['blind'] == 1 ? '  •  عدّ أعمى' : ''}${r['scope'] != null && r['scope'] != 'all' ? '  •  جزئي' : ''}'),
                    trailing: Pill(_stStatus[st] ?? st, color: _stColor(st)),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => StocktakeDetailScreen(id: r['id'] as int)));
                      if (mounted) setState(() => _tick++);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class StocktakeDetailScreen extends StatefulWidget {
  final int id;
  const StocktakeDetailScreen({super.key, required this.id});

  @override
  State<StocktakeDetailScreen> createState() => _StocktakeDetailScreenState();
}

class _StocktakeDetailScreenState extends State<StocktakeDetailScreen> {
  int _tick = 0;
  final Map<int, TextEditingController> _ctl = {};
  final Map<int, TextEditingController> _gain = {};
  final Map<int, TextEditingController> _note = {};
  final Map<int, String?> _reason = {};
  final _search = TextEditingController();
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  String _filter = 'all'; // all | open | diff | same
  bool _busy = false;

  @override
  void dispose() {
    for (final m in [_ctl, _gain, _note]) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _search.dispose();
    _scan.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  double? _counted(int id) => double.tryParse((_ctl[id]?.text ?? '').trim());

  Future<void> _save(List<Json> lines, {bool quiet = false}) async {
    final s = context.read<Session>();
    final counts = <String, dynamic>{};
    for (final l in lines) {
      final id = l['id'] as int;
      final t = _ctl[id]?.text.trim() ?? '';
      final g = _gain[id]?.text.trim() ?? '';
      final n = _note[id]?.text.trim() ?? '';
      if (t.isNotEmpty) counts['$id'] = {'counted_qty': t, if (g.isNotEmpty) 'gain_unit_cost': g, 'note': n, if (_reason[id] != null) 'reason_code': _reason[id]};
    }
    if (counts.isEmpty) {
      if (!quiet) toast(context, 'لم تُدخل أي كميات.', error: true);
      return;
    }
    await s.api.put('/stocktakes/${widget.id}/counts', {'counts': counts});
    if (!quiet && mounted) toast(context, 'تم حفظ الكميات.');
  }

  Future<void> _addItem(List<Json> lines) async {
    final s = context.read<Session>();
    try {
      await _save(lines, quiet: true);
      final items = asList(await s.api.get('/items', query: {'active': 1})).where((i) => i['tracks_rolls'] != true).toList();
      if (!mounted) return;
      final it = await pickOne(context, 'اختر صنفًا غير مدرج في الكشف (لتسجيل زيادة)', items, (i) => '${i['name']}  (${i['code']})');
      if (it == null) return;
      await s.api.post('/stocktakes/${widget.id}/lines', {'item_id': it['id']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  void _onScan(List<Json> all, String raw) {
    final code = raw.trim();
    _scan.clear();
    _scanFocus.requestFocus();
    if (code.isEmpty) return;
    Json? hit;
    for (final l in all) {
      final it = l['item'] as Map?;
      if ('${l['roll']?['roll_no'] ?? ''}' == code) {
        hit = l;
        break;
      }
      if (hit == null && ('${it?['barcode']}' == code || '${it?['code']}' == code) && l['roll'] == null) hit = l;
    }
    if (hit == null) {
      toast(context, 'الباركود «$code» غير موجود في هذا الكشف. استخدم «إضافة صنف غير مدرج» لو وجدته فعليًا.', error: true);
      return;
    }
    final id = hit['id'] as int;
    final c = _ctl[id]!;
    if (hit['roll'] != null) {
      // الرول يُمسح مرة واحدة: يُعتبر موجودًا بطوله الدفتري (يمكن تعديله). في الأعمى يكتب العدّاد الطول.
      final b = double.tryParse('${hit['book_qty']}');
      if (b != null) {
        c.text = fmtQty(b);
        toast(context, 'رول ${hit['roll']['roll_no']}: موجود (${fmtQty(b)}). عدّل الطول لو مختلف.');
      } else {
        toast(context, 'رول ${hit['roll']['roll_no']}: اكتب الطول الفعلي.');
      }
    } else {
      final n = (double.tryParse(c.text.trim()) ?? 0) + 1;
      c.text = fmtQty(n);
      toast(context, '${hit['item']['name']}: العدد الآن ${fmtQty(n)}');
    }
    setState(() {});
  }

  Future<void> _submit(List<Json> lines) async {
    final s = context.read<Session>();
    if (!await confirm(context, 'تسليم العدّ؟ بعدها يظهر الرصيد الدفتري للمراجعة، ويمكن إعادة عدّ البنود التي بها فرق.')) return;
    setState(() => _busy = true);
    try {
      await _save(lines, quiet: true);
      await s.api.post('/stocktakes/${widget.id}/submit');
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sheet() async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/reports/stocktake-sheet/csv-url', query: {'stocktake_id': widget.id});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء كشف الجرد', [const FieldSpec('reason', 'سبب الإلغاء')], submitLabel: 'إلغاء الكشف');
    if (v == null) return;
    try {
      await s.api.post('/stocktakes/${widget.id}/cancel', {'reason': v['reason']});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _post(List<Json> lines) async {
    final s = context.read<Session>();
    final missing = lines.where((l) => _counted(l['id'] as int) == null).length;
    if (missing > 0) {
      toast(context, 'باقي $missing بند بدون كمية فعلية. أدخلها أو استخدم «اعتبر غير المعدود مطابقًا».', error: true);
      return;
    }
    final changedLines = lines.where((l) => (_counted(l['id'] as int) ?? 0) != (double.tryParse('${l['book_qty']}') ?? 0)).toList();
    final changed = changedLines.length;
    final noReason = changedLines.where((l) => (_reason.containsKey(l['id']) ? _reason[l['id']] : l['reason_code']) == null).length;
    if (noReason > 0) {
      toast(context, 'اختر سبب الفرق لـ $noReason بند به فرق.', error: true);
      return;
    }
    final v = await showForm(context, 'ترحيل الجرد', [const FieldSpec('date', 'تاريخ التسوية', type: 'date')], submitLabel: 'ترحيل');
    if (v == null || !mounted) return;
    if (!await confirm(context, 'سيتم ترحيل $changed فرق (عجز وزيادة) للمخزون والحسابات، ولا يمكن تعديلها بعد ذلك. متأكد؟')) return;
    setState(() => _busy = true);
    try {
      await _save(lines, quiet: true);
      await s.api.post('/stocktakes/${widget.id}/post', {'date': v['date']});
      if (mounted) {
        toast(context, 'تم ترحيل الجرد.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stat(String label, String value, Color c) => Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('كشف جرد')),
      body: Loader(
        key: ValueKey(_tick),
        load: () => s.api.get('/stocktakes/${widget.id}'),
        builder: (context, data, reload) {
          final st = Map<String, dynamic>.from(data as Map);
          final all = asList(st['lines']);
          all.sort((a, b) => '${a['item']?['name']}${a['roll']?['roll_no'] ?? ''}'.compareTo('${b['item']?['name']}${b['roll']?['roll_no'] ?? ''}'));
          final status = st['status'].toString();
          final draft = status == 'draft' || status == 'counted';          // قابل للتعديل
          final isBlind = st['blind'] == true || st['blind'] == 1;
          final hidden = st['blind_hidden'] == true;                      // الرصيد الدفتري مخفي عن العدّاد
          final reasons = (st['reasons'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? <String, String>{};
          final over = asList((st['tolerance'] as Map?)?['over']);
          for (final l in all) {
            final id = l['id'] as int;
            _ctl.putIfAbsent(id, () => TextEditingController(text: l['counted_qty'] == null ? '' : fmtQty(l['counted_qty'])));
            _gain.putIfAbsent(id, () => TextEditingController(text: l['gain_unit_cost'] == null ? '' : fmtQty(l['gain_unit_cost'])));
            _note.putIfAbsent(id, () => TextEditingController(text: l['note']?.toString() ?? ''));
          }
          double book(Json l) => double.tryParse('${l['book_qty']}') ?? 0;
          bool hasDiff(Json l) => !hidden && _counted(l['id'] as int) != null && _counted(l['id'] as int) != book(l);
          final counted = all.where((l) => _counted(l['id'] as int) != null).length;
          final shortage = hidden ? 0 : all.where((l) => (_counted(l['id'] as int) ?? book(l)) < book(l)).length;
          final surplus = hidden ? 0 : all.where((l) => (_counted(l['id'] as int) ?? book(l)) > book(l)).length;
          final q = _search.text.trim().toLowerCase();
          final lines = all.where((l) {
            final c = _counted(l['id'] as int);
            if (q.isNotEmpty && !'${l['item']?['name']} ${l['item']?['code']} ${l['roll']?['roll_no'] ?? ''}'.toLowerCase().contains(q)) return false;
            return switch (_filter) {
              'open' => c == null,
              'diff' => hasDiff(l),
              'same' => !hidden && c != null && c == book(l),
              _ => true,
            };
          }).toList();
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${st['number']}  •  ${st['warehouse']?['name'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                  Text('${st['count_date'].toString().substring(0, 10)}'),
                  Pill(_stStatus[status] ?? status, color: _stColor(status)),
                ]),
              ),
              const SizedBox(height: 8),
              if (over.isNotEmpty && !hidden)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text('تنبيه: ${over.length} بند فروقه تتجاوز حد السماح (${st['tolerance']['pct']}% أو ${st['tolerance']['value']} ج) — ترحيلها يلزمه اعتماد المالك. مثال: ${over.first['name']} (${over.first['diff']})', style: const TextStyle(fontSize: 12.5)),
                ),
              if (draft)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text(hidden ? 'جرد أعمى: الرصيد الدفتري مخفي. عُدّ البضاعة واكتب ما تراه فقط، ثم اضغط «تسليم العدّ» وسيراجع المحاسب الفروق.' : (status == 'counted' ? 'تم تسليم العدّ. راجع البنود التي بها فرق: يمكنك إعادة عدّها وتعديل الكمية، ثم اختر السبب ورحّل.' : 'طريقة الجرد:  ١) اطبع «ورقة الجرد» وعُدّ البضاعة فعليًا.  ٢) اكتب الكمية الفعلية أمام كل صنف (لو مطابقة اكتب نفس الدفتري).  ٣) راجع الفروق (الأحمر عجز، الأزرق زيادة) واكتب سببها.  ٤) اضغط «ترحيل الفروق» لتسوية المخزون والحسابات.'), style: const TextStyle(fontSize: 12.5, height: 1.5)),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  OutlinedButton.icon(onPressed: _sheet, icon: const Icon(Icons.table_view), label: const Text('ورقة الجرد (Excel)')),
                  if (draft) ...[
                    OutlinedButton(onPressed: _busy ? null : () => _addItem(all), child: const Text('إضافة صنف غير مدرج')),
                    if (!hidden)
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        for (final l in all) {
                          final id = l['id'] as int;
                          if ((_ctl[id]?.text.trim() ?? '').isEmpty) _ctl[id]!.text = fmtQty(l['book_qty']);
                        }
                      }),
                      icon: const Icon(Icons.done_all),
                      label: const Text('اعتبر غير المعدود مطابقًا'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () async {
                        try {
                          await _save(all);
                        } catch (e) {
                          if (context.mounted) toast(context, e.toString(), error: true);
                        }
                      },
                      child: const Text('حفظ'),
                    ),
                    if (isBlind && status == 'draft') FilledButton(onPressed: _busy ? null : () => _submit(all), child: const Text('تسليم العدّ')),
                    if (!isBlind || status == 'counted') FilledButton(onPressed: _busy ? null : () => _post(all), child: const Text('ترحيل الفروق')),
                    IconButton(onPressed: _busy ? null : _cancel, tooltip: 'إلغاء الكشف', icon: const Icon(Icons.delete_outline)),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(runSpacing: 6, children: [
                  _stat('إجمالي البنود', '${all.length}', Colors.black87),
                  _stat('تم عدّها', '$counted', Colors.green.shade700),
                  _stat('لم تُعدّ', '${all.length - counted}', Colors.orange.shade800),
                  _stat('بها عجز', '$shortage', Colors.red.shade700),
                  _stat('بها زيادة', '$surplus', Colors.blue.shade700),
                ]),
              ),
              const SizedBox(height: 8),
              if (draft)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _scan,
                    focusNode: _scanFocus,
                    autofocus: true,
                    onSubmitted: (v) => _onScan(all, v),
                    decoration: const InputDecoration(labelText: 'امسح الباركود هنا (كل مسحة = +1 للصنف، والرول يُسجَّل موجودًا) ثم Enter', prefixIcon: Icon(Icons.qr_code_scanner)),
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(width: 260, child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'بحث بالاسم أو الكود أو الرول', prefixIcon: Icon(Icons.search)))),
                  for (final f in const {'all': 'الكل', 'open': 'لم يُعد', 'diff': 'فيه فرق', 'same': 'مطابق'}.entries)
                    ChoiceChip(label: Text(f.value), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key)),
                ]),
              ),
              const Divider(),
              Expanded(
                child: lines.isEmpty
                    ? const EmptyState('لا توجد بنود مطابقة')
                    : ListView.separated(
                        itemCount: lines.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final l = lines[i];
                          final id = l['id'] as int;
                          final b = book(l);
                          final c = draft ? _counted(id) : double.tryParse('${l['counted_qty']}');
                          final diff = (c == null || hidden) ? null : c - b;
                          final name = '${l['item']?['name'] ?? ''}${l['roll'] != null ? '  (رول ${l['roll']['roll_no']})' : ''}';
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                const SizedBox(height: 6),
                                Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                  if (!hidden) Text('الدفتري: ${fmtQty(l['book_qty'])}', style: const TextStyle(fontSize: 13)),
                                  if (draft)
                                    SizedBox(width: 130, child: TextField(controller: _ctl[id], onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية الفعلية', isDense: true)))
                                  else
                                    Text('الفعلي: ${fmtQty(l['counted_qty'])}', style: const TextStyle(fontSize: 13)),
                                  if (c == null)
                                    Pill('لم يُعدّ', color: Colors.orange.shade800)
                                  else if (diff == null)
                                    Pill('تم العدّ', color: Colors.green.shade700)
                                  else if (diff == 0)
                                    Pill('مطابق', color: Colors.green.shade700)
                                  else
                                    Pill(diff < 0 ? 'عجز ${fmtQty(-diff)}' : 'زيادة ${fmtQty(diff)}', color: diff < 0 ? Colors.red.shade700 : Colors.blue.shade700),
                                  if (draft && diff != null && diff > 0 && l['roll_id'] == null && b == 0)
                                    SizedBox(width: 140, child: TextField(controller: _gain[id], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة الوحدة', isDense: true))),
                                  if (draft && diff != null && diff != 0) ...[
                                    SizedBox(
                                      width: 190,
                                      child: DropdownButtonFormField<String>(
                                        value: _reason.containsKey(id) ? _reason[id] : l['reason_code']?.toString(),
                                        isExpanded: true,
                                        decoration: const InputDecoration(labelText: 'سبب الفرق (إلزامي)', isDense: true),
                                        items: [for (final r in reasons.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
                                        onChanged: (v) => setState(() => _reason[id] = v),
                                      ),
                                    ),
                                    SizedBox(width: 200, child: TextField(controller: _note[id], decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', isDense: true))),
                                  ],
                                  if (!draft && (l['reason_code'] ?? '').toString().isNotEmpty) Text('السبب: ${reasons[l['reason_code']] ?? l['reason_code']}${(l['note'] ?? '').toString().isEmpty ? '' : ' — ${l['note']}'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                  if (!draft && l['diff_value'] != null && (double.tryParse('${l['diff_qty']}') ?? 0) != 0) Text('قيمة الفرق: ${fmtCell(l['diff_value'])}', style: const TextStyle(fontSize: 12)),
                                ]),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
