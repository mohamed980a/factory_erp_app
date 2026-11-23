import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';
import '../core/nav.dart';

/// إنتاج القطعة: تسجيل ما أنجزه كل عامل على أمر تصنيع؛ يدخل تلقائيًا في تكلفة الأمر (تحت التشغيل).
class PieceWorkPage extends StatefulWidget {
  const PieceWorkPage({super.key});

  @override
  State<PieceWorkPage> createState() => _PieceWorkPageState();
}

class _PieceWorkPageState extends State<PieceWorkPage> {
  int _tick = 0;
  String _status = 'open';

  Future<void> _add() async {
    final s = context.read<Session>();
    try {
      final orders = asList(await s.api.get('/production', query: {'status': 'in_progress'}));
      final ops = asList(await s.api.get('/piece-operations')).where((o) => o['is_active'] != false).toList();
      final emps = asList(await s.api.get('/employees')).where((e) => e['pay_type'] == 'piece' && e['is_active'] != false).toList();
      if (!mounted) return;
      if (orders.isEmpty) return _blocked('لا يوجد أمر تصنيع قيد التنفيذ.', 'أنشئ أمر تصنيع واضغط «بدء التنفيذ» ثم سجّل الإنتاج عليه.', 'production', 'فتح التصنيع');
      if (ops.isEmpty) return _blocked('لم تُعرَّف عمليات قطعة بعد.', 'من شاشة الموظفين والعمال اضغط «عمليات القطعة وأسعارها» وأضف عملية مثل «تركيب جيب» بسعرها.', 'employees', 'فتح الموظفين');
      if (emps.isEmpty) return _blocked('لا يوجد عمال بنظام «بالقطعة».', 'أضف عاملًا واختر نظام المحاسبة «بالقطعة». العامل الشهري أو اليومي لا يُسجَّل له إنتاج قطعة.', 'employees', 'فتح الموظفين');
      final head = await showForm(context, 'تسجيل إنتاج', [
        FieldSpec('order', 'أمر التصنيع', type: 'picker', options: orders.map((o) => <String, dynamic>{'value': o['id'], 'label': '${o['number']}'}).toList()),
        FieldSpec('op', 'العملية', type: 'picker', options: ops.map((o) => <String, dynamic>{'value': o['id'], 'label': '${o['name']}  (${fmtCell(o['rate'])})'}).toList()),
        const FieldSpec('date', 'التاريخ', type: 'date'),
      ], submitLabel: 'التالي');
      if (head == null || !mounted) return;
      final qty = <int, TextEditingController>{for (final e in emps) e['id'] as int: TextEditingController()};
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('كمية كل عامل'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in emps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text('${e['name']}')),
                      SizedBox(width: 110, child: TextField(controller: qty[e['id']], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'القطع'))),
                    ]),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
          ],
        ),
      );
      final entries = <Map<String, dynamic>>[
        for (final e in emps)
          if ((double.tryParse(qty[e['id']]!.text.trim()) ?? 0) > 0)
            {'employee_id': e['id'], 'piece_operation_id': int.parse(head['op']!), 'production_order_id': int.parse(head['order']!), 'qty': qty[e['id']]!.text.trim(), 'work_date': head['date']},
      ];
      for (final c in qty.values) {
        c.dispose();
      }
      if (ok != true) return;
      if (entries.isEmpty) return toast(context, 'لم تدخل أي كمية.', error: true);
      await s.api.post('/piece-entries', {'entries': entries});
      if (mounted) {
        toast(context, 'تم تسجيل ${entries.length} إدخال وإضافتها لتكلفة الأمر.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _blocked(String title, String body, String page, String action) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إغلاق')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action))],
      ),
    );
    if (go == true && mounted) context.read<NavState>().goTo(page);
  }

  Future<void> _cancel(Json p) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء إدخال إنتاج', [const FieldSpec('reason', 'السبب')], submitLabel: 'إلغاء الإدخال');
    if (v == null) return;
    try {
      await s.api.post('/piece-entries/${p['id']}/cancel', {'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final manage = s.can('payroll.manage');
    const names = {'open': 'لم يُحاسَب', 'payrolled': 'تمت محاسبته', 'cancelled': 'ملغى', '': 'الكل'};
    return Column(children: [
      PageHeader('إنتاج القطعة', subtitle: 'ما أنجزه كل عامل على أوامر التصنيع', actions: [
        DropdownButton<String>(value: _status, items: [for (final x in names.entries) DropdownMenuItem(value: x.key, child: Text(x.value))], onChanged: (v) => setState(() {
              _status = v ?? '';
              _tick++;
            })),
        if (manage) FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('تسجيل إنتاج')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_status'),
          load: () => s.api.get('/piece-entries', query: {if (_status.isNotEmpty) 'status': _status}),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا يوجد إنتاج مسجل');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final p = rows[i];
                final st = p['status'].toString();
                return Card(
                  child: ListTile(
                    title: Text('${p['employee_name']}  —  ${p['operation_name']}  ×  ${fmtQty(p['qty'])}'),
                    subtitle: Text('${p['work_date'].toString().substring(0, 10)}  •  أمر ${p['order_number']}  •  الإجمالي ${fmtCell(p['amount'])}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Pill(names[st] ?? st, color: st == 'open' ? Colors.orange.shade800 : (st == 'cancelled' ? Colors.grey : Colors.green.shade700)),
                      if (manage && st == 'open') IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'إلغاء', onPressed: () => _cancel(p)),
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
