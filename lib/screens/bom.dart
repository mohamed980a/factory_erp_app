import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';
import 'line_editor.dart';

/// قوائم المواد (BOM): ما يلزم لإنتاج قطعة من كل منتج تام، والتكلفة المعيارية مقابل الفعلية.
class BomPage extends StatefulWidget {
  const BomPage({super.key});

  @override
  State<BomPage> createState() => _BomPageState();
}

class _BomPageState extends State<BomPage> {
  int _tick = 0;

  Future<void> _edit([Json? existing]) async {
    final s = context.read<Session>();
    try {
      final finished = asList(await s.api.get('/items', query: {'kind': 'finished'}));
      final mats = asList(await s.api.get('/items', query: {'kind': ''})).where((i) => i['kind'] != 'finished').toList();
      Json? bom;
      if (existing != null) bom = await s.api.get('/boms/${existing['id']}') as Json;
      if (!mounted) return;
      Json? fin = existing?['item'] as Json?;
      final outQty = TextEditingController(text: bom != null ? fmtCell(bom['output_qty']) : '1');
      final other = TextEditingController(text: bom != null ? fmtCell(bom['other_cost']) : '0');
      final lines = <ItemLine>[];
      if (bom != null) {
        for (final l in asList(bom['lines'])) {
          final x = ItemLine()..item = l['item'] as Json?;
          x.qty.text = fmtCell(l['qty']);
          x.waste.text = fmtCell(l['waste_pct']);
          lines.add(x);
        }
      }
      if (lines.isEmpty) lines.add(ItemLine());
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Text(existing == null ? 'قائمة مواد جديدة' : 'تعديل قائمة المواد'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  OutlinedButton(
                    onPressed: existing != null
                        ? null
                        : () async {
                            final r = await pickOne(ctx, 'اختر المنتج التام', finished, (i) => '${i['name']}');
                            if (r != null) setS(() => fin = r);
                          },
                    child: Text(fin == null ? 'اختر المنتج التام' : '${fin!['name']}'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: outQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكميات أدناه تكفي لإنتاج كم قطعة؟'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: other, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أجور/تكاليف أخرى معيارية (لنفس الكمية)'))),
                  ]),
                  const SizedBox(height: 12),
                  const Text('الخامات والمستلزمات', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ItemLinesEditor(items: mats, lines: lines, showWaste: true),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (fin == null || lines.any((l) => l.item == null || l.qty.text.trim().isEmpty)) {
                    toast(ctx, 'اختر المنتج وأكمل كل الأسطر.', error: true);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        await s.api.post('/boms', {
          'item_id': fin!['id'], 'output_qty': outQty.text.trim(), 'other_cost': other.text.trim().isEmpty ? '0' : other.text.trim(),
          'lines': [for (final l in lines) {'item_id': l.item!['id'], 'qty': l.qty.text.trim(), 'waste_pct': l.waste.text.trim().isEmpty ? '0' : l.waste.text.trim()}],
        });
        if (mounted) {
          toast(context, 'تم حفظ قائمة المواد.');
          setState(() => _tick++);
        }
      }
      for (final l in lines) {
        l.dispose();
      }
      outQty.dispose();
      other.dispose();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _plan(Json b) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'احتياج الإنتاج — ${b['item']?['name']}', [const FieldSpec('qty', 'عدد القطع المطلوب إنتاجها', type: 'number', initial: '100')], submitLabel: 'احسب');
    if (v == null) return;
    try {
      final p = await s.api.post('/boms/${b['id']}/plan', {'qty': v['qty']}) as Map;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('احتياج ${fmtCell(p['qty'])} قطعة'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Table(border: TableBorder.all(color: Colors.black12), children: [
                  const TableRow(decoration: BoxDecoration(color: Color(0xFFF1F4F8)), children: [
                    Padding(padding: EdgeInsets.all(6), child: Text('الخامة', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('المطلوب', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('المتاح', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('العجز', style: TextStyle(fontWeight: FontWeight.w700))),
                    Padding(padding: EdgeInsets.all(6), child: Text('التكلفة', style: TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                  for (final r in asList(p['rows']))
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.all(6), child: Text('${r['item']?['name'] ?? ''}')),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(r['need']))),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(r['available']))),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(fmtCell(r['shortage']), style: TextStyle(color: (double.tryParse('${r['shortage']}') ?? 0) > 0 ? Colors.red.shade700 : null, fontWeight: FontWeight.w700)),
                      ),
                      Padding(padding: const EdgeInsets.all(6), child: Text(fmtCell(r['est_cost']))),
                    ]),
                ]),
                const SizedBox(height: 10),
                Text('تكلفة الخامات: ${fmtCell(p['materials_cost'])}   |   تكاليف أخرى: ${fmtCell(p['other_cost'])}'),
                Text('إجمالي التكلفة التقديرية: ${fmtCell(p['total_cost'])}   |   للقطعة: ${fmtCell(p['unit_cost'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (p['has_shortage'] == true)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('يوجد عجز في بعض الخامات: اطلبها بأمر شراء قبل بدء التصنيع.', style: TextStyle(color: Colors.red.shade700))),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _delete(Json b) async {
    final s = context.read<Session>();
    if (!await confirm(context, 'حذف قائمة مواد «${b['item']?['name']}»؟ لا يؤثر هذا على أوامر التصنيع السابقة.')) return;
    try {
      await s.api.delete('/boms/${b['id']}');
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final manage = s.can('production.manage');
    return Column(children: [
      PageHeader('قوائم المواد (BOM)', subtitle: 'التكلفة المعيارية للمنتج ومقارنتها بالفعلية', actions: [
        if (manage) FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('قائمة جديدة')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/boms'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا توجد قوائم مواد بعد');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final b = rows[i];
                final std = double.tryParse('${b['standard_unit_cost']}');
                final act = double.tryParse('${b['actual_unit_cost']}');
                final varPct = (std != null && act != null && std > 0) ? ((act - std) / std * 100) : null;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${b['item']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('${b['lines_count']} خامة لكل ${fmtCell(b['output_qty'])} قطعة   |   تكلفة معيارية للقطعة: ${fmtCell(b['standard_unit_cost'])}'
                              '${act != null ? '   |   فعلية: ${fmtCell(b['actual_unit_cost'])}' : '   |   لا توجد تكلفة فعلية بعد'}', style: const TextStyle(fontSize: 12.5)),
                        ]),
                      ),
                      if (varPct != null) Pill('${varPct >= 0 ? '+' : ''}${varPct.toStringAsFixed(1)}%', color: varPct > 5 ? Colors.red.shade800 : Colors.teal.shade800),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: () => _plan(b), child: const Text('احتياج الإنتاج')),
                      if (manage) IconButton(tooltip: 'تعديل', onPressed: () => _edit(b), icon: const Icon(Icons.edit_outlined)),
                      if (manage) IconButton(tooltip: 'حذف', onPressed: () => _delete(b), icon: const Icon(Icons.delete_outline)),
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
