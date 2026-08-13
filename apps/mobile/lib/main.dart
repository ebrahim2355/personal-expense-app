import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: HouseholdExpensesApp()));
}

class HouseholdExpensesApp extends StatelessWidget {
  const HouseholdExpensesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Household Expenses',
      home: Scaffold(
        appBar: AppBar(title: const Text('Household Expenses')),
        body: const Center(child: Text('Development shell ready')),
      ),
    );
  }
}
