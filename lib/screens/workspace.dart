import 'package:flutter/material.dart';

import 'common.dart';

class WorkspaceDestination {
  const WorkspaceDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Desktop section navigation and an accessible compact switcher on phones.
class WorkspaceNavigation extends StatelessWidget {
  const WorkspaceNavigation({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.child,
  });
  final List<WorkspaceDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              key: ValueKey(('workspace-section', selected)),
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Workspace section',
                prefixIcon: Icon(Icons.dashboard_outlined),
              ),
              items: [
                for (var i = 0; i < destinations.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(destinations[i].label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
            const SizedBox(height: 24),
            child,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          selected: selected == i,
                          selectedTileColor: lime.withValues(alpha: .5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(destinations[i].icon, size: 20),
                          title: Text(
                            destinations[i].label,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: child),
        ],
      );
    },
  );
}

class WorkspaceMetric extends StatelessWidget {
  const WorkspaceMetric({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });
  final String label, value, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ink, size: 22),
          const SizedBox(height: 16),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class WorkspaceSkeleton extends StatelessWidget {
  const WorkspaceSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading workspace',
    child: const Column(
      children: [
        LinearProgressIndicator(),
        SizedBox(height: 16),
        Panel(child: SizedBox(height: 120, width: double.infinity)),
        Panel(child: SizedBox(height: 160, width: double.infinity)),
      ],
    ),
  );
}
