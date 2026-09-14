import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class AccountProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _currentTransactions = [];

  List<Map<String, dynamic>> get customers => _customers;
  List<Map<String, dynamic>> get categories => _categories;
  List<Map<String, dynamic>> get currencies => _currencies;
  List<Map<String, dynamic>> get currentTransactions => _currentTransactions;

  Future<void> loadInitialData() async {
    await loadCategories();
    await loadCurrencies();
    await loadCustomers();
  }

  Future<void> loadCategories() async {
    _categories = await DBHelper.instance.getCategories();
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    await DBHelper.instance.addCategory(name);
    await loadCategories();
  }

  Future<void> deleteCategory(int id) async {
    await DBHelper.instance.deleteCategory(id);
    await loadCategories();
  }

  Future<void> loadCurrencies() async {
    _currencies = await DBHelper.instance.getCurrencies();
    notifyListeners();
  }

  Future<void> addCurrency(String name, String symbol) async {
    await DBHelper.instance.addCurrency(name, symbol);
    await loadCurrencies();
  }

  Future<void> loadCustomers() async {
    _customers = await DBHelper.instance.getCustomers();
    notifyListeners();
  }

  Future<void> addCustomer(String name, String phone, String currency, int categoryId) async {
    await DBHelper.instance.addCustomer(name, phone, currency, categoryId);
    await loadCustomers();
  }

  Future<void> deleteCustomer(int id) async {
    await DBHelper.instance.deleteCustomer(id);
    await loadCustomers();
  }

  Future<void> loadTransactions(int customerId) async {
    _currentTransactions = await DBHelper.instance.getTransactions(customerId);
    notifyListeners();
  }

  Future<void> addTransaction(int customerId, double amount, String type, String details, String date) async {
    await DBHelper.instance.addTransaction(customerId, amount, type, details, date);
    await loadTransactions(customerId);
  }

  Future<void> deleteTransaction(int id, int customerId) async {
    await DBHelper.instance.deleteTransaction(id);
    await loadTransactions(customerId);
  }

  double getCustomerBalance(List<Map<String, dynamic>> txs) {
    double total = 0.0;
    for (var tx in txs) {
      if (tx['type'] == 'give') {
        total += tx['amount']; // له
      } else {
        total -= tx['amount']; // عليه
      }
    }
    return total;
  }
}

