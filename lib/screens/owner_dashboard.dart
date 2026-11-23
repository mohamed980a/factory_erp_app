import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/nav.dart';
import '../core/session.dart';
import '../core/util.dart';

/// لوحة صاحب المصنع: السيولة والديون والشيكات والأداء مقابل الشهر السابق والموازنة والتنبيهات.
class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});

  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  int _tick = 0;

  Widget _kpi(String title, dynamic value, {String? sub, Color? color, double width = 250}) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 6),
            Text(fmtCell(value), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            if (sub != null) ...[const SizedBox(height: 4), Text(sub, style: const TextStyle(fontSize: 12))],
          ]),
        ),
      ),
    );
  }

  String _chg(dynamic pct) {
    if (pct == null) return 'لا مقارنة (الشهر السابق صفر)';
    final p = double.tryParse('$pct') ?? 0;
    return '${p >= 0 ? '▲' : '▼'} ${p.abs().toStringAsFixed(1)}% عن الشهر السابق';
  }

  Color _chgColor(dynamic pct, {bool upIsGood = true}) {
    final p = double.tryParse('$pct');
    if (p == null || p == 0) return Colors.grey.shade700;
    return (p > 0) == upIsGood ? Colors.teal.shade800 : Colors.red.shade700;
  }

  Widget _list(String title, List<Widget> children, {double width = 380}) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Divider(height: 18),
            if (children.isEmpty) const Text('لا بيانات', style: TextStyle(color: AppColors.muted)) else ...children,
          ]),
        ),
      ),
    );
  }

  Widget _line(String a, String b, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(a, overflow: TextOverflow.ellipsis)), Text(b, style: TextStyle(fontWeight: FontWeight.w700, color: color))]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final nav = context.read<NavState>();
    return Column(children: [
      PageHeader('لوحة المالك', subtitle: 'صورة سريعة للمصنع الآن', actions: [IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh))]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/owner-dashboard'),
          builder: (context, data, reload) {
            final d = data as Map;
            final cash = d['cash'] as Map;
            final rec = d['receivables'] as Map;
            final pay = d['payables'] as Map;
            final chq = d['cheques'] as Map;
            final inv = d['inventory'] as Map;
            final mo = d['month'] as Map;
            final al = d['alerts'] as Map;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                _kpi('السيولة (الخزائن والبنوك)', cash['total'], color: Colors.teal.shade800),
                _kpi('مستحق على العملاء', rec['total'], sub: 'منها متأخر: ${fmtCell(rec['overdue'])}  •  فوق 90 يوم: ${fmtCell(rec['over_90'])}'),
                _kpi('مستحق للموردين', pay['total'], color: Colors.red.shade700),
                _kpi('الصافي (سيولة + عملاء + شيكات مستلمة − موردين − شيكات صادرة)', d['net_position'], width: 330),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _kpi('إيرادات ${mo['label']}', mo['revenue'], sub: _chg(mo['revenue_change_pct']), color: _chgColor(mo['revenue_change_pct'])),
                _kpi('مصروفات الشهر', mo['expenses'], sub: 'الشهر السابق: ${fmtCell(mo['prev_expenses'])}'),
                _kpi('صافي ربح الشهر', mo['net_profit'], sub: _chg(mo['profit_change_pct']), color: _chgColor(mo['profit_change_pct'])),
                _kpi('قيمة المخزون', inv['total'], sub: 'خامات ${fmtCell(inv['raw'])}  •  مستلزمات ${fmtCell(inv['supply'])}  •  تام ${fmtCell(inv['finished'])}', width: 330),
              ]),
              const SizedBox(height: 4),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('${mo['note']}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [
                _list('الشيكات', [
                  _line('مستلمة قيد التحصيل', fmtCell(chq['receivable_holding'])),
                  _line('منها متأخرة', fmtCell(chq['receivable_overdue']), color: (double.tryParse('${chq['receivable_overdue']}') ?? 0) > 0 ? Colors.red.shade700 : null),
                  _line('صادرة قيد الصرف', fmtCell(chq['payable_holding'])),
                  _line('تستحق خلال 7 أيام', fmtCell(chq['payable_due_7d'])),
                  TextButton(onPressed: () => nav.goTo('cheques'), child: const Text('فتح الشيكات')),
                ]),
                _list('الخزائن والبنوك', [for (final t in asList(cash['rows'])) _line('${t['name']}', fmtCell(t['balance']))]),
                _list('بنود تجاوزت الموازنة هذا الشهر', [
                  for (final b in asList(d['budget_over'])) _line('${b['name']}', '+${fmtCell(b['variance'])} (${b['variance_pct'] == null ? '-' : '${b['variance_pct']}%'})', color: Colors.red.shade700),
                  TextButton(onPressed: () => nav.goTo('budgets'), child: const Text('فتح الموازنة')),
                ]),
                _list('أكبر العملاء هذا الشهر', [for (final c in asList(d['top_customers'])) _line('${c['name']}', fmtCell(c['net']))]),
                _list('أربح المنتجات هذا الشهر', [for (final p in asList(d['top_products'])) _line('${p['name']}', '${fmtCell(p['profit'])}  (${p['margin_pct']}%)')]),
                _list('تنبيهات (${al['high']} عاجل • ${al['medium']} متوسط)', [
                  if ((d['pending_approvals'] ?? 0) > 0) _line('طلبات موافقة معلّقة', '${d['pending_approvals']}', color: Colors.orange.shade800),
                  for (final a in asList(al['top'])) _line('${a['title']}', a['severity'] == 'high' ? 'عاجل' : '', color: Colors.red.shade700),
                  TextButton(onPressed: () => nav.goTo('alerts'), child: const Text('كل التنبيهات')),
                ], width: 420),
              ]),
            ]);
          },
        ),
      ),
    ]);
  }
}
