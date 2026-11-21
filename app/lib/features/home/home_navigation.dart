import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';

enum HomeTab { home, notices, report, mine, profile }

class HomeNavigationBar extends StatelessWidget {
  const HomeNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final HomeTab selected;
  final ValueChanged<HomeTab> onSelected;
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selected.index,
    height: MediaQuery.textScalerOf(context).scale(14) > 20 ? 104 : 80,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300),
    onDestinationSelected: (i) => onSelected(HomeTab.values[i]),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Inicio',
      ),
      NavigationDestination(
        icon: Icon(Icons.notifications_outlined),
        selectedIcon: Icon(Icons.notifications),
        label: 'Avisos',
      ),
      NavigationDestination(icon: _ReportPill(), label: S.newReport),
      NavigationDestination(
        icon: Icon(Icons.assignment_outlined),
        selectedIcon: Icon(Icons.assignment),
        label: S.myReports,
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Perfil',
      ),
    ],
  );
}

/// The key call to action of the bar: a coral pill with a plus.
class _ReportPill extends StatelessWidget {
  const _ReportPill();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 56,
      height: 36,
      decoration: ShapeDecoration(
        color: dark ? AldiaColors.darkAccent : AldiaColors.accent,
        shape: const StadiumBorder(),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.add, color: AldiaColors.onAccent, size: 26),
    );
  }
}
