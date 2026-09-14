import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/account_provider.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        Provider.of<AccountProvider>(context, listen: false).loadTransactions(widget.customer['id']));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context);
    final transactions = provider.currentTransactions;
    final balance = provider.getCustomerBalance(transactions);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer['name']),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _sendWhatsApp(widget.customer['phone'], balance),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الرصيد الإجمالي:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  '${balance.abs()} ${widget.customer['currency']} (${balance >= 0 ? "له" : "عليه"})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: balance >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: transactions.isEmpty
                ? const Center(child: Text('لا توجد عمليات مسجلة'))
                : ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (ctx, i) {
                      final tx = transactions[i];
                      final isGive = tx['type'] == 'give';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isGive ? Colors.green.shade100 : Colors.red.shade100,
                            child: Icon(
                              isGive ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isGive ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text('${tx['amount']} ${widget.customer['currency']}'),
                          subtitle: Text('${tx['details'] ?? ''}\n${tx['date']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey),
                            onPressed: () => provider.deleteTransaction(tx['id'], widget.customer['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('له (قبض)', style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: () => _showAddTransactionDialog(context, 'give'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.remove, color: Colors.white),
                    label: const Text('عليه (دفع)', style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: () => _showAddTransactionDialog(context, 'take'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context, String type) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'give' ? 'إضافة مبلغ (له)' : 'إضافة مبلغ (عليه)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
            TextField(controller: detailsCtrl, decoration: const InputDecoration(labelText: 'التفاصيل / البيان')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text);
              if (amount != null) {
                final dateStr = DateTime.now().toString().split('.')[0];
                Provider.of<AccountProvider>(context, listen: false).addTransaction(
                  widget.customer['id'],
                  amount,
                  type,
                  detailsCtrl.text,
                  dateStr,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendWhatsApp(String? phone, double balance) async {
    if (phone == null || phone.isEmpty) return;
    String status = balance >= 0 ? "لك في حسابنا" : "عليكم لحسابنا";
    String message = "كشف حساب من تطبيق المحاسب:\n"
        "العميل: ${widget.customer['name']}\n"
        "المبلغ الحالي: ${balance.abs()} ${widget.customer['currency']} ($status)";
    final Uri url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
