import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const _payTypes = {'monthly': 'مرتب شهري', 'daily': 'أجر يومي', 'piece': 'بالقطعة'};

/// الموظفون والعمال: نوع المحاسبة (شهري/يومي/بالقطعة) والمرتب وقسط السلفة، وإدارة عمليات القطعة وأسعارها.
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  int _tick = 0;

  Future<void> _edit([Json? e]) async {
    final s = context.read<Session>();
    final v = await showForm(context, e == null ? 'إضافة موظف / عامل' : 'تعديل ${e['name']}', [
      FieldSpec('name', 'الاسم', initial: e?['name']?.toString()),
      FieldSpec('job_title', 'الوظيفة (مثال: خياطة، قص)', required: false, initial: e?['job_title']?.toString()),
      FieldSpec('phone', 'التليفون', required: false, initial: e?['phone']?.toString()),
      FieldSpec('pay_type', 'نظام المحاسبة', type: 'picker', initial: e?['pay_type']?.toString() ?? 'piece',
          options: _payTypes.entries.map((x) => <String, dynamic>{'value': x.key, 'label': x.value}).toList()),
      FieldSpec('monthly_salary', 'المرتب الشهري (للشهري فقط)', type: 'number', required: false, initial: e == null ? null : fmtCell(e['monthly_salary'])),
      FieldSpec('daily_wage', 'الأجر اليومي (لليومي فقط)', type: 'number', required: false, initial: e == null ? null : fmtCell(e['daily_wage'])),
      FieldSpec('hire_date', 'تاريخ التعيين', type: 'date', required: false, initial: e?['hire_date']?.toString().substring(0, 10)),
      if (e != null)
        FieldSpec('is_active', 'الحالة', type: 'picker', initial: (e['is_active'] == true) ? '1' : '0', options: const [
          {'value': '1', 'label': 'يعمل'},
          {'value': '0', 'label': 'متوقف'},
        ]),
    ]);
    if (v == null) return;
    try {
      final body = <String, dynamic>{
        'name': v['name'], 'job_title': v['job_title'], 'phone': v['phone'], 'pay_type': v['pay_type'],
        'monthly_salary': (v['monthly_salary'] ?? '').isEmpty ? 0 : v['monthly_salary'], 'daily_wage': (v['daily_wage'] ?? '').isEmpty ? 0 : v['daily_wage'],
        'advance_installment': e == null ? 0 : (e['advance_installment'] ?? 0), 'hire_date': (v['hire_date'] ?? '').isEmpty ? null : v['hire_date'],
        'is_active': e == null ? true : v['is_active'] == '1',
      };
      if (e == null) {
        await s.api.post('/employees', body);
      } else {
        await s.api.put('/employees/${e['id']}', body);
      }
      if (mounted) setState(() => _tick++);
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  Future<void> _credentials(Json e) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'بيانات البصمة — ${e['name']}', [
      FieldSpec('badge_code', 'رقم الكارت / الباركود (اتركه فارغًا لاستخدام ${e['code']})', required: false, initial: e['badge_code']?.toString()),
      FieldSpec('pin', e['has_pin'] == true ? 'رقم سري جديد (اتركه فارغًا للإبقاء على الحالي)' : 'الرقم السري (4 إلى 8 أرقام)', required: e['has_pin'] != true),
    ]);
    if (v == null) return;
    try {
      await s.api.put('/employees/${e['id']}/credentials', {'badge_code': v['badge_code'], 'pin': v['pin']});
      if (mounted) {
        toast(context, 'تم حفظ بيانات البصمة.');
        setState(() => _tick++);
      }
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  Future<void> _operations() async {
    final s = context.read<Session>();
    try {
      var ops = asList(await s.api.get('/piece-operations'));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('عمليات القطعة وأسعارها'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('السعر الجديد يسري على الإدخالات القادمة فقط؛ ما سُجّل قبل التعديل يبقى بسعره.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  for (final o in ops)
                    ListTile(
                      dense: true,
                      title: Text('${o['name']}${o['is_active'] == false ? '  (موقوفة)' : ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(fmtCell(o['rate']), style: const TextStyle(fontWeight: FontWeight.w800)),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () async {
                            final v = await showForm(ctx, 'تعديل ${o['name']}', [
                              FieldSpec('name', 'اسم العملية', initial: o['name']?.toString()),
                              FieldSpec('rate', 'أجر القطعة', type: 'number', initial: fmtCell(o['rate'])),
                              FieldSpec('is_active', 'الحالة', type: 'picker', initial: o['is_active'] == false ? '0' : '1', options: const [
                                {'value': '1', 'label': 'مفعّلة'},
                                {'value': '0', 'label': 'موقوفة'},
                              ]),
                            ]);
                            if (v == null) return;
                            try {
                              await s.api.put('/piece-operations/${o['id']}', {'name': v['name'], 'rate': v['rate'], 'is_active': v['is_active'] == '1'});
                              ops = asList(await s.api.get('/piece-operations'));
                              setS(() {});
                            } catch (err) {
                              if (ctx.mounted) toast(ctx, err.toString(), error: true);
                            }
                          },
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final v = await showForm(ctx, 'عملية جديدة', [const FieldSpec('name', 'اسم العملية (مثال: تركيب جيب)'), const FieldSpec('rate', 'أجر القطعة', type: 'number')]);
                  if (v == null) return;
                  try {
                    await s.api.post('/piece-operations', {'name': v['name'], 'rate': v['rate']});
                    ops = asList(await s.api.get('/piece-operations'));
                    setS(() {});
                  } catch (err) {
                    if (ctx.mounted) toast(ctx, err.toString(), error: true);
                  }
                },
                child: const Text('إضافة عملية'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            ],
          ),
        ),
      );
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final manage = s.can('payroll.manage');
    return Column(children: [
      PageHeader('الموظفون والعمال', subtitle: 'نظام المحاسبة والمرتبات وأسعار عمليات القطعة', actions: [
        if (manage) OutlinedButton.icon(onPressed: _operations, icon: const Icon(Icons.content_cut), label: const Text('عمليات القطعة وأسعارها')),
        if (manage) FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt), label: const Text('إضافة')),
        IconButton(onPressed: () => setState(() => _tick++), icon: const Icon(Icons.refresh)),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey(_tick),
          load: () => s.api.get('/employees'),
          builder: (context, data, reload) {
            final rows = asList(data);
            if (rows.isEmpty) return const EmptyState('لا يوجد موظفون بعد');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = rows[i];
                final pt = e['pay_type'].toString();
                final amount = pt == 'monthly' ? '${fmtCell(e['monthly_salary'])} / شهر' : (pt == 'daily' ? '${fmtCell(e['daily_wage'])} / يوم' : 'بالقطعة');
                final adv = double.tryParse('${e['advance_balance']}') ?? 0;
                return Card(
                  child: ListTile(
                    onTap: manage ? () => _edit(e) : null,
                    title: Text('${e['name']}   ${e['code']}${e['is_active'] == false ? '   (متوقف)' : ''}'),
                    subtitle: Text('${e['job_title'] ?? ''}${(e['job_title'] ?? '').toString().isEmpty ? '' : '  •  '}${_payTypes[pt]}  •  $amount'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (adv > 0) Pill('سلفة ${fmtCell(e['advance_balance'])}', color: Colors.orange.shade800),
                      if (manage) IconButton(icon: Icon(Icons.fingerprint, color: e['has_pin'] == true ? Colors.green.shade700 : Colors.grey), tooltip: e['has_pin'] == true ? 'بيانات البصمة (مُفعَّلة)' : 'تفعيل البصمة', onPressed: () => _credentials(e)),
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
