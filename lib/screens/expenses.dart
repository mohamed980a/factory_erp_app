import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// المصروفات: كل ما صُرف على بنود المصروفات (نقل، إيجار، صيانة...) مع إجمالي كل بند، وإضافة بنود جديدة.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  int _tick = 0;
  final _from = TextEditingController(text: DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10));
  final _to = TextEditingController(text: today());
  Json? _cat;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _date(TextEditingController c) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(c.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) {
      setState(() {
        c.text = d.toIso8601String().substring(0, 10);
        _tick++;
      });
    }
  }

  Future<void> _add() async {
    final s = context.read<Session>();
    try {
      final cats = asList(await s.api.get('/expense-categories'));
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final ts = asList(meta['treasuries']);
      final v = await showForm(context, 'تسجيل مصروف', [
        FieldSpec('expense_account_id', 'بند المصروف', type: 'picker', options: cats.map((a) => <String, dynamic>{'value': a['id'], 'label': '${a['name']}'}).toList()),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        FieldSpec('treasury_id', 'يُصرف من', type: 'picker', options: ts.map((t) => <String, dynamic>{'value': t['id'], 'label': t['name']}).toList(), initial: ts.isNotEmpty ? ts.first['id'].toString() : null),
        const FieldSpec('date', 'التاريخ', type: 'date'),
        const FieldSpec('notes', 'البيان (مثال: فاتورة كهرباء أكتوبر)', required: false),
      ], submitLabel: 'تسجيل');
      if (v == null) return;
      await s.api.post('/payments', {
        'kind': 'expense', 'expense_account_id': int.parse(v['expense_account_id']!), 'amount': v['amount'], 'treasury_id': int.parse(v['treasury_id']!), 'date': v['date'], 'notes': v['notes'],
      });
      s.meta(refresh: true);
      if (mounted) {
        toast(context, 'تم تسجيل المصروف.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _newCategory() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'بند مصروف جديد', [const FieldSpec('name', 'اسم البند (مثال: صيانة ماكينات)')], submitLabel: 'إضافة');
    if (v == null) return;
    try {
      await s.api.post('/expense-categories', {'name': v['name']});
      s.meta(refresh: true);
      if (mounted) toast(context, 'تمت إضافة البند.');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _reverse(Json p) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء المصروف ${p['number']}', [const FieldSpec('date', 'تاريخ الإلغاء', type: 'date'), const FieldSpec('reason', 'السبب')], submitLabel: 'إلغاء المصروف');
    if (v == null) return;
    try {
      await s.api.post('/payments/${p['id']}/reverse', {'date': v['date'], 'reason': v['reason']});
      if (mounted) {
        toast(context, 'تم إلغاء المصروف.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Column(children: [
      PageHeader('المصروفات', subtitle: 'كل مصروف مرتبط ببند وخزينة وقيد محاسبي', actions: [
        if (s.can('payments.create')) OutlinedButton.icon(onPressed: _newCategory, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('بند جديد')),
        if (s.can('payments.create')) FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('تسجيل مصروف')),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 150, child: TextField(controller: _from, readOnly: true, onTap: () => _date(_from), decoration: const InputDecoration(labelText: 'من', suffixIcon: Icon(Icons.calendar_today, size: 18)))),
          SizedBox(width: 150, child: TextField(controller: _to, readOnly: true, onTap: () => _date(_to), decoration: const InputDecoration(labelText: 'إلى', suffixIcon: Icon(Icons.calendar_today, size: 18)))),
          SizedBox(
            width: 240,
            child: PickerField(
              label: 'بند معيّن (اختياري)',
              valueText: _cat?['name']?.toString(),
              onTap: () async {
                final list = asList(await context.read<Session>().api.get('/expense-categories'));
                if (!mounted) return;
                final c = await pickOne(context, 'اختر البند', list, (c) => '${c['name']}');
                if (c != null) {
                  setState(() {
                    _cat = c;
                    _tick++;
                  });
                }
              },
            ),
          ),
          if (_cat != null) TextButton.icon(onPressed: () => setState(() {
                _cat = null;
                _tick++;
              }), icon: const Icon(Icons.clear, size: 16), label: const Text('كل البنود')),
        ]),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick'),
          load: () => s.api.get('/expenses', query: {'from': _from.text, 'to': _to.text, if (_cat != null) 'account_id': _cat!['id']}),
          builder: (context, data, reload) {
            final d = Map<String, dynamic>.from(data as Map);
            final rows = asList(d['rows']);
            final by = asList(d['by_category']);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('إجمالي المصروفات في الفترة: ${fmtCell(d['total'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [for (final b in by) Pill('${b['category']}: ${fmtCell(b['total'])}', color: AppColors.muted)]),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: EmptyState('لا توجد مصروفات في الفترة')),
              for (final p in rows)
                Card(
                  child: ListTile(
                    title: Text('${p['category'] ?? 'بدون بند'}  —  ${fmtCell(p['amount'])}${p['status'] == 'reversed' ? '   (ملغى)' : ''}', style: TextStyle(decoration: p['status'] == 'reversed' ? TextDecoration.lineThrough : null)),
                    subtitle: Text('${p['payment_date'].toString().substring(0, 10)}  •  ${p['number']}  •  ${p['treasury']}${(p['notes'] ?? '').toString().isEmpty ? '' : '  •  ${p['notes']}'}'),
                    trailing: p['status'] == 'posted' && s.can('payments.reverse') ? IconButton(icon: const Icon(Icons.undo, size: 18), tooltip: 'إلغاء المصروف', onPressed: () => _reverse(p)) : null,
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}
