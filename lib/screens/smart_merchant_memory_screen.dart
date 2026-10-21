part of '../main.dart';

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
  List<Map<String, Object?>> _recentTransactions = [];
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
                      const SizedBox(height: 12),
                      const Text('ملاحظة: هذه اقتراحات للمراجعة فقط؛ لا تُعدّل الميزة البيانات ولا تحذف أي عملية تلقائياً.', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
    );
  }
}
