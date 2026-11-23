import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

class _Line {
  final Json item;
  String qty;
  String price;
  String disc;
  String taxRate;
  int? rollId;
  String? rollLabel;
  List<Json> rolls;
  int? unitId;
  _Line({this.unitId, required this.item, required this.qty, required this.price, required this.disc, required this.taxRate, this.rollId, this.rollLabel, this.rolls = const []});

  double get net => toD(qty) * toD(price) * (1 - toD(disc) / 100);
}

/// فاتورة بيع أو شراء. الحساب هنا للعرض فقط، والسيرفر هو المرجع النهائي للأرقام.
class InvoiceFormScreen extends StatefulWidget {
  final String side; // sales | purchase
  const InvoiceFormScreen({super.key, required this.side});

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  late Future<Json> _init;
  Json? _party;
  Map<dynamic, String> _plPrices = {};
  Json? _warehouse;
  Json? _treasury;
  String _cur = 'EGP';
  final _rate = TextEditingController();
  final _date = TextEditingController(text: today());
  final _discount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  final _supplierNo = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final List<_Line> _lines = [];
  bool _overLimit = false;
  bool _busy = false;
  final String _key = newKey(); // يمنع تكرار ترحيل نفس الفاتورة لو اتضغط حفظ مرتين
  Json? _order;

  bool get _sales => widget.side == 'sales';

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    _init = () async {
      final meta = await s.meta();
      final parties = asList(await s.api.get('/parties', query: {'type': _sales ? 'customer' : 'supplier', 'active': 1}));
      final items = asList(await s.api.get('/items', query: {'active': 1}));
      final wh = asList(meta['warehouses']);
      final wanted = _sales ? 'finished' : 'raw';
      _warehouse = wh.where((w) => w['type'] == wanted).isNotEmpty ? wh.firstWhere((w) => w['type'] == wanted) : (wh.isNotEmpty ? wh.first : null);
      return <String, dynamic>{'meta': meta, 'parties': parties, 'items': items};
    }();
  }

  double _taxRateFor(Json meta, Json item) {
    final id = item['default_tax_rate_id'];
    for (final t in asList(meta['tax_rates'])) {
      if (t['id'] == id) return toD(t['rate']);
    }
    return 0;
  }

  Future<void> _loadPriceList(dynamic id) async {
    try {
      final pl = await context.read<Session>().api.get('/price-lists/$id') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _plPrices = {for (final r in asList(pl['items'])) r['item_id']: r['price'].toString()});
      toast(context, 'تم تطبيق قائمة أسعار «${pl['name']}» لهذا العميل.');
    } catch (_) {}
  }

  /// سعر البيع: قائمة أسعار العميل ثم مستوى السعر (جملة / قطاعي)
  String? _priceFor(Json item) {
    final fromList = _plPrices[item['id']];
    if (fromList != null) return fromList;
    if (_party?['price_level'] == 'wholesale' && toD(item['wholesale_price']) > 0) return item['wholesale_price']?.toString();
    return item['sale_price']?.toString();
  }

  Future<void> _addLine(Json data, {Json? pre}) async {
    final s = context.read<Session>();
    final meta = data['meta'] as Json;
    var all = data['items'] as List<Json>;
    try {
      all = asList(await s.api.get('/items', query: {'active': 1})); // رصيد محدّث
    } catch (_) {}
    final items = all.where((i) => _sales ? true : (i['kind'] == 'raw' || i['kind'] == 'supply' || i['kind'] == 'finished')).toList();
    String stockLabel(Json i) {
      final q = (i['stock_by_wh'] is Map && _warehouse != null) ? (i['stock_by_wh'] as Map)['${_warehouse!['id']}'] : null;
      return _sales ? '  •  المتاح: ${fmtQty(q)}' : '';
    }
    final item = pre ?? await pickOne(context, 'اختر الصنف', items, (i) => '${i['name']}  (${i['code']})${stockLabel(i)}');
    if (item == null || !mounted) return;
    final tracks = item['tracks_rolls'] == true;
    final rate = _taxRateFor(meta, item).toString();

    try {
      if (_sales && tracks) {
        final rolls = asList((await s.api.get('/reports/rolls', query: {'item_id': item['id']}))['rows']);
        if (rolls.isEmpty) {
          if (mounted) toast(context, 'لا توجد رولات متاحة لهذا الصنف.', error: true);
          return;
        }
        if (!mounted) return;
        final roll = await pickOne(context, 'اختر الرول', rolls, (r) => 'رول ${r['roll_no']} - متبقي ${r['remaining_qty']}');
        if (roll == null || !mounted) return;
        final v = await showForm(context, 'بند: ${item['name']} (رول ${roll['roll_no']})', [
          FieldSpec('qty', 'الكمية (متر) - المتاح ${roll['remaining_qty']}', type: 'number'),
          FieldSpec('price', 'سعر المتر (بدون ضريبة)', type: 'number', initial: _priceFor(item)),
          const FieldSpec('disc', 'خصم %', type: 'number', initial: '0', required: false),
          FieldSpec('tax', 'ضريبة %', type: 'number', initial: rate, required: false),
        ]);
        if (v == null) return;
        setState(() => _lines.add(_Line(item: item, qty: v['qty']!, price: v['price']!, disc: v['disc'] ?? '0', taxRate: v['tax'] ?? rate, rollId: roll['id'] as int?, rollLabel: 'رول ${roll['roll_no']}')));
        return;
      }

      if (!_sales && tracks) {
        final v = await showForm(context, 'شراء قماش: ${item['name']}', [
          const FieldSpec('price', 'سعر المتر (بدون ضريبة)', type: 'number'),
          const FieldSpec('disc', 'خصم %', type: 'number', initial: '0', required: false),
          FieldSpec('tax', 'ضريبة %', type: 'number', initial: rate, required: false),
          const FieldSpec('rolls', 'الرولات: سطر لكل رول بالشكل  رقم_الرول=الطول\nمثال:\n101=120\n102=95', type: 'multiline'),
        ]);
        if (v == null) return;
        final rolls = <Json>[];
        var total = 0.0;
        for (final raw in v['rolls']!.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final parts = line.split('=');
          if (parts.length != 2 || toD(parts[1]) <= 0) {
            if (mounted) toast(context, 'سطر رول غير صحيح: $line', error: true);
            return;
          }
          rolls.add({'roll_no': parts[0].trim(), 'qty': parts[1].trim()});
          total += toD(parts[1]);
        }
        if (rolls.isEmpty) return;
        setState(() => _lines.add(_Line(item: item, qty: total.toString(), price: v['price']!, disc: v['disc'] ?? '0', taxRate: v['tax'] ?? rate, rolls: rolls)));
        return;
      }

      // وحدات بديلة للصنف (مثال: دستة = 12 قطعة)
      final alt = asList(await s.api.get('/items/${item['id']}/units'));
      final unitOpts = <Json>[
        {'value': '${item['unit_id']}', 'label': '${item['unit']?['name'] ?? 'الوحدة الأساسية'} (أساسية)'},
        for (final u in alt) {'value': '${u['unit_id']}', 'label': '${u['unit']?['name']} (= ${fmtCell(u['factor'])} ${item['unit']?['name'] ?? ''})'},
      ];
      if (!mounted) return;
      final v = await showForm(context, 'بند: ${item['name']}', [
        if (alt.isNotEmpty) FieldSpec('unit_id', 'وحدة البيع/الشراء (السعر بنفس الوحدة)', type: 'picker', options: unitOpts, initial: '${item['unit_id']}', required: false),
        const FieldSpec('qty', 'الكمية', type: 'number'),
        FieldSpec('price', 'السعر (بدون ضريبة)', type: 'number', initial: _sales ? _priceFor(item) : null),
        const FieldSpec('disc', 'خصم %', type: 'number', initial: '0', required: false),
        FieldSpec('tax', 'ضريبة %', type: 'number', initial: rate, required: false),
      ]);
      if (v == null) return;
      final chosen = int.tryParse(v['unit_id'] ?? '');
      setState(() => _lines.add(_Line(
          item: item, qty: v['qty']!, price: v['price']!, disc: v['disc'] ?? '0', taxRate: v['tax'] ?? rate,
          unitId: (chosen != null && chosen != item['unit_id']) ? chosen : null)));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  /// تسليم من أمر بيع: يملأ البنود بالمتبقي من الأمر (المحجوز للعميل)
  Future<void> _pickOrder(Json data) async {
    final s = context.read<Session>();
    if (_party == null) return toast(context, 'اختر العميل أولًا.', error: true);
    try {
      final orders = asList(await s.api.get('/sales-orders', query: {'party_id': _party!['id']})).where((o) => o['status'] == 'open' || o['status'] == 'partial').toList();
      if (orders.isEmpty) return toast(context, 'لا توجد أوامر بيع مفتوحة لهذا العميل.', error: true);
      if (!mounted) return;
      final o = await pickOne(context, 'اختر أمر البيع', orders, (o) => '${o['number']}  -  ${o['order_date']}  (${o['status'] == 'partial' ? 'مسلّم جزئيًا' : 'مفتوح'})');
      if (o == null) return;
      final full = await s.api.get('/sales-orders/${o['id']}') as Map<String, dynamic>;
      final meta = data['meta'] as Json;
      final wh = asList(meta['warehouses']).where((w) => w['id'] == full['warehouse_id']).toList();
      setState(() {
        _order = full;
        if (wh.isNotEmpty) _warehouse = wh.first;
        _lines.clear();
        for (final l in asList(full['lines'])) {
          final remaining = toD(l['qty']) - toD(l['delivered_qty']);
          if (remaining <= 0) continue;
          final item = Map<String, dynamic>.from(l['item'] as Map);
          _lines.add(_Line(item: item, qty: remaining.toStringAsFixed(4), price: (toD(l['unit_price']) > 0 ? l['unit_price'] : (_priceFor(item) ?? '0')).toString(),
              disc: (l['discount_pct'] ?? '0').toString(), taxRate: _taxRateFor(meta, item).toString()));
        }
      });
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  double get _subtotal {
    final hd = toD(_discount.text);
    return _lines.fold<double>(0, (a, l) => a + l.net * (1 - hd / 100));
  }

  double get _tax {
    final hd = toD(_discount.text);
    return _lines.fold<double>(0, (a, l) => a + l.net * (1 - hd / 100) * toD(l.taxRate) / 100);
  }

  Future<void> _submit() async {
    final s = context.read<Session>();
    if (_party == null) return toast(context, 'اختر ${_sales ? 'العميل' : 'المورد'}.', error: true);
    if (_warehouse == null) return toast(context, 'اختر المخزن.', error: true);
    if (_lines.isEmpty) return toast(context, 'أضف بندًا واحدًا على الأقل.', error: true);
    final paidAmount = toD(_paid.text);
    final foreign = !_sales && _cur != 'EGP';
    if (foreign && toD(_rate.text) <= 0) return toast(context, 'اكتب سعر صرف $_cur (جنيه لكل وحدة).', error: true);
    if (foreign && paidAmount > 0) return toast(context, 'فاتورة العملة الأجنبية لا تُسدَّد عند إنشائها. احفظها ثم اسدد من زر «سداد بالعملة الأجنبية».', error: true);
    if (paidAmount > 0 && _treasury == null) return toast(context, 'اختر الخزينة للمبلغ المدفوع.', error: true);

    final body = <String, dynamic>{
      'party_id': _party!['id'], 'warehouse_id': _warehouse!['id'], 'date': _date.text, 'discount_pct': _discount.text.isEmpty ? '0' : _discount.text,
      'notes': _notes.text, if (!_sales && _supplierNo.text.isNotEmpty) 'supplier_invoice_no': _supplierNo.text,
      if (_sales && _overLimit) 'allow_over_limit': true,
      if (foreign) ...{'currency': _cur, 'exchange_rate': _rate.text},
      if (_sales && _order != null) 'sales_order_id': _order!['id'],
      'lines': [
        for (final l in _lines)
          {
            'item_id': l.item['id'], 'qty': l.qty, 'unit_price': l.price, 'discount_pct': l.disc.isEmpty ? '0' : l.disc, 'tax_rate': l.taxRate.isEmpty ? '0' : l.taxRate,
            if (l.rollId != null) 'roll_id': l.rollId,
            if (l.unitId != null) 'unit_id': l.unitId,
            if (l.rolls.isNotEmpty) 'rolls': l.rolls,
          },
      ],
      if (paidAmount > 0) 'paid': {'treasury_id': _treasury!['id'], 'amount': _paid.text},
    };

    setState(() => _busy = true);
    try {
      final inv = await s.api.post(_sales ? '/invoices/sales' : '/invoices/purchases', body, _key) as Map<String, dynamic>;
      if (!mounted) return;
      final print = await confirm(context, 'تم حفظ الفاتورة رقم ${inv['number']} بإجمالي ${fmtCell(inv['total'])}.\nهل تريد طباعتها الآن؟');
      if (print && mounted) {
        final r = await s.api.get('/invoices/${inv['id']}/print-url');
        if (mounted) await openUrl(context, r['url'].toString());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(_sales ? 'فاتورة بيع جديدة' : 'فاتورة شراء جديدة')),
      body: FutureBuilder<Json>(
        future: _init,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text(snap.error.toString(), style: const TextStyle(color: Colors.red)));
          final data = snap.data!;
          final meta = data['meta'] as Json;
          final parties = data['parties'] as List<Json>;
          final whs = asList(meta['warehouses']);
          final treasuries = asList(meta['treasuries']);
          final subtotal = _subtotal;
          final tax = _tax;
          final total = subtotal + tax;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(child: PickerField(label: _sales ? 'العميل' : 'المورد', valueText: _party?['name']?.toString(), onTap: () async {
                  final p = await pickOne(context, _sales ? 'اختر العميل' : 'اختر المورد', parties, (p) => p['name'].toString());
                  if (p != null) {
                    setState(() {
                      _party = p;
                      if (_sales) _discount.text = toD(p['default_discount_pct']).toString();
                      _plPrices = {};
                    });
                    if (_sales && p['price_list_id'] != null) _loadPriceList(p['price_list_id']);
                  }
                })),
                const SizedBox(width: 12),
                Expanded(child: PickerField(label: 'المخزن', valueText: _warehouse?['name']?.toString(), onTap: () async {
                  final w = await pickOne(context, 'اختر المخزن', whs, (w) => w['name'].toString());
                  if (w != null) setState(() => _warehouse = w);
                })),
                const SizedBox(width: 12),
                SizedBox(width: 160, child: TextField(
                  controller: _date,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'التاريخ', suffixIcon: Icon(Icons.calendar_today)),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(_date.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => _date.text = d.toIso8601String().substring(0, 10));
                  },
                )),
                const SizedBox(width: 12),
                if (!_sales) ...[
                  SizedBox(width: 150, child: PickerField(label: 'العملة', valueText: _cur == 'EGP' ? 'جنيه مصري' : _cur, onTap: () async {
                    final s = context.read<Session>();
                    try {
                      final list = <Json>[{'code': 'EGP', 'name': 'جنيه مصري'}, ...asList(await s.api.get('/currencies')).where((c) => c['is_active'] == true)];
                      if (!mounted) return;
                      final c = await pickOne(context, 'عملة الفاتورة', list, (c) => '${c['code']} - ${c['name']}');
                      if (c == null) return;
                      setState(() {
                        _cur = c['code'].toString();
                        _rate.text = c['latest_rate']?.toString() ?? '';
                      });
                    } catch (e) {
                      if (mounted) toast(context, e.toString(), error: true);
                    }
                  })),
                  const SizedBox(width: 12),
                  if (_cur != 'EGP') SizedBox(width: 150, child: TextField(controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'سعر الصرف (ج لكل 1 $_cur)'))),
                  if (_cur != 'EGP') const SizedBox(width: 12),
                ],
                SizedBox(width: 120, child: TextField(controller: _discount, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'خصم الفاتورة %'))),
                const SizedBox(width: 12),
                SizedBox(width: 190, child: TextField(
                  controller: _barcode,
                  decoration: const InputDecoration(labelText: 'باركود (امسح ثم Enter)', prefixIcon: Icon(Icons.qr_code_scanner)),
                  onSubmitted: (v) async {
                    final code = v.trim();
                    _barcode.clear();
                    if (code.isEmpty) return;
                    try {
                      final r = await context.read<Session>().api.get('/scan/${Uri.encodeComponent(code)}') as Map;
                      final scanned = Map<String, dynamic>.from(r['item'] as Map);
                      final inList = (data['items'] as List<Json>).where((i) => i['id'] == scanned['id']).toList();
                      if (!mounted) return;
                      _addLine(data, pre: inList.isNotEmpty ? inList.first : scanned);
                    } catch (e) {
                      if (mounted) toast(context, e.toString(), error: true);
                    }
                  },
                )),
                if (!_sales) ...[
                  const SizedBox(width: 12),
                  SizedBox(width: 160, child: TextField(controller: _supplierNo, decoration: const InputDecoration(labelText: 'رقم فاتورة المورد'))),
                ],
              ]),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(onPressed: () => _addLine(data), icon: const Icon(Icons.add), label: const Text('إضافة بند')),
                if (_sales) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pickOrder(data),
                    icon: const Icon(Icons.assignment_outlined),
                    label: Text(_order == null ? 'تسليم من أمر بيع' : 'أمر ${_order!['number']} (تغيير)'),
                  ),
                ],
                const SizedBox(width: 12),
                Text('${_lines.length} بند'),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: _lines.isEmpty
                      ? const EmptyState('لا توجد بنود بعد')
                      : ListView.separated(
                          itemCount: _lines.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final l = _lines[i];
                            final net = l.net * (1 - toD(_discount.text) / 100);
                            return ListTile(
                              dense: true,
                              title: Text('${l.item['name']}${l.rollLabel != null ? '  (${l.rollLabel})' : ''}${l.rolls.isNotEmpty ? '  (${l.rolls.length} رول)' : ''}'),
                              subtitle: Text('كمية ${fmtCell(l.qty)} × سعر ${fmtCell(l.price)}${toD(l.disc) > 0 ? ' - خصم ${l.disc}%' : ''}  |  ضريبة ${l.taxRate}%'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(net.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _lines.removeAt(i))),
                              ]),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [
                  TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: PickerField(label: _sales ? 'خزينة التحصيل (لو فيه مدفوع الآن)' : 'خزينة السداد (لو فيه مدفوع الآن)', valueText: _treasury?['name']?.toString(), onTap: () async {
                      final t = await pickOne(context, 'اختر الخزينة', treasuries, (t) => t['name'].toString());
                      if (t != null) setState(() => _treasury = t);
                    })),
                    const SizedBox(width: 12),
                    SizedBox(width: 160, child: TextField(controller: _paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'المدفوع الآن'))),
                  ]),
                  if (_sales && s.can('settings.manage'))
                    CheckboxListTile(dense: true, value: _overLimit, onChanged: (v) => setState(() => _overLimit = v ?? false), title: const Text('السماح بتجاوز الحد الائتماني (صاحب المصنع)')),
                ])),
                const SizedBox(width: 16),
                SizedBox(
                  width: 300,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        _row('الإجمالي قبل الضريبة${_cur != 'EGP' && !_sales ? ' ($_cur)' : ''}', subtotal.toStringAsFixed(2)),
                        _row('الضريبة (تقديري)', tax.toStringAsFixed(2)),
                        const Divider(),
                        _row('الإجمالي (تقديري)${_cur != 'EGP' && !_sales ? ' ($_cur)' : ''}', total.toStringAsFixed(2), bold: true),
                        _row('المتبقي', (total - toD(_paid.text)).toStringAsFixed(2)),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ وترحيل'))),
                        const SizedBox(height: 4),
                        const Text('الأرقام النهائية يحسبها السيرفر.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(a)), Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))]),
      );
}
