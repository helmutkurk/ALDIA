import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/strings.dart';

/// States a citizen can filter by (`oculto` is never public).
final List<String> _filterStates = [
  for (final state in citizenStates.keys)
    if (state != 'oculto') state,
];

class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key, this.state, this.category});
  final String? state;
  final String? category;

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late String? _state = widget.state;
  late String? _category = widget.category;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                S.filtersLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _state,
              isExpanded: true,
              decoration: const InputDecoration(labelText: S.filterState),
              items: [
                const DropdownMenuItem(child: Text(S.allStates)),
                for (final state in _filterStates)
                  DropdownMenuItem(
                    value: state,
                    child: Text(citizenStates[state]!.label),
                  ),
              ],
              onChanged: (value) => setState(() => _state = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: S.filterCategory),
              items: [
                const DropdownMenuItem(child: Text(S.allCategories)),
                for (final category in reportCategories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((_state, _category)),
              child: const Text(S.apply),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop((null, null)),
              child: const Text(S.clearFilters),
            ),
          ],
        ),
      ),
    );
  }
}
