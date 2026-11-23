import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// الموازنة التقديرية الشهرية للإيرادات والمصروفات. المقارنة بالفعلي من «التقارير ← الموازنة مقابل الفعلي».
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  int _year = DateTime.now().year;
  int _tick = 0;
  bool _saving = false;
  final Map<String, TextEditingController> _ctl = {};

  static const _mn = ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'];

  TextEditingController _c(int acc, int m, String initial) => _ctl.putIfAbsent('$acc-$m', () => TextEditingController(text: initial == '' ? '' : fmtCell(initial)));

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl.clear();
    _tick++;
  }

  Future<void> _save(List<Json> rows) async {
    final s = context.read<Session>();
    setState(() => _saving = true);
    try {
      final body = <Map<String, dynamic>>[];
      for (final r in rows) {
        final months = <String, dynamic>{};
        for (var m = 1; m <= 12; m++) {
          final c = _ctl['${r['account_id']}-$m'];
          if (c != null) months['$m'] = c.text.trim().replaceAll(',', '');
        }
        body.add({'account_id': r['account_id'], 'months': months});
      }
      final res = await s.api.post('/budgets', {'year': _year, 'rows': body}) as Map;
      if (mounted) {
        toast(context, 'تم حفظ الموازنة (${res['saved']} خانة).');
        setState(_reset);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _seed() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'تعبئة موازنة $_year من فعلي سنة سابقة', [
      FieldSpec('source_year', 'سنة المصدر', type: 'number', initial: '${_year - 1}'),
      const FieldSpec('pct', 'زيادة/نقص % على الفعلي (مثال 10 أو -5)', type: 'number', initial: '0'),
    ], submitLabel: 'تعبئة');
    if (v == null) return;
    if (!mounted || !await confirm(context, 'سيتم استبدال موازنة $_year الحالية بالكامل. متابعة؟')) return;
    try {
      final r = await s.api.post('/budgets/seed', {'year': _year, 'source_year': int.parse(v['source_year']!), 'pct': v['pct']}) as Map;
      if (mounted) {
        toast(context, 'تمت التعبئة (${r['saved']} خانة). راجعها ثم عدّل ما يلزم.');
        setState(_reset);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final manage = s.can('settings.manage');
    return Loader(
      key: ValueKey('$_year$_tick'),
      load: () => s.api.get('/budgets', query: {'year': _year}),
      builder: (context, data, reload) {
        final rows = asList((data as Map)['rows']);
        return Column(children: [
          PageHeader('الموازنة التقديرية', subtitle: 'اكتب المبلغ المتوقع لكل بند في كل شهر (اتركه فارغًا لو لا موازنة)', actions: [
            IconButton(tooltip: 'السنة السابقة', onPressed: () => setState(() {
                  _year--;
                  _reset();
                }), icon: const Icon(Icons.chevron_right)),
            Text('$_year', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            IconButton(tooltip: 'السنة التالية', onPressed: () => setState(() {
                  _year++;
                  _reset();
                }), icon: const Icon(Icons.chevron_left)),
            if (manage) OutlinedButton.icon(onPressed: _seed, icon: const Icon(Icons.auto_fix_high), label: const Text('تعبئة من فعلي سنة سابقة')),
            if (manage) FilledButton.icon(onPressed: _saving ? null : () => _save(rows), icon: const Icon(Icons.save), label: const Text('حفظ الموازنة')),
          ]),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(82),
                  columnWidths: const {0: FixedColumnWidth(220), 13: FixedColumnWidth(100)},
                  border: TableBorder.all(color: Colors.black12),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(decoration: const BoxDecoration(color: Color(0xFFF1F4F8)), children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('البند', style: TextStyle(fontWeight: FontWeight.w700))),
                      for (final m in _mn) Padding(padding: const EdgeInsets.all(8), child: Text(m, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                      const Padding(padding: EdgeInsets.all(8), child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                    for (final r in rows)
                      TableRow(children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('${r['code']}  ${r['name']}  ${r['type'] == 'revenue' ? '(إيراد)' : ''}', style: const TextStyle(fontSize: 13))),
                        for (var m = 1; m <= 12; m++)
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: TextField(
                              controller: _c(r['account_id'] as int, m, '${(r['months'] as Map)['$m'] ?? ''}'),
                              enabled: manage,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                            ),
                          ),
                        Padding(padding: const EdgeInsets.all(8), child: Text(fmtCell(r['total']), style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
