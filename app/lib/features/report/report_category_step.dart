import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import 'report_flow_widgets.dart';
import 'report_flow_controller.dart';

class CategoryStep extends StatefulWidget {
  const CategoryStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  State<CategoryStep> createState() => _CategoryStepState();
}

class _CategoryStepState extends State<CategoryStep> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.categories
        .where((c) => c.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final groups = categories.map((c) => c.group).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(S.chooseCategory, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        TextField(
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'Buscar categoría',
            prefixIcon: Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (categories.isEmpty)
          const FlowNotice(
            'No encontramos esa categoría. Prueba con otra palabra.',
          ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Semantics(
              header: true,
              child: Text(
                categoryGroupLabel(group),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final category in categories.where((c) => c.group == group))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CategoryRow(
                category: category,
                selected: widget.controller.categoryId == category.id,
                onTap: () => widget.controller.setCategory(category.id),
              ),
            ),
        ],
      ],
    );
  }
}

/// Large selectable row: icon, label and a check when chosen.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.selected,
    required this.onTap,
  });
  final ReportCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AldiaSpace.l,
                vertical: AldiaSpace.m,
              ),
              child: Row(
                children: [
                  Icon(
                    category.icon,
                    size: 24,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.primary,
                  ),
                  const SizedBox(width: AldiaSpace.l),
                  Expanded(
                    child: Text(
                      category.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    child: selected
                        ? Icon(
                            Icons.check_circle,
                            size: 24,
                            color: scheme.onPrimaryContainer,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
