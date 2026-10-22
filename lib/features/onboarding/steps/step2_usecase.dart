/// Step 2 — What will you scan?
/// Source: docs/design/mocks/Onb5-Usecase.dc.html
library;

import 'package:flutter/material.dart';

import '../../../core/widgets/ss.dart';
import '../onboarding_flow.dart';

// ─── Mock-to-template mapping ────────────────────────────────────────────────

class _UsecaseOption {
  final String id; // matches SessionTemplate.id or 'custom'
  final String label;
  final String shortLabel; // for button copy
  final String colSummary;
  final IconData icon;

  const _UsecaseOption({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.colSummary,
    required this.icon,
  });
}

// Map the 6 mock cards to built-in template ids. 'blank' → custom columns.
const _options = [
  _UsecaseOption(
    id: 'builtin_inventory',
    label: 'Inventory',
    shortLabel: 'an inventory',
    colSummary: 'Item · Qty · Time',
    icon: LucideIcons.package,
  ),
  _UsecaseOption(
    id: 'builtin_attendance',
    label: 'Attendance',
    shortLabel: 'an attendance',
    colSummary: 'Name · ID · Check-in',
    icon: LucideIcons.userCheck,
  ),
  _UsecaseOption(
    id: 'builtin_asset_tracking',
    label: 'Asset tracking',
    shortLabel: 'an asset',
    colSummary: 'Tag · Location · Status',
    icon: LucideIcons.tag,
  ),
  _UsecaseOption(
    id: 'builtin_event_checkin',
    label: 'Event check-in',
    shortLabel: 'a check-in',
    colSummary: 'Ticket · Gate · Time',
    icon: LucideIcons.ticket,
  ),
  _UsecaseOption(
    id: 'builtin_price_list',
    label: 'Price list',
    shortLabel: 'a price',
    colSummary: 'Barcode · Name · MRP',
    icon: LucideIcons.circleDollarSign,
  ),
  _UsecaseOption(
    id: 'custom',
    label: 'Start blank',
    shortLabel: 'a blank',
    colSummary: 'Your own columns',
    icon: LucideIcons.plus,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────

class OnbUsecaseStep extends StatefulWidget {
  final OnbStateScope scope;
  const OnbUsecaseStep({super.key, required this.scope});

  @override
  State<OnbUsecaseStep> createState() => _OnbUsecaseStepState();
}

class _OnbUsecaseStepState extends State<OnbUsecaseStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  String _picked = 'builtin_inventory';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(_fade);
    _ctrl.forward();
    // Restore pick from shared state
    _picked = widget.scope.state.selectedTemplateId ?? 'builtin_inventory';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  _UsecaseOption get _sel => _options.firstWhere((o) => o.id == _picked);

  void _pick(String id) {
    setState(() => _picked = id);
    widget.scope.state.selectedTemplateId = id;
  }

  void _continue() {
    widget.scope.state.selectedTemplateId = _picked;
    widget.scope.goNext(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ss;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Headline
              Text(
                'What will you\nscan first?',
                style: SsText.title(color: c.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'We’ll set up the right columns. You can change them anytime.',
                style: SsText.body(color: c.ink2),
              ),
              const SizedBox(height: 20),

              // 2-column grid
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 150 / 128,
                  ),
                  itemCount: _options.length,
                  itemBuilder: (ctx, i) {
                    final opt = _options[i];
                    final selected = _picked == opt.id;
                    return _UsecaseCard(
                      option: opt,
                      selected: selected,
                      onTap: () => _pick(opt.id),
                      c: c,
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // CTA
              SsButton('Create ${_sel.shortLabel} sheet', onPressed: _continue),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsecaseCard extends StatelessWidget {
  final _UsecaseOption option;
  final bool selected;
  final VoidCallback onTap;
  final SsColors c;

  const _UsecaseCard({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SsRadius.lg),
          border: Border.all(
            color: selected ? c.ink : c.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon tile
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? SsColors.brandLime : c.chip,
                    borderRadius: BorderRadius.circular(SsRadius.sm),
                  ),
                  child: Center(
                    child: Icon(option.icon, size: 18, color: c.ink),
                  ),
                ),
                // Labels
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label, style: SsText.label(color: c.ink)),
                    const SizedBox(height: 3),
                    Text(
                      option.colSummary,
                      style: SsText.mono(size: 11, color: c.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
            // Checkmark badge
            if (selected)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      LucideIcons.check,
                      size: 12,
                      color: SsColors.brandLime,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
