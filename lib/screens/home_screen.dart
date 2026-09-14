import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import 'customer_details_screen.dart';
import 'categories_screen.dart';
import 'currencies_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String searchQuery = '';
  int? selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context);

    List<Map<String, dynamic>> filteredCustomers = provider.customers.where((c) {
      final String name = (c['name'] ?? '').toString();
      final String phone = (c['phone'] ?? '').toString();
      
      final matchesSearch = name.contains(searchQuery) || phone.contains(searchQuery);
      final matchesCategory = selectedCategoryId == null || c['category_id'] == selectedCategoryId;
      return matchesSearch && matchesCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر المحاسب الشامل'),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Center(child: Text('تطبيق المحاسب', style: TextStyle(color: Colors.white, fontSize: 22))),
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('إدارة التصنيفات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.attach_money),
              title: const Text('إدارة العملات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CurrenciesScreen())),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'بحث عن حساب...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => searchQuery = val),
            ),
          ),
          Expanded(
            child: filteredCustomers.isEmpty
                ? const Center(child: Text('لا توجد حسابات مطابقة'))
                : ListView.builder(
                    itemCount: filteredCustomers.length,
                    itemBuilder: (ctx, i) {
                      final customer = filteredCustomers[i];
                      final String custName = (customer['name'] ?? 'حساب').toString();
                      final String firstLetter = custName.isNotEmpty ? custName[0] : '?';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(firstLetter)),
                          title: Text(custName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('العملة: ${customer['currency']} | ${customer['phone'] ?? ''}'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerDetailsScreen(customer: customer),
                              ),
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            onPressed: () => provider.deleteCustomer(customer['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCustomerDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedCurrency = provider.currencies.isNotEmpty ? provider.currencies.first['name'].toString() : 'ريال يمني';
    int selectedCat = provider.categories.isNotEmpty ? provider.categories.first['id'] as int : 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة حساب جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الحساب/العميل')),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: provider.currencies.map((c) {
                    final String cName = c['name'].toString();
                    return DropdownMenuItem<String>(
                      value: cName,
                      child: Text(cName),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedCurrency = val);
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  value: selectedCat,
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: provider.categories.map((c) {
                    return DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name'].toString()),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedCat = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  provider.addCustomer(nameCtrl.text.trim(), phoneCtrl.text.trim(), selectedCurrency, selectedCat);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
