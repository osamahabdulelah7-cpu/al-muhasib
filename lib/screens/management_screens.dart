part of '../main.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('إدارة التصنيفات'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: provider.categories.isEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة أول تصنيف'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: provider.categories.length,
              itemBuilder: (ctx, i) {
                final cat = provider.categories[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onLongPress: () =>
                        _showOptionsSheet(context, provider, cat),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.folder,
                            color: AppColors.primary),
                      ),
                      title: Text(cat['name'].toString(),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddDialog(context),
          child: const Icon(Icons.add, size: 30)),
    );
  }

  void _showOptionsSheet(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> cat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.primary),
            title: const Text('تعديل الاسم'),
            onTap: () {
              Navigator.pop(ctx);
              _showEditDialog(context, provider, cat);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert, color: AppColors.goldDark),
            title: const Text('إعادة الترتيب'),
            onTap: () {
              Navigator.pop(ctx);
              _showReorderDialog(context, provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.red),
            title: const Text('حذف'),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context, provider, cat);
            },
          ),
        ]),
      ),
    );
  }

  void _showEditDialog(BuildContext context, AppAccountProvider provider,
      Map<String, dynamic> cat) {
    final controller = TextEditingController(text: cat['name'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('تعديل التصنيف'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                provider.updateCategory(int.parse(cat['id'].toString()),
                    controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showReorderDialog(BuildContext context, AppAccountProvider provider) {
    List<Map<String, dynamic>> tempCats = List.from(provider.categories);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Text('إعادة الترتيب'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ReorderableListView.builder(
              itemCount: tempCats.length,
              onReorder: (oldIndex, newIndex) {
                setStateDialog(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = tempCats.removeAt(oldIndex);
                  tempCats.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final cat = tempCats[index];
                return Card(
                  key: ValueKey(cat['id']),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: Text(cat['name'].toString()),
                    trailing: Text('${index + 1}'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              onPressed: () {
                provider.reorderCategories(
                    tempCats.map((c) => int.parse(c['id'].toString())).toList());
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> cat) async {
    final int catId = int.parse(cat['id'].toString());
    final int count = await provider.countCustomersInCategory(catId);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('تأكيد الحذف'),
        content: Text(count > 0
            ? 'يوجد $count حساب داخل التصنيف. لا يمكن حذف التصنيف حتى لا تضيع الحسابات والمعاملات.'
            : 'هل أنت متأكد من حذف التصنيف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () async {
              if (count > 0) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('لا يمكن حذف تصنيف يحتوي على حسابات. انقل الحسابات أولاً.'),
                  backgroundColor: AppColors.red,
                ));
                return;
              }
              final success = await provider.deleteCategory(catId);
              if (context.mounted) {
                Navigator.pop(ctx);
                if (!success) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('لا يمكن حذف آخر تصنيف في التطبيق'),
                    backgroundColor: AppColors.red,
                  ));
                }
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('إضافة تصنيف جديد'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false)
                    .addCategory(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

// ==================== CurrenciesScreen ====================
class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('إدارة العملات'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: provider.currencies.isEmpty
          ? const Center(child: Text('لا توجد عملات'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: provider.currencies.length,
              itemBuilder: (ctx, i) {
                final curr = provider.currencies[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.attach_money,
                        color: AppColors.goldDark),
                    title: Text(curr['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('الرمز: ${curr['symbol']}'),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddDialog(context),
          child: const Icon(Icons.add, size: 30)),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('إضافة عملة جديدة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم العملة')),
          const SizedBox(height: 10),
          TextField(
              controller: symbolCtrl,
              decoration: const InputDecoration(labelText: 'الرمز')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty &&
                  symbolCtrl.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false)
                    .addCurrency(
                        nameCtrl.text.trim(), symbolCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
