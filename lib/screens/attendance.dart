import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

const _statuses = {'present': 'حاضر', 'absent': 'غائب', 'half': 'نصف يوم', 'paid_leave': 'إجازة بأجر', 'unpaid_leave': 'إجازة بدون أجر'};

/// الحضور والانصراف اليومي: يُستخدم لخصم الغياب وحساب الإضافي للمرتب الشهري والأجر اليومي.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _date = TextEditingController(text: today());
  int _tick = 0;
  final Map<int, String> _st = {};
  final Map<int, TextEditingController> _ot = {};
  bool _saving = false;
  List<Json> _rows = [];

  @override
  void dispose() {
    _date.dispose();
    for (final c in _ot.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(_date.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d != null) {
      setState(() {
        _date.text = d.toIso8601String().substring(0, 10);
        _st.clear();
        _tick++;
      });
    }
  }

  Future<void> _times(Json e) async {
    final s = context.read<Session>();
    final v = await showForm(context, 'حضور وانصراف ${e['name']}', [
      FieldSpec('check_in', 'وقت الحضور (مثال 08:30)', initial: e['check_in']?.toString()),
      FieldSpec('check_out', 'وقت الانصراف (اتركه فارغًا لو لم ينصرف)', required: false, initial: e['check_out']?.toString()),
      FieldSpec('note', 'ملاحظة', required: false),
    ]);
    if (v == null) return;
    try {
      await s.api.post('/attendance/times', {'employee_id': e['id'], 'date': _date.text, 'check_in': v['check_in'], if ((v['check_out'] ?? '').isNotEmpty) 'check_out': v['check_out'], 'note': v['note']});
      if (mounted) {
        toast(context, 'تم التسجيل وحُسب التأخير والإضافي تلقائيًا.');
        setState(() {
          _st.remove(e['id']);
          _tick++;
        });
      }
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  Future<void> _closeDay() async {
    final s = context.read<Session>();
    if (!await confirm(context, 'تسجيل غياب كل من لم يسجَّل له حضور يوم ${_date.text} (عدا عمال القطعة)؟')) return;
    try {
      final r = await s.api.post('/attendance/close-day', {'date': _date.text}) as Map;
      if (mounted) {
        toast(context, 'تم تسجيل غياب ${r['absent']} موظف.');
        setState(() {
          _st.clear();
          _tick++;
        });
      }
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  Future<void> _settings() async {
    final s = context.read<Session>();
    try {
      final c = await s.api.get('/attendance-settings') as Map;
      if (!mounted) return;
      final v = await showForm(context, 'إعدادات الحضور (وردية واحدة)', [
        FieldSpec('shift_start', 'بداية الوردية (HH:MM)', initial: '${c['shift_start']}'),
        FieldSpec('shift_end', 'نهاية الوردية (HH:MM)', initial: '${c['shift_end']}'),
        FieldSpec('grace_minutes', 'فترة السماح بالتأخير (دقيقة)', type: 'number', initial: '${c['grace_minutes']}'),
        FieldSpec('ot_min_minutes', 'يبدأ الإضافي بعد نهاية الوردية بـ (دقيقة)', type: 'number', initial: '${c['ot_min_minutes']}'),
        FieldSpec('half_day_minutes', 'أقل مدة تُحسب يوم كامل (دقيقة)', type: 'number', initial: '${c['half_day_minutes']}'),
        FieldSpec('late_per_penalty', 'كل كم مرة تأخير تُخصم؟ (0 = بدون خصم)', type: 'number', initial: '${c['late_per_penalty']}'),
        FieldSpec('late_penalty_days', 'المخصوم (بالأيام) كل مرة تتحقق القاعدة', type: 'number', initial: '${c['late_penalty_days']}'),
        FieldSpec('annual_leave_days', 'رصيد الإجازة الاعتيادية السنوي (يوم)', type: 'number', initial: '${c['annual_leave_days']}'),
        FieldSpec('weekly_off', 'الإجازة الأسبوعية (0=الأحد … 5=الجمعة، 6=السبت، افصل بفاصلة)', initial: (c['weekly_off'] as List).join(',')),
      ]);
      if (v == null) return;
      await s.api.put('/attendance-settings', {
        'shift_start': v['shift_start'], 'shift_end': v['shift_end'], 'grace_minutes': int.parse(v['grace_minutes']!), 'ot_min_minutes': int.parse(v['ot_min_minutes']!),
        'half_day_minutes': int.parse(v['half_day_minutes']!), 'late_per_penalty': int.parse(v['late_per_penalty']!), 'late_penalty_days': v['late_penalty_days'],
        'annual_leave_days': int.parse(v['annual_leave_days']!), 'weekly_off': v['weekly_off'],
      });
      if (mounted) toast(context, 'تم حفظ الإعدادات.');
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  Future<void> _save() async {
    final s = context.read<Session>();
    final rows = <Map<String, dynamic>>[];
    for (final e in _rows) {
      final id = e['id'] as int;
      final st = _st[id];
      if (st == null) continue;
      rows.add({'employee_id': id, 'status': st, 'overtime_hours': (_ot[id]?.text.trim().isEmpty ?? true) ? 0 : _ot[id]!.text.trim()});
    }
    if (rows.isEmpty) return toast(context, 'لم تحدد حالة أي موظف.', error: true);
    setState(() => _saving = true);
    try {
      final r = await s.api.post('/attendance', {'date': _date.text, 'rows': rows}) as Map;
      if (mounted) toast(context, 'تم حفظ حضور ${r['saved']} موظف.');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final manage = s.can('payroll.manage');
    return Column(children: [
      PageHeader('الحضور اليومي', subtitle: 'اختر اليوم ثم حدّد حالة كل موظف واحفظ', actions: [
        SizedBox(width: 160, child: TextField(controller: _date, readOnly: true, onTap: _pick, decoration: const InputDecoration(labelText: 'التاريخ', suffixIcon: Icon(Icons.calendar_today, size: 18)))),
        if (manage)
          OutlinedButton.icon(
            onPressed: () => setState(() {
              for (final e in _rows) {
                if (e['pay_type'] != 'piece') _st[e['id'] as int] = 'present';
              }
            }),
            icon: const Icon(Icons.done_all),
            label: const Text('حضور الكل'),
          ),
        if (manage) OutlinedButton.icon(onPressed: _closeDay, icon: const Icon(Icons.event_busy), label: const Text('إغلاق اليوم (غياب من لم يحضر)')),
        if (s.can('payroll.approve')) IconButton(onPressed: _settings, tooltip: 'إعدادات الوردية والتأخير', icon: const Icon(Icons.settings_outlined)),
        if (manage) FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_tick${_date.text}'),
          load: () => s.api.get('/attendance', query: {'date': _date.text}),
          builder: (context, data, reload) {
            _rows = asList(data);
            for (final e in _rows) {
              final id = e['id'] as int;
              if (e['status'] != null && !_st.containsKey(id)) _st[id] = e['status'].toString();
              _ot.putIfAbsent(id, () => TextEditingController(text: (double.tryParse('${e['overtime_hours']}') ?? 0) > 0 ? fmtCell(e['overtime_hours']) : ''));
            }
            if (_rows.isEmpty) return const EmptyState('لا يوجد موظفون');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final e = _rows[i];
                final id = e['id'] as int;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(children: [
                      Expanded(
                        flex: 3,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (e['check_in'] != null)
                            Text('حضور ${e['check_in']}${e['check_out'] == null ? '' : '  •  انصراف ${e['check_out']}'}${(e['late_minutes'] ?? 0) > 0 ? '  •  تأخير ${e['late_minutes']} د' : ''}', style: TextStyle(fontSize: 11.5, color: (e['late_minutes'] ?? 0) > 0 ? Colors.red.shade700 : AppColors.muted)),
                        ]),
                      ),
                      Expanded(
                        flex: 4,
                        child: Wrap(spacing: 6, children: [
                          for (final x in _statuses.entries)
                            ChoiceChip(label: Text(x.value), selected: _st[id] == x.key, onSelected: manage ? (_) => setState(() => _st[id] = x.key) : null),
                        ]),
                      ),
                      if (manage) IconButton(icon: const Icon(Icons.schedule, size: 20), tooltip: 'تسجيل بالأوقات', onPressed: () => _times(e)),
                      SizedBox(width: 110, child: TextField(controller: _ot[id], enabled: manage, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'ساعات إضافي'))),
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
