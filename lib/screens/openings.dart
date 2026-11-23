import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// أرصدة افتتاحية للمخزون (نقل أرصدة المصنع القديمة من الإكسل): كمية وتكلفة لكل صنف في مستند واحد موثق.
class OpeningsPage extends StatefulWidget {
  const OpeningsPage({super.key});

  @override
  State<OpeningsPage> createState() => _OpeningsPageState();
}

class _OpeningsPageState extends State<OpeningsPage> {
  int _tick = 0;

  Future<void> _create() async {
    final s = context.read<Session>();
    try {
      final meta = await s.meta();
      final items = asList(await s.api.get('/items', query: {'active': 1}));
      if (!mounted) return;
      final head = await showForm(context, 'رصيد افتتاحي مخزني', [
        FieldSpec('warehouse_id', 'المخزن', type: 'picker', options: [for (final w in asList(meta['warehouses'])) {'value': w['id'], 'label': w['name']}]),
        const FieldSpec('date', 'تاريخ الرصيد', type: 'date'),
        const FieldSpec('notes', 'ملاحظات', required: false),
      ]);
      if (head == null) return;
      final lines = <Json>[];
      while (mounted) {
        final it = await pickOne(context, lines.isEmpty ? 'اختر الصنف' : 'اختر صنفًا آخر (إلغاء للانتهاء) — أُضيف ${lines.length}', items, (i) => '${i['name']}  (${i['code']})');
        if (it == null || !mounted) break;
        if (it['tracks_rolls'] == true) {
          final l = await showForm(context, 'قماش بالرولات: ${it['name']}', [
            const FieldSpec('rolls', 'الرولات: سطر لكل رول  رقم_الرول=الطول\nمثال:\n101=120\n102=95', type: 'multiline'),
            const FieldSpec('unit_cost', 'تكلفة المتر', type: 'number'),
          ]);
          if (l == null) continue;
          final rolls = <Json>[];
          var bad = false;
          for (final raw in l['rolls']!.split('\n')) {
            final line = raw.trim();
            if (line.isEmpty) continue;
            final p = line.split('=');
            if (p.length != 2 || toD(p[1]) <= 0) {
              bad = true;
              break;
            }
            rolls.add({'roll_no': p[0].trim(), 'qty': p[1].trim()});
          }
          if (bad || rolls.isEmpty) {
            if (mounted) toast(context, 'صيغة الرولات غير صحيحة.', error: true);
            continue;
          }
          lines.add({'item_id': it['id'], 'unit_cost': l['unit_cost'], 'rolls': rolls});
        } else {
          final l = await showForm(context, it['name'].toString(), [
            const FieldSpec('qty', 'الكمية', type: 'number'),
            const FieldSpec('unit_cost', 'تكلفة الوحدة', type: 'number'),
          ]);
          if (l == null) continue;
          lines.add({'item_id': it['id'], 'qty': l['qty'], 'unit_cost': l['unit_cost']});
        }
      }
      if (lines.isEmpty || !mounted) return;
      if (!await confirm(context, 'ترحيل رصيد افتتاحي لـ ${lines.length} صنف؟\nيدخل المخزون ويُسجَّل قيد افتتاحي. التصحيح بعد ذلك يكون بإلغاء المستند بسبب موثق.')) return;
      await s.api.post('/stock-openings', {'warehouse_id': int.parse(head['warehouse_id']!), 'date': head['date'], 'notes': head['notes'], 'lines': lines}, newKey());
      if (mounted) {
        toast(context, 'تم ترحيل الرصيد الافتتاحي.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _reverse(Json o) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إلغاء ${o['number']}', [const FieldSpec('reason', 'سبب الإلغاء')]);
    if (v == null) return;
    try {
      await s.api.post('/stock-openings/${o['id']}/reverse', {'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('الأرصدة الافتتاحية للمخزون', actions: [
        if (s.can('items.manage')) FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('رصيد افتتاحي جديد')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/stock-openings'),
          builder: (context, data, reload) {
            final docs = asList(data);
            if (docs.isEmpty) return const EmptyState('لا توجد أرصدة افتتاحية');
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = docs[i];
                final reversed = d['status'] == 'reversed';
                return ListTile(
                  dense: true,
                  title: Text('${d['number']}  -  ${d['warehouse']?['name'] ?? ''}'),
                  subtitle: Text('تاريخ ${d['opening_date']}  •  ${d['lines_count']} صنف${(d['notes'] ?? '').toString().isEmpty ? '' : '  •  ${d['notes']}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Pill(reversed ? 'ملغي' : 'مرحَّل', color: reversed ? Colors.grey : Colors.green),
                    if (!reversed && s.can('items.manage')) IconButton(tooltip: 'إلغاء المستند', icon: const Icon(Icons.undo), onPressed: () => _reverse(d)),
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
