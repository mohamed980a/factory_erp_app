import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/nav.dart';
import '../core/session.dart';
import '../core/util.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const List<String> _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  static const List<String> _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  String _dateLine() {
    final d = DateTime.now();
    return '${_days[d.weekday - 1]}، ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  Widget _alertRow(IconData icon, Color color, String text, int n, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 19)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          Pill('$n', color: color),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_left, size: 18, color: AppColors.muted),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final nav = context.read<NavState>();
    return Loader(
      load: () => s.api.get('/dashboard'),
      builder: (context, data, reload) {
        final d = Map<String, dynamic>.from(data as Map);
        return LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final cols = w > 1100 ? 4 : (w > 640 ? 2 : 1);
          final cardW = (w - 40 - (cols - 1) * 14) / cols;
          final wide = w > 900;

          Widget kpi(String label, dynamic value, IconData icon, Color color, {String? hint, String? go}) => SizedBox(
                width: cardW,
                child: StatCard(label: label, value: fmtMoney(value), icon: icon, color: color, hint: hint, onTap: go == null ? null : () => nav.goTo(go)),
              );

          final overdue = toD(d['overdue_customers']).toInt();
          final overLimit = toD(d['over_limit_customers']).toInt();
          final low = toD(d['low_stock_items']).toInt();
          final late = toD(d['production_late']).toInt();
          final alerts = <Widget>[
            if (overdue > 0) _alertRow(Icons.schedule, AppColors.danger, 'عملاء متأخرون في السداد', overdue, () => nav.goTo('reports')),
            if (overLimit > 0) _alertRow(Icons.block, AppColors.danger, 'عملاء تجاوزوا الحد الائتماني', overLimit, () => nav.goTo('customers')),
            if (low > 0) _alertRow(Icons.production_quantity_limits, AppColors.warning, 'أصناف وصلت لحد إعادة الطلب', low, () => nav.goTo('reports')),
            if (late > 0) _alertRow(Icons.warning_amber, AppColors.warning, 'أوامر تصنيع متأخرة', late, () => nav.goTo('production')),
          ];
          final trend = asList(d['sales_trend']);
          final values = trend.map((t) => toD(t['sales'])).toList();
          final labels = trend.map((t) => _months[(int.tryParse(t['month'].toString().substring(5)) ?? 1) - 1]).toList();
          final debtors = asList(d['top_debtors']);

          final alertsPanel = Panel(
            title: 'تنبيهات تحتاج متابعة',
            child: alerts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle, color: AppColors.success),
                      SizedBox(width: 8),
                      Text('كل شيء تمام، لا توجد تنبيهات', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                    ]),
                  )
                : Column(children: alerts),
          );
          final chartPanel = Panel(
            title: 'المبيعات (صافي) آخر 6 شهور',
            trailing: Pill('هذا الشهر: ${fmtCell(d['sales_month'])}', color: AppColors.brand),
            child: values.isEmpty ? const SizedBox(height: 120, child: EmptyState('لا توجد بيانات بعد')) : BarChartMini(values: values, labels: labels),
          );
          final debtorsPanel = Panel(
            title: 'أعلى العملاء مديونية',
            trailing: TextButton(onPressed: () => nav.goTo('customers'), child: const Text('عرض الكل')),
            child: debtors.isEmpty
                ? const SizedBox(height: 90, child: EmptyState('لا توجد مديونيات'))
                : Column(children: [
                    for (final r in debtors)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(children: [
                          const CircleAvatar(radius: 15, backgroundColor: Color(0xFFEAF2F4), child: Icon(Icons.person, size: 17, color: AppColors.brand)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r['name'].toString(), overflow: TextOverflow.ellipsis)),
                          Text(fmtMoney(r['balance']), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
                        ]),
                      ),
                  ]),
          );
          final prodPanel = Panel(
            title: 'التصنيع',
            trailing: TextButton(onPressed: () => nav.goTo('production'), child: const Text('فتح الأوامر')),
            child: Column(children: [
              _line('أوامر قيد التنفيذ', '${toD(d['production_in_progress']).toInt()}', Icons.play_circle_outline, AppColors.brand),
              _line('أوامر متأخرة', '$late', Icons.warning_amber, late > 0 ? AppColors.danger : AppColors.muted),
              _line('تكلفة تحت التشغيل', fmtMoney(d['production_wip_value']), Icons.hourglass_bottom, AppColors.warning),
            ]),
          );

          Widget twoCols(Widget a, Widget b, {int fa = 3, int fb = 2}) => wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: fa, child: a), const SizedBox(width: 14), Expanded(flex: fb, child: b)])
              : Column(children: [a, const SizedBox(height: 14), b]);

          final quick = <Widget>[
            if (s.can('sales.create')) FilledButton.icon(onPressed: () => nav.goTo('sales'), icon: const Icon(Icons.point_of_sale, size: 18), label: const Text('فاتورة بيع')),
            if (s.can('payments.create')) FilledButton.tonalIcon(onPressed: () => nav.goTo('payments'), icon: const Icon(Icons.south_west, size: 18), label: const Text('سند قبض')),
            if (s.can('production.manage')) FilledButton.tonalIcon(onPressed: () => nav.goTo('production'), icon: const Icon(Icons.precision_manufacturing_outlined, size: 18), label: const Text('أمر تصنيع')),
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('أهلًا، ${s.user?['name'] ?? ''}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.navy)),
                    const SizedBox(height: 2),
                    Text(_dateLine(), style: const TextStyle(color: AppColors.muted)),
                  ]),
                ),
                IconButton(tooltip: 'تحديث', onPressed: reload, icon: const Icon(Icons.refresh)),
              ]),
              if (quick.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 8, runSpacing: 8, children: quick)),
              const SizedBox(height: 18),
              Wrap(spacing: 14, runSpacing: 14, children: [
                kpi('مبيعات الشهر', d['sales_month'], Icons.trending_up, AppColors.brand, hint: 'اليوم: ${fmtCell(d['sales_today'])}', go: 'sales'),
                kpi('مديونيات العملاء', d['customers_receivable'], Icons.call_received, const Color(0xFF3949AB), hint: overdue > 0 ? '$overdue عميل متأخر' : 'لا متأخرات', go: 'customers'),
                kpi('أرصدة الخزائن', d['cash'], Icons.savings_outlined, AppColors.success, go: 'payments'),
                kpi('قيمة المخزون', d['stock_value'], Icons.inventory_2_outlined, const Color(0xFF8E24AA), hint: 'مستحقات الموردين: ${fmtCell(d['suppliers_payable'])}', go: 'items'),
              ]),
              const SizedBox(height: 14),
              twoCols(chartPanel, alertsPanel),
              const SizedBox(height: 14),
              twoCols(debtorsPanel, prodPanel, fa: 3, fb: 2),
            ]),
          );
        });
      },
    );
  }

  Widget _line(String label, String value, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}
