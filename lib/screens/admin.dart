import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const Map<String, String> _roleLabels = {'owner': 'صاحب المصنع', 'accountant': 'محاسب'};

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _tick = 0;

  List<Json> get _roles => [for (final e in _roleLabels.entries) <String, dynamic>{'value': e.key, 'label': e.value}];

  Future<void> _add() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'مستخدم جديد', [
      const FieldSpec('name', 'الاسم'),
      const FieldSpec('email', 'البريد الإلكتروني'),
      const FieldSpec('password', 'كلمة المرور (8 أحرف على الأقل)'),
      FieldSpec('role', 'الدور', type: 'picker', options: _roles, initial: 'accountant'),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/users', v);
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(Json u) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'تعديل ${u['name']}', [
      FieldSpec('name', 'الاسم', initial: u['name']?.toString()),
      FieldSpec('role', 'الدور', type: 'picker', options: _roles, initial: u['role']?.toString()),
      FieldSpec('is_active', 'الحالة', type: 'picker', initial: u['is_active'] == true ? '1' : '0', options: const [
        {'value': '1', 'label': 'مفعّل'}, {'value': '0', 'label': 'موقوف (يخرج من كل الأجهزة)'},
      ]),
      const FieldSpec('password', 'كلمة مرور جديدة (اتركها فارغة لو لا تغيير)', required: false),
    ]);
    if (v == null) return;
    try {
      await s.api.put('/users/${u['id']}', {'name': v['name'], 'role': v['role'], 'is_active': v['is_active'] == '1', if ((v['password'] ?? '').isNotEmpty) 'password': v['password']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('مستخدم جديد')),
      body: Loader(
        key: ValueKey(_tick),
        load: () => s.api.get('/users'),
        builder: (context, data, reload) {
          final rows = asList(data);
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = rows[i];
              return ListTile(
                leading: Icon(u['is_active'] == true ? Icons.person : Icons.person_off),
                title: Text(u['name'].toString()),
                subtitle: Text('${u['email']}  •  ${_roleLabels[u['role']] ?? u['role']}'),
                trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(u)),
              );
            },
          );
        },
      ),
    );
  }
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _q = '';
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المراجعة (من فعل ماذا ومتى)')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بنوع العملية (مثال: invoice أو payment أو period)'),
            onSubmitted: (v) => setState(() {
              _q = v;
              _tick++;
            }),
          ),
        ),
        Expanded(
          child: Loader(
            key: ValueKey('$_q$_tick'),
            load: () => s.api.get('/audit-logs', query: {'action': _q}),
            builder: (context, data, reload) {
              final rows = asList(data);
              if (rows.isEmpty) return const EmptyState('لا توجد سجلات.');
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return ListTile(
                    dense: true,
                    title: Text('${r['action']}   ${r['subject_type'] ?? ''} ${r['subject_id'] ?? ''}'),
                    subtitle: Text('${r['user_name'] ?? '-'}   |   ${r['created_at']}${r['details'] != null ? '\n${r['details']}' : ''}'),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  int _tick = 0;
  bool _busy = false;

  Future<void> _run() async {
    final s = context.read<Session>();
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/backups') as Map;
      if (mounted) {
        toast(context, 'تم إنشاء النسخة ${r['file']}');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(String name) async {
    final s = context.read<Session>();
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/backups/$name/verify') as Map;
      if (!mounted) return;
      final checks = asList(r['checks']);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(r['ok'] == true ? 'النسخة سليمة وقابلة للاستعادة ✔' : 'النسخة بها مشاكل ✘ — لا تعتمد عليها'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in checks) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${c['ok'] == true ? '✔' : '✘'} ${c['name']}${(c['detail'] ?? '').toString().isEmpty || c['ok'] == true ? '' : ' — ${c['detail']}'}')),
          ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(String name) async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/backups/$name/url');
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _busy ? null : _run, icon: const Icon(Icons.backup), label: Text(_busy ? 'جارٍ النسخ...' : 'نسخة الآن')),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('النسخ التلقائي يومي الساعة 11:30 مساءً بشرط تشغيل المجدول على السيرفر (php artisan schedule:run). يُحتفظ بآخر 30 نسخة. احفظ نسخة خارج السيرفر بانتظام.'),
        ),
        Expanded(
          child: Loader(
            key: ValueKey(_tick),
            load: () => s.api.get('/backups'),
            builder: (context, data, reload) {
              final rows = asList(data);
              if (rows.isEmpty) return const EmptyState('لا توجد نسخ بعد.');
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.storage),
                  title: Text(rows[i]['name'].toString()),
                  subtitle: Text('${rows[i]['at']}   •   ${(toD(rows[i]['size']) / 1024).toStringAsFixed(0)} KB'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'فحص الاستعادة (يستعيدها في قاعدة مؤقتة ويتحقق)', icon: const Icon(Icons.verified_outlined), onPressed: _busy ? null : () => _verify(rows[i]['name'].toString())),
                    IconButton(tooltip: 'تنزيل', icon: const Icon(Icons.download), onPressed: () => _download(rows[i]['name'].toString())),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// أكواد الوحدات للفاتورة الإلكترونية (MTR, EA, KGM ...)
class UnitsEtaScreen extends StatefulWidget {
  const UnitsEtaScreen({super.key});

  @override
  State<UnitsEtaScreen> createState() => _UnitsEtaScreenState();
}

class _UnitsEtaScreenState extends State<UnitsEtaScreen> {
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('أكواد الوحدات للفاتورة الإلكترونية')),
      body: Loader(
        key: ValueKey(_tick),
        load: () async => (await s.meta(refresh: true))['units'],
        builder: (context, data, reload) {
          final rows = asList(data);
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = rows[i];
              return ListTile(
                title: Text(u['name'].toString()),
                subtitle: const Text('راجع الكود الصحيح لكل وحدة مع محاسب الضرائب / قائمة أكواد المصلحة'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(u['eta_code']?.toString() ?? '— غير محدد —'),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final v = await showForm(context, 'كود ${u['name']}', [FieldSpec('eta_code', 'الكود (مثال: MTR)', initial: u['eta_code']?.toString())]);
                      if (v == null) return;
                      try {
                        await s.api.put('/units/${u['id']}', {'eta_code': v['eta_code']});
                        if (mounted) setState(() => _tick++);
                      } catch (e) {
                        if (mounted) toast(context, e.toString(), error: true);
                      }
                    },
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
