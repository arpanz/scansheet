import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/scan_session_service.dart';
import '../models/scan_session.dart';
import 'scan_session_screen.dart';
import '../../../core/utils/app_router.dart';

class AllSessionsScreen extends StatefulWidget {
  const AllSessionsScreen({super.key});

  @override
  State<AllSessionsScreen> createState() => _AllSessionsScreenState();
}

class _AllSessionsScreenState extends State<AllSessionsScreen> {
  void _openSessionMode(ScanSession session) {
    Navigator.push(
      context,
      FadeSlideRoute(page: ScanSessionScreen(session: session)),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final allSessions = ScanSessionService.getAllSessions();
    final pastSessions = allSessions.where((s) => !s.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Sheets'),
      ),
      body: pastSessions.isEmpty
          ? Center(
              child: Text(
                'No past sheets.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.themeTextSecondary,
                    ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: pastSessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final s = pastSessions[index];
                final rowCount = ScanSessionService.getRowCount(s.id);
                const months = [
                  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                ];
                final dateStr = '${months[s.createdAt.month - 1]} ${s.createdAt.day}';

                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _openSessionMode(s);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.themeCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.themeBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.table_view_rounded,
                          color: context.themeTextSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: TextStyle(
                                  color: context.themeTextPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$rowCount rows · $dateStr',
                                style: TextStyle(
                                  color: context.themeTextSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: context.themeTextSecondary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
