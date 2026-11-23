import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

class CustodyPage extends StatefulWidget {
  const CustodyPage({super.key});

  @override
  State<CustodyPage> createState() => _CustodyPageState();
}

class _CustodyPageState extends State<CustodyPage> {
  int _tick = 0;

  Future<List<Json>> _employees() async {
    final s = context.read<Session>();
    final r = await s.api.get('/reports/custody') as Map;
    return asList(r['rows']);
  }

  Future<void> _newEmployee() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'موظف جديد (صاحب عهدة)', [const FieldSpec('name', 'الاسم'), const FieldSpec('phone', 'التليفون', required: false)]);
    if (v == null) return;
    try {
      await s.api.post('/parties', {'type': 'employee', 'name': v['name'], 'phone': v['phone']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<Json?> _pickEmployee() async {
    final list = await _employees();
    if (!mounted) return null;
    if (list.isEmpty) {
      toast(context, 'أضف موظفًا أولًا.', error: true);
      return null;
    }
    return pickOne(context, 'اختر الموظف', list, (e) => '${e['name']}  (عهدة قائمة: ${fmtCell(e['balance'])})');
  }

  Future<void> _advance() async {
    final s = context.read<Session>();
    try {
      final emp = await _pickEmployee();
      if (emp == null || !mounted) return;
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final v = await showForm(context, 'صرف عهدة لـ ${emp['name']}', [
        FieldSpec('treasury_id', 'من خزينة', type: 'picker', options: asList(meta['treasuries']).map((t) => <String, dynamic>{'value': t['id'], 'label': t['name']}).toList()),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        const FieldSpec('date', 'التاريخ', type: 'date'),
        const FieldSpec('notes', 'الغرض', required: false),
      ]);
      if (v == null) return;
      await s.api.post('/custody/advance', {'party_id': emp['id'], 'treasury_id': int.parse(v['treasury_id']!), 'amount': v['amount'], 'date': v['date'], 'notes': v['notes']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _settle() async {
    final emp = await _pickEmployee();
    if (emp == null || !mounted) return;
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _SettleScreen(employee: emp)));
    if (ok == true && mounted) setState(() => _tick++);
  }

  Future<void> _reverse(Json d) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء ${d['number']}', [const FieldSpec('reason', 'السبب'), const FieldSpec('date', 'التاريخ', type: 'date')], submitLabel: 'إلغاء المستند');
    if (v == null) return;
    try {
      await s.api.post('/custody/${d['id']}/reverse', {'reason': v['reason'], 'date': v['date']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('العهد', actions: [
        OutlinedButton.icon(onPressed: _newEmployee, icon: const Icon(Icons.person_add), label: const Text('موظف جديد')),
        FilledButton.icon(onPressed: _advance, icon: const Icon(Icons.north_east), label: const Text('صرف عهدة')),
        FilledButton.tonalIcon(onPressed: _settle, icon: const Icon(Icons.fact_check), label: const Text('تسوية عهدة')),
      ]),
      SizedBox(
        height: 64,
        child: Loader(
          key: ValueKey('e$_tick'),
          load: () => s.api.get('/reports/custody'),
          builder: (c, data, reload) => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final e in asList((data as Map)['rows']))
                Padding(padding: const EdgeInsets.only(left: 8), child: Chip(avatar: const Icon(Icons.person, size: 18), label: Text('${e['name']}: ${fmtCell(e['balance'])}'))),
            ],
          ),
        ),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('d$_tick'),
          load: () => s.api.get('/custody'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد مستندات عهد.');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = rows[i];
                final adv = d['kind'] == 'advance';
                final reversed = d['status'] == 'reversed';
                final lines = asList(d['lines']).map((l) => '${l['account']?['name'] ?? ''}: ${fmtCell(l['amount'])}').join('، ');
                return ListTile(
                  leading: Icon(adv ? Icons.north_east : Icons.fact_check),
                  title: Text('${d['number']}  •  ${adv ? 'صرف عهدة' : 'تسوية عهدة'}  •  ${d['party']?['name'] ?? ''}', style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null)),
                  subtitle: Text('${d['doc_date']}${adv ? '' : '   |   $lines${toD(d['returned_amount']) > 0 ? '   |   مردود نقدًا ${fmtCell(d['returned_amount'])}' : ''}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (reversed) const Chip(label: Text('ملغي')),
                    Text(fmtCell(d['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (!reversed) IconButton(icon: const Icon(Icons.cancel_outlined), onPressed: () => _reverse(d)),
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

class _Exp {
  final Json account;
  final String amount;
  final String desc;
  _Exp(this.account, this.amount, this.desc);
}

class _SettleScreen extends StatefulWidget {
  final Json employee;
  const _SettleScreen({required this.employee});

  @override
  State<_SettleScreen> createState() => _SettleScreenState();
}

class _SettleScreenState extends State<_SettleScreen> {
  final List<_Exp> _exps = [];
  final _return = TextEditingController(text: '0');
  final _date = TextEditingController(text: today());
  final _notes = TextEditingController();
  Json? _treasury;
  bool _busy = false;

  double get _total => _exps.fold<double>(0, (a, e) => a + toD(e.amount)) + toD(_return.text);

  Future<void> _addExp() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final v = await showForm(context, 'بند مصروف', [
        FieldSpec('acc', 'بند المصروف', type: 'picker', options: asList(meta['expense_accounts']).map((a) => <String, dynamic>{'value': a['id'], 'label': '${a['code']} - ${a['name']}'}).toList()),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        const FieldSpec('desc', 'البيان (إيصال / مورد...)', required: false),
      ], submitLabel: 'إضافة');
      if (v == null) return;
      final acc = asList(meta['expense_accounts']).firstWhere((a) => a['id'].toString() == v['acc']);
      setState(() => _exps.add(_Exp(acc, v['amount']!, v['desc'] ?? '')));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _submit() async {
    final s = context.read<Session>();
    setState(() => _busy = true);
    try {
      await s.api.post('/custody/settle', {
        'party_id': widget.employee['id'], 'date': _date.text, 'notes': _notes.text,
        'return_amount': _return.text.isEmpty ? '0' : _return.text, if (_treasury != null) 'return_treasury_id': _treasury!['id'],
        'expenses': [for (final e in _exps) {'expense_account_id': e.account['id'], 'amount': e.amount, 'description': e.desc}],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: Text('تسوية عهدة ${widget.employee['name']}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: Text('العهدة القائمة: ${fmtCell(widget.employee['balance'])}', style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _addExp, icon: const Icon(Icons.add), label: const Text('إضافة بند مصروف'))),
          Expanded(
            child: Card(
              child: _exps.isEmpty
                  ? const Center(child: Text('أضف المصروفات الموثّقة (بإيصالات)'))
                  : ListView(children: [
                      for (var i = 0; i < _exps.length; i++)
                        ListTile(
                          title: Text('${_exps[i].account['name']}'),
                          subtitle: Text(_exps[i].desc),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(fmtCell(_exps[i].amount)), IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _exps.removeAt(i)))]),
                        ),
                    ]),
            ),
          ),
          Row(children: [
            SizedBox(width: 200, child: TextField(controller: _return, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'نقدية مردودة للخزينة'))),
            const SizedBox(width: 12),
            Expanded(child: PickerField(label: 'الخزينة المستلمة (لو فيه مردود)', valueText: _treasury?['name']?.toString(), onTap: () async {
              final meta = await s.meta(refresh: true);
              if (!mounted) return;
              final t = await pickOne(context, 'اختر الخزينة', asList(meta['treasuries']), (t) => t['name'].toString());
              if (t != null) setState(() => _treasury = t);
            })),
            const SizedBox(width: 12),
            SizedBox(width: 160, child: TextField(controller: _date, decoration: const InputDecoration(labelText: 'التاريخ'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات'))),
            const SizedBox(width: 12),
            Text('إجمالي التسوية: ${_total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'جارٍ الحفظ...' : 'ترحيل التسوية')),
          ]),
        ]),
      ),
    );
  }
}
