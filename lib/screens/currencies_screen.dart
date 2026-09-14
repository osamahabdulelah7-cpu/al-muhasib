import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';

class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة العملات'),
        centerTitle: true,
      ),
      body: ListView.builder(
        itemCount: provider.currencies.length,
        itemBuilder: (ctx, i) {
          final curr = provider.currencies[i];
          return ListTile(
            title: Text(curr['name']),
            subtitle: Text('الرمز: ${curr['symbol']}'),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة عملة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم العملة')),
            TextField(controller: symbolCtrl, decoration: const InputDecoration(labelText: 'رمز العملة (مثلاً: ر.ي)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && symbolCtrl.text.isNotEmpty) {
                Provider.of<AccountProvider>(context, listen: false).addCurrency(nameCtrl.text, symbolCtrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );
  }
}

