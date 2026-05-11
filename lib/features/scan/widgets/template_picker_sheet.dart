import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/template_service.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_theme.dart';

/// Returned by [TemplatePicker.show].
/// - [dismissed] == true  → user swiped the sheet away; do nothing.
/// - [dismissed] == false → user made a choice; [template] is null for blank.
class TemplatePickerResult {
  final bool dismissed;
  final SessionTemplate? template;
  const TemplatePickerResult._({required this.dismissed, this.template});

  factory TemplatePickerResult.blank() =>
      const TemplatePickerResult._(dismissed: false, template: null);
  factory TemplatePickerResult.fromTemplate(SessionTemplate t) =>
      TemplatePickerResult._(dismissed: false, template: t);
  static const TemplatePickerResult dismiss =
      TemplatePickerResult._(dismissed: true);
}

/// Bottom sheet that lets the user pick a template (built-in or custom)
/// or start a blank session. Returns a [TemplatePickerResult].
///
/// Usage:
/// ```dart
/// final result = await TemplatePicker.show(context);
/// if (!result.dismissed) { /* open SessionSetupSheet */ }
/// ```
class TemplatePicker {
  static Future<TemplatePickerResult> show(BuildContext context) async {
    final result = await showModalBottomSheet<TemplatePickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TemplatePickerSheet(),
    );
    return result ?? TemplatePickerResult.dismiss;
  }
}

class _TemplatePickerSheet extends StatefulWidget {
  const _TemplatePickerSheet();

  @override
  State<_TemplatePickerSheet> createState() => _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends State<_TemplatePickerSheet> {
  String _search = '';

  List<SessionTemplate> get _filtered {
    final all = TemplateService.getAllTemplates();
    if (_search.trim().isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  static const _iconMap = <String, IconData>{
    'inventory_2_rounded': Icons.inventory_2_rounded,
    'people_rounded': Icons.people_rounded,
    'confirmation_number_rounded': Icons.confirmation_number_rounded,
    'devices_rounded': Icons.devices_rounded,
    'sell_rounded': Icons.sell_rounded,
    'grid_view_rounded': Icons.grid_view_rounded,
  };

  IconData _iconFor(String name) =>
      _iconMap[name] ?? Icons.grid_view_rounded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;
    final templates = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.55, 0.72, 0.95],
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121215) : const Color(0xFFFCFCFD),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? const Color(0xFF2A2A32).withValues(alpha: 0.5)
                    : const Color(0xFFE4E4EB).withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3A42)
                      : const Color(0xFFD4D4DC),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'New Session',
                            style: t.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.themeTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Choose a template or start blank',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: context.themeTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.themeTextSecondary,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: context.themeCard,
                        padding: const EdgeInsets.all(8),
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search templates…',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: context.themeTextSecondary,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Blank session shortcut
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AppCard(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, TemplatePickerResult.blank());
                  },
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: context.themeCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: context.themeBorder, width: 1),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: context.themeTextSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Blank session',
                              style: t.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.themeTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Start with one barcode column',
                              style: t.textTheme.bodySmall?.copyWith(
                                color: context.themeTextSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 13,
                        color: context.themeTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'TEMPLATES',
                    style: t.textTheme.labelSmall?.copyWith(
                      color: context.themeTextSecondary,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Template list
              Expanded(
                child: templates.isEmpty
                    ? Center(
                        child: Text(
                          'No templates found',
                          style: t.textTheme.bodySmall?.copyWith(
                            color: context.themeTextSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        itemCount: templates.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _TemplateCard(
                          template: templates[i],
                          iconData: _iconFor(templates[i].icon),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(
                              context,
                              TemplatePickerResult.fromTemplate(templates[i]),
                            );
                          },
                          onDuplicate: templates[i].isBuiltIn
                              ? () => _duplicateTemplate(context, templates[i])
                              : null,
                          onDelete: !templates[i].isBuiltIn
                              ? () => _deleteTemplate(context, templates[i])
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _duplicateTemplate(
      BuildContext context, SessionTemplate template) async {
    final nameController =
        TextEditingController(text: '${template.name} copy');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicate template'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      await TemplateService.duplicateTemplate(
          template.id, nameController.text.trim());
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteTemplate(
      BuildContext context, SessionTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('"${template.name}" will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await TemplateService.deleteTemplate(template.id);
      if (mounted) setState(() {});
    }
  }
}

class _TemplateCard extends StatelessWidget {
  final SessionTemplate template;
  final IconData iconData;
  final VoidCallback onTap;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  const _TemplateCard({
    required this.template,
    required this.iconData,
    required this.onTap,
    this.onDuplicate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.themeAccentContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(iconData, color: context.themeAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.name,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.themeTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (template.isBuiltIn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.themeCard,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: context.themeBorder, width: 0.5),
                        ),
                        child: Text(
                          'Built-in',
                          style: t.textTheme.labelSmall?.copyWith(
                            color: context.themeTextSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  template.columnSummary,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: context.themeTextSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: context.themeTextSecondary,
            ),
            onSelected: (v) {
              if (v == 'duplicate') onDuplicate?.call();
              if (v == 'delete') onDelete?.call();
            },
            itemBuilder: (_) => [
              if (onDuplicate != null)
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate'),
                ),
              if (onDelete != null)
                PopupMenuItem(
                  value: 'delete',
                  child:
                      Text('Delete', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
