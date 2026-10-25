import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';

const ink = Color(0xff153e37);
const cream = Color(0xfffaf9f0);
const lime = Color(0xffdcf4a5);

class LocationSearchBar extends StatelessWidget {
  const LocationSearchBar({
    super.key,
    required this.controller,
    required this.onSearch,
  });
  final TextEditingController controller;
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSearch(),
        decoration: const InputDecoration(
          hintText: 'Search suburb, town or postcode',
          counterText: '',
          prefixIcon: Icon(Icons.search),
          labelText: 'Where are you looking?',
        ),
      );
}

ThemeData spicyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ink,
    primary: ink,
    secondary: lime,
    surface: cream,
    onSurface: const Color(0xff242b29),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: Color(0xffdce1da)),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: cream,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: lime,
      height: 80,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: ink, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: Colors.white,
      selectedColor: lime,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cream,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) Text(subtitle!),
              ],
            ),
            if (action != null) action!,
          ],
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.icon = Icons.info_outline});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: lime.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Icon(icon, size: 16, color: ink),
            Text(
              label,
              style: const TextStyle(color: ink, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class BrandPlaceholder extends StatelessWidget {
  const BrandPlaceholder({super.key, this.home = false, this.height = 128});
  final bool home;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: cream,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Icon(
            home ? Icons.home_outlined : Icons.content_cut,
            size: 40,
            color: ink,
          ),
        ),
      );
}

class DiscoverySkeleton extends StatelessWidget {
  const DiscoverySkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading nearby businesses',
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            for (var i = 0; i < 2; i++)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: cream,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(height: 16, width: 180, color: cream),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 120, color: cream),
                  ],
                ),
              ),
          ],
        ),
      );
}

class WorkspaceGroup extends StatelessWidget {
  const WorkspaceGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey(title),
          leading: Icon(icon, color: ink),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

/// Shared scissors artwork and wordmark for configured and setup screens.
class SpicySelfBrand extends StatelessWidget {
  const SpicySelfBrand({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'spicyself',
        image: true,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/branding/scissors.png',
                  width: 56, height: 56),
              const SizedBox(width: 4),
              const Flexible(
                child: Text(
                  'spicyself',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

String money(dynamic cents) => NumberFormat.currency(
      locale: 'en_NZ',
      symbol: '\$',
    ).format((cents as num) / 100);
tz.TZDateTime nzNow() => tz.TZDateTime.now(tz.getLocation('Pacific/Auckland'));
String nzTime(dynamic iso) => DateFormat('EEE d MMM, h:mm a').format(
      tz.TZDateTime.from(
        DateTime.parse(iso as String),
        tz.getLocation('Pacific/Auckland'),
      ),
    );
String dayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String normalizePhone(String raw) {
  final value = raw.replaceAll(RegExp(r'[\s()-]'), '');
  final phone = value.startsWith('0') ? '+64${value.substring(1)}' : value;
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone))
    throw Exception(
      'Enter a phone number such as 021 123 4567 or +64 21 123 4567',
    );
  return phone;
}

Future<void> openLink(String url) async {
  final uri = Uri.parse(url);
  if (!['https', 'mailto'].contains(uri.scheme))
    throw Exception('Invalid link');
  if (!await launchUrl(
    uri,
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_self',
  )) throw Exception('Could not open the link');
}

Future<T?> showSessionDialog<T>(
  BuildContext context,
  AppStore store, {
  required WidgetBuilder builder,
  bool requireAdmin = false,
  bool requireMfa = false,
}) async {
  final session = store.sessionRevision;
  final user = store.backend?.userId;
  bool allowed() =>
      store.isCurrentSession(session, user) &&
      (!requireAdmin || store.isAdmin) &&
      (!requireMfa || store.unlocked);
  final result = await showDialog<T>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => allowed()
          ? builder(context)
          : AlertDialog(
              title: const Text('Session changed'),
              content: const Text(
                'Your account or access changed. Close this dialog and start again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop<T>(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            ),
    ),
  );
  return allowed() ? result : null;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  required AppStore store,
  String action = 'Confirm',
  bool requireMfa = false,
}) async =>
    await showSessionDialog<bool>(
      context,
      store,
      requireMfa: requireMfa,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.width = 1050});
  final List<Widget> children;
  final double width;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: ink),
            ),
            const SizedBox(height: 8),
            Text(subtitle),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: action),
          ],
        ),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: action),
          ],
        ),
      );
}

class FormFieldBox extends StatelessWidget {
  const FormFieldBox(
    this.controller,
    this.label, {
    super.key,
    this.hint,
    this.keyboard,
    this.lines = 1,
    this.required = true,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final int lines;
  final bool required;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          key: ValueKey(label),
          controller: controller,
          keyboardType: keyboard,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          validator: validator ??
              (v) => required && (v == null || v.trim().isEmpty)
                  ? 'Enter $label'
                  : null,
        ),
      );
}

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.store,
    this.label,
    this.action, {
    super.key,
    this.icon,
    this.busyLabel,
  });
  final AppStore store;
  final String? busyLabel;
  final String label;
  final Future<void> Function() action;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: store.busy ? null : () => store.run(action),
        icon: store.busy && busyLabel != null
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon ?? Icons.arrow_forward, size: 18),
        label: Text(store.busy ? busyLabel ?? label : label),
      );
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel({
    super.key,
    required this.future,
    required this.builder,
    this.retry,
  });
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Notice(
              friendlyError(snapshot.error!),
              action: retry == null
                  ? null
                  : TextButton(
                      onPressed: retry, child: const Text('Try again')),
            );
          if (!snapshot.hasData)
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          return builder(snapshot.data as T);
        },
      );
}
