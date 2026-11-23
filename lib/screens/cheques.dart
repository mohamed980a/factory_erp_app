import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// الشيكات: المستلمة من العملاء (أوراق قبض) والصادرة للموردين (أوراق دفع).
class ChequesPage extends StatefulWidget {
  const ChequesPage({super.key});

  @override
  State<ChequesPage> createState() => _ChequesPageState();
}

class _ChequesPageState extends State<ChequesPage> {
  int _tick = 0;
  String _dir = '';
  String _status = 'holding';

  static const _dirs = {'': 'الكل', 'receivable': 'مستلمة من عملاء', 'payable': 'صادرة لموردين'};
  static const _statuses = {'holding': 'قيد التحصيل/الصرف', 'settled': 'تم التحصيل/الصرف', 'bounced': 'مرتدة', 'cancelled': 'ملغاة', '': 'الكل'};

  Future<void> _new() async {
    final s = context.read<Session>();
    final dirV = await pickOne(context, 'نوع الشيك', [
      {'v': 'receivable', 'l': 'شيك مستلم من عميل'},
      {'v': 'payable', 'l': 'شيك صادر لمورد'},
    ], (o) => o['l'].toString());
    if (dirV == null || !mounted) return;
    final dir = dirV['v'].toString();
    try {
      final parties = asList(await s.api.get('/parties', query: {'type': dir == 'receivable' ? 'customer' : 'supplier', 'active': 1}));
      if (!mounted) return;
      final v = await showForm(context, dir == 'receivable' ? 'تسجيل شيك مستلم' : 'تسجيل شيك صادر', [
        FieldSpec('party_id', dir == 'receivable' ? 'العميل' : 'المورد', type: 'picker', options: parties.map((p) => <String, dynamic>{'value': p['id'], 'label': p['name']}).toList()),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        const FieldSpec('cheque_no', 'رقم الشيك'),
        const FieldSpec('bank', 'البنك', required: false),
        const FieldSpec('issue_date', 'تاريخ الشيك', type: 'date'),
        const FieldSpec('due_date', 'تاريخ الاستحقاق', type: 'date'),
        const FieldSpec('notes', 'ملاحظات', type: 'multiline', required: false),
      ], submitLabel: 'تسجيل');
      if (v == null) return;
      await s.api.post('/cheques', {
        'direction': dir, 'party_id': int.parse(v['party_id']!), 'amount': v['amount'], 'cheque_no': v['cheque_no'], 'bank': v['bank'],
        'issue_date': v['issue_date'], 'due_date': v['due_date'], 'notes': v['notes'],
      });
      if (mounted) {
        toast(context, dir == 'receivable' ? 'تم تسجيل الشيك وتسوية الفواتير الأقدم تلقائيًا.' : 'تم تسجيل الشيك.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _settle(Json c) async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final rec = c['direction'] == 'receivable';
      final ts = asList(meta['treasuries']);
      final v = await showForm(context, rec ? 'تحصيل الشيك ${c['cheque_no']}' : 'صرف الشيك ${c['cheque_no']}', [
        FieldSpec('treasury_id', rec ? 'تورَّد في خزينة/بنك' : 'يُصرف من خزينة/بنك', type: 'picker',
            options: ts.map((t) => <String, dynamic>{'value': t['id'], 'label': t['name']}).toList(), initial: ts.isNotEmpty ? ts.first['id'].toString() : null),
        const FieldSpec('date', 'التاريخ', type: 'date'),
      ], submitLabel: rec ? 'تحصيل' : 'صرف');
      if (v == null) return;
      await s.api.post('/cheques/${c['id']}/settle', {'treasury_id': int.parse(v['treasury_id']!), 'date': v['date']});
      if (mounted) {
        toast(context, rec ? 'تم التحصيل.' : 'تم الصرف.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _undo(Json c, String action) async {
    final s = context.read<Session>();
    final bounce = action == 'bounce';
    final v = await showForm(context, bounce ? 'ارتداد الشيك ${c['cheque_no']}' : 'إلغاء الشيك ${c['cheque_no']}', [
      const FieldSpec('date', 'التاريخ', type: 'date'),
      FieldSpec('reason', bounce ? 'سبب الارتداد (مثال: رصيد غير كافٍ)' : 'سبب الإلغاء'),
    ], submitLabel: bounce ? 'تسجيل الارتداد' : 'إلغاء الشيك');
    if (v == null) return;
    try {
      await s.api.post('/cheques/${c['id']}/$action', {'date': v['date'], 'reason': v['reason']});
      if (mounted) {
        toast(context, bounce ? 'تم تسجيل الارتداد وعاد الدين على العميل.' : 'تم الإلغاء.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Widget _sum(String title, Json? x, Color color) {
    final h = x ?? const {};
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${fmtCell(h['holding_total'] ?? 0)}  (${h['holding_count'] ?? 0} شيك)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text('متأخر: ${fmtCell(h['overdue_total'] ?? 0)}   |   خلال 7 أيام: ${fmtCell(h['due_7d_total'] ?? 0)}', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final canCreate = s.can('payments.create');
    final canReverse = s.can('payments.reverse');
    return Column(children: [
      PageHeader('الشيكات', subtitle: 'أوراق القبض والدفع', actions: [
        if (canCreate) FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('تسجيل شيك')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in _dirs.entries) ChoiceChip(label: Text(e.value), selected: _dir == e.key, onSelected: (_) => setState(() => _dir = e.key)),
          const SizedBox(width: 16),
          for (final e in _statuses.entries) ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
        ]),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_dir$_status'),
          load: () => s.api.get('/cheques', query: {if (_dir.isNotEmpty) 'direction': _dir, if (_status.isNotEmpty) 'status': _status}),
          builder: (context, data, reload) {
            final m = data as Map;
            final rows = asList(m['list']);
            final sum = (m['summary'] as Map?) ?? const {};
            final today0 = today();
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                _sum('مستلمة قيد التحصيل', sum['receivable'] as Json?, Colors.green.shade800),
                _sum('صادرة قيد الصرف', sum['payable'] as Json?, Colors.red.shade800),
              ]),
              if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: EmptyState('لا توجد شيكات')),
              for (final c in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Pill(c['direction'] == 'receivable' ? 'مستلم' : 'صادر', color: c['direction'] == 'receivable' ? Colors.green.shade800 : Colors.red.shade800),
                        const SizedBox(width: 8),
                        Pill(_statuses[c['status']] ?? '${c['status']}', color: c['status'] == 'holding' ? Colors.orange.shade800 : (c['status'] == 'settled' ? Colors.teal.shade800 : Colors.grey.shade700)),
                        const SizedBox(width: 8),
                        Text('${c['party']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(fmtCell(c['amount']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 6),
                      Text('شيك رقم ${c['cheque_no']}${(c['bank'] ?? '').toString().isEmpty ? '' : '  •  ${c['bank']}'}   |   الاستحقاق: ${c['due_date'].toString().substring(0, 10)}'
                          '${c['status'] == 'holding' && c['due_date'].toString().substring(0, 10).compareTo(today0) < 0 ? '   (متأخر)' : ''}   |   ${c['number']}',
                          style: const TextStyle(fontSize: 12.5)),
                      if ((c['status_note'] ?? '').toString().isNotEmpty) Text('السبب: ${c['status_note']}', style: const TextStyle(fontSize: 12)),
                      if (c['status'] == 'settled') Text('التاريخ: ${c['settled_date'].toString().substring(0, 10)}  •  ${c['treasury']?['name'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      if (c['status'] == 'holding')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(spacing: 8, children: [
                            if (canCreate) FilledButton.tonalIcon(onPressed: () => _settle(c), icon: const Icon(Icons.price_check), label: Text(c['direction'] == 'receivable' ? 'تحصيل' : 'صرف')),
                            if (canReverse && c['direction'] == 'receivable') OutlinedButton.icon(onPressed: () => _undo(c, 'bounce'), icon: const Icon(Icons.undo), label: const Text('ارتداد')),
                            if (canReverse) TextButton(onPressed: () => _undo(c, 'cancel'), child: const Text('إلغاء')),
                          ]),
                        ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}
