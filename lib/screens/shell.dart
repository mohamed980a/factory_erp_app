import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/nav.dart';
import '../core/session.dart';
import '../core/util.dart';
import 'catalog.dart';
import 'custody.dart';
import 'alerts.dart';
import 'approvals.dart';
import 'bom.dart';
import 'budgets.dart';
import 'owner_dashboard.dart';
import 'cheques.dart';
import 'payroll.dart';
import 'expenses.dart';
import 'punch.dart';
import 'leaves.dart';
import 'advances.dart';
import 'piece_work.dart';
import 'attendance.dart';
import 'employees.dart';
import 'purchase_orders.dart';
import 'imports.dart';
import 'openings.dart';
import 'orders.dart';
import 'dashboard.dart';
import 'invoices.dart';
import 'items.dart';
import 'parties.dart';
import 'payments.dart';
import 'production.dart';
import 'customers_plus.dart';
import 'landed_cost.dart';
import 'reports.dart';
import 'settings.dart';
import 'stocktake.dart';
import 'transfers.dart';
import 'warehouse_plus.dart';

class _Item {
  final String id;
  final String label;
  final IconData icon;
  final String perm;
  final Widget Function() page;
  final bool plain;
  const _Item(this.id, this.label, this.icon, this.perm, this.page, {this.plain = false});
}

class _Group {
  final String title;
  final List<_Item> items;
  const _Group(this.title, this.items);
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  bool? _forceCollapsed;

  static const Color _sidebar = AppColors.navy;

  List<_Group> _groups() => [
        _Group('الرئيسية', [
          _Item('dashboard', 'لوحة التحكم', Icons.space_dashboard_outlined, 'reports.view', () => const DashboardPage(), plain: true),
          _Item('owner', 'لوحة المالك', Icons.insights_outlined, 'settings.manage', () => const OwnerDashboardPage()),
        ]),
        _Group('المبيعات والمشتريات', [
          _Item('sales', 'المبيعات', Icons.point_of_sale, 'parties.view', () => const InvoicesPage(side: 'sales')),
          _Item('purchases', 'المشتريات', Icons.shopping_cart_outlined, 'parties.view', () => const InvoicesPage(side: 'purchase')),
          _Item('orders', 'أوامر البيع والحجز', Icons.assignment_outlined, 'parties.view', () => const OrdersPage()),
          _Item('quotes', 'عروض الأسعار', Icons.request_page_outlined, 'parties.view', () => const QuotesPage()),
          _Item('collections', 'قائمة التحصيل', Icons.notifications_active, 'parties.view', () => const CollectionsPage()),
          _Item('pricelists', 'قوائم الأسعار', Icons.sell_outlined, 'parties.view', () => const PriceListsPage()),
          _Item('reps', 'مناديب المبيعات', Icons.support_agent, 'parties.view', () => const SalesRepsPage()),
          _Item('customers', 'العملاء', Icons.groups_outlined, 'parties.view', () => const PartiesPage(type: 'customer')),
          _Item('suppliers', 'الموردون', Icons.local_shipping_outlined, 'parties.view', () => const PartiesPage(type: 'supplier')),
          _Item('pos', 'أوامر الشراء', Icons.assignment_outlined, 'parties.view', () => const PurchaseOrdersPage()),
        ]),
        _Group('المخزون والتصنيع', [
          _Item('items', 'الأصناف', Icons.inventory_2_outlined, 'items.view', () => const ItemsPage()),
          _Item('catalog', 'كتالوج المنتجات', Icons.category_outlined, 'items.view', () => const CatalogPage()),
          _Item('import', 'استيراد من Excel', Icons.upload_file, 'items.manage', () => const ImportPage()),
          _Item('openings', 'الأرصدة الافتتاحية', Icons.playlist_add_check, 'stock.view', () => const OpeningsPage()),
          _Item('bom', 'قوائم المواد (BOM)', Icons.account_tree_outlined, 'production.view', () => const BomPage()),
          _Item('production', 'التصنيع', Icons.precision_manufacturing_outlined, 'production.view', () => const ProductionPage()),
          _Item('stocktake', 'الجرد', Icons.fact_check_outlined, 'stocktake.manage', () => const StocktakePage()),
          _Item('landed', 'التكلفة النهائية للمستورد', Icons.local_shipping_outlined, 'purchases.create', () => const LandedCostPage()),
          _Item('currencies', 'العملات وأسعار الصرف', Icons.currency_exchange, 'purchases.create', () => const CurrenciesPage()),
          _Item('shelves', 'مواقع الأرفف', Icons.shelves, 'stock.view', () => const ShelvesPage()),
          _Item('reorder', 'اقتراح أوامر الشراء', Icons.auto_awesome_outlined, 'stock.view', () => const ReorderPage()),
          _Item('transfers', 'التحويل المخزني', Icons.swap_horiz, 'stock.view', () => const TransfersPage()),
        ]),
        _Group('العمالة والرواتب', [
          _Item('employees', 'الموظفون والعمال', Icons.badge_outlined, 'payroll.view', () => const EmployeesPage()),
          _Item('punch', 'بصمة الحضور', Icons.fingerprint, 'attendance.punch', () => const PunchPage()),
          _Item('attendance', 'الحضور اليومي', Icons.event_available_outlined, 'payroll.view', () => const AttendancePage()),
          _Item('leaves', 'الإجازات', Icons.beach_access_outlined, 'payroll.view', () => const LeavesPage()),
          _Item('piecework', 'إنتاج القطعة', Icons.content_cut, 'payroll.view', () => const PieceWorkPage()),
          _Item('advances', 'سلف الموظفين', Icons.request_quote_outlined, 'payroll.view', () => const AdvancesPage()),
          _Item('payroll', 'كشوف الرواتب', Icons.payments_outlined, 'payroll.view', () => const PayrollPage()),
        ]),
        _Group('المالية', [
          _Item('payments', 'السندات والخزينة', Icons.account_balance_wallet_outlined, 'treasury.view', () => const PaymentsPage()),
          _Item('expenses', 'المصروفات', Icons.receipt_outlined, 'treasury.view', () => const ExpensesPage()),
          _Item('cheques', 'الشيكات', Icons.receipt_long_outlined, 'treasury.view', () => const ChequesPage()),
          _Item('custody', 'العهد', Icons.badge_outlined, 'custody.manage', () => const CustodyPage()),
          _Item('alerts', 'التنبيهات', Icons.notifications_active_outlined, 'reports.view', () => const AlertsPage()),
          _Item('approvals', 'طلبات الموافقة', Icons.approval, 'parties.view', () => const ApprovalsPage()),
          _Item('budgets', 'الموازنة التقديرية', Icons.savings_outlined, 'reports.view', () => const BudgetsPage()),
          _Item('reports', 'التقارير', Icons.assessment_outlined, 'reports.view', () => const ReportsPage()),
          _Item('monthend', 'قفل الشهر', Icons.lock_clock_outlined, 'reports.view', () => const MonthEndPage()),
        ]),
        _Group('النظام', [
          _Item('settings', 'الإعدادات', Icons.settings_outlined, 'reports.view', () => const SettingsPage()),
        ]),
      ];

  String _roleLabel(Session s) {
    final roles = (s.user?['roles'] as List?) ?? const [];
    if (roles.contains('owner')) return 'صاحب المصنع';
    if (roles.contains('accountant')) return 'محاسب';
    return '';
  }

  Widget _tile(_Item it, bool selected, bool collapsed) {
    final fg = selected ? Colors.white : Colors.white70;
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white10,
        onTap: () => context.read<NavState>().goTo(it.id),
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
          decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Icon(it.icon, size: 21, color: fg),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Expanded(child: Text(it.label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
            ],
          ]),
        ),
      ),
    );
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: collapsed ? Tooltip(message: it.label, child: tile) : tile);
  }

  Widget _sidebarView(Session s, List<_Group> groups, _Item current, bool collapsed) {
    final name = s.user?['name']?.toString() ?? '';
    return Container(
      width: collapsed ? 74 : 262,
      color: _sidebar,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 0 : 16, 20, collapsed ? 0 : 16, 14),
          child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.precision_manufacturing, color: Colors.white, size: 22),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ERP المصنع', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('إدارة المخزون والتصنيع والحسابات', style: TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ],
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
            for (final g in groups) ...[
              if (!collapsed) Padding(padding: const EdgeInsets.fromLTRB(22, 14, 16, 6), child: Text(g.title, style: const TextStyle(color: Colors.white38, fontSize: 11.5, fontWeight: FontWeight.w600)))
              else const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 18), child: Divider(color: Colors.white12, height: 1)),
              for (final it in g.items) _tile(it, it.id == current.id, collapsed),
            ],
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        Padding(
          padding: EdgeInsets.all(collapsed ? 8 : 12),
          child: collapsed
              ? Column(children: [
                  IconButton(tooltip: 'توسيع القائمة', onPressed: () => setState(() => _forceCollapsed = false), icon: const Icon(Icons.keyboard_double_arrow_left, color: Colors.white70)),
                  IconButton(tooltip: 'تسجيل الخروج', onPressed: s.logout, icon: const Icon(Icons.logout, color: Colors.white70)),
                ])
              : Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: AppColors.brand, child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(_roleLabel(s), style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                    ]),
                  ),
                  IconButton(tooltip: 'تصغير القائمة', onPressed: () => setState(() => _forceCollapsed = true), icon: const Icon(Icons.keyboard_double_arrow_right, color: Colors.white54, size: 20)),
                  IconButton(tooltip: 'تسجيل الخروج', onPressed: s.logout, icon: const Icon(Icons.logout, color: Colors.white70, size: 20)),
                ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final nav = context.watch<NavState>();

    final groups = <_Group>[];
    for (final g in _groups()) {
      final items = g.items.where((i) => s.can(i.perm)).toList();
      if (items.isNotEmpty) groups.add(_Group(g.title, items));
    }
    final flat = [for (final g in groups) ...g.items];
    if (flat.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const EmptyState('لا توجد صلاحيات لهذا المستخدم.', icon: Icons.lock_outline),
            const SizedBox(height: 12),
            FilledButton(onPressed: s.logout, child: const Text('تسجيل الخروج')),
          ]),
        ),
      );
    }
    final current = flat.firstWhere((i) => i.id == nav.current, orElse: () => flat.first);
    final width = MediaQuery.sizeOf(context).width;
    final collapsed = _forceCollapsed ?? width < 1100;

    final page = KeyedSubtree(key: ValueKey(current.id), child: current.page());
    return Scaffold(
      body: Row(children: [
        _sidebarView(s, groups, current, collapsed),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: current.plain
                ? page
                : Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
                    clipBehavior: Clip.antiAlias,
                    child: page,
                  ),
          ),
        ),
      ]),
    );
  }
}
