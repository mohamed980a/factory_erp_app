import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const Map<String, String> _statusLabels = {'open': 'مفتوح', 'partial': 'مسلَّم جزئيًا', 'fulfilled': 'مكتمل', 'cancelled': 'ملغي'};

/// أوامر البيع وحجز البضاعة للعملاء (متابعة الطلبات قبل التسليم).
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  int _tick = 0;
  String _status = '';

  Future<void> _create() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta();
      final parties = asList(await s.api.get('/parties', query: {'type': 'customer', 'active': 1}));
      final items = asList(await s.api.get('/items', query: {'active': 1, 'kind': 'finished'}));
      if (!mounted) return;
      final whs = asList(meta['warehouses']).where((w) => w['type'] == 'finished').toList();
      final head = await showForm(context, 'أمر بيع / حجز بضاعة', [
        FieldSpec('party_id', 'العميل', type: 'picker', options: [for (final p in parties) {'value': p['id'], 'label': p['name']}]),
        FieldSpec('warehouse_id', 'المخزن', type: 'picker', initial: whs.isNotEmpty ? whs.first['id'].toString() : null, options: [for (final w in asList(meta['warehouses'])) {'value': w['id'], 'label': w['name']}]),
        const FieldSpec('date', 'تاريخ الأمر', type: 'date'),
        const FieldSpec('delivery_date', 'موعد التسليم المتوقع', type: 'date', required: false),
        const FieldSpec('allow_backorder', 'لو الكمية مش متاحة بالكامل', type: 'picker', initial: '0', options: [
          {'value': '0', 'label': 'ارفض الأمر'},
          {'value': '1', 'label': 'سجّل الأمر واحجز المتاح فقط'},
        ]),
        const FieldSpec('notes', 'ملاحظات', required: false),
      ]);
      if (head == null) return;
      final lines = <Json>[];
      while (mounted) {
        final it = await pickOne(context, lines.isEmpty ? 'اختر الصنف' : 'اختر صنفًا آخر (إلغاء للانتهاء)', items, (i) => '${i['name']}  (${i['code']})');
        if (it == null || !mounted) break;
        final l = await showForm(context, it['name'].toString(), [
          const FieldSpec('qty', 'الكمية', type: 'number'),
          FieldSpec('unit_price', 'سعر الوحدة (بدون ضريبة)', type: 'number', initial: it['sale_price']?.toString() ?? '0', required: false),
        ]);
        if (l == null) continue;
        lines.add({'item_id': it['id'], 'qty': l['qty'], 'unit_price': l['unit_price']});
      }
      if (lines.isEmpty || !mounted) return;
      await s.api.post('/sales-orders', {
        'party_id': int.parse(head['party_id']!), 'warehouse_id': int.parse(head['warehouse_id']!), 'date': head['date'],
        if ((head['delivery_date'] ?? '').isNotEmpty) 'delivery_date': head['delivery_date'],
        'allow_backorder': head['allow_backorder'] == '1', 'notes': head['notes'], 'lines': lines,
      }, newKey());
      if (mounted) {
        toast(context, 'تم تسجيل الأمر وحجز الكميات.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel(Json o) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء الأمر ${o['number']}', [const FieldSpec('reason', 'سبب الإلغاء')]);
    if (v == null) return;
    try {
      await s.api.post('/sales-orders/${o['id']}/cancel', {'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _show(Json o) async {
    final s = context.read<Session>();
    try {
      final d = await s.api.get('/sales-orders/${o['id']}') as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('أمر ${d['number']} - ${d['party']?['name']}'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in asList(d['lines']))
                ListTile(
                  dense: true,
                  title: Text(l['item']?['name']?.toString() ?? ''),
                  subtitle: Text('مطلوب ${fmtCell(l['qty'])}  •  مسلَّم ${fmtCell(l['delivered_qty'])}  •  محجوز ${fmtCell(l['reserved_qty'])}'),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('أوامر البيع والحجز', actions: [
        SizedBox(
          width: 190,
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _status,
                isDense: true,
                items: [const DropdownMenuItem(value: '', child: Text('كل الحالات')), for (final e in _statusLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() {
                  _status = v ?? '';
                  _tick++;
                }),
              ),
            ),
          ),
        ),
        if (s.can('sales.create')) FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('أمر بيع جديد')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_status'),
          load: () => s.api.get('/sales-orders', query: {'status': _status}),
          builder: (context, data, reload) {
            final orders = asList(data);
            if (orders.isEmpty) return const EmptyState('لا توجد أوامر بيع');
            return ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final o = orders[i];
                final isLate = (o['status'] == 'open' || o['status'] == 'partial') && (o['delivery_date'] ?? '').toString().isNotEmpty && o['delivery_date'].toString().compareTo(today()) < 0;
                return ListTile(
                  dense: true,
                  onTap: () => _show(o),
                  title: Text('${o['number']}  -  ${o['party']?['name'] ?? ''}'),
                  subtitle: Text('تاريخ ${o['order_date']}${(o['delivery_date'] ?? '').toString().isEmpty ? '' : '  •  تسليم ${o['delivery_date']}'}  •  ${o['warehouse']?['name'] ?? ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isLate) const Pill('متأخر', color: Colors.red),
                    Pill(_statusLabels[o['status']] ?? o['status'].toString(), color: o['status'] == 'cancelled' ? Colors.grey : AppColors.brand),
                    if ((o['status'] == 'open' || o['status'] == 'partial') && s.can('sales.create')) IconButton(tooltip: 'إلغاء الأمر', icon: const Icon(Icons.cancel_outlined), onPressed: () => _cancel(o)),
                  ]),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
