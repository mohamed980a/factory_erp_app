import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// التكلفة النهائية للمستورد: رسملة مصروف شحن/جمارك/تخليص على بضاعة فاتورة شراء.
class LandedCostPage extends StatefulWidget {
  const LandedCostPage({super.key});

  @override
  State<LandedCostPage> createState() => _LandedCostPageState();
}

class _LandedCostPageState extends State<LandedCostPage> {
  int _tick = 0;

  Future<void> _create() async {
    final s = context.read<Session>();
    try {
      final cands = asList(await s.api.get('/landed-costs/candidates'));
      if (!mounted) return;
      if (cands.isEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('سجّل المصروف أولًا'),
            content: const Text('التكلفة النهائية تُرسمل مصروفًا سبق تسجيله.\nاذهب إلى «المصروفات»، سجّل مصروف الشحن/الجمارك/التخليص (من بند «نقل وشحن» مثلًا)، ثم ارجع هنا واربطه بفاتورة الشراء.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
          ),
        );
        return;
      }
      final pay = await pickOne(context, '١) اختر مصروف الشحن/الجمارك', cands, (c) => '${c['number']} • ${c['date']} • ${c['account']} • متاح ${fmtCell(c['available'])}');
      if (pay == null || !mounted) return;
      final inv = asList((await s.api.get('/invoices', query: {'type': 'purchase', 'status': 'posted'}))['data']);
      if (!mounted) return;
      final invoice = await pickOne(context, '٢) اختر فاتورة الشراء التي وصلت بضاعتها', inv, (i) => '${i['number']} • ${i['party']?['name'] ?? ''} • ${fmtCell(i['total'])}');
      if (invoice == null || !mounted) return;
      final v = await showForm(context, 'توزيع ${fmtCell(pay['available'])} على ${invoice['number']}', [
        FieldSpec('method', 'طريقة التوزيع على الأصناف', type: 'picker', initial: 'value', options: [{'value': 'value', 'label': 'بنسبة القيمة (الأغلى يتحمل أكثر)'}, {'value': 'qty', 'label': 'بنسبة الكمية'}]),
        FieldSpec('amount', 'المبلغ المراد رسملته', type: 'number', initial: fmtCell(pay['available'])),
        const FieldSpec('date', 'التاريخ', type: 'date'),
        const FieldSpec('notes', 'ملاحظات', required: false),
      ]);
      if (v == null) return;
      await s.api.post('/landed-costs', {'invoice_id': invoice['id'], 'payment_id': pay['payment_id'], 'method': v['method'], 'amount': v['amount'], 'date': v['date'], 'notes': v['notes']}, newKey());
      if (mounted) {
        toast(context, 'تمت رسملة التكلفة على المخزون، وارتفع متوسط تكلفة الأصناف.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _reverse(Json lc) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء ${lc['number']}', [const FieldSpec('date', 'تاريخ الإلغاء', type: 'date'), const FieldSpec('reason', 'السبب')]);
    if (v == null) return;
    try {
      await s.api.post('/landed-costs/${lc['id']}/reverse', {'date': v['date'], 'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('التكلفة النهائية للمستورد', actions: [
        if (s.can('purchases.create')) FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('رسملة تكلفة جديدة')),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text('الخطوات: سجّل مصروف الشحن/الجمارك من «المصروفات» ← اربطه هنا بفاتورة الشراء. تتوزع التكلفة على أصناف الفاتورة فترتفع تكلفة المخزون ولا تظهر كمصروف. لا تُقبل الرسملة لو صُرف جزء من البضاعة.'),
        ),
      ),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/landed-costs'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد تكاليف نهائية مسجّلة');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final ok = r['status'] == 'posted';
                return ListTile(
                  title: Text('${r['number']}  •  ${fmtCell(r['amount'])}  على فاتورة ${r['invoice']?['number'] ?? ''}'),
                  subtitle: Text('${r['invoice']?['party']?['name'] ?? ''}  •  من ${r['payment']?['number'] ?? ''}  •  ${r['method'] == 'qty' ? 'بالكمية' : 'بالقيمة'}  •  ${r['cost_date']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Pill(ok ? 'مُرسمَلة' : 'ملغاة', color: ok ? Colors.green : Colors.grey),
                    if (ok && s.can('purchases.create')) IconButton(tooltip: 'إلغاء', icon: const Icon(Icons.undo), onPressed: () => _reverse(r)),
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

/// العملات الأجنبية وأسعار الصرف اليومية (للموردين المستوردين).
class CurrenciesPage extends StatefulWidget {
  const CurrenciesPage({super.key});

  @override
  State<CurrenciesPage> createState() => _CurrenciesPageState();
}

class _CurrenciesPageState extends State<CurrenciesPage> {
  int _tick = 0;

  Future<void> _setRate(Json c) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'سعر ${c['name']} (جنيه لكل 1 ${c['code']})', [
      FieldSpec('rate', 'السعر', type: 'number', initial: c['latest_rate']?.toString()),
      const FieldSpec('date', 'ساريًا من', type: 'date'),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/exchange-rates', {'currency_code': c['code'], 'date': v['date'], 'rate': v['rate']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      const PageHeader('العملات وأسعار الصرف'),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(alignment: Alignment.centerRight, child: Text('سجّل سعر اليوم ليُقترح تلقائيًا في فاتورة الشراء بعملة أجنبية وعند السداد. الفرق بين سعر القيد وسعر السداد يُسجَّل ربح/خسارة فروق عملة.')),
      ),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/currencies'),
          builder: (context, data, reload) {
            final rows = asList(data);
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = rows[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(c['symbol']?.toString() ?? c['code'].toString())),
                  title: Text('${c['name']}  (${c['code']})'),
                  subtitle: Text(c['latest_rate'] == null ? 'لا يوجد سعر مسجَّل' : 'آخر سعر: ${fmtCell(c['latest_rate'])} جنيه'),
                  trailing: s.can('purchases.create') ? TextButton.icon(onPressed: () => _setRate(c), icon: const Icon(Icons.edit_outlined), label: const Text('تحديث السعر')) : null,
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
