import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// طلبات الموافقة: العمليات الحساسة فوق الحد (إلغاء، مرتجع، خصم كبير) تنتظر هنا قرار صاحب المصنع.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  int _tick = 0;
  String _status = 'pending';

  static const _statuses = {'pending': 'معلّقة', 'approved': 'تمت الموافقة', 'rejected': 'مرفوضة', 'cancelled': 'مسحوبة', '': 'الكل'};
  static const _actions = {'invoice.reverse': 'إلغاء فاتورة', 'payment.reverse': 'إلغاء سند', 'invoice.return': 'مرتجع', 'invoice.create': 'فاتورة بخصم كبير'};

  Future<void> _decide(Json a, bool approve) async {
    final s = context.read<Session>();
    final v = await showForm(context, approve ? 'موافقة على الطلب' : 'رفض الطلب', [
      FieldSpec('note', approve ? 'ملاحظة (اختياري)' : 'سبب الرفض', required: !approve),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/approvals/${a['id']}/${approve ? 'approve' : 'reject'}', {'note': v['note']});
      if (mounted) {
        toast(context, approve ? 'تمت الموافقة وتنفيذ العملية.' : 'تم الرفض.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _cancel(Json a) async {
    final s = context.read<Session>();
    if (!await confirm(context, 'سحب هذا الطلب؟')) return;
    try {
      await s.api.post('/approvals/${a['id']}/cancel');
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final isOwner = s.can('approvals.decide');
    return Column(children: [
      PageHeader('طلبات الموافقة', subtitle: isOwner ? 'اعتمد أو ارفض العمليات المعلّقة' : 'طلباتك المرسلة لصاحب المصنع'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [
          for (final e in _statuses.entries) ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
          IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick$_status'),
          load: () => s.api.get('/approvals', query: {if (_status.isNotEmpty) 'status': _status}),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد طلبات');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = rows[i];
                final pending = a['status'] == 'pending';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Pill(_actions[a['action']] ?? '${a['action']}'),
                        const SizedBox(width: 8),
                        Pill(_statuses[a['status']] ?? '${a['status']}'),
                        const Spacer(),
                        Text('#${a['id']}  ${(a['created_at'] ?? '').toString().split('T').first}'),
                      ]),
                      const SizedBox(height: 8),
                      Text('${a['summary']}'),
                      const SizedBox(height: 4),
                      Text('بواسطة: ${a['requester']?['name'] ?? ''}${a['decider'] != null ? '   |   القرار: ${a['decider']['name']}' : ''}', style: const TextStyle(fontSize: 12)),
                      if ((a['decision_note'] ?? '').toString().isNotEmpty) Text('ملاحظة القرار: ${a['decision_note']}', style: const TextStyle(fontSize: 12)),
                      if ((a['result_ref'] ?? '').toString().isNotEmpty) Text('المستند الناتج: ${a['result_ref']}', style: const TextStyle(fontSize: 12)),
                      if (pending)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(spacing: 8, children: [
                            if (isOwner && a['requested_by'] != s.user?['id']) ...[
                              FilledButton.icon(onPressed: () => _decide(a, true), icon: const Icon(Icons.check), label: const Text('موافقة وتنفيذ')),
                              OutlinedButton.icon(onPressed: () => _decide(a, false), icon: const Icon(Icons.close), label: const Text('رفض')),
                            ],
                            if (a['requested_by'] == s.user?['id']) TextButton(onPressed: () => _cancel(a), child: const Text('سحب الطلب')),
                          ]),
                        ),
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
