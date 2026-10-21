part of '../main.dart';


/// سجل تدقيق محلي لتغييرات العمليات. لا يخزن صور العمليات ولا كلمات مرور.
class SmartMerchantAuditService {
  static Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS smart_merchant_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        customer_id INTEGER,
        action TEXT NOT NULL,
        before_json TEXT,
        after_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> record({
    required DatabaseExecutor db,
    required String action,
    required int customerId,
    int? transactionId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) async {
    await _ensure(db);
    await db.insert('smart_merchant_audit', {
      'transaction_id': transactionId,
      'customer_id': customerId,
      'action': action,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

/// قراءة محلية فقط: لا تعدّل العمليات أو الأرصدة تلقائياً.
class SmartMerchantMemoryScreen extends StatefulWidget {
  const SmartMerchantMemoryScreen({super.key});

  @override
  State<SmartMerchantMemoryScreen> createState() => _SmartMerchantMemoryScreenState();
}

class _SmartMerchantMemoryScreenState extends State<SmartMerchantMemoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _duplicates = [];
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _recentTransactions = [];  List<Map<String, Object?>> _auditEntries = [];

  int? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = await AppDBHelper.instance.database;
      // Exact amount/type/customer/currency with dates within 48 hours.
      await SmartMerchantAuditService._ensure(db);
      final auditRows = await db.rawQuery('''
        SELECT a.id, a.transaction_id, a.customer_id, a.action,
               a.before_json, a.after_json, a.created_at, c.name AS customer_name
        FROM smart_merchant_audit a
        LEFT JOIN customers c ON c.id = a.customer_id
        ORDER BY datetime(a.created_at) DESC, a.id DESC LIMIT 100
      ''');
      final duplicateRows = await db.rawQuery('''
        SELECT c.name AS customer_name, t.customer_id, t.amount, t.type,
               t.currency, COUNT(*) AS occurrences,
               MIN(t.date) AS first_date, MAX(t.date) AS last_date,
               GROUP_CONCAT(t.id, ', ') AS transaction_ids
        FROM transactions t
        INNER JOIN customers c ON c.id = t.customer_id
        GROUP BY t.customer_id, t.amount, t.type, t.currency,
                 date(t.date), COALESCE(TRIM(t.details), '')
        HAVING COUNT(*) > 1
        ORDER BY MAX(datetime(t.date)) DESC
        LIMIT 100
      ''');
      final customers = await db.rawQuery('''
        SELECT c.id, c.name, c.currency,
               COALESCE(SUM(CASE WHEN t.currency = c.currency
                 THEN CASE WHEN t.type = 'give' THEN t.amount ELSE -t.amount END
                 ELSE 0 END), 0) AS balance,
               COUNT(CASE WHEN t.currency = c.currency THEN t.id END) AS tx_count
        FROM customers c LEFT JOIN transactions t ON t.customer_id = c.id
        GROUP BY c.id ORDER BY c.name COLLATE NOCASE
      ''');
      final recent = await db.rawQuery('''
        SELECT t.id, t.customer_id, c.name AS customer_name, t.amount,
               t.type, t.currency, t.details, t.date
        FROM transactions t INNER JOIN customers c ON c.id = t.customer_id
        ORDER BY datetime(t.date) DESC, t.id DESC LIMIT 300
      ''');
      if (!mounted) return;
      setState(() {
        _duplicates = duplicateRows;
        _auditEntries = auditRows;
        _customers = customers;
        _recentTransactions = recent;
        _selectedCustomerId ??= customers.isEmpty ? null : int.tryParse(customers.first['id'].toString());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'تعذر تحليل البيانات: $e'; _loading = false; });
    }
  }

  String _amount(Object? value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return formatNumber(n.abs());
  }

  String _date(Object? value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _customers.where((c) => int.tryParse(c['id'].toString()) == _selectedCustomerId).toList();
    final tx = _recentTransactions.where((t) => int.tryParse(t['customer_id'].toString()) == _selectedCustomerId).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('ذاكرة التاجر الذكية'),
        actions: [IconButton(onPressed: _loadInsights, icon: const Icon(Icons.refresh), tooltip: 'تحديث التحليل')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _loadInsights,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.manage_search)),
                          title: const Text('مراجعة العمليات المتشابهة', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(_duplicates.isEmpty
                              ? 'لم تُكتشف مجموعات متطابقة حسب الحساب والمبلغ والنوع والتاريخ والتفاصيل.'
                              : 'عُثر على ${_duplicates.length} مجموعة تستحق المراجعة. التشابه لا يعني بالضرورة وجود خطأ.'),
                        ),
                      ),
                      if (_duplicates.isNotEmpty) ...[
                        const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 6), child: Text('عمليات قد تكون مكررة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                        ..._duplicates.map((d) {
                          final give = d['type']?.toString() == 'give';
                          return Card(
                            child: ListTile(
                              leading: Icon(Icons.content_copy, color: Colors.orange.shade800),
                              title: Text(d['customer_name']?.toString() ?? 'حساب غير معروف'),
                              subtitle: Text('${give ? 'له' : 'عليه'} • ${_amount(d['amount'])} ${d['currency'] ?? ''}\nعدد العمليات: ${d['occurrences']} • ${_date(d['first_date'])} — ${_date(d['last_date'])}'),
                              isThreeLine: true,
                              trailing: const Icon(Icons.info_outline),
                              onTap: () => setState(() => _selectedCustomerId = int.tryParse(d['customer_id'].toString())),
                            ),
                          );
                        }),
                      ],
                      const Padding(padding: EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text('تفسير رصيد العميل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                      if (_customers.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حسابات لتحليلها.')))
                      else ...[
                        DropdownButtonFormField<int>(
                          value: _customers.any((c) => int.tryParse(c['id'].toString()) == _selectedCustomerId) ? _selectedCustomerId : null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'اختر الحساب', border: OutlineInputBorder()),
                          items: _customers.map((c) => DropdownMenuItem<int>(
                            value: int.tryParse(c['id'].toString()),
                            child: Text(c['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedCustomerId = v),
                        ),
                        if (selected.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(selected.first['name']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('الرصيد الحالي: ${_amount(selected.first['balance'])} ${selected.first['currency'] ?? ''} ${(selected.first['balance'] as num? ?? 0) >= 0 ? 'له' : 'عليه'}'),
                                Text('عدد العمليات المسجلة: ${selected.first['tx_count'] ?? 0}'),
                                const Divider(),
                                const Text('طريقة الحساب: تُجمع عمليات «له» وتُطرح منها عمليات «عليه»، وتُحسب كل عملة بصورة مستقلة.', style: TextStyle(color: Colors.black54)),
                              ]),
                            ),
                          ),
                          const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 6), child: Text('العمليات التي كوّنت الرصيد', style: TextStyle(fontWeight: FontWeight.bold))),
                          if (tx.isEmpty)
                            const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('لا توجد عمليات لهذا الحساب.')))
                          else
                            ...tx.map((t) {
                              final give = t['type']?.toString() == 'give';
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(give ? Icons.add_circle_outline : Icons.remove_circle_outline, color: give ? Colors.green : Colors.red),
                                  title: Text('${give ? 'له' : 'عليه'}: ${_amount(t['amount'])} ${t['currency'] ?? ''}'),
                                  subtitle: Text('${_date(t['date'])} • ${(t['details']?.toString().trim().isNotEmpty ?? false) ? t['details'] : 'بدون تفاصيل'}'),
                                ),
                              );
                            }),
                        ],
                      ],
                      const Padding(padding: EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text('سجل مراجعة التغييرات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                      Card(
                        child: _auditEntries.isEmpty
                            ? const Padding(padding: EdgeInsets.all(14), child: Text('سيظهر هنا سجل إضافة العمليات وتعديلها وحذفها منذ تفعيل هذه الميزة. لا يتضمن السجل تغييرات قديمة حدثت قبل التفعيل.'))
                            : Column(children: _auditEntries.map((a) {
                                final action = a['action']?.toString() ?? '';
                                final label = action == 'add' ? 'إضافة عملية' : action == 'update' ? 'تعديل عملية' : action == 'delete' ? 'حذف عملية' : action;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(action == 'add' ? Icons.add_circle_outline : action == 'update' ? Icons.edit_outlined : Icons.delete_outline),
                                  title: Text('$label — ${a['customer_name'] ?? 'حساب محذوف'}'),
                                  subtitle: Text('${_date(a['created_at'])} • رقم العملية: ${a['transaction_id'] ?? '—'}'),
                                  onTap: () {
                                    showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: Text('$label — ${a['customer_name'] ?? 'حساب محذوف'}'),
                                        content: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text('قبل التغيير', style: TextStyle(fontWeight: FontWeight.bold)),
                                              SelectableText(a['before_json']?.toString() ?? 'لا توجد بيانات سابقة'),
                                              const SizedBox(height: 12),
                                              const Text('بعد التغيير', style: TextStyle(fontWeight: FontWeight.bold)),
                                              SelectableText(a['after_json']?.toString() ?? 'لا توجد بيانات لاحقة'),
                                              const SizedBox(height: 12),
                                              Text('وقت التسجيل: ${a['created_at'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                                            ],
                                          ),
                                        ),
                                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
                                      ),
                                    );
                                  },
                                );
                              }).toList()),
                      ),
                      const SizedBox(height: 12),
                      const Text('ملاحظة: هذه اقتراحات للمراجعة فقط؛ لا تُعدّل الميزة البيانات ولا تحذف أي عملية تلقائياً.', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
    );
  }
}
