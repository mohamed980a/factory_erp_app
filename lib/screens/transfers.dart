import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  int _tick = 0;

  Future<void> _act(Json t, String action, String confirmMsg) async {
    final s = context.read<Session>();
    if (!await confirm(context, confirmMsg)) return;
    try {
      await s.api.post('/stock-transfers/${t['id']}/$action', {'date': today()});
      if (mounted) {
        toast(context, action == 'receive' ? 'تم الاستلام في المخزن.' : 'تم إلغاء التحويل وإرجاع البضاعة للمصدر.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('التحويلات المخزنية', actions: [
        if (s.can('stock.transfer'))
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('تحويل جديد'),
            onPressed: () async {
              final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _TransferForm()));
              if (ok == true && mounted) setState(() => _tick++);
            },
          ),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/stock-transfers'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد تحويلات.');
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = rows[i];
                final lines = asList(t['lines']).map((l) => '${l['item']?['name'] ?? ''} × ${fmtCell(l['qty'])}').join('، ');
                final st = t['status']?.toString() ?? 'done';
                final transit = st == 'in_transit';
                return ListTile(
                  title: Text('${t['number']}  •  ${t['transfer_date']}'),
                  subtitle: Text(lines, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (st != 'done') Pill(const {'in_transit': 'في الطريق', 'received': 'تم الاستلام', 'cancelled': 'ملغي'}[st] ?? st, color: transit ? Colors.orange : (st == 'received' ? Colors.green : Colors.grey)),
                    if (transit && s.can('stock.transfer')) ...[
                      TextButton.icon(onPressed: () => _act(t, 'receive', 'تأكيد استلام ${t['number']} في المخزن المستلم؟'), icon: const Icon(Icons.download_done), label: const Text('استلام')),
                      IconButton(tooltip: 'إلغاء وإرجاع للمصدر', icon: const Icon(Icons.undo), onPressed: () => _act(t, 'cancel-transit', 'إلغاء ${t['number']} وإرجاع البضاعة للمصدر؟')),
                    ],
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

class _TLine {
  final Json item;
  final String qty;
  final int? rollId;
  final String? rollLabel;
  _TLine(this.item, this.qty, this.rollId, this.rollLabel);
}

class _TransferForm extends StatefulWidget {
  const _TransferForm();

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  Json? _from;
  Json? _to;
  final _date = TextEditingController(text: today());
  final _notes = TextEditingController();
  final List<_TLine> _lines = [];
  bool _busy = false;
  bool _transit = false;

  Future<void> _add() async {
    final s = context.read<Session>();
    if (_from == null) return toast(context, 'اختر المخزن المصدر أولًا.', error: true);
    try {
      final items = asList(await s.api.get('/items', query: {'active': 1}));
      if (!mounted) return;
      final item = await pickOne(context, 'اختر الصنف', items, (i) => '${i['name']}  (${i['code']})');
      if (item == null || !mounted) return;
      if (item['tracks_rolls'] == true) {
        final rolls = asList((await s.api.get('/reports/rolls', query: {'item_id': item['id']}))['rows']);
        if (!mounted) return;
        final roll = await pickOne(context, 'اختر الرول (يُنقل كاملًا)', rolls, (r) => 'رول ${r['roll_no']} - ${r['remaining_qty']}');
        if (roll != null) setState(() => _lines.add(_TLine(item, roll['remaining_qty'].toString(), roll['id'] as int, 'رول ${roll['roll_no']}')));
      } else {
        final v = await showForm(context, item['name'].toString(), [const FieldSpec('qty', 'الكمية', type: 'number')]);
        if (v != null) setState(() => _lines.add(_TLine(item, v['qty']!, null, null)));
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _submit() async {
    final s = context.read<Session>();
    if (_from == null || _to == null) return toast(context, 'اختر المخزنين.', error: true);
    if (_lines.isEmpty) return toast(context, 'أضف صنفًا.', error: true);
    setState(() => _busy = true);
    try {
      await s.api.post(_transit ? '/stock-transfers/send' : '/stock-transfers', {
        'from_warehouse_id': _from!['id'], 'to_warehouse_id': _to!['id'], 'date': _date.text, 'notes': _notes.text,
        'lines': [for (final l in _lines) {'item_id': l.item['id'], 'qty': l.qty, if (l.rollId != null) 'roll_id': l.rollId}],
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
      appBar: AppBar(title: const Text('تحويل مخزني')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(child: PickerField(label: 'من مخزن', valueText: _from?['name']?.toString(), onTap: () async {
              final w = await pickOne(context, 'من مخزن', asList((await s.meta(refresh: true))['warehouses']), (w) => w['name'].toString());
              if (w != null) setState(() => _from = w);
            })),
            const SizedBox(width: 12),
            Expanded(child: PickerField(label: 'إلى مخزن', valueText: _to?['name']?.toString(), onTap: () async {
              final w = await pickOne(context, 'إلى مخزن', asList((await s.meta(refresh: true))['warehouses']), (w) => w['name'].toString());
              if (w != null) setState(() => _to = w);
            })),
            const SizedBox(width: 12),
            SizedBox(width: 160, child: TextField(controller: _date, decoration: const InputDecoration(labelText: 'التاريخ'))),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _transit,
            onChanged: (v) => setState(() => _transit = v),
            title: const Text('تحويل «في الطريق»'),
            subtitle: const Text('البضاعة تخرج من المصدر الآن ولا تدخل المخزن المستلم إلا عند تأكيد الاستلام.'),
          ),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('إضافة صنف'))),
          Expanded(
            child: Card(
              child: ListView(children: [
                for (var i = 0; i < _lines.length; i++)
                  ListTile(
                    title: Text('${_lines[i].item['name']}${_lines[i].rollLabel != null ? '  (${_lines[i].rollLabel})' : ''}'),
                    subtitle: Text('الكمية: ${fmtCell(_lines[i].qty)}'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _lines.removeAt(i))),
                  ),
              ]),
            ),
          ),
          Row(children: [
            Expanded(child: TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات'))),
            const SizedBox(width: 12),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'جارٍ الحفظ...' : (_transit ? 'إرسال (في الطريق)' : 'تنفيذ التحويل'))),
          ]),
        ]),
      ),
    );
  }
}
