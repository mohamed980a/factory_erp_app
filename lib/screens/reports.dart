import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../core/util.dart';

class _Rep {
  final String id;
  final String title;
  final List<String> params; // range | asof | party | treasury | item
  const _Rep(this.id, this.title, [this.params = const []]);
}

const List<MapEntry<String, List<_Rep>>> _groups = [
  MapEntry('المخزون', [
    _Rep('stock', 'أرصدة المخزون (لتاريخ)', ['asof']),
    _Rep('low-stock', 'أصناف وصلت لحد الطلب'),
    _Rep('stock-matrix', 'المنتجات التامة حسب النوع والمقاس واللون والقماش', ['asof']),
    _Rep('rolls', 'أرصدة رولات القماش'),
    _Rep('stocktake-variance', 'فروق الجرد المرحَّلة', ['range']),
    _Rep('stocktake-reasons', 'أسباب فروق الجرد', ['range']),
    _Rep('abc-analysis', 'تحليل ABC للمخزون'),
    _Rep('dead-stock', 'مخزون راكد (بدون صرف)', ['days']),
    _Rep('qc-claims', 'فحص الجودة: مرفوضات وخصومات', ['range']),
    _Rep('item-card', 'كارت صنف (حركة)', ['item', 'range']),
  ]),
  MapEntry('العملاء والموردون', [
    _Rep('customers', 'أرصدة العملاء (لتاريخ)', ['asof']),
    _Rep('customer-ratings', 'تقييم العملاء بالسداد'),
    _Rep('sales-commission', 'عمولات المناديب', ['range']),
    _Rep('fx-exposure', 'مستحقات الموردين بالعملة الأجنبية (تقييم)', ['asof']),
    _Rep('suppliers', 'أرصدة الموردين (لتاريخ)', ['asof']),
    _Rep('statement', 'كشف حساب (عميل / مورد / الكل)', ['partyopt', 'ptype', 'range']),
    _Rep('aging-customers', 'أعمار ديون العملاء', ['asof']),
    _Rep('aging-suppliers', 'أعمار مستحقات الموردين', ['asof']),
  ]),
  MapEntry('الخزينة', [
    _Rep('treasuries', 'أرصدة الخزائن والبنوك (لتاريخ)', ['asof']),
    _Rep('treasury-statement', 'حركة خزينة', ['treasury', 'range']),
    _Rep('custody', 'أرصدة العهد'),
  ]),
  MapEntry('المبيعات والمشتريات', [
    _Rep('sales-by-customer', 'المبيعات حسب العميل', ['range']),
    _Rep('purchases-by-supplier', 'المشتريات حسب المورد', ['range']),
    _Rep('profit-by-item', 'ربحية الأصناف', ['range']),
    _Rep('budget-vs-actual', 'الموازنة مقابل الفعلي', ['year']),
    _Rep('period-comparison', 'مقارنة فترتين (قائمة الدخل)', ['range', 'range2']),
    _Rep('product-profitability', 'ربحية المنتجات والتكلفة (معيارية/فعلية)', ['range']),
    _Rep('sales-orders', 'أوامر البيع المفتوحة (قبل التسليم)'),
  ]),
  MapEntry('المالية والضريبة', [
    _Rep('vat', 'إقرار ضريبة القيمة المضافة (مسودة)', ['range']),
    _Rep('trial-balance', 'ميزان المراجعة', ['range']),
    _Rep('income', 'قائمة الدخل', ['range']),
    _Rep('balance-sheet', 'الميزانية العمومية', ['asof']),
    _Rep('journal', 'دفتر اليومية (بفلاتر)', ['range', 'partyopt', 'account', 'acctype', 'search']),
    _Rep('period-snapshots', 'لقطات قفل الشهور'),
    _Rep('eta-pending', 'فواتير لم تُقبل إلكترونيًا بعد', ['range']),
  ]),
  MapEntry('التصنيع', [
    _Rep('production', 'ملخص أوامر التصنيع', ['range']),
    _Rep('waste', 'الهالك والبواقي', ['range']),
  ]),
  MapEntry('العمالة والرواتب', [
    _Rep('attendance-month', 'حضور الشهر (يُؤخذ من شهر تاريخ «من»)', ['range']),
    _Rep('attendance-piece', 'الحضور مقابل إنتاج القطعة', ['range']),
    _Rep('piece-work', 'إنتاج العمال بالقطعة', ['range']),
    _Rep('labor-cost-per-piece', 'تكلفة التشغيل الحقيقية لكل قطعة', ['range']),
    _Rep('employee-advances', 'أرصدة سلف الموظفين'),
  ]),
];

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _days = TextEditingController(text: '90');
  _Rep? _sel;
  final _from = TextEditingController(text: DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10));
  final _to = TextEditingController(text: today());
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _m1 = TextEditingController(text: '1');
  final _m2 = TextEditingController(text: '${DateTime.now().month}');
  final _from2 = TextEditingController(text: DateTime(DateTime.now().year, DateTime.now().month - 1, 1).toIso8601String().substring(0, 10));
  final _to2 = TextEditingController(text: DateTime(DateTime.now().year, DateTime.now().month, 0).toIso8601String().substring(0, 10));
  Json? _party;
  Json? _account;
  String _ptype = 'customer';
  String _acctype = '';
  final _search = TextEditingController();
  Json? _treasury;
  Json? _item;
  Future<dynamic>? _result;
  Map<String, dynamic>? _query;

  Future<void> _pickDate(TextEditingController c) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(c.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => c.text = d.toIso8601String().substring(0, 10));
  }

  Widget _dateField(String label, TextEditingController c) => SizedBox(
        width: 150,
        child: TextField(controller: c, readOnly: true, onTap: () => _pickDate(c), decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today, size: 18))),
      );

  Future<void> _run() async {
    final r = _sel!;
    final q = <String, dynamic>{};
    if (r.params.contains('range')) {
      q['from'] = _from.text;
      q['to'] = _to.text;
    }
    if (r.params.contains('asof')) q['as_of'] = _to.text;
    if (r.params.contains('days')) q['days'] = _days.text.trim().isEmpty ? '90' : _days.text.trim();
    if (r.params.contains('range2')) {
      q['from2'] = _from2.text;
      q['to2'] = _to2.text;
    }
    if (r.params.contains('year')) {
      q['year'] = _year.text.trim();
      q['from_month'] = _m1.text.trim();
      q['to_month'] = _m2.text.trim();
    }
    if (r.params.contains('party')) {
      if (_party == null) return toast(context, 'اختر الطرف أولًا.', error: true);
      q['party_id'] = _party!['id'];
    }
    if (r.params.contains('partyopt') && _party != null) q['party_id'] = _party!['id'];
    if (r.params.contains('partyopt') && _party == null && r.params.contains('ptype')) q['type'] = _ptype;
    if (r.params.contains('account') && _account != null) q['account_id'] = _account!['id'];
    if (r.params.contains('acctype') && _acctype.isNotEmpty) q['account_type'] = _acctype;
    if (r.params.contains('search') && _search.text.trim().isNotEmpty) q['q'] = _search.text.trim();
    if (r.params.contains('treasury')) {
      if (_treasury == null) return toast(context, 'اختر الخزينة أولًا.', error: true);
      q['treasury_id'] = _treasury!['id'];
    }
    if (r.params.contains('item')) {
      if (_item == null) return toast(context, 'اختر الصنف أولًا.', error: true);
      q['item_id'] = _item!['id'];
    }
    final s = context.read<Session>();
    setState(() {
      _query = q;
      _result = s.api.get('/reports/${r.id}', query: q);
    });
  }

  Future<void> _csv() async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/reports/${_sel!.id}/csv-url', query: _query);
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _printStatement() async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/parties/${_party!['id']}/statement-print-url', query: {'from': _from.text, 'to': _to.text});
      if (mounted) await openUrl(context, r['url'].toString());
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    final sel = _sel;
    return Row(children: [
      SizedBox(
        width: 270,
        child: ListView(children: [
          for (final g in _groups) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
            for (final r in g.value)
              ListTile(
                dense: true,
                selected: sel?.id == r.id,
                title: Text(r.title),
                onTap: () {
                  setState(() {
                    _sel = r;
                    _result = null;
                  });
                  if (r.params.isEmpty) _run();
                },
              ),
          ],
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: sel == null
            ? const EmptyState('اختر تقريرًا من القائمة', icon: Icons.assessment_outlined)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PageHeader(sel.title, actions: [
                  if (_result != null) OutlinedButton.icon(onPressed: _csv, icon: const Icon(Icons.table_view), label: const Text('تصدير Excel')),
                  if (_result != null && sel.id == 'statement' && _party != null && sel.params.contains('partyopt')) OutlinedButton.icon(onPressed: _printStatement, icon: const Icon(Icons.print), label: const Text('طباعة')),
                ]),
                if (sel.params.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (sel.params.contains('partyopt'))
                        SizedBox(
                          width: 300,
                          child: PickerField(
                            label: sel.id == 'statement' ? 'عميل / مورد (اتركه فارغًا لعرض الكل)' : 'عميل / مورد (اختياري)',
                            valueText: _party?['name']?.toString(),
                            onTap: () async {
                              final list = asList(await s.api.get('/parties'));
                              if (!mounted) return;
                              final p = await pickOne(context, 'اختر الطرف', list, (p) => '${partyTypeLabel(p['type'].toString())}: ${p['name']}');
                              if (p != null) setState(() => _party = p);
                            },
                          ),
                        ),
                      if (sel.params.contains('partyopt') && _party != null) TextButton.icon(onPressed: () => setState(() => _party = null), icon: const Icon(Icons.clear, size: 16), label: const Text('إلغاء تحديد الطرف')),
                      if (sel.params.contains('ptype') && _party == null)
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            value: _ptype,
                            decoration: const InputDecoration(labelText: 'عند عرض الكل'),
                            items: const [DropdownMenuItem(value: 'customer', child: Text('كل العملاء')), DropdownMenuItem(value: 'supplier', child: Text('كل الموردين'))],
                            onChanged: (v) => setState(() => _ptype = v ?? 'customer'),
                          ),
                        ),
                      if (sel.params.contains('account'))
                        SizedBox(
                          width: 280,
                          child: PickerField(
                            label: 'حساب / بند مصروف (اختياري)',
                            valueText: _account == null ? null : '${_account!['code']} ${_account!['name']}',
                            onTap: () async {
                              final list = asList(await s.api.get('/accounts'));
                              if (!mounted) return;
                              final a = await pickOne(context, 'اختر الحساب', list, (a) => '${a['code']}  ${a['name']}');
                              if (a != null) setState(() => _account = a);
                            },
                          ),
                        ),
                      if (sel.params.contains('account') && _account != null) TextButton.icon(onPressed: () => setState(() => _account = null), icon: const Icon(Icons.clear, size: 16), label: const Text('إلغاء الحساب')),
                      if (sel.params.contains('acctype'))
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            value: _acctype,
                            decoration: const InputDecoration(labelText: 'نوع الحساب'),
                            items: const [
                              DropdownMenuItem(value: '', child: Text('الكل')),
                              DropdownMenuItem(value: 'expense', child: Text('مصروفات')),
                              DropdownMenuItem(value: 'revenue', child: Text('إيرادات')),
                              DropdownMenuItem(value: 'asset', child: Text('أصول')),
                              DropdownMenuItem(value: 'liability', child: Text('التزامات')),
                              DropdownMenuItem(value: 'equity', child: Text('حقوق ملكية')),
                            ],
                            onChanged: (v) => setState(() => _acctype = v ?? ''),
                          ),
                        ),
                      if (sel.params.contains('search')) SizedBox(width: 220, child: TextField(controller: _search, decoration: const InputDecoration(labelText: 'بحث في البيان'))),
                      if (sel.params.contains('party'))
                        SizedBox(width: 260, child: PickerField(label: 'العميل / المورد', valueText: _party?['name']?.toString(), onTap: () async {
                          final list = asList(await s.api.get('/parties'));
                          if (!mounted) return;
                          final p = await pickOne(context, 'اختر الطرف', list, (p) => '${partyTypeLabel(p['type'].toString())}: ${p['name']}');
                          if (p != null) setState(() => _party = p);
                        })),
                      if (sel.params.contains('treasury'))
                        SizedBox(width: 220, child: PickerField(label: 'الخزينة', valueText: _treasury?['name']?.toString(), onTap: () async {
                          final list = asList((await s.meta(refresh: true))['treasuries']);
                          if (!mounted) return;
                          final t = await pickOne(context, 'اختر الخزينة', list, (t) => t['name'].toString());
                          if (t != null) setState(() => _treasury = t);
                        })),
                      if (sel.params.contains('item'))
                        SizedBox(width: 300, child: PickerField(label: 'الصنف', valueText: _item?['name']?.toString(), onTap: () async {
                          final list = asList(await s.api.get('/items'));
                          if (!mounted) return;
                          final i = await pickOne(context, 'اختر الصنف', list, (i) => '${i['name']}  (${i['code']})');
                          if (i != null) setState(() => _item = i);
                        })),
                      if (sel.params.contains('days')) SizedBox(width: 160, child: TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'بدون صرف منذ (يوم)'))),
                      if (sel.params.contains('range')) _dateField('من', _from),
                      if (sel.params.contains('range') || sel.params.contains('asof')) _dateField(sel.params.contains('asof') ? 'حتى تاريخ' : 'إلى', _to),
                      if (sel.params.contains('range2')) ...[_dateField('الفترة الثانية من', _from2), _dateField('الفترة الثانية إلى', _to2)],
                      if (sel.params.contains('year')) ...[
                        SizedBox(width: 100, child: TextField(controller: _year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السنة'))),
                        SizedBox(width: 110, child: TextField(controller: _m1, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'من شهر'))),
                        SizedBox(width: 110, child: TextField(controller: _m2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إلى شهر'))),
                      ],
                      FilledButton.icon(onPressed: _run, icon: const Icon(Icons.play_arrow), label: const Text('عرض')),
                    ]),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _result == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: FutureBuilder<dynamic>(
                            future: _result,
                            builder: (c, snap) {
                              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                              if (snap.hasError) return Center(child: Text(snap.error.toString(), style: const TextStyle(color: Colors.red)));
                              return ReportTable(report: Map<String, dynamic>.from(snap.data as Map));
                            },
                          ),
                        ),
                ),
              ]),
      ),
    ]);
  }
}

// ── قفل الشهر ─────────────────────────────────────────────────────────────

class MonthEndPage extends StatefulWidget {
  const MonthEndPage({super.key});

  @override
  State<MonthEndPage> createState() => _MonthEndPageState();
}

class _MonthEndPageState extends State<MonthEndPage> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int _tick = 0;
  bool _busy = false;
  bool _early = false;

  static const Map<String, String> _checkLabels = {
    'integrity_ok': 'فحص سلامة البيانات (مخزون، قيود، أرصدة)',
    'trial_balance_balanced': 'ميزان المراجعة متوازن',
    'balance_sheet_balanced': 'الميزانية متوازنة',
    'no_unposted_stocktake': 'لا يوجد كشف جرد غير مرحَّل',
    'stocktake_done_for_all_warehouses': 'تم جرد كل المخازن التي بها رصيد وترحيله',
    'vat_matches_ledger': 'الضريبة تطابق الأستاذ (تحذير)',
    'no_late_production': 'لا توجد أوامر تصنيع متأخرة (تحذير)',
    'no_open_sales_orders_overdue': 'لا توجد أوامر بيع متأخرة التسليم (تحذير)',
  };

  Future<void> _close() async {
    final s = context.read<Session>();
    if (!await confirm(context, 'قفل شهر $_year-${_month.toString().padLeft(2, '0')}؟\nلن يمكن تسجيل أو تعديل أي حركة بتاريخ داخله إلا بإعادة فتحه بسبب موثّق.')) return;
    setState(() => _busy = true);
    try {
      await s.api.post('/periods/$_year/$_month/close', {'allow_early': _early});
      if (mounted) {
        toast(context, 'تم قفل الشهر.');
        setState(() => _tick++);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final s = context.read<Session>();
    try {
      final r = await s.api.get('/periods/$_year/$_month/verify') as Map<String, dynamic>;
      if (!mounted) return;
      final diff = (r['differences'] as Map?) ?? {};
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(r['matches'] == true && r['checksum_ok'] == true ? 'الأرقام مطابقة للقفل ✔' : 'تنبيه: يوجد اختلاف عن لقطة القفل'),
          content: Text(diff.isEmpty
              ? 'أرصدة المخزون والعملاء والموردين والخزينة حتى نهاية الشهر مطابقة لما وقت القفل.'
              : diff.entries.map((e) => '${e.key}: وقت القفل ${e.value['at_close']} ← الآن ${e.value['now']}').join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _reopen() async {
    final s = context.read<Session>();
    final v = await showForm(context, 'إعادة فتح الشهر', [const FieldSpec('reason', 'سبب إعادة الفتح (يُسجَّل في سجل المراجعة)')]);
    if (v == null) return;
    try {
      await s.api.post('/periods/$_year/$_month/reopen', {'reason': v['reason']});
      if (mounted) setState(() => _tick++);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Widget _tableTile(String title, dynamic report) => ExpansionTile(
        title: Text(title),
        children: [SizedBox(height: 380, child: Padding(padding: const EdgeInsets.all(8), child: ReportTable(report: Map<String, dynamic>.from(report as Map))))],
      );

  @override
  Widget build(BuildContext context) {
    final s = context.read<Session>();
    return Column(children: [
      PageHeader('قفل الشهر', actions: [
        InputDecorator(
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _month,
              isDense: true,
              items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('شهر $m'))],
              onChanged: (v) => setState(() {
                _month = v ?? _month;
                _tick++;
              }),
            ),
          ),
        ),
        InputDecorator(
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _year,
              isDense: true,
              items: [for (var y = DateTime.now().year - 3; y <= DateTime.now().year + 1; y++) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => setState(() {
                _year = v ?? _year;
                _tick++;
              }),
            ),
          ),
        ),
      ]),
      Expanded(
        child: Loader(
          key: ValueKey('$_year-$_month-$_tick'),
          load: () => s.api.get('/month-end', query: {'year': _year, 'month': _month}),
          builder: (context, data, reload) {
            final d = Map<String, dynamic>.from(data as Map);
            final checks = Map<String, dynamic>.from(d['checks'] as Map);
            final ready = d['ready_to_close'] == true;
            final closed = d['status'] == 'closed';
            final integrity = asList(d['integrity']);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                color: closed ? Colors.grey.shade200 : (ready ? Colors.green.shade50 : Colors.red.shade50),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(closed ? 'الشهر مقفول' : (ready ? 'جاهز للقفل' : 'غير جاهز للقفل: راجع البنود الحمراء'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    for (final e in _checkLabels.entries)
                      Row(children: [
                        Icon(checks[e.key] == true ? Icons.check_circle : Icons.error, color: checks[e.key] == true ? Colors.green : Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.value + (d['notes'] is Map && (d['notes'] as Map)[e.key] != null ? ' — ${(d['notes'] as Map)[e.key]}' : ''))),
                      ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      if (!closed && s.can('periods.close'))
                        FilterChip(label: const Text('قفل قبل نهاية الشهر'), selected: _early, onSelected: (v) => setState(() => _early = v)),
                      if (closed) OutlinedButton.icon(onPressed: _verify, icon: const Icon(Icons.verified_outlined), label: const Text('مطابقة لقطة القفل')),
                      if (!closed && s.can('periods.close')) FilledButton.icon(onPressed: (ready && !_busy) ? _close : null, icon: const Icon(Icons.lock), label: const Text('قفل الشهر')),
                      if (closed && s.can('periods.reopen')) OutlinedButton.icon(onPressed: _reopen, icon: const Icon(Icons.lock_open), label: const Text('إعادة فتح الشهر')),
                      if (!closed && !s.can('periods.close')) const Chip(label: Text('القفل من صلاحية صاحب المصنع')),
                      IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text('نتيجة فحص سلامة البيانات'),
                initiallyExpanded: !(checks['integrity_ok'] == true),
                children: [
                  for (final r in integrity)
                    ListTile(
                      dense: true,
                      leading: Icon(r['ok'] == true ? Icons.check_circle : Icons.error, color: r['ok'] == true ? Colors.green : Colors.red),
                      title: Text(r['check'].toString()),
                      subtitle: (r['details'] as List).isEmpty ? null : Text((r['details'] as List).join('\n')),
                    ),
                ],
              ),
              _tableTile('ميزان المراجعة', d['trial_balance']),
              _tableTile('قائمة الدخل', d['income_statement']),
              _tableTile('الميزانية العمومية', d['balance_sheet']),
              _tableTile('ضريبة القيمة المضافة (مسودة)', d['vat']),
              _tableTile('أرصدة المخزون (في نهاية الشهر)', d['stock']),
              _tableTile('المنتجات التامة حسب النوع والمقاس واللون', d['stock_matrix']),
              _tableTile('فروق الجرد', d['stocktakes']),
              _tableTile('أوامر البيع المفتوحة', d['sales_orders']),
              _tableTile('أرصدة العملاء (في نهاية الشهر)', d['customers']),
              _tableTile('أعمار ديون العملاء', d['aging_customers']),
              _tableTile('أعمار مستحقات الموردين', d['aging_suppliers']),
              _tableTile('أرصدة العهد', d['custody']),
              _tableTile('أرصدة الموردين', d['suppliers']),
              _tableTile('أرصدة الخزائن', d['treasuries']),
              _tableTile('ربحية الأصناف', d['sales_profit']),
              _tableTile('أوامر التصنيع', d['production']),
              _tableTile('الهالك والبواقي', d['waste']),
            ]);
          },
        ),
      ),
    ]);
  }
}
