import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// أنواع المنتجات + قوائم المقاسات والألوان والأقمشة: إضافة بدون أي تعديل في الكود.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  int _tick = 0;

  static const Map<String, String> _kinds = {'size': 'المقاسات', 'color': 'الألوان', 'fabric': 'الأقمشة'};

  Future<void> _addType() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'نوع منتج جديد', [
      const FieldSpec('name', 'اسم النوع (مثال: بالطو ممرضات)'),
      const FieldSpec('category', 'الفئة (مثال: بالطو، اسكراب، تونيك)', required: false),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/catalog/types', {'name': v['name'], 'category': (v['category'] ?? '').isEmpty ? null : v['category']});
      s.invalidateMeta();
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _toggleType(Json t) async {
    final s = context.read<Session>();
    try {
      await s.api.put('/catalog/types/${t['id']}', {'is_active': !(t['is_active'] == true)});
      s.invalidateMeta();
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _addOption(String kind) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إضافة إلى ${_kinds[kind]}', [const FieldSpec('value', 'القيمة (يمكن إضافة عدة قيم مفصولة بفاصلة)')]);
    if (v == null) return;
    try {
      for (final x in v['value']!.split(RegExp(r'[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        await s.api.post('/catalog/options', {'kind': kind, 'value': x});
      }
      s.invalidateMeta();
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _toggleOption(Json o) async {
    final s = context.read<Session>();
    try {
      await s.api.put('/catalog/options/${o['id']}', {'is_active': !(o['is_active'] == true)});
      s.invalidateMeta();
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final canManage = s.can('items.manage');
    return Column(children: [
      PageHeader('كتالوج المنتجات', subtitle: 'أنواع المنتجات والمقاسات والألوان والأقمشة — أضف أي نوع جديد من هنا ويظهر فورًا عند إضافة المنتجات', actions: [
        if (canManage) FilledButton.icon(onPressed: _addType, icon: const Icon(Icons.add), label: const Text('نوع منتج')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () async => {'types': await s.api.get('/catalog/types'), 'options': await s.api.get('/catalog/options')},
          builder: (context, data, reload) {
            final types = asList((data as Map)['types']);
            final options = asList(data['options']);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Panel(title: 'أنواع المنتجات', child: Column(children: [
                for (final t in types)
                  ListTile(
                    dense: true,
                    title: Text(t['name'].toString()),
                    subtitle: Text('${t['category'] ?? '—'}  •  ${t['items_count']} صنف'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (t['is_active'] != true) const Pill('موقوف', color: Colors.grey),
                      if (canManage) TextButton(onPressed: () => _toggleType(t), child: Text(t['is_active'] == true ? 'إيقاف' : 'تفعيل')),
                    ]),
                  ),
              ])),
              const SizedBox(height: 12),
              for (final k in _kinds.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    title: k.value,
                    trailing: canManage ? TextButton.icon(onPressed: () => _addOption(k.key), icon: const Icon(Icons.add), label: const Text('إضافة')) : null,
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final o in options.where((o) => o['kind'] == k.key))
                        InputChip(
                          label: Text(o['value'].toString(), style: TextStyle(decoration: o['is_active'] == true ? null : TextDecoration.lineThrough)),
                          onPressed: canManage ? () => _toggleOption(o) : null,
                          tooltip: canManage ? 'اضغط لإيقاف/تفعيل' : null,
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
