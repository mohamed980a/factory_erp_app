import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const Map<String, String> paymentKindLabels = {'receipt': 'سند قبض', 'payment': 'سند صرف', 'expense': 'مصروف'};

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  int _tick = 0;
  String _kind = '';

  List<Json> _treasuryOptions(Json meta) => asList(meta['treasuries']).map((t) => <String, dynamic>{'value': t['id'], 'label': t['name']}).toList();

  Future<void> _newPayment(String kind, {bool refund = false}) async {
    final s = context.read<Session>();
    final custSide = refund ? kind == 'payment' : kind == 'receipt';
    try {
      final meta = await s.meta(refresh: true);
      List<Json> partyOpts = [];
      if (kind != 'expense') {
        final parties = asList(await s.api.get('/parties', query: {'type': custSide ? 'customer' : 'supplier', 'active': 1}));
        partyOpts = parties.map((p) => <String, dynamic>{'value': p['id'], 'label': p['name']}).toList();
      }
      if (!mounted) return;
      final v = await showForm(context, refund ? (kind == 'payment' ? 'استرداد مبلغ لعميل (رصيده دائن)' : 'استرداد مبلغ من مورد (رصيده مدين)') : paymentKindLabels[kind]!, [
        if (kind != 'expense') FieldSpec('party_id', custSide ? 'العميل' : 'المورد', type: 'picker', options: partyOpts),
        if (kind == 'expense')
          FieldSpec('expense_account_id', 'بند المصروف', type: 'picker', options: asList(meta['expense_accounts']).map((a) => <String, dynamic>{'value': a['id'], 'label': '${a['code']} - ${a['name']}'}).toList()),
        FieldSpec('treasury_id', 'الخزينة', type: 'picker', options: _treasuryOptions(meta), initial: asList(meta['treasuries']).isNotEmpty ? asList(meta['treasuries']).first['id'].toString() : null),
        const FieldSpec('date', 'التاريخ', type: 'date'),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        const FieldSpec('method', 'طريقة الدفع', type: 'picker', initial: 'cash', options: [
          {'value': 'cash', 'label': 'نقدي'}, {'value': 'bank', 'label': 'تحويل بنكي'}, {'value': 'other', 'label': 'أخرى'},
        ]),
        const FieldSpec('reference', 'رقم الإيصال / المرجع', required: false),
        const FieldSpec('notes', 'البيان', type: 'multiline', required: false),
      ]);
      if (v == null) return;
      final body = <String, dynamic>{
        'kind': kind, 'treasury_id': int.parse(v['treasury_id']!), 'date': v['date'], 'amount': v['amount'], 'method': v['method'],
        'reference': v['reference'], 'notes': v['notes'],
        if (kind != 'expense') 'party_id': int.parse(v['party_id']!),
        if (kind == 'expense') 'expense_account_id': int.parse(v['expense_account_id']!),
      };
      final p = await s.api.post('/payments', body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _tick++);
      final adv = toD(p['unallocated_amount']);
      final msg = 'تم تسجيل ${paymentKindLabels[kind]} رقم ${p['number']}${adv > 0 ? '\nمنه ${fmtCell(p['unallocated_amount'])} رصيد مقدم (دفعة زائدة عن المستحق).' : ''}\nهل تريد الطباعة؟';
      if (await confirm(context, msg) && mounted) await _print(p['id'] as int);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _print(int id) async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/payments/$id/print-url');
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _reverse(Json p) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء ${p['number']}', [const FieldSpec('reason', 'سبب الإلغاء'), const FieldSpec('date', 'تاريخ الإلغاء', type: 'date')], submitLabel: 'إلغاء السند');
    if (v == null) return;
    try {
      await s.api.post('/payments/${p['id']}/reverse', {'reason': v['reason'], 'date': v['date']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _allocate(Json p) async {
    final s = context.read<Session>();
    if (!await confirm(context, 'توزيع الرصيد المقدم (${fmtCell(p['unallocated_amount'])}) على الفواتير المستحقة تلقائيًا (الأقدم أولًا)؟')) return;
    try {
      await s.api.post('/payments/${p['id']}/allocate', {});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _transfer() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta(refresh: true);
      if (!mounted) return;
      final opts = _treasuryOptions(meta);
      final v = await showForm(context, 'تحويل بين الخزائن', [
        FieldSpec('from', 'من خزينة', type: 'picker', options: opts),
        FieldSpec('to', 'إلى خزينة', type: 'picker', options: opts),
        const FieldSpec('amount', 'المبلغ', type: 'number'),
        const FieldSpec('date', 'التاريخ', type: 'date'),
        const FieldSpec('notes', 'ملاحظات', required: false),
      ]);
      if (v == null) return;
      await s.api.post('/treasuries/transfer', {'from_treasury_id': int.parse(v['from']!), 'to_treasury_id': int.parse(v['to']!), 'amount': v['amount'], 'date': v['date'], 'notes': v['notes']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _newTreasury() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'خزينة / حساب بنكي جديد', [
      const FieldSpec('name', 'الاسم'),
      const FieldSpec('type', 'النوع', type: 'picker', initial: 'cash', options: [{'value': 'cash', 'label': 'خزينة نقدية'}, {'value': 'bank', 'label': 'بنك'}]),
      const FieldSpec('opening_balance', 'رصيد افتتاحي', type: 'number', initial: '0', required: false),
      const FieldSpec('opening_date', 'تاريخ الرصيد الافتتاحي', type: 'date'),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/treasuries', {'name': v['name'], 'type': v['type'], 'opening_balance': v['opening_balance'], 'opening_date': v['opening_date']});
      await s.meta(refresh: true);
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('السندات والخزينة', actions: [
        if (s.can('payments.create')) ...[
          FilledButton.icon(onPressed: () => _newPayment('receipt'), icon: const Icon(Icons.south_west), label: const Text('سند قبض')),
          FilledButton.tonalIcon(onPressed: () => _newPayment('payment'), icon: const Icon(Icons.north_east), label: const Text('سند صرف')),
          OutlinedButton.icon(onPressed: () => _newPayment('expense'), icon: const Icon(Icons.receipt_long), label: const Text('مصروف')),
          OutlinedButton.icon(onPressed: () => _newPayment('payment', refund: true), icon: const Icon(Icons.undo), label: const Text('استرداد لعميل')),
          OutlinedButton.icon(onPressed: () => _newPayment('receipt', refund: true), icon: const Icon(Icons.redo), label: const Text('استرداد من مورد')),
        ],
        if (s.can('treasury.transfer')) ...[
          OutlinedButton.icon(onPressed: _transfer, icon: const Icon(Icons.swap_horiz), label: const Text('تحويل')),
          OutlinedButton.icon(onPressed: _newTreasury, icon: const Icon(Icons.add), label: const Text('خزينة جديدة')),
        ],
      ]),
      SizedBox(
        height: 64,
        child: Loader(
          key: ValueKey('t$_tick'),
          load: () => s.api.get('/treasuries'),
          builder: (c, data, reload) => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final t in asList(data))
                Padding(padding: const EdgeInsets.only(left: 8), child: Chip(avatar: Icon(t['type'] == 'bank' ? Icons.account_balance : Icons.payments, size: 18), label: Text('${t['name']}: ${fmtCell(t['balance'])}'))),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerRight,
          child: InputDecorator(
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _kind,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: '', child: Text('كل السندات')),
                  DropdownMenuItem(value: 'receipt', child: Text('سندات القبض')),
                  DropdownMenuItem(value: 'payment', child: Text('سندات الصرف')),
                  DropdownMenuItem(value: 'expense', child: Text('المصروفات')),
                ],
                onChanged: (v) => setState(() {
                  _kind = v ?? '';
                  _tick++;
                }),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('p$_tick$_kind'),
          load: () => s.api.get('/payments', query: {'kind': _kind}),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد سندات.');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = rows[i];
                final reversed = p['status'] == 'reversed';
                final adv = toD(p['unallocated_amount']);
                return ListTile(
                  title: Text('${p['number']}  •  ${paymentKindLabels[p['kind']]}  •  ${p['party']?['name'] ?? p['notes'] ?? ''}', style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null)),
                  subtitle: Text('${p['payment_date']}'.substring(0, 10) + '  •  ${p['treasury']?['name'] ?? ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (reversed) const Chip(label: Text('ملغي')),
                    if (!reversed && adv > 0) Chip(label: Text('رصيد مقدم ${fmtCell(p['unallocated_amount'])}'), backgroundColor: const Color(0xFFFFE0B2)),
                    const SizedBox(width: 8),
                    Text(fmtCell(p['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'print') _print(p['id'] as int);
                        if (v == 'reverse') _reverse(p);
                        if (v == 'alloc') _allocate(p);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'print', child: Text('طباعة')),
                        if (!reversed && adv > 0 && s.can('payments.create')) const PopupMenuItem(value: 'alloc', child: Text('توزيع الرصيد المقدم')),
                        if (!reversed && s.can('payments.reverse')) const PopupMenuItem(value: 'reverse', child: Text('إلغاء السند')),
                      ],
                    ),
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
