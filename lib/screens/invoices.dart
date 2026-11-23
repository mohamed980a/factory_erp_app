import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';
import 'customers_plus.dart';
import 'warehouse_plus.dart';
import 'invoice_form.dart';

class InvoicesPage extends StatefulWidget {
  final String side; // sales | purchase
  const InvoicesPage({super.key, required this.side});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  int _tick = 0;
  String _type = '';
  bool _unpaid = false;

  bool get _sales => widget.side == 'sales';

  Future<void> _new() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => InvoiceFormScreen(side: widget.side)));
    if (ok == true && mounted) setState(() => _tick++);
  }

  Future<void> _etaBatch() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'تصدير فواتير البيع للفاتورة الإلكترونية', [
      FieldSpec('from', 'من', type: 'date', initial: DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10)),
      const FieldSpec('to', 'إلى', type: 'date'),
    ], submitLabel: 'تجهيز');
    if (v == null) return;
    try {
      final r = await s.api.get('/eta/batch', query: {'from': v['from'], 'to': v['to']}) as Map;
      final docs = r['documents'] as List;
      final skipped = asList(r['skipped']);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('نتيجة التجهيز'),
          content: SizedBox(
            width: 560,
            height: 380,
            child: ListView(children: [
              Text('جاهز للإرسال: ${docs.length} مستند', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (skipped.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('تعذّر تجهيز ${skipped.length} مستند (أكمل البيانات الناقصة):', style: const TextStyle(color: Colors.red)),
                for (final x in skipped) ListTile(dense: true, title: Text(x['number'].toString()), subtitle: Text((x['errors'] as List).join('\n'))),
              ],
              const SizedBox(height: 8),
              const Text('الملف غير موقَّع. التوقيع الإلكتروني والإرسال يتمّان عبر بوابة المصلحة/SDK بمعرفة محاسب الضرائب، ثم سجّل حالة كل فاتورة هنا.', style: TextStyle(color: Colors.orange)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            if (docs.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  try {
                    final u = await s.api.get('/eta/batch-url', query: {'from': v['from'], 'to': v['to']});
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      await openUrl(ctx, u['url'].toString());
                    }
                  } catch (e) {
                    if (ctx.mounted) toast(ctx, e.toString(), error: true);
                  }
                },
                child: const Text('حفظ ملف JSON'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Widget _statusChip(Json inv) {
    if (inv['status'] == 'reversed') return const Chip(label: Text('ملغاة'), backgroundColor: Color(0xFFFFCDD2));
    switch (inv['payment_status']) {
      case 'paid':
        return const Chip(label: Text('مسددة'), backgroundColor: Color(0xFFC8E6C9));
      case 'partial':
        return const Chip(label: Text('سداد جزئي'), backgroundColor: Color(0xFFFFE0B2));
      default:
        return const Chip(label: Text('غير مسددة'), backgroundColor: Color(0xFFFFF9C4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final canCreate = s.can(_sales ? 'sales.create' : 'purchases.create');
    return Column(children: [
      PageHeader(_sales ? 'المبيعات' : 'المشتريات', actions: [
        InputDecorator(
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _type,
              isDense: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('الفواتير والمرتجعات')),
                DropdownMenuItem(value: _sales ? 'sales' : 'purchase', child: const Text('الفواتير فقط')),
                DropdownMenuItem(value: _sales ? 'sales_return' : 'purchase_return', child: const Text('المرتجعات فقط')),
              ],
              onChanged: (v) => setState(() {
                _type = v ?? '';
                _tick++;
              }),
            ),
          ),
        ),
        FilterChip(label: const Text('غير المسددة فقط'), selected: _unpaid, onSelected: (v) => setState(() {
          _unpaid = v;
          _tick++;
        })),
        if (_sales && canCreate) OutlinedButton.icon(onPressed: _etaBatch, icon: const Icon(Icons.cloud_upload), label: const Text('فاتورة إلكترونية للفترة')),
        if (canCreate) FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: Text(_sales ? 'فاتورة بيع' : 'فاتورة شراء')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick'),
          load: () => s.api.get('/invoices', query: {'side': widget.side, 'type': _type, if (_unpaid) 'unpaid': 1}),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد مستندات.');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final inv = rows[i];
                return ListTile(
                  title: Text('${inv['number']}  •  ${invoiceTypeLabels[inv['type']] ?? inv['type']}  •  ${inv['party']?['name'] ?? ''}'),
                  subtitle: Text('${inv['invoice_date']}'.substring(0, 10)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(fmtCell(inv['total']), style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (inv['type'] == 'sales' || inv['type'] == 'purchase') Text('مسدد ${fmtCell(inv['paid_amount'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                    const SizedBox(width: 12),
                    _statusChip(inv),
                  ]),
                  onTap: () async {
                    final changed = await showDialog<bool>(context: context, builder: (_) => _InvoiceDialog(id: inv['id'] as int));
                    if (changed == true) reload();
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

class _InvoiceDialog extends StatelessWidget {
  final int id;
  const _InvoiceDialog({required this.id});

  Future<void> _print(BuildContext context, Session s) async {
    try {
      final r = await s.api.get('/invoices/$id/print-url');
      if (context.mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _eta(BuildContext context, Session s, Json inv) async {
    try {
      final r = await s.api.get('/invoices/$id/eta') as Map;
      final errors = (r['errors'] as List).map((e) => e.toString()).toList();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('الفاتورة الإلكترونية ${inv['number']}  (${inv['eta_status'] ?? 'لم تُرسل'})'),
          content: SizedBox(
            width: 560,
            height: 320,
            child: ListView(children: [
              Row(children: [
                Icon(r['ready'] == true ? Icons.check_circle : Icons.error, color: r['ready'] == true ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(r['ready'] == true ? 'المستند جاهز (غير موقَّع)' : 'بيانات ناقصة / ملاحظات:'),
              ]),
              for (final e in errors) ListTile(dense: true, leading: const Icon(Icons.warning_amber, size: 18), title: Text(e)),
              const SizedBox(height: 8),
              const Text('بعد التوقيع والإرسال عبر بوابة المصلحة، سجّل الحالة و UUID هنا (ضروري لإشعارات المرتجع).', style: TextStyle(color: Colors.orange)),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final v = await showForm(ctx, 'تسجيل حالة المصلحة', [
                  const FieldSpec('status', 'الحالة', type: 'picker', initial: 'submitted', options: [
                    {'value': 'submitted', 'label': 'أُرسلت'}, {'value': 'valid', 'label': 'مقبولة (Valid)'}, {'value': 'invalid', 'label': 'مرفوضة (Invalid)'}, {'value': 'cancelled', 'label': 'ملغاة'},
                  ]),
                  const FieldSpec('uuid', 'UUID المستند', required: false),
                  const FieldSpec('submission_id', 'رقم الإرسال (Submission ID)', required: false),
                ]);
                if (v == null) return;
                try {
                  await s.api.post('/invoices/$id/eta-status', {'status': v['status'], 'uuid': v['uuid'], 'submission_id': v['submission_id']});
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    toast(ctx, 'تم تسجيل الحالة.');
                  }
                } catch (e) {
                  if (ctx.mounted) toast(ctx, e.toString(), error: true);
                }
              },
              child: const Text('تسجيل حالة المصلحة'),
            ),
            if (r['document'] != null)
              FilledButton(
                onPressed: () async {
                  try {
                    final u = await s.api.get('/invoices/$id/eta-url');
                    if (ctx.mounted) await openUrl(ctx, u['url'].toString());
                  } catch (e) {
                    if (ctx.mounted) toast(ctx, e.toString(), error: true);
                  }
                },
                child: const Text('حفظ JSON'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _reverse(BuildContext context, Session s, Json inv) async {
    final v = await showForm(context, 'إلغاء ${inv['number']}', [
      const FieldSpec('reason', 'سبب الإلغاء'),
      const FieldSpec('date', 'تاريخ الإلغاء', type: 'date'),
    ], submitLabel: 'إلغاء المستند');
    if (v == null || !context.mounted) return;
    try {
      await s.api.post('/invoices/$id/reverse', {'reason': v['reason'], 'date': v['date']});
      if (context.mounted) {
        toast(context, 'تم الإلغاء بقيد عكسي.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (context.mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 620,
        child: Loader(
          load: () => s.api.get('/invoices/$id'),
          builder: (context, data, reload) {
            final inv = Map<String, dynamic>.from(data as Map);
            final lines = asList(inv['lines']);
            final isDoc = inv['type'] == 'sales' || inv['type'] == 'purchase';
            final posted = inv['status'] == 'posted';
            return Column(children: [
              PageHeader('${invoiceTypeLabels[inv['type']]} ${inv['number']}', actions: [
                OutlinedButton.icon(onPressed: () => _print(context, s), icon: const Icon(Icons.print), label: const Text('طباعة')),
                if (posted && (inv['type'] == 'sales' || inv['type'] == 'sales_return') && s.can('sales.create'))
                  OutlinedButton.icon(onPressed: () => _eta(context, s, inv), icon: const Icon(Icons.cloud_upload), label: const Text('فاتورة إلكترونية')),
                if (posted && inv['type'] == 'sales' && s.can('parties.view'))
                  OutlinedButton.icon(onPressed: () => showInstallments(context, inv), icon: const Icon(Icons.calendar_month_outlined), label: const Text('الأقساط')),
                if (posted && inv['type'] == 'purchase' && inv['currency_code'] != null && toD(inv['total']) > toD(inv['paid_amount']) && s.can('payments.create'))
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showForeignPayment(context, inv);
                      if (ok && context.mounted) {
                        toast(context, 'تم تسجيل السداد.');
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.currency_exchange),
                    label: const Text('سداد بالعملة الأجنبية'),
                  ),
                if (posted && inv['type'] == 'purchase' && s.can('purchases.create'))
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showQcDialog(context, inv);
                      if (ok && context.mounted) {
                        toast(context, 'تم تسجيل فحص الجودة.');
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('فحص جودة'),
                  ),
                if (posted && isDoc && s.can('returns.create'))
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(context: context, builder: (_) => _ReturnDialog(invoice: inv));
                      if (ok == true && context.mounted) Navigator.pop(context, true);
                    },
                    icon: const Icon(Icons.undo),
                    label: const Text('مرتجع'),
                  ),
                if (posted && s.can(inv['type'].toString().contains('purchase') ? 'purchases.reverse' : 'sales.reverse'))
                  OutlinedButton.icon(onPressed: () => _reverse(context, s, inv), icon: const Icon(Icons.cancel, color: Colors.red), label: const Text('إلغاء')),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('${inv['party']?['name'] ?? ''}   |   التاريخ: ${inv['invoice_date'].toString().substring(0, 10)}   |   الحالة: ${posted ? 'سارية' : 'ملغاة'}'),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الصنف')), DataColumn(label: Text('الكمية')), DataColumn(label: Text('السعر')), DataColumn(label: Text('خصم %')),
                        DataColumn(label: Text('الصافي')), DataColumn(label: Text('الضريبة')), DataColumn(label: Text('الإجمالي')),
                      ],
                      rows: [
                        for (final l in lines)
                          DataRow(cells: [
                            DataCell(Text('${l['item']?['name'] ?? ''}')), DataCell(Text(fmtCell(l['qty']))), DataCell(Text(fmtCell(l['unit_price']))),
                            DataCell(Text(fmtCell(l['discount_pct']))), DataCell(Text(fmtCell(l['net_amount']))), DataCell(Text(fmtCell(l['tax_amount']))),
                            DataCell(Text(fmtCell(l['total']))),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, children: [
                  Chip(label: Text('قبل الضريبة: ${fmtCell(inv['subtotal'])}')),
                  Chip(label: Text('الضريبة: ${fmtCell(inv['tax_amount'])}')),
                  Chip(label: Text('الإجمالي: ${fmtCell(inv['total'])}')),
                  if (isDoc) Chip(label: Text('المسدّد: ${fmtCell(inv['paid_amount'])}')),
                  if (isDoc) Chip(label: Text('المتبقي: ${fmtCell((toD(inv['total']) - toD(inv['paid_amount'])).toStringAsFixed(2))}')),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _ReturnDialog extends StatefulWidget {
  final Json invoice;
  const _ReturnDialog({required this.invoice});

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  final Map<int, TextEditingController> _qty = {};
  final Map<int, int> _roll = {};
  final Map<int, String> _rollLabel = {};
  final _date = TextEditingController(text: today());
  final _notes = TextEditingController();
  bool _busy = false;

  bool get _purchase => widget.invoice['type'] == 'purchase';

  @override
  void initState() {
    super.initState();
    for (final l in asList(widget.invoice['lines'])) {
      _qty[l['id'] as int] = TextEditingController();
    }
  }

  Future<void> _pickRoll(Json line) async {
    final s = context.read<Session>();
    try {
      final rolls = asList((await s.api.get('/reports/rolls', query: {'item_id': line['item_id'], 'include_empty': 1}))['rows']);
      if (!mounted) return;
      final r = await pickOne(context, 'اختر الرول المرتجع منه', rolls, (r) => 'رول ${r['roll_no']} - متبقي ${r['remaining_qty']}');
      if (r != null) {
        setState(() {
          _roll[line['id'] as int] = r['id'] as int;
          _rollLabel[line['id'] as int] = 'رول ${r['roll_no']}';
        });
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _submit() async {
    final s = context.read<Session>();
    final lines = <Json>[];
    for (final l in asList(widget.invoice['lines'])) {
      final id = l['id'] as int;
      final q = _qty[id]!.text.trim();
      if (q.isEmpty || toD(q) <= 0) continue;
      final tracks = l['item']?['tracks_rolls'] == true;
      if (_purchase && tracks && !_roll.containsKey(id)) return toast(context, 'اختر الرول المرتجع منه للصنف ${l['item']?['name']}.', error: true);
      lines.add({'original_line_id': id, 'qty': q, if (_roll.containsKey(id)) 'roll_id': _roll[id]});
    }
    if (lines.isEmpty) return toast(context, 'أدخل كمية مرتجع لبند واحد على الأقل.', error: true);
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/invoices/${widget.invoice['id']}/return', {'date': _date.text, 'notes': _notes.text, 'lines': lines});
      if (mounted) {
        toast(context, 'تم المرتجع ${r['number']} بإجمالي ${fmtCell(r['total'])}.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = asList(widget.invoice['lines']);
    return AlertDialog(
      title: Text('مرتجع على ${widget.invoice['number']}'),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: _date, readOnly: true, onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(_date.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null) setState(() => _date.text = d.toIso8601String().substring(0, 10));
            }, decoration: const InputDecoration(labelText: 'تاريخ المرتجع', suffixIcon: Icon(Icons.calendar_today, size: 18)))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات'))),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final l in lines)
                ListTile(
                  title: Text('${l['item']?['name']}'),
                  subtitle: Text('الكمية الأصلية: ${fmtCell(l['qty'])}'),
                  trailing: SizedBox(
                    width: 260,
                    child: Row(children: [
                      if (_purchase && l['item']?['tracks_rolls'] == true)
                        TextButton(onPressed: () => _pickRoll(l), child: Text(_rollLabel[l['id'] as int] ?? 'اختر الرول')),
                      Expanded(child: TextField(controller: _qty[l['id'] as int], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'كمية المرتجع'))),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('تسجيل المرتجع')),
      ],
    );
  }
}
