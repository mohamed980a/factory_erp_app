import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

class PartiesPage extends StatefulWidget {
  final String type; // customer | supplier
  const PartiesPage({super.key, required this.type});

  @override
  State<PartiesPage> createState() => _PartiesPageState();
}

class _PartiesPageState extends State<PartiesPage> {
  String _q = '';
  int _tick = 0;

  bool get _cust => widget.type == 'customer';

  Future<void> _add() async {
    final s = context.read<Session>();
    final v = await showForm(context, _cust ? 'عميل جديد' : 'مورد جديد', [
      const FieldSpec('name', 'الاسم'),
      const FieldSpec('phone', 'التليفون', required: false),
      const FieldSpec('address', 'العنوان', required: false),
      const FieldSpec('tax_no', 'الرقم الضريبي', required: false),
      if (_cust) const FieldSpec('credit_limit', 'الحد الائتماني (0 = بدون حد)', type: 'number', initial: '0', required: false),
      if (_cust) const FieldSpec('price_level', 'مستوى السعر', type: 'picker', initial: 'retail', options: [{'value': 'retail', 'label': 'قطاعي'}, {'value': 'wholesale', 'label': 'جملة'}]),
      if (_cust) const FieldSpec('default_discount_pct', 'خصم افتراضي على فواتيره %', type: 'number', initial: '0', required: false),
      if (_cust) const FieldSpec('eta_receiver_type', 'نوع العميل (فاتورة إلكترونية)', type: 'picker', initial: 'B', options: [{'value': 'B', 'label': 'شركة / منشأة'}, {'value': 'P', 'label': 'شخص طبيعي'}, {'value': 'F', 'label': 'أجنبي'}]),
      const FieldSpec('payment_terms_days', 'مدة السداد (أيام)', type: 'number', initial: '0', required: false),
      FieldSpec('opening_balance', _cust ? 'رصيد افتتاحي (مستحق علينا له/لنا عليه)' : 'رصيد افتتاحي (مستحق للمورد)', type: 'number', initial: '0', required: false),
      const FieldSpec('opening_date', 'تاريخ الرصيد الافتتاحي', type: 'date'),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/parties', {
        'type': widget.type, 'name': v['name'], 'phone': v['phone'], 'address': v['address'], 'tax_no': v['tax_no'],
        if (_cust) 'credit_limit': v['credit_limit'],
        if (_cust) 'price_level': v['price_level'], if (_cust) 'default_discount_pct': v['default_discount_pct'], if (_cust) 'eta_receiver_type': v['eta_receiver_type'],
        'payment_terms_days': v['payment_terms_days'],
        'opening_balance': v['opening_balance'], 'opening_date': v['opening_date'],
      });
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(Json row) async {
    final s = context.read<Session>();
    Json p = row;
    try {
      final all = asList(await s.api.get('/parties', query: {'type': widget.type, 'q': row['name']}));
      p = all.firstWhere((x) => x['id'] == row['id'], orElse: () => row);
    } catch (_) {}
    List<Json> lists = [], reps = [];
    if (_cust) {
      try {
        lists = asList(await s.api.get('/price-lists'));
        reps = asList(await s.api.get('/sales-reps'));
      } catch (_) {}
    }
    if (!mounted) return;
    final v = await showForm(context, 'تعديل ${p['name']}', [
      FieldSpec('name', 'الاسم', initial: p['name']?.toString()),
      FieldSpec('phone', 'التليفون', initial: p['phone']?.toString(), required: false),
      FieldSpec('tax_no', 'الرقم الضريبي', initial: p['tax_no']?.toString(), required: false),
      FieldSpec('address', 'العنوان', initial: p['address']?.toString(), required: false),
      if (_cust) FieldSpec('credit_limit', 'الحد الائتماني', type: 'number', initial: p['credit_limit']?.toString(), required: false),
      if (_cust) FieldSpec('price_level', 'مستوى السعر', type: 'picker', initial: p['price_level']?.toString() ?? 'retail', options: const [{'value': 'retail', 'label': 'قطاعي'}, {'value': 'wholesale', 'label': 'جملة'}]),
      if (_cust) FieldSpec('price_list_id', 'قائمة الأسعار', type: 'picker', required: false, initial: p['price_list_id']?.toString(), options: [{'value': '', 'label': 'بدون (سعر الصنف)'}, for (final l in lists) {'value': l['id'], 'label': l['name']}]),
      if (_cust) FieldSpec('sales_rep_id', 'المندوب', type: 'picker', required: false, initial: p['sales_rep_id']?.toString(), options: [{'value': '', 'label': 'بدون'}, for (final r in reps) {'value': r['id'], 'label': r['name']}]),
      if (_cust) FieldSpec('default_discount_pct', 'خصم افتراضي %', type: 'number', initial: p['default_discount_pct']?.toString() ?? '0', required: false),
      if (_cust) FieldSpec('eta_receiver_type', 'نوع العميل (فاتورة إلكترونية)', type: 'picker', initial: p['eta_receiver_type']?.toString() ?? 'B', options: const [{'value': 'B', 'label': 'شركة / منشأة'}, {'value': 'P', 'label': 'شخص طبيعي'}, {'value': 'F', 'label': 'أجنبي'}]),
    ]);
    if (v == null) return;
    try {
      await s.api.put('/parties/${p['id']}', {
        'name': v['name'], 'phone': v['phone'], 'tax_no': v['tax_no'], 'address': v['address'],
        if (_cust) 'credit_limit': v['credit_limit'], if (_cust) 'price_level': v['price_level'],
        if (_cust) 'price_list_id': (v['price_list_id'] ?? '').isEmpty ? null : int.parse(v['price_list_id']!),
        if (_cust) 'sales_rep_id': (v['sales_rep_id'] ?? '').isEmpty ? null : int.parse(v['sales_rep_id']!),
        if (_cust) 'default_discount_pct': v['default_discount_pct'], if (_cust) 'eta_receiver_type': v['eta_receiver_type'],
      });
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _statement(Json p) async {
    final s = context.read<Session>();
    final range = await showForm(context, 'كشف حساب ${p['name']}', [
      FieldSpec('from', 'من', type: 'date', initial: DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10)),
      const FieldSpec('to', 'إلى', type: 'date'),
    ], submitLabel: 'عرض');
    if (range == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 900,
          height: 600,
          child: Column(children: [
            PageHeader('كشف حساب ${p['name']}', actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text('طباعة'),
                onPressed: () async {
                  try {
                    final r = await s.api.get('/parties/${p['id']}/statement-print-url', query: {'from': range['from'], 'to': range['to']});
                    if (ctx.mounted) await openUrl(ctx, r['url'].toString());
                  } catch (e) {
                    if (ctx.mounted) toast(ctx, e.toString(), error: true);
                  }
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.chat),
                label: const Text('واتساب'),
                onPressed: () async {
                  try {
                    final r = await s.api.get('/parties/${p['id']}/statement-share', query: {'from': range['from'], 'to': range['to']});
                    if (r['whatsapp'] == null) {
                      await Clipboard.setData(ClipboardData(text: r['text'].toString()));
                      if (ctx.mounted) toast(ctx, 'لا يوجد رقم تليفون للطرف. تم نسخ نص الكشف مع الرابط (صالح 3 أيام).');
                    } else if (ctx.mounted) {
                      await openUrl(ctx, r['whatsapp'].toString());
                    }
                  } catch (e) {
                    if (ctx.mounted) toast(ctx, e.toString(), error: true);
                  }
                },
              ),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Loader(
                  load: () => s.api.get('/reports/statement', query: {'party_id': p['id'], 'from': range['from'], 'to': range['to']}),
                  builder: (c, data, reload) => ReportTable(report: Map<String, dynamic>.from(data as Map)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader(_cust ? 'العملاء' : 'الموردون', actions: [
        SizedBox(
          width: 220,
          child: TextField(decoration: const InputDecoration(hintText: 'بحث بالاسم', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v)),
        ),
        if (s.can('parties.manage')) FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: Text(_cust ? 'عميل جديد' : 'مورد جديد')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/reports/${_cust ? 'customers' : 'suppliers'}'),
          builder: (context, data, reload) {
            final report = Map<String, dynamic>.from(data as Map);
            final rows = asList(report['rows']).where((r) => r['name'].toString().contains(_q)).toList();
            final total = report['totals'] is Map ? report['totals']['balance'] : null;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('${_cust ? 'إجمالي مديونيات العملاء' : 'إجمالي مستحقات الموردين'}: ${fmtCell(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = rows[i];
                    final over = p['over_limit'] == true;
                    return ListTile(
                      title: Text(p['name'].toString()),
                      subtitle: Text('${p['phone'] ?? ''}${toD(p['credit_limit']) > 0 ? '   الحد الائتماني: ${fmtCell(p['credit_limit'])}' : ''}'),
                      leading: over ? const Icon(Icons.warning, color: Colors.red) : const Icon(Icons.person),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_cust && p['rating'] != null) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: Tooltip(message: 'متوسط التأخير ${p['rating']['avg_delay_days']} يوم • متأخر الآن ${fmtCell(p['rating']['overdue'])}', child: Pill(p['rating']['label'].toString(), color: const {'A': Colors.green, 'B': Colors.blue, 'C': Colors.orange, 'D': Colors.red}[p['rating']['grade']] ?? Colors.grey))),
                        Text(fmtCell(p['balance']), style: TextStyle(fontWeight: FontWeight.bold, color: toD(p['balance']) < 0 ? Colors.orange : null)),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'st') _statement(p);
                            if (v == 'edit') _edit(p);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'st', child: Text('كشف حساب')),
                            if (s.can('parties.manage')) const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          ],
                        ),
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
