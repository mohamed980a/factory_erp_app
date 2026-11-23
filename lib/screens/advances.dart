import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// سلف الموظفين: تُصرف من خزينة وتُخصم تلقائيًا (بالأقدم أولًا) من كشف الراتب.
class AdvancesPage extends StatefulWidget {
  const AdvancesPage({super.key});

  @override
  State<AdvancesPage> createState() => _AdvancesPageState();
}

class _AdvancesPageState extends State<AdvancesPage> {
  int _tick = 0;

  Future<void> _give() async {
    final s = context.read<Session>();
    try {
      final emps = asList(await s.api.get('/employees')).where((e) => e['is_active'] != false).toList();
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final ts = asList(meta['treasuries']);
      final v = await showForm(context, 'صرف سلفة', [
        FieldSpec('employee_id', 'الموظف', type: 'picker', options: emps.map((e) => <String, dynamic>{'value': e['id'], 'label': '${e['name']}'}).toList()),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        const FieldSpec('months', 'يُسدَّد على كم شهر؟ (1 = دفعة واحدة)', type: 'number', initial: '1'),
        FieldSpec('treasury_id', 'تُصرف من', type: 'picker', options: ts.map((t) => <String, dynamic>{'value': t['id'], 'label': t['name']}).toList(), initial: ts.isNotEmpty ? ts.first['id'].toString() : null),
        const FieldSpec('date', 'التاريخ', type: 'date'),
        const FieldSpec('note', 'ملاحظة', required: false),
      ], submitLabel: 'صرف');
      if (v == null) return;
      await s.api.post('/employee-advances', {'employee_id': int.parse(v['employee_id']!), 'amount': v['amount'], 'months': int.tryParse(v['months'] ?? '') ?? 1, 'treasury_id': int.parse(v['treasury_id']!), 'date': v['date'], 'note': v['note']});
      if (mounted) {
        toast(context, 'تم صرف السلفة.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel(Json a) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء السلفة', [const FieldSpec('reason', 'السبب')], submitLabel: 'إلغاء السلفة');
    if (v == null) return;
    try {
      await s.api.post('/employee-advances/${a['id']}/cancel', {'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final manage = s.can('payroll.manage');
    return Column(children: [
      PageHeader('سلف الموظفين', actions: [
        if (manage) FilledButton.icon(onPressed: _give, icon: const Icon(Icons.add), label: const Text('صرف سلفة')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/employee-advances'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد سلف');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final a = rows[i];
                final st = a['status'].toString();
                return Card(
                  child: ListTile(
                    title: Text('${a['employee_name']}  —  ${fmtCell(a['amount'])}'),
                    subtitle: Text('${a['advance_date'].toString().substring(0, 10)}  •  ${a['installments'] == null ? 'بدون تقسيط' : 'على ${a['installments']} شهر — القسط ${fmtCell(a['installment_amount'])}'}  •  المتبقي ${fmtCell((double.tryParse('${a['amount']}') ?? 0) - (double.tryParse('${a['recovered']}') ?? 0))}${(a['note'] ?? '').toString().isEmpty ? '' : '  •  ${a['note']}'}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Pill(st == 'open' ? 'مفتوحة' : (st == 'settled' ? 'مُسدَّدة' : 'ملغاة'), color: st == 'open' ? Colors.orange.shade800 : (st == 'settled' ? Colors.green.shade700 : Colors.grey)),
                      if (manage && st == 'open') IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'إلغاء', onPressed: () => _cancel(a)),
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
