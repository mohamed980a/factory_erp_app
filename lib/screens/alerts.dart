import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// التنبيهات التشغيلية: مخزون منخفض، ائتمان متجاوز، فواتير متأخرة، النسخ الاحتياطي، موافقات معلّقة.
class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  int _tick = 0;
  String _type = '';

  static const _types = {
    '': 'الكل', 'low_stock': 'مخزون منخفض', 'over_limit': 'تجاوز ائتمان', 'overdue_invoice': 'فواتير متأخرة', 'backup': 'نسخ احتياطي',
    'production_late': 'تصنيع متأخر', 'approvals': 'موافقات', 'cheque_due': 'شيكات مستلمة', 'cheque_pay': 'شيكات صادرة',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Column(children: [
      PageHeader('التنبيهات', subtitle: 'تُحسب لحظيًا من بيانات النظام', actions: [IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh))]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [
          for (final e in _types.entries) ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
        ]),
      ),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick'),
          load: () => s.api.get('/alerts'),
          builder: (context, data, reload) {
            final all = asList((data as Map)['alerts']).where((a) => _type.isEmpty || a['type'] == _type).toList();
            if (all.isEmpty) return const EmptyState('لا توجد تنبيهات 👌');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: all.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final a = all[i];
                final color = a['severity'] == 'high' ? Colors.red : (a['severity'] == 'medium' ? Colors.orange : Colors.blueGrey);
                return Card(
                  child: ListTile(
                    leading: Icon(a['severity'] == 'high' ? Icons.error : Icons.warning_amber, color: color),
                    title: Text('${a['title']}'),
                    subtitle: Text('${a['detail']}'),
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
