import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

/// شاشة بصمة الحضور (بدون جهاز): الموظف يكتب كوده (أو يمسح كارته بالسكانر) ورقمه السري ثم Enter.
/// أول مرة في اليوم = حضور، والثانية = انصراف.
class PunchPage extends StatefulWidget {
  const PunchPage({super.key});

  @override
  State<PunchPage> createState() => _PunchPageState();
}

class _PunchPageState extends State<PunchPage> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _codeFocus = FocusNode();
  final _pinFocus = FocusNode();
  String? _msg;
  bool _ok = true;
  bool _busy = false;
  int _tick = 0;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    _code.dispose();
    _pin.dispose();
    _codeFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final s = context.read<Session>();
    if (_code.text.trim().isEmpty || _pin.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/attendance/punch', {'code': _code.text.trim(), 'pin': _pin.text.trim()}) as Map;
      _show(r['message'].toString(), true);
    } catch (e) {
      _show(e.toString(), false);
    } finally {
      _code.clear();
      _pin.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _tick++;
        });
        _codeFocus.requestFocus();
      }
    }
  }

  void _show(String m, bool ok) {
    _clear?.cancel();
    setState(() {
      _msg = m;
      _ok = ok;
    });
    _clear = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      const PageHeader('بصمة الحضور', subtitle: 'اكتب الكود أو امسح الكارت، ثم الرقم السري واضغط Enter'),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    TextField(
                      controller: _code,
                      focusNode: _codeFocus,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _pinFocus.requestFocus(),
                      decoration: const InputDecoration(labelText: 'كود الموظف / الكارت', prefixIcon: Icon(Icons.badge_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      focusNode: _pinFocus,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _go(),
                      decoration: const InputDecoration(labelText: 'الرقم السري', prefixIcon: Icon(Icons.lock_outline)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, height: 48, child: FilledButton.icon(onPressed: _busy ? null : _go, icon: const Icon(Icons.fingerprint), label: const Text('تسجيل', style: TextStyle(fontSize: 16)))),
                    if (_msg != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: _ok ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Text(_msg!, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ok ? Colors.green.shade800 : Colors.red.shade800)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('حضور اليوم', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Loader(
            key: ValueKey(_tick),
            load: () => s.api.get('/attendance-today'),
            builder: (context, data, reload) {
              final rows = asList(data);
              return Column(children: [
                for (final e in rows)
                  Card(
                    child: ListTile(
                      dense: true,
                      title: Text('${e['name']}'),
                      subtitle: Text(e['in'] == null ? 'لم يحضر بعد' : 'حضور ${e['in']}${e['out'] == null ? '' : '  •  انصراف ${e['out']}'}${(e['late_minutes'] ?? 0) > 0 ? '  •  متأخر ${e['late_minutes']} د' : ''}'),
                      trailing: e['in'] == null ? null : Pill(e['out'] == null ? 'داخل' : 'انصرف', color: e['out'] == null ? Colors.green.shade700 : Colors.grey),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    ]);
  }
}
