import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';
import 'line_editor.dart';

/// أوامر الشراء: تُطلب من المورد ثم تُستلم (كليًا أو جزئيًا) بفاتورة شراء مرتبطة بالأمر.
class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  int _tick = 0;
  String _status = '';

  static const _statuses = {'': 'الكل', 'open': 'مفتوح', 'partial': 'مستلم جزئيًا', 'received': 'مستلم بالكامل', 'cancelled': 'ملغي'};

  Future<void> _new() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta(refresh: true);
      final suppliers = asList(await s.api.get('/parties', query: {'type': 'supplier', 'active': 1}));
      final all = asList(await s.api.get('/items', query: {'kind': ''})).where((i) => i['kind'] != 'finished' && i['is_active'] != false).toList();
      if (!mounted) return;
      final whs = asList(meta['warehouses']);
      Json? supplier;
      Json? wh = whs.cast<Json?>().firstWhere((w) => w!['type'] == 'raw', orElse: () => whs.isNotEmpty ? whs.first : null);
      final date = TextEditingController(text: today());
      final expected = TextEditingController();
      final notes = TextEditingController();
      final lines = <ItemLine>[ItemLine()];
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('أمر شراء جديد'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  OutlinedButton(
                    onPressed: () async {
                      final r = await pickOne(ctx, 'اختر المورد', suppliers, (p) => '${p['name']}');
                      if (r != null) setS(() => supplier = r);
                    },
                    child: Text(supplier == null ? 'اختر المورد' : '${supplier!['name']}'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final r = await pickOne(ctx, 'مخزن الاستلام', whs, (w) => '${w['name']}');
                      if (r != null) setS(() => wh = r);
                    },
                    child: Text(wh == null ? 'مخزن الاستلام' : 'مخزن الاستلام: ${wh!['name']}'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: date, readOnly: true, onTap: () async {
                      final d = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(date.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (d != null) setS(() => date.text = d.toIso8601String().substring(0, 10));
                    }, decoration: const InputDecoration(labelText: 'تاريخ الأمر', suffixIcon: Icon(Icons.calendar_today, size: 18)))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: expected, readOnly: true, onTap: () async {
                      final d = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(expected.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (d != null) setS(() => expected.text = d.toIso8601String().substring(0, 10));
                    }, decoration: const InputDecoration(labelText: 'تاريخ التوريد المتوقع (اختياري)', suffixIcon: Icon(Icons.calendar_today, size: 18)))),
                  ]),
                  const SizedBox(height: 8),
                  TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات / شروط التوريد (اختياري)')),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Text('الأصناف المطلوب شراؤها', style: TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final low = asList((await s.api.get('/reports/low-stock'))['rows']);
                          final byCode = {for (final i in all) '${i['code']}': i};
                          final add = <ItemLine>[];
                          for (final r in low) {
                            final it = byCode['${r['code']}'];
                            if (it == null) continue;
                            if (lines.any((l) => l.item?['id'] == it['id'])) continue;
                            add.add(ItemLine()
                              ..item = it
                              ..qty.text = fmtQty(r['shortage'])
                              ..price.text = fmtCell(it['cost_price'] ?? it['avg_cost'] ?? ''));
                          }
                          if (add.isEmpty) {
                            if (ctx.mounted) toast(ctx, 'لا توجد أصناف ناقصة ليست في الأمر.');
                            return;
                          }
                          setS(() {
                            lines.removeWhere((l) => l.item == null && l.qty.text.trim().isEmpty);
                            lines.addAll(add);
                          });
                        } catch (e) {
                          if (ctx.mounted) toast(ctx, e.toString(), error: true);
                        }
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('اقتراح من النواقص'),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  ItemLinesEditor(items: all, lines: lines, showPrice: true),
                  const SizedBox(height: 6),
                  Builder(builder: (_) {
                    var total = 0.0;
                    for (final l in lines) {
                      total += (double.tryParse(l.qty.text.trim()) ?? 0) * (double.tryParse(l.price.text.trim()) ?? 0);
                    }
                    return Text('إجمالي الأمر قبل الضريبة: ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800));
                  }),
                  const SizedBox(height: 4),
                  const Text('مصاريف الشحن والتحميل تُسجَّل من شاشة «المصروفات».', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (supplier == null || wh == null || lines.any((l) => l.item == null || l.qty.text.trim().isEmpty)) {
                    toast(ctx, 'اختر المورد والمخزن وأكمل كل الأسطر.', error: true);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('حفظ الأمر'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await s.api.post('/purchase-orders', {
          'party_id': supplier!['id'], 'warehouse_id': wh!['id'], 'order_date': date.text,
          if (expected.text.trim().isNotEmpty) 'expected_date': expected.text.trim(),
          if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
          'lines': [for (final l in lines) {'item_id': l.item!['id'], 'qty': l.qty.text.trim(), 'unit_price': l.price.text.trim().isEmpty ? '0' : l.price.text.trim()}],
        });
        if (mounted) {
          toast(context, 'تم حفظ أمر الشراء.');
          setState(() => _tick++);
        }
      }
      for (final l in lines) {
        l.dispose();
      }
      date.dispose();
      expected.dispose();
      notes.dispose();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _open(Json po) async {
    final s = context.read<Session>();
    try {
      final d = await s.api.get('/purchase-orders/${po['id']}') as Map;
      if (!mounted) return;
      final order = d['order'] as Map;
      final lines = asList(d['lines']);
      final active = order['status'] == 'open' || order['status'] == 'partial';
      final canCreate = s.can('purchases.create');
      final act = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('أمر شراء ${order['number']}  —  ${order['party']?['name'] ?? ''}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('الحالة: ${_statuses[order['status']] ?? order['status']}   |   المخزن: ${order['warehouse']?['name'] ?? ''}   |   التاريخ: ${order['order_date'].toString().substring(0, 10)}'),
                const SizedBox(height: 10),
                Table(border: TableBorder.all(color: Colors.black12), children: [
                  const TableRow(decoration: BoxDecoration(color: Color(0xFFF1F4F8)), children: [
                    Padding(padding: EdgeInsets.all(6), child: Text('الصنف', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('المطلوب', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('المستلم', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('المتبقي', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('السعر', style: TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                  for (final l in lines)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.all(6), child: Text('${l['item']?['name'] ?? ''}')),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(l['qty']))),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(l['received']))),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(l['remaining']))),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(l['unit_price']))),
                    ]),
                ]),
                const SizedBox(height: 10),
                if (asList(d['invoices']).isNotEmpty)
                  Text('فواتير الاستلام: ${asList(d['invoices']).map((i) => '${i['number']}${i['status'] == 'reversed' ? ' (ملغاة)' : ''}').join('، ')}', style: const TextStyle(fontSize: 12.5)),
                if ((order['notes'] ?? '').toString().isNotEmpty) Text('${order['notes']}', style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
          ),
          actions: [
            if (active && canCreate) FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'receive'), icon: const Icon(Icons.inventory), label: const Text('استلام (فاتورة شراء)')),
            if (active && canCreate && order['status'] == 'open') TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('إلغاء الأمر')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      );
      if (act == 'receive') await _receive(order, lines);
      if (act == 'cancel') await _cancel(order);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _receive(Map order, List<Json> lines) async {
    final s = context.read<Session>();
    final open = lines.where((l) => double.tryParse('${l['remaining']}') != null && double.parse('${l['remaining']}') > 0).toList();
    if (open.isEmpty) return toast(context, 'لا يوجد متبقٍ للاستلام.', error: true);
    final fields = <FieldSpec>[
      const FieldSpec('date', 'تاريخ الاستلام', type: 'date'),
      const FieldSpec('supplier_invoice_no', 'رقم فاتورة المورد', required: false),
      for (final l in open) FieldSpec('q_${l['id']}', 'استلام «${l['item']?['name']}» (المتبقي ${fmtCell(l['remaining'])})', type: 'number', initial: fmtCell(l['remaining']), required: false),
      for (final l in open.where((l) => l['item']?['tracks_rolls'] == true))
        FieldSpec('r_${l['id']}', 'رولات «${l['item']?['name']}» — كل سطر: رقم_الرول,المتر', type: 'multiline', required: true),
    ];
    final v = await showForm(context, 'استلام على أمر ${order['number']}', fields, submitLabel: 'إنشاء فاتورة الشراء');
    if (v == null) return;
    try {
      final body = <String, dynamic>{'date': v['date'], 'supplier_invoice_no': v['supplier_invoice_no'], 'lines': []};
      for (final l in open) {
        final q = (v['q_${l['id']}'] ?? '').trim();
        if (q.isEmpty || (double.tryParse(q) ?? 0) <= 0) continue;
        final line = <String, dynamic>{'item_id': l['item_id'], 'qty': q, 'unit_price': l['unit_price']};
        if (l['item']?['tracks_rolls'] == true) {
          final rolls = <Map<String, dynamic>>[];
          for (final row in (v['r_${l['id']}'] ?? '').split('\n')) {
            final p = row.trim().split(RegExp(r'[,،\t]'));
            if (p.length >= 2 && p[0].trim().isNotEmpty) rolls.add({'roll_no': p[0].trim(), 'qty': p[1].trim()});
          }
          line['rolls'] = rolls;
        }
        (body['lines'] as List).add(line);
      }
      if ((body['lines'] as List).isEmpty) return toast(context, 'اكتب كمية لصنف واحد على الأقل.', error: true);
      await s.api.post('/purchase-orders/${order['id']}/receive', body);
      if (mounted) {
        toast(context, 'تم الاستلام وإنشاء فاتورة الشراء.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel(Map order) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء أمر ${order['number']}', [const FieldSpec('reason', 'السبب')], submitLabel: 'إلغاء الأمر');
    if (v == null) return;
    try {
      await s.api.post('/purchase-orders/${order['id']}/cancel', {'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Column(children: [
      PageHeader('أوامر الشراء', subtitle: 'اطلب من المورد ثم استلم بفاتورة مرتبطة', actions: [
        if (s.can('purchases.create')) FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('أمر شراء')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [
          for (final e in _statuses.entries) ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
        ]),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_status'),
          load: () => s.api.get('/purchase-orders', query: {if (_status.isNotEmpty) 'status': _status}),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد أوامر شراء');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = rows[i];
                return Card(
                  child: ListTile(
                    onTap: () => _open(p),
                    title: Text('${p['number']}  •  ${p['party']?['name'] ?? ''}'),
                    subtitle: Text('${p['order_date'].toString().substring(0, 10)}   |   ${p['lines_count']} بند${p['expected_date'] != null ? '   |   متوقع: ${p['expected_date'].toString().substring(0, 10)}' : ''}'),
                    trailing: Pill(_statuses[p['status']] ?? '${p['status']}', color: p['status'] == 'received' ? Colors.teal.shade800 : (p['status'] == 'cancelled' ? Colors.grey.shade700 : Colors.orange.shade800)),
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
