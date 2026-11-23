import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';
import 'admin.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _tick = 0;

  Future<void> _edit(Json cur) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'بيانات المصنع (تظهر على الفواتير)', [
      FieldSpec('company_name', 'اسم المصنع', initial: cur['company_name']?.toString(), required: false),
      FieldSpec('company_address', 'العنوان', initial: cur['company_address']?.toString(), required: false),
      FieldSpec('company_phone', 'التليفونات', initial: cur['company_phone']?.toString(), required: false),
      FieldSpec('company_tax_no', 'الرقم الضريبي', initial: cur['company_tax_no']?.toString(), required: false),
      FieldSpec('company_commercial_reg', 'السجل التجاري', initial: cur['company_commercial_reg']?.toString(), required: false),
      FieldSpec('invoice_footer', 'نص أسفل الفاتورة', initial: cur['invoice_footer']?.toString(), required: false),
      FieldSpec('company_activity_code', 'كود النشاط (فاتورة إلكترونية)', initial: cur['company_activity_code']?.toString(), required: false),
      FieldSpec('company_branch_id', 'كود الفرع (فاتورة إلكترونية)', initial: cur['company_branch_id']?.toString(), required: false),
      FieldSpec('company_governate', 'المحافظة', initial: cur['company_governate']?.toString(), required: false),
      FieldSpec('company_city', 'المدينة / المركز', initial: cur['company_city']?.toString(), required: false),
      FieldSpec('company_street', 'الشارع', initial: cur['company_street']?.toString(), required: false),
      FieldSpec('company_building', 'رقم المبنى', initial: cur['company_building']?.toString(), required: false),
      FieldSpec('approval_reverse_min', 'إلغاء فاتورة/سند يحتاج موافقة المالك من مبلغ (0 = بدون)', type: 'number', initial: cur['approval_reverse_min']?.toString() ?? '0', required: false),
      FieldSpec('approval_return_min', 'مرتجع يحتاج موافقة المالك من مبلغ (0 = بدون)', type: 'number', initial: cur['approval_return_min']?.toString() ?? '0', required: false),
      FieldSpec('approval_max_discount_pct', 'أقصى خصم % للمحاسب بدون موافقة (فارغ = بدون حد)', type: 'number', initial: cur['approval_max_discount_pct']?.toString(), required: false),
      FieldSpec('allow_negative_cash', 'السماح برصيد خزينة سالب', type: 'picker', initial: cur['allow_negative_cash'] == '1' ? '1' : '0', options: const [
        {'value': '0', 'label': 'لا (موصى به)'},
        {'value': '1', 'label': 'نعم'},
      ]),
    ]);
    if (v == null) return;
    try {
      await s.api.put('/settings', v);
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      const PageHeader('الإعدادات'),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/settings'),
          builder: (context, data, reload) {
            final cur = Map<String, dynamic>.from(data as Map);
            Widget row(String a, dynamic b) => ListTile(dense: true, title: Text(a), trailing: Text(b?.toString() ?? '-'));
            return ListView(children: [
              row('المستخدم', s.user?['name']),
              row('الدور', (s.user?['roles'] as List?)?.join('، ')),
              row('السيرفر', s.serverUrl),
              const Divider(),
              row('اسم المصنع', cur['company_name']),
              row('العنوان', cur['company_address']),
              row('التليفونات', cur['company_phone']),
              row('الرقم الضريبي', cur['company_tax_no']),
              row('السجل التجاري', cur['company_commercial_reg']),
              row('نص أسفل الفاتورة', cur['invoice_footer']),
              row('كود النشاط / الفرع', '${cur['company_activity_code'] ?? '-'} / ${cur['company_branch_id'] ?? '-'}'),
              row('العنوان الإلكتروني', '${cur['company_governate'] ?? ''} ${cur['company_city'] ?? ''} ${cur['company_street'] ?? ''} ${cur['company_building'] ?? ''}'),
              row('السماح برصيد خزينة سالب', cur['allow_negative_cash'] == '1' ? 'نعم' : 'لا'),
              row('حد الموافقة: إلغاء / مرتجع', '${cur['approval_reverse_min'] ?? '-'} / ${cur['approval_return_min'] ?? '-'}'),
              row('أقصى خصم بدون موافقة', cur['approval_max_discount_pct'] == null || cur['approval_max_discount_pct'] == '' ? 'بدون حد' : '${cur['approval_max_discount_pct']}%'),
              if (s.can('users.manage') || s.can('settings.manage')) const Divider(),
              if (s.can('users.manage')) ListTile(leading: const Icon(Icons.manage_accounts), title: const Text('إدارة المستخدمين'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen()))),
              if (s.can('settings.manage')) ListTile(leading: const Icon(Icons.history), title: const Text('سجل المراجعة'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditScreen()))),
              if (s.can('settings.manage')) ListTile(leading: const Icon(Icons.backup), title: const Text('النسخ الاحتياطي'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))),
              if (s.can('settings.manage')) ListTile(leading: const Icon(Icons.receipt_long), title: const Text('أكواد الوحدات للفاتورة الإلكترونية'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UnitsEtaScreen()))),
              if (s.can('settings.manage'))
                Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () => _edit(cur), icon: const Icon(Icons.edit), label: const Text('تعديل بيانات المصنع')))),
              if (!s.can('settings.manage')) const Padding(padding: EdgeInsets.all(16), child: Text('تعديل بيانات المصنع من صلاحية صاحب المصنع.', style: TextStyle(color: Colors.grey))),
            ]);
          },
        ),
      ),
    ]);
  }
}
