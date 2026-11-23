import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const _runStatus = {'draft': 'مسودة', 'approved': 'معتمد', 'cancelled': 'ملغى'};

/// كشوف الرواتب الشهرية: إنشاء مسودة، تعديل الخصومات، اعتماد (قيد تلقائي)، صرف، وطباعة القسائم.
class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key});

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  int _tick = 0;

  Future<void> _generate() async {
    final s = context.read<Session>();
    final now = DateTime.now();
    final v = await showForm(context, 'إنشاء كشف رواتب', [
      FieldSpec('year', 'السنة', type: 'number', initial: '${now.year}'),
      FieldSpec('month', 'الشهر (1-12)', type: 'number', initial: '${now.month}'),
    ], submitLabel: 'إنشاء');
    if (v == null) return;
    try {
      final r = await s.api.post('/payroll-runs/generate', {'year': int.parse(v['year']!), 'month': int.parse(v['month']!)});
      if (!mounted) return;
      setState(() => _tick++);
      final id = (r is Map ? (r['run'] is Map ? r['run']['id'] : r['id']) : null);
      if (id != null) await _open(id as int);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _open(int id) async {
    await showDialog<void>(context: context, builder: (_) => _RunDialog(id: id));
    if (mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Column(children: [
      PageHeader('كشوف الرواتب', subtitle: 'إنتاج القطعة + الحضور + السلف والخصومات', actions: [
        if (s.can('payroll.manage')) FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.add), label: const Text('كشف شهر')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/payroll-runs'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد كشوف رواتب');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final r = rows[i];
                final st = r['status'].toString();
                return Card(
                  child: ListTile(
                    onTap: () => _open(r['id'] as int),
                    title: Text('${r['number']}  —  ${r['month']}/${r['year']}'),
                    subtitle: Text('الإجمالي ${fmtCell(r['total_gross'])}  •  الخصومات ${fmtCell(r['total_deductions'])}  •  الصافي ${fmtCell(r['total_net'])}'),
                    trailing: Pill(_runStatus[st] ?? st, color: st == 'approved' ? Colors.green.shade700 : (st == 'draft' ? Colors.orange.shade800 : Colors.grey)),
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

class _RunDialog extends StatefulWidget {
  final int id;
  const _RunDialog({required this.id});

  @override
  State<_RunDialog> createState() => _RunDialogState();
}

class _RunDialogState extends State<_RunDialog> {
  int _tick = 0;

  Future<void> _do(Future<dynamic> Function() f, {String? ok}) async {
    try {
      await f();
      if (!mounted) return;
      if (ok != null) toast(context, ok);
      setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _editLine(Session s, Json l) async {
    final v = await showForm(context, 'تعديل ${l['employee_name']}', [
      FieldSpec('allowances', 'بدلات / مكافآت', type: 'number', required: false, initial: fmtCell(l['allowances'])),
      FieldSpec('penalties', 'جزاءات', type: 'number', required: false, initial: fmtCell(l['penalties'])),
      FieldSpec('insurance', 'تأمينات', type: 'number', required: false, initial: fmtCell(l['insurance'])),
      FieldSpec('tax', 'ضرائب', type: 'number', required: false, initial: fmtCell(l['tax'])),
      FieldSpec('other_deductions', 'خصومات أخرى', type: 'number', required: false, initial: fmtCell(l['other_deductions'])),
      FieldSpec('advance_recovery', 'سداد سلفة هذا الشهر', type: 'number', required: false, initial: fmtCell(l['advance_recovery'])),
      FieldSpec('notes', 'ملاحظات', required: false, initial: l['notes']?.toString()),
    ]);
    if (v == null) return;
    String n(String k) => (v[k] ?? '').isEmpty ? '0' : v[k]!;
    await _do(() => s.api.put('/payroll-lines/${l['id']}', {
          'allowances': n('allowances'), 'penalties': n('penalties'), 'insurance': n('insurance'), 'tax': n('tax'),
          'other_deductions': n('other_deductions'), 'advance_recovery': n('advance_recovery'), 'notes': v['notes'],
        }));
  }

  Future<void> _pay(Session s, Json run, {int? lineId}) async {
    try {
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final ts = asList(meta['treasuries']);
      final v = await showForm(context, 'صرف الرواتب', [
        FieldSpec('treasury_id', 'تُصرف من', type: 'picker', options: ts.map((t) => <String, dynamic>{'value': t['id'], 'label': t['name']}).toList(), initial: ts.isNotEmpty ? ts.first['id'].toString() : null),
        const FieldSpec('date', 'تاريخ الصرف', type: 'date'),
      ], submitLabel: 'صرف');
      if (v == null) return;
      await _do(() => s.api.post('/payroll-runs/${run['id']}/pay', {'treasury_id': int.parse(v['treasury_id']!), 'date': v['date'], if (lineId != null) 'line_ids': [lineId]}), ok: 'تم الصرف.');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _print(Session s, {int? line, int? run}) async {
    try {
      final r = await s.api.get('/payslips-url', query: {if (line != null) 'line': line, if (run != null) 'run': run});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _excel(Session s) async {
    try {
      final r = await s.api.get('/reports/payroll-run/csv-url', query: {'run_id': widget.id});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 980,
        height: 640,
        child: Loader(
          key: ValueKey(_tick),
          load: () async {
            var d = await s.api.get('/payroll-runs/${widget.id}');
            // المسودة تُحدَّث تلقائيًا من الحضور والإنتاج والسلف عند فتحها (التعديلات اليدوية محفوظة)
            if (d['run']['status'] == 'draft' && s.can('payroll.manage')) {
              await s.api.post('/payroll-runs/generate', {'year': d['run']['year'], 'month': d['run']['month']});
              d = await s.api.get('/payroll-runs/${widget.id}');
            }
            return d;
          },
          builder: (context, data, reload) {
            final run = Map<String, dynamic>.from(data['run'] as Map);
            final lines = asList(data['lines']);
            final st = run['status'].toString();
            final draft = st == 'draft';
            final approved = st == 'approved';
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${run['number']}  —  ${run['month']}/${run['year']}  (${_runStatus[st] ?? st})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
                Text('الإجمالي ${fmtCell(run['total_gross'])}   •   الخصومات ${fmtCell(run['total_deductions'])}   •   الصافي ${fmtCell(run['total_net'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (draft && s.can('payroll.manage')) OutlinedButton.icon(onPressed: () => _do(() => s.api.post('/payroll-runs/generate', {'year': run['year'], 'month': run['month']}), ok: 'تم تحديث الكشف من البيانات الحالية.'), icon: const Icon(Icons.refresh), label: const Text('تحديث من الحضور والإنتاج')),
                  if (draft && s.can('payroll.approve'))
                    FilledButton.icon(
                      onPressed: () async {
                        if (await confirm(context, 'اعتماد الكشف؟ سيُسجَّل قيد الرواتب وتُقفل بيانات الشهر.')) {
                          await _do(() => s.api.post('/payroll-runs/${run['id']}/approve'), ok: 'تم الاعتماد.');
                        }
                      },
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('اعتماد'),
                    ),
                  if (draft && s.can('payroll.manage'))
                    TextButton.icon(
                      onPressed: () async {
                        if (await confirm(context, 'حذف مسودة الكشف؟')) {
                          try {
                            await s.api.delete('/payroll-runs/${run['id']}');
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            if (context.mounted) toast(context, e.toString(), error: true);
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('حذف المسودة'),
                    ),
                  if (approved && s.can('payroll.manage')) FilledButton.icon(onPressed: () => _pay(s, run), icon: const Icon(Icons.payments_outlined), label: const Text('صرف الكل')),
                  if (approved && s.can('payroll.approve'))
                    TextButton.icon(
                      onPressed: () async {
                        final v = await showForm(context, 'عكس الاعتماد', [const FieldSpec('reason', 'السبب')], submitLabel: 'عكس');
                        if (v != null) await _do(() => s.api.post('/payroll-runs/${run['id']}/reverse', {'reason': v['reason']}), ok: 'تم عكس الاعتماد.');
                      },
                      icon: const Icon(Icons.undo),
                      label: const Text('عكس الاعتماد'),
                    ),
                  OutlinedButton.icon(onPressed: () => _print(s, run: run['id'] as int), icon: const Icon(Icons.print_outlined), label: const Text('طباعة كل القسائم')),
                  OutlinedButton.icon(onPressed: () => _excel(s), icon: const Icon(Icons.table_view), label: const Text('Excel')),
                ]),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      final net = double.tryParse('${l['net']}') ?? 0;
                      final paid = double.tryParse('${l['paid_amount']}') ?? 0;
                      final due = net - paid;
                      return ListTile(
                        dense: true,
                        title: Text('${l['employee_name']}   (${l['pay_type'] == 'piece' ? 'قطعة' : (l['pay_type'] == 'daily' ? 'يومي' : 'شهري')})', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('أساسي ${fmtCell(l['base_amount'])} • قطعة ${fmtCell(l['piece_amount'])} • إضافي ${fmtCell(l['overtime_amount'])} • بدلات ${fmtCell(l['allowances'])}  |  سلفة ${fmtCell(l['advance_recovery'])} • جزاءات ${fmtCell(l['penalties'])} • تأمين ${fmtCell(l['insurance'])} • ضريبة ${fmtCell(l['tax'])} • أخرى ${fmtCell(l['other_deductions'])}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('الصافي ${fmtCell(l['net'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            if (approved) Text(due <= 0 ? 'مدفوع' : 'متبقي ${fmtCell(due)}', style: TextStyle(fontSize: 11, color: due <= 0 ? Colors.green.shade700 : Colors.orange.shade800)),
                          ]),
                          if (draft && s.can('payroll.manage')) IconButton(icon: const Icon(Icons.edit_outlined, size: 18), tooltip: 'تعديل الخصومات', onPressed: () => _editLine(s, l)),
                          if (approved && due > 0 && s.can('payroll.manage')) IconButton(icon: const Icon(Icons.payments_outlined, size: 18), tooltip: 'صرف هذا الموظف', onPressed: () => _pay(s, run, lineId: l['id'] as int)),
                          IconButton(icon: const Icon(Icons.print_outlined, size: 18), tooltip: 'قسيمة', onPressed: () => _print(s, line: l['id'] as int)),
                        ]),
                      );
                    },
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
