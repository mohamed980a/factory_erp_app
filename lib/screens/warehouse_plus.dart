import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// مواقع الأصناف على الأرفف + طباعة ملصقات الأرفف.
class ShelvesPage extends StatefulWidget {
  const ShelvesPage({super.key});

  @override
  State<ShelvesPage> createState() => _ShelvesPageState();
}

class _ShelvesPageState extends State<ShelvesPage> {
  Json? _wh;
  int _tick = 0;
  final _q = TextEditingController();

  Future<void> _pickWh() async {
    final s = context.read<Session>();
    final meta = await s.meta();
    if (!mounted) return;
    final w = await pickOne(context, 'اختر المخزن', asList(meta['warehouses']), (w) => w['name'].toString());
    if (w != null) setState(() {
      _wh = w;
      _tick++;
    });
  }

  Future<void> _newShelf() async {
    final s = context.read<Session>();
    if (_wh == null) return toast(context, 'اختر المخزن أولًا.', error: true);
    final v = await showForm(context, 'رف جديد في ${_wh!['name']}', [const FieldSpec('code', 'كود الرف (مثال: A-1-3)'), const FieldSpec('notes', 'ملاحظات', required: false)]);
    if (v == null) return;
    try {
      await s.api.post('/shelves', {'warehouse_id': _wh!['id'], 'code': v['code'], 'notes': v['notes']});
      if (mounted) toast(context, 'تم إنشاء الرف.');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _assign(Json row) async {
    final s = context.read<Session>();
    try {
      final shelves = asList(await s.api.get('/shelves', query: {'warehouse_id': _wh!['id']}));
      if (!mounted) return;
      if (shelves.isEmpty) return toast(context, 'أنشئ أرفف المخزن أولًا من زر «رف جديد».', error: true);
      final v = await showForm(context, 'رف ${row['name']}', [
        FieldSpec('shelf_id', 'الرف', type: 'picker', required: false, initial: row['shelf_id']?.toString(), options: [{'value': '', 'label': 'بدون رف'}, for (final sh in shelves) {'value': sh['id'], 'label': sh['code']}]),
      ]);
      if (v == null) return;
      await s.api.put('/stock-locations', {'warehouse_id': _wh!['id'], 'item_id': row['item_id'], 'shelf_id': (v['shelf_id'] ?? '').isEmpty ? null : int.parse(v['shelf_id']!)});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _labels() async {
    final s = context.read<Session>();
    if (_wh == null) return toast(context, 'اختر المخزن أولًا.', error: true);
    try {
      final r = await s.api.get('/labels-url', query: {'type': 'shelves', 'warehouse_id': _wh!['id'].toString(), 'copies': '1', 'size': '50x30'});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('مواقع الأصناف (الأرفف)', actions: [
        OutlinedButton.icon(onPressed: _pickWh, icon: const Icon(Icons.warehouse_outlined), label: Text(_wh?['name']?.toString() ?? 'اختر المخزن')),
        if (s.can('stock.transfer')) OutlinedButton.icon(onPressed: _newShelf, icon: const Icon(Icons.add), label: const Text('رف جديد')),
        OutlinedButton.icon(onPressed: _labels, icon: const Icon(Icons.print), label: const Text('طباعة ملصقات الأرفف')),
      ]),
      if (_wh != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(controller: _q, decoration: const InputDecoration(labelText: 'بحث بالاسم أو الكود', prefixIcon: Icon(Icons.search)), onSubmitted: (_) => setState(() => _tick++)),
        ),
      Expanded(
        child: _wh == null
            ? const EmptyState('اختر المخزن لعرض مواقع أصنافه')
            : Loader(
                key: ValueKey('$_tick${_wh!['id']}'),
                load: () => s.api.get('/stock-locations', query: {'warehouse_id': _wh!['id'].toString(), 'q': _q.text.trim()}),
                builder: (context, data, reload) {
                  final rows = asList(data);
                  if (rows.isEmpty) return const EmptyState('لا توجد أصناف في هذا المخزن');
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        dense: true,
                        title: Text('${r['name']}  (${r['code']})'),
                        subtitle: Text('الرصيد ${fmtQty(r['qty'])}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Pill(r['shelf']?.toString() ?? 'بدون رف', color: r['shelf'] == null ? Colors.grey : AppColors.brand),
                          if (s.can('stock.transfer')) IconButton(tooltip: 'تحديد الرف', icon: const Icon(Icons.edit_location_alt_outlined), onPressed: () => _assign(r)),
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

/// اقتراح أوامر شراء للأصناف التي وصلت لحد الطلب، مجمّعة بالمورد.
class ReorderPage extends StatefulWidget {
  const ReorderPage({super.key});

  @override
  State<ReorderPage> createState() => _ReorderPageState();
}

class _ReorderPageState extends State<ReorderPage> {
  int _tick = 0;

  Future<void> _createPo(Json g) async {
    final s = context.read<Session>();
    try {
      int? partyId = g['supplier_id'] as int?;
      if (partyId == null) {
        final sups = asList(await s.api.get('/parties', query: {'type': 'supplier', 'active': 1}));
        if (!mounted) return;
        final p = await pickOne(context, 'اختر المورد', sups, (p) => p['name'].toString());
        if (p == null) return;
        partyId = p['id'] as int;
      }
      final meta = await s.meta();
      if (!mounted) return;
      final whs = asList(meta['warehouses']).where((w) => w['type'] == 'raw').toList();
      final v = await showForm(context, 'أمر شراء من ${g['supplier']}', [
        FieldSpec('warehouse_id', 'مخزن الاستلام', type: 'picker', initial: whs.isNotEmpty ? whs.first['id'].toString() : null, options: [for (final w in asList(meta['warehouses'])) {'value': w['id'], 'label': w['name']}]),
      ]);
      if (v == null) return;
      await s.api.post('/reorder-suggestions/create-po', {
        'party_id': partyId, 'warehouse_id': int.parse(v['warehouse_id']!),
        'lines': [for (final l in asList(g['lines'])) {'item_id': l['item_id'], 'qty': l['suggest_qty'], 'unit_price': l['last_price']}],
      }, newKey());
      if (mounted) {
        toast(context, 'تم إنشاء أمر الشراء. راجعه من «أوامر الشراء».');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('اقتراح أوامر الشراء', actions: [IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh))]),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(alignment: Alignment.centerRight, child: Text('الكمية المقترحة = ضعف حد الطلب − المتاح − المطلوب في أوامر شراء مفتوحة. المورد = آخر مورد اشتُري منه الصنف.')),
      ),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/reorder-suggestions'),
          builder: (context, data, reload) {
            final groups = asList(data);
            if (groups.isEmpty) return const EmptyState('كل الأصناف فوق حد إعادة الطلب 👌');
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final g in groups)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(g['supplier'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        if (s.can('purchases.create')) FilledButton.icon(onPressed: () => _createPo(g), icon: const Icon(Icons.shopping_cart_checkout), label: const Text('إنشاء أمر شراء')),
                      ]),
                      const Divider(),
                      for (final l in asList(g['lines']))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${l['name']}  (${l['code']})'),
                          subtitle: Text('المتاح ${fmtQty(l['on_hand'])}  •  مطلوب بأوامر ${fmtQty(l['on_order'])}  •  حد الطلب ${fmtQty(l['reorder_level'])}  •  آخر سعر ${fmtCell(l['last_price'])}'),
                          trailing: Pill('اشترِ ${fmtQty(l['suggest_qty'])}', color: Colors.orange),
                        ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

/// فحص جودة فاتورة شراء: لكل بند كمية مرفوضة (تُرجَع للمورد تلقائيًا) وخصم مطلوب للمقبول بعيب.
Future<bool> showQcDialog(BuildContext context, Json invoice) async {
  final s = context.read<Session>();
  final lines = asList(invoice['lines']);
  final rej = [for (final _ in lines) TextEditingController(text: '0')];
  final disc = [for (final _ in lines) TextEditingController(text: '0')];
  final reason = [for (final _ in lines) TextEditingController()];
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('فحص جودة ${invoice['number']}'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: ListView(children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('اكتب الكمية المرفوضة (تُرجَع للمورد بمرتجع شراء تلقائي). «الخصم المطلوب» للبضاعة المقبولة بعيب يُسجَّل للمتابعة مع المورد ولا ينشئ قيدًا.'),
          ),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${lines[i]['item']?['name'] ?? ''}  —  المستلم ${fmtQty(lines[i]['qty'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: TextField(controller: rej[i], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مرفوض'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: disc[i], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'خصم مطلوب'))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextField(controller: reason[i], decoration: const InputDecoration(labelText: 'السبب / الملاحظة'))),
                ]),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () async {
            try {
              await s.api.post('/invoices/${invoice['id']}/qc', {
                'date': today(),
                'lines': [
                  for (var i = 0; i < lines.length; i++)
                    {'invoice_line_id': lines[i]['id'], 'qty_rejected': rej[i].text.trim().isEmpty ? '0' : rej[i].text.trim(), 'discount_requested': disc[i].text.trim().isEmpty ? '0' : disc[i].text.trim(), 'reason': reason[i].text.trim()},
                ],
              }, newKey());
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) toast(ctx, e.toString(), error: true);
            }
          },
          child: const Text('تسجيل الفحص'),
        ),
      ],
    ),
  );
  for (final c in [...rej, ...disc, ...reason]) {
    c.dispose();
  }
  return res == true;
}

/// سداد فاتورة مورد بعملة أجنبية: المبلغ الأجنبي × سعر اليوم = النقدية، والفرق عن سعر القيد يُسجَّل ربح/خسارة فروق عملة.
Future<bool> showForeignPayment(BuildContext context, Json invoice) async {
  final s = context.read<Session>();
  final code = invoice['currency_code'].toString();
  final bookRate = toD(invoice['exchange_rate']);
  final restEgp = toD(invoice['total']) - toD(invoice['paid_amount']);
  final restForeign = bookRate > 0 ? restEgp / bookRate : 0.0;
  String todayRate = '';
  try {
    final r = await s.api.get('/exchange-rate', query: {'currency_code': code}) as Map<String, dynamic>;
    todayRate = r['rate']?.toString() ?? '';
  } catch (_) {}
  final treasuries = asList((await s.meta())['treasuries']);
  if (!context.mounted) return false;
  final amt = TextEditingController(text: restForeign.toStringAsFixed(2));
  final rate = TextEditingController(text: todayRate);
  Json? treasury;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final cash = toD(amt.text) * toD(rate.text);
        final booked = toD(amt.text) * bookRate;
        final diff = cash - booked;
        return AlertDialog(
          title: Text('سداد ${invoice['number']} بعملة $code'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المتبقي ≈ ${restForeign.toStringAsFixed(2)} $code  (سعر القيد ${fmtCell(invoice['exchange_rate'])})'),
              const SizedBox(height: 10),
              TextField(controller: amt, onChanged: (_) => setD(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'المبلغ بـ $code')),
              const SizedBox(height: 8),
              TextField(controller: rate, onChanged: (_) => setD(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الصرف اليوم (جنيه)')),
              const SizedBox(height: 8),
              PickerField(label: 'الخزينة / البنك', valueText: treasury?['name']?.toString(), onTap: () async {
                final t = await pickOne(ctx, 'اختر الخزينة', treasuries, (t) => t['name'].toString());
                if (t != null) setD(() => treasury = t);
              }),
              const SizedBox(height: 12),
              Text('النقدية المدفوعة: ${cash.toStringAsFixed(2)} ج', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('يُقيَّد على المورد: ${booked.toStringAsFixed(2)} ج'),
              Text(diff == 0 ? 'لا فروق عملة' : (diff > 0 ? 'خسارة فروق عملة: ${diff.toStringAsFixed(2)} ج' : 'ربح فروق عملة: ${(-diff).toStringAsFixed(2)} ج'), style: TextStyle(color: diff > 0 ? Colors.red : Colors.green)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (treasury == null) return toast(ctx, 'اختر الخزينة.', error: true);
                try {
                  await s.api.post('/payments', {
                    'kind': 'payment', 'party_id': invoice['party_id'], 'treasury_id': treasury!['id'], 'date': today(),
                    'fx': {'currency': code, 'rate': rate.text, 'foreign_amount': amt.text},
                    'allocations': [{'invoice_id': invoice['id'], 'amount': 1}],
                  }, newKey());
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) toast(ctx, e.toString(), error: true);
                }
              },
              child: const Text('تسجيل السداد'),
            ),
          ],
        );
      },
    ),
  );
  amt.dispose();
  rate.dispose();
  return res == true;
}
