import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:batchqr/core/theme/app_theme.dart';
import 'package:batchqr/core/widgets/custom_pill_toggle.dart';
import 'package:batchqr/core/widgets/pro_crown.dart';
import 'package:batchqr/features/single_gen/screens/single_gen_screen.dart';
import 'package:batchqr/features/bulk_gen/screens/bulk_gen_screen.dart';

class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark =
        themeProvider.themeMode == ThemeMode.dark ||
        (themeProvider.themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          width: 240,
          child: CustomPillToggle(
            options: const ['Single Code', 'Batch Studio'],
            selectedIndex: _selectedIndex,
            onChanged: (index) {
              setState(() => _selectedIndex = index);
              // Make sure to unfocus keyboard when switching
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        actions: [
          const ProCrownIcon(),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () => themeProvider.toggleTheme(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [SingleGenScreen(), BulkGenScreen()],
      ),
    );
  }
}
