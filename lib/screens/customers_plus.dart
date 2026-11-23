import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const Map<String, Color> _gradeColors = {'A': Colors.green, 'B': Colors.blue, 'C': Colors.orange, 'D': Colors.red, 'N': Colors.grey};

/// قائمة التحصيل اليومية: المتأخر + المستحق قريبًا، مع تذكير واتساب جاهز لكل عميل.
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  int _tick = 0;

  Future<void> _overdueInstallments() async {
    final s = context.read<Session>();
    try {
      final rows = asList(await s.api.get('/installments/overdue'));
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('الأقساط المتأخرة'),
          content: SizedBox(
            width: 560,
            height: 380,
            child: rows.isEmpty
                ? const EmptyState('لا توجد أقساط متأخرة')
                : ListView(children: [
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        title: Text('${r['party']}  •  فاتورة ${r['invoice']}'),
                        subtitle: Text('القسط ${r['seq']}  •  استحقاق ${r['due_date']}  •  المتبقي ${fmtCell(r['rest'])}'),
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
      PageHeader('قائمة التحصيل', actions: [
        OutlinedButton.icon(onPressed: _overdueInstallments, icon: const Icon(Icons.event_busy), label: const Text('الأقساط المتأخرة')),
        IconButton(tooltip: 'تحديث', onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(alignment: Alignment.centerRight, child: Text('العملاء المتأخرون أو المستحق عليهم خلال 3 أيام، الأعلى مديونية أولًا. اضغط «واتساب» لفتح رسالة تذكير جاهزة.')),
      ),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/collections'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد مستحقات متأخرة أو قريبة 🎉');
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = rows[i];
                final wa = r['whatsapp_url']?.toString();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(r['party'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Pill(const {'A': 'ممتاز', 'B': 'جيد', 'C': 'متأخر', 'D': 'خطر'}[r['grade']] ?? 'ممتاز', color: _gradeColors[r['grade']] ?? Colors.green),
                        if (toD(r['max_days_late']) > 0) Pill('متأخر ${r['max_days_late']} يوم', color: Colors.red),
                        Text(r['phone']?.toString() ?? 'لا يوجد رقم تليفون'),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        Chip(label: Text('متأخر: ${fmtCell(r['overdue'])}')),
                        Chip(label: Text('مستحق قريبًا: ${fmtCell(r['upcoming'])}')),
                        Chip(label: Text('الإجمالي: ${fmtCell(r['total'])}')),
                        Chip(label: Text('${r['invoices']} فاتورة')),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, children: [
                        FilledButton.icon(
                          onPressed: wa == null ? null : () => openUrl(context, wa),
                          icon: const Icon(Icons.chat),
                          label: Text(wa == null ? 'لا يوجد رقم' : 'واتساب'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: r['message'].toString()));
                            if (context.mounted) toast(context, 'تم نسخ نص التذكير.');
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('نسخ الرسالة'),
                        ),
                      ]),
                    ]),
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

/// عروض الأسعار: عرض → تحويل لأمر بيع (حجز) → فاتورة.
class QuotesPage extends StatefulWidget {
  const QuotesPage({super.key});

  @override
  State<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends State<QuotesPage> {
  int _tick = 0;
  static const _labels = {'open': 'مفتوح', 'converted': 'حُوِّل لأمر بيع', 'cancelled': 'ملغي'};

  Future<void> _create() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta();
      final parties = asList(await s.api.get('/parties', query: {'type': 'customer', 'active': 1}));
      final items = asList(await s.api.get('/items', query: {'active': 1, 'kind': 'finished'}));
      if (!mounted) return;
      final whs = asList(meta['warehouses']);
      final fin = whs.where((w) => w['type'] == 'finished').toList();
      final head = await showForm(context, 'عرض سعر جديد', [
        FieldSpec('party_id', 'العميل', type: 'picker', options: [for (final p in parties) {'value': p['id'], 'label': p['name']}]),
        FieldSpec('warehouse_id', 'المخزن', type: 'picker', initial: fin.isNotEmpty ? fin.first['id'].toString() : null, options: [for (final w in whs) {'value': w['id'], 'label': w['name']}]),
        const FieldSpec('date', 'تاريخ العرض', type: 'date'),
        FieldSpec('valid_until', 'صالح حتى', type: 'date', required: false, initial: DateTime.now().add(const Duration(days: 14)).toIso8601String().substring(0, 10)),
        const FieldSpec('notes', 'ملاحظات', required: false),
      ]);
      if (head == null) return;
      final lines = <Json>[];
      while (mounted) {
        final it = await pickOne(context, lines.isEmpty ? 'اختر الصنف' : 'اختر صنفًا آخر (إلغاء للانتهاء)', items, (i) => '${i['name']}  (${i['code']})');
        if (it == null || !mounted) break;
        String price = fmtCell(it['sale_price'] ?? '0');
        try {
          final pr = await s.api.get('/price-lookup', query: {'party_id': head['party_id'], 'item_id': it['id']}) as Map<String, dynamic>;
          price = fmtCell(pr['price']);
        } catch (_) {}
        if (!mounted) break;
        final l = await showForm(context, it['name'].toString(), [
          const FieldSpec('qty', 'الكمية', type: 'number'),
          FieldSpec('unit_price', 'سعر الوحدة (بدون ضريبة)', type: 'number', initial: price),
          const FieldSpec('discount_pct', 'خصم %', type: 'number', initial: '0', required: false),
        ]);
        if (l == null) continue;
        lines.add({'item_id': it['id'], 'qty': l['qty'], 'unit_price': l['unit_price'], 'discount_pct': (l['discount_pct'] ?? '').isEmpty ? '0' : l['discount_pct']});
      }
      if (lines.isEmpty || !mounted) return;
      await s.api.post('/quotes', {
        'party_id': int.parse(head['party_id']!), 'warehouse_id': int.parse(head['warehouse_id']!), 'date': head['date'],
        if ((head['valid_until'] ?? '').isNotEmpty) 'valid_until': head['valid_until'], 'notes': head['notes'], 'lines': lines,
      }, newKey());
      if (mounted) {
        toast(context, 'تم حفظ عرض السعر.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _convert(Json q) async {
    final s = context.read<Session>();
    final ok = await confirm(context, 'تحويل العرض ${q['number']} إلى أمر بيع؟ سيتم حجز الكميات من المخزون.');
    if (ok != true) return;
    try {
      await s.api.post('/quotes/${q['id']}/convert', {});
      if (mounted) {
        toast(context, 'تم التحويل. تجده في «أوامر البيع والحجز» وتحوّله لفاتورة من شاشة المبيعات.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel(Json q) async {
    final s = context.read<Session>();
    final ok = await confirm(context, 'إلغاء العرض ${q['number']}؟');
    if (ok != true) return;
    try {
      await s.api.post('/quotes/${q['id']}/cancel', {});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _show(Json q) async {
    final s = context.read<Session>();
    try {
      final d = await s.api.get('/quotes/${q['id']}') as Map<String, dynamic>;
      if (!mounted) return;
      var total = 0.0;
      final lines = asList(d['lines']);
      for (final l in lines) {
        total += toD(l['qty']) * toD(l['unit_price']) * (1 - toD(l['discount_pct']) / 100);
      }
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('عرض ${d['number']} - ${d['party']?['name']}'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in lines)
                ListTile(
                  dense: true,
                  title: Text(l['item']?['name']?.toString() ?? ''),
                  subtitle: Text('${fmtQty(l['qty'])} × ${fmtCell(l['unit_price'])}${toD(l['discount_pct']) > 0 ? '  خصم ${fmtCell(l['discount_pct'])}%' : ''}'),
                ),
              const Divider(),
              Text('الإجمالي قبل الضريبة: ${fmtCell(total.toStringAsFixed(2))}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
      PageHeader('عروض الأسعار', actions: [
        if (s.can('sales.create')) FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('عرض سعر جديد')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/quotes'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد عروض أسعار');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final q = rows[i];
                final expired = q['status'] == 'open' && (q['valid_until'] ?? '').toString().isNotEmpty && q['valid_until'].toString().compareTo(today()) < 0;
                return ListTile(
                  dense: true,
                  onTap: () => _show(q),
                  title: Text('${q['number']}  -  ${q['party']?['name'] ?? ''}'),
                  subtitle: Text('تاريخ ${q['quote_date']}  •  صالح حتى ${q['valid_until'] ?? '-'}  •  تقديري ${fmtCell(q['total_est'])}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (expired) const Pill('منتهي الصلاحية', color: Colors.red),
                    Pill(_labels[q['status']] ?? q['status'].toString(), color: q['status'] == 'open' ? AppColors.brand : Colors.grey),
                    if (q['status'] == 'open' && s.can('sales.create')) ...[
                      IconButton(tooltip: 'تحويل لأمر بيع', icon: const Icon(Icons.arrow_circle_left_outlined), onPressed: expired ? null : () => _convert(q)),
                      IconButton(tooltip: 'إلغاء', icon: const Icon(Icons.cancel_outlined), onPressed: () => _cancel(q)),
                    ],
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

/// قوائم الأسعار المسماة (جملة كبار، موزعين، ...).
class PriceListsPage extends StatefulWidget {
  const PriceListsPage({super.key});

  @override
  State<PriceListsPage> createState() => _PriceListsPageState();
}

class _PriceListsPageState extends State<PriceListsPage> {
  int _tick = 0;

  Future<void> _create() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'قائمة أسعار جديدة', [const FieldSpec('name', 'اسم القائمة'), const FieldSpec('notes', 'ملاحظات', required: false)]);
    if (v == null) return;
    try {
      await s.api.post('/price-lists', {'name': v['name'], 'notes': v['notes']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(Json pl) async {
    final s = context.read<Session>();
    try {
      final d = await s.api.get('/price-lists/${pl['id']}') as Map<String, dynamic>;
      final all = asList(await s.api.get('/items', query: {'active': 1}));
      if (!mounted) return;
      final rows = <Json>[
        for (final r in asList(d['items'])) {'item_id': r['item_id'], 'name': r['item']?['name'] ?? '', 'price': fmtCell(r['price'])},
      ];
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text('أسعار «${pl['name']}»'),
            content: SizedBox(
              width: 560,
              height: 420,
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة صنف'),
                    onPressed: () async {
                      final it = await pickOne(ctx, 'اختر الصنف', all, (i) => '${i['name']}  (${i['code']})');
                      if (it == null || !ctx.mounted) return;
                      if (rows.any((r) => r['item_id'] == it['id'])) return toast(ctx, 'الصنف موجود بالفعل في القائمة.', error: true);
                      final v = await showForm(ctx, it['name'].toString(), [FieldSpec('price', 'السعر (بدون ضريبة)', type: 'number', initial: fmtCell(it['sale_price'] ?? '0'))]);
                      if (v == null) return;
                      setD(() => rows.add({'item_id': it['id'], 'name': it['name'], 'price': v['price']}));
                    },
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? const EmptyState('القائمة فارغة — الأصناف غير المسعّرة هنا تأخذ سعرها العادي')
                      : ListView(children: [
                          for (final r in rows)
                            ListTile(
                              dense: true,
                              title: Text(r['name'].toString()),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(r['price'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setD(() => rows.remove(r))),
                              ]),
                            ),
                        ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
            ],
          ),
        ),
      );
      if (saved != true) return;
      await s.api.put('/price-lists/${pl['id']}/items', {'items': [for (final r in rows) {'item_id': r['item_id'], 'price': r['price']}]});
      if (mounted) {
        toast(context, 'تم حفظ القائمة.');
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
      PageHeader('قوائم الأسعار', actions: [
        if (s.can('parties.manage')) FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('قائمة جديدة')),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(alignment: Alignment.centerRight, child: Text('اربط العميل بقائمة من «العملاء ← تعديل»؛ فتظهر أسعارها تلقائيًا في فاتورته.')),
      ),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/price-lists'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد قوائم أسعار');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                title: Text(rows[i]['name'].toString()),
                subtitle: Text('${rows[i]['items_count']} صنف${(rows[i]['notes'] ?? '').toString().isEmpty ? '' : '  •  ${rows[i]['notes']}'}'),
                trailing: s.can('parties.manage') ? const Icon(Icons.edit_outlined) : null,
                onTap: s.can('parties.manage') ? () => _edit(rows[i]) : null,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// مناديب المبيعات ونسب عمولاتهم.
class SalesRepsPage extends StatefulWidget {
  const SalesRepsPage({super.key});

  @override
  State<SalesRepsPage> createState() => _SalesRepsPageState();
}

class _SalesRepsPageState extends State<SalesRepsPage> {
  int _tick = 0;

  Future<void> _form([Json? r]) async {
    final s = context.read<Session>();
    final v = await showForm(context, r == null ? 'مندوب جديد' : 'تعديل ${r['name']}', [
      FieldSpec('name', 'الاسم', initial: r?['name']?.toString()),
      FieldSpec('phone', 'التليفون', initial: r?['phone']?.toString(), required: false),
      FieldSpec('commission_pct', 'نسبة العمولة % (على المحصَّل قبل الضريبة)', type: 'number', initial: r == null ? '0' : fmtCell(r['commission_pct'])),
    ]);
    if (v == null) return;
    try {
      final body = {'name': v['name'], 'phone': v['phone'], 'commission_pct': v['commission_pct']};
      if (r == null) {
        await s.api.post('/sales-reps', body);
      } else {
        await s.api.put('/sales-reps/${r['id']}', body);
      }
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _toggle(Json r) async {
    try {
      await context.read<Session>().api.put('/sales-reps/${r['id']}', {'is_active': !(r['is_active'] == true)});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('مناديب المبيعات', actions: [
        if (s.can('parties.manage')) FilledButton.icon(onPressed: () => _form(), icon: const Icon(Icons.add), label: const Text('مندوب جديد')),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(alignment: Alignment.centerRight, child: Text('اربط العميل بمندوبه من «العملاء ← تعديل». تقرير «عمولات المناديب» في شاشة التقارير يحسب العمولة على ما تم تحصيله فعلًا.')),
      ),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/sales-reps'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا يوجد مناديب');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final active = r['is_active'] == true;
                return ListTile(
                  title: Text(r['name'].toString()),
                  subtitle: Text('${r['phone'] ?? ''}   عمولة ${fmtCell(r['commission_pct'])}%'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Pill(active ? 'نشط' : 'موقوف', color: active ? Colors.green : Colors.grey),
                    if (s.can('parties.manage')) ...[
                      IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () => _form(r)),
                      IconButton(tooltip: active ? 'إيقاف' : 'تفعيل', icon: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline), onPressed: () => _toggle(r)),
                    ],
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

/// خطة أقساط فاتورة بيع: عرض الحالة، إنشاء، حذف.
Future<void> showInstallments(BuildContext context, Json invoice) async {
  final s = context.read<Session>();
  final id = invoice['id'];
  Future<Map<String, dynamic>> load() async => await s.api.get('/invoices/$id/installments') as Map<String, dynamic>;
  try {
    var plan = await load();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final rows = asList(plan['rows']);
          Future<void> create() async {
            final v = await showForm(ctx, 'خطة أقساط', [
              const FieldSpec('count', 'عدد الأقساط', type: 'number', initial: '3'),
              FieldSpec('first_due', 'تاريخ القسط الأول', type: 'date', initial: DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10)),
              const FieldSpec('interval_days', 'عدد الأيام بين الأقساط', type: 'number', initial: '30'),
            ]);
            if (v == null) return;
            try {
              await s.api.post('/invoices/$id/installments', {'count': int.parse(v['count']!.split('.').first), 'first_due': v['first_due'], 'interval_days': int.parse(v['interval_days']!.split('.').first)});
              plan = await load();
              setD(() {});
            } catch (e) {
              if (ctx.mounted) toast(ctx, e.toString(), error: true);
            }
          }

          Future<void> remove() async {
            final ok = await confirm(ctx, 'حذف خطة الأقساط؟ (الفاتورة نفسها لا تتأثر)');
            if (ok != true) return;
            try {
              await s.api.delete('/invoices/$id/installments');
              plan = await load();
              setD(() {});
            } catch (e) {
              if (ctx.mounted) toast(ctx, e.toString(), error: true);
            }
          }

          const colors = {'paid': Colors.green, 'overdue': Colors.red, 'partial': Colors.orange, 'pending': Colors.grey};
          const names = {'paid': 'مسدَّد', 'overdue': 'متأخر', 'partial': 'جزئي', 'pending': 'قادم'};
          return AlertDialog(
            title: Text('أقساط الفاتورة ${invoice['number']}'),
            content: SizedBox(
              width: 560,
              height: 360,
              child: rows.isEmpty
                  ? const EmptyState('لا توجد خطة أقساط لهذه الفاتورة')
                  : ListView(children: [
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(radius: 14, child: Text('${r['seq']}')),
                          title: Text('${fmtCell(r['amount'])}  •  استحقاق ${r['due_date']}'),
                          subtitle: Text('مسدَّد ${fmtCell(r['paid'])}  •  متبقي ${fmtCell(r['rest'])}'),
                          trailing: Pill(names[r['status']] ?? '', color: colors[r['status']] ?? Colors.grey),
                        ),
                    ]),
            ),
            actions: [
              if (s.can('parties.manage') && rows.isEmpty) FilledButton(onPressed: create, child: const Text('إنشاء خطة أقساط')),
              if (s.can('parties.manage') && rows.isNotEmpty) TextButton(onPressed: remove, child: const Text('حذف الخطة', style: TextStyle(color: Colors.red))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            ],
          );
        },
      ),
    );
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), error: true);
  }
}
