import 'package:flutter/material.dart';
import '../core/util.dart';

class ItemLine {
  Json? item;
  final qty = TextEditingController();
  final price = TextEditingController();
  final waste = TextEditingController(text: '0');
  void dispose() {
    qty.dispose();
    price.dispose();
    waste.dispose();
  }
}

/// محرر أسطر (صنف + كمية [+ سعر] [+ نسبة هالك]) يُستخدم في أوامر الشراء وقوائم المواد.
class ItemLinesEditor extends StatefulWidget {
  final List<Json> items;
  final List<ItemLine> lines;
  final bool showPrice;
  final bool showWaste;
  const ItemLinesEditor({super.key, required this.items, required this.lines, this.showPrice = false, this.showWaste = false});

  @override
  State<ItemLinesEditor> createState() => _ItemLinesEditorState();
}

class _ItemLinesEditorState extends State<ItemLinesEditor> {
  String _label(Json i) => '${i['name']}${(i['code'] ?? '').toString().isEmpty ? '' : '  (${i['code']})'}${i['stock_total'] == null ? '' : '   —   المتاح ${fmtQty(i['stock_total'])}'}';

  String _info(ItemLine l) {
    final it = l.item;
    if (it == null) return '';
    final parts = <String>[];
    if (it['stock_total'] != null) parts.add('المتاح حاليًا: ${fmtQty(it['stock_total'])}');
    if ((double.tryParse('${it['reorder_level']}') ?? 0) > 0) parts.add('حد الطلب: ${fmtQty(it['reorder_level'])}');
    final q = double.tryParse(l.qty.text.trim());
    final p = double.tryParse(l.price.text.trim());
    if (widget.showPrice && q != null && p != null) parts.add('إجمالي السطر: ${(q * p).toStringAsFixed(2)}');
    return parts.join('   •   ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var n = 0; n < widget.lines.length; n++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
            Expanded(
              flex: 4,
              child: OutlinedButton(
                onPressed: () async {
                  final r = await pickOne(context, 'اختر الصنف', widget.items, _label);
                  if (r != null) {
                    setState(() {
                      widget.lines[n].item = r;
                      if (widget.showPrice && widget.lines[n].price.text.isEmpty) {
                        widget.lines[n].price.text = fmtCell(r['cost_price'] ?? r['avg_cost'] ?? '');
                      }
                    });
                  }
                },
                child: Align(alignment: AlignmentDirectional.centerStart, child: Text(widget.lines[n].item == null ? 'اختر الصنف' : _label(widget.lines[n].item!), overflow: TextOverflow.ellipsis)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: widget.lines[n].qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'الكمية'))),
            if (widget.showPrice) ...[
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: widget.lines[n].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'السعر'))),
            ],
            if (widget.showWaste) ...[
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: widget.lines[n].waste, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'هالك %'))),
            ],
            IconButton(
              tooltip: 'حذف السطر',
              onPressed: widget.lines.length <= 1 ? null : () => setState(() => widget.lines.removeAt(n).dispose()),
              icon: const Icon(Icons.delete_outline),
            ),
            ]),
            if (_info(widget.lines[n]).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2, right: 4), child: Text(_info(widget.lines[n]), style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
          ]),
        ),
      TextButton.icon(onPressed: () => setState(() => widget.lines.add(ItemLine())), icon: const Icon(Icons.add), label: const Text('إضافة سطر')),
    ]);
  }
}
