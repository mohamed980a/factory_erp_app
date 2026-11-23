import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const _leaveStatus = {'pending': 'بانتظار الموافقة', 'approved': 'معتمدة', 'rejected': 'مرفوضة', 'cancelled': 'ملغاة'};

/// طلبات الإجازات: المحاسب يسجّل الطلب، والمالك يوافق أو يرفض، والإجازة المعتمدة تُسجَّل تلقائيًا في الحضور.
class LeavesPage extends StatefulWidget {
  const LeavesPage({super.key});

  @override
  State<LeavesPage> createState() => _LeavesPageState();
}

class _LeavesPageState extends State<LeavesPage> {
  int _tick = 0;

  Future<void> _new() async {
    final s = context.read<Session>();
    try {
      final emps = asList(await s.api.get('/employees')).where((e) => e['is_active'] != false).toList();
      final st = await s.api.get('/attendance-settings') as Map;
      if (!mounted) return;
      final types = (st['leave_types'] as Map).entries.map((e) => <String, dynamic>{'value': e.key, 'label': e.value}).toList();
      final v = await showForm(context, 'طلب إجازة', [
        FieldSpec('employee_id', 'الموظف', type: 'picker', options: emps.map((e) => <String, dynamic>{'value': e['id'], 'label': '${e['name']}'}).toList()),
        FieldSpec('type', 'نوع الإجازة', type: 'picker', initial: 'annual', options: types),
        const FieldSpec('from_date', 'من', type: 'date'),
        const FieldSpec('to_date', 'إلى', type: 'date'),
        const FieldSpec('reason', 'السبب', required: false),
      ], submitLabel: 'تسجيل الطلب');
      if (v == null) return;
      await s.api.post('/leave-requests', {'employee_id': int.parse(v['employee_id']!), 'type': v['type'], 'from_date': v['from_date'], 'to_date': v['to_date'], 'reason': v['reason']});
      if (mounted) {
        toast(context, 'تم تسجيل الطلب وبانتظار موافقة المالك.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _decide(Json l, bool approve) async {
    final s = context.read<Session>();
    String? note;
    if (!approve) {
      final v = await showForm(context, 'رفض الطلب', [const FieldSpec('note', 'سبب الرفض')], submitLabel: 'رفض');
      if (v == null) return;
      note = v['note'];
    } else if (!await confirm(context, 'الموافقة على إجازة ${l['employee_name']} (${fmtQty(l['days'])} يوم)؟ ستُسجَّل في الحضور تلقائيًا.')) {
      return;
    }
    try {
      await s.api.post('/leave-requests/${l['id']}/decide', {'approve': approve, 'note': note});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel(Json l) async {
    final s = context.read<Session>();
    if (!await confirm(context, 'إلغاء هذا الطلب؟')) return;
    try {
      await s.api.post('/leave-requests/${l['id']}/cancel');
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _balances() async {
    final s = context.read<Session>();
    try {
      final rows = asList(await s.api.get('/leave-balances'));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('رصيد الإجازات الاعتيادية ${DateTime.now().year}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final r in rows) ListTile(dense: true, title: Text('${r['name']}'), subtitle: Text('الإجمالي ${fmtQty(r['total'])} • المستخدم ${fmtQty(r['used'])}'), trailing: Text('متبقي ${fmtQty(r['remaining'])}', style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
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
    final s = context.watch<Session>();
    return Column(children: [
      PageHeader('الإجازات', subtitle: 'طلب ← موافقة المالك ← تُسجَّل في الحضور وتُخصم من الرصيد', actions: [
        OutlinedButton.icon(onPressed: _balances, icon: const Icon(Icons.event_note), label: const Text('أرصدة الإجازات')),
        if (s.can('payroll.manage')) FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('طلب إجازة')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/leave-requests'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد طلبات إجازة');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final l = rows[i];
                final st = l['status'].toString();
                return Card(
                  child: ListTile(
                    title: Text('${l['employee_name']}  —  ${l['type_label']}  (${fmtQty(l['days'])} يوم)'),
                    subtitle: Text('${l['from_date'].toString().substring(0, 10)}  →  ${l['to_date'].toString().substring(0, 10)}${(l['reason'] ?? '').toString().isEmpty ? '' : '  •  ${l['reason']}'}${(l['decision_note'] ?? '').toString().isEmpty ? '' : '  •  ${l['decision_note']}'}'),
                    trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Pill(_leaveStatus[st] ?? st, color: st == 'approved' ? Colors.green.shade700 : (st == 'pending' ? Colors.orange.shade800 : Colors.grey)),
                      if (st == 'pending' && s.can('payroll.approve')) IconButton(icon: const Icon(Icons.check_circle_outline), tooltip: 'موافقة', onPressed: () => _decide(l, true)),
                      if (st == 'pending' && s.can('payroll.approve')) IconButton(icon: const Icon(Icons.cancel_outlined), tooltip: 'رفض', onPressed: () => _decide(l, false)),
                      if ((st == 'pending' && s.can('payroll.manage')) || (st == 'approved' && s.can('payroll.approve'))) IconButton(icon: const Icon(Icons.undo, size: 18), tooltip: 'إلغاء', onPressed: () => _cancel(l)),
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
