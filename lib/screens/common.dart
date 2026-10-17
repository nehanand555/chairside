import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import '../data/store.dart';

const ink = Color(0xff12302d);
const cream = Color(0xfff5f5ef);
const lime = Color(0xffdcf4a5);
String money(dynamic cents) =>
    NumberFormat.currency(locale: 'en_NZ', symbol: '\$')
        .format((cents as num) / 100);
tz.TZDateTime nzNow() => tz.TZDateTime.now(tz.getLocation('Pacific/Auckland'));
String nzTime(dynamic iso) =>
    DateFormat('EEE d MMM, h:mm a').format(tz.TZDateTime.from(
        DateTime.parse(iso as String), tz.getLocation('Pacific/Auckland')));
String dayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String normalizePhone(String raw) {
  final value = raw.replaceAll(RegExp(r'[\s()-]'), '');
  final phone = value.startsWith('0') ? '+64${value.substring(1)}' : value;
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone))
    throw Exception(
        'Enter a phone number such as 021 123 4567 or +64 21 123 4567');
  return phone;
}

Future<void> openLink(String url) async {
  final uri = Uri.parse(url);
  if (!['https', 'mailto'].contains(uri.scheme))
    throw Exception('Invalid link');
  if (!await launchUrl(uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self')) throw Exception('Could not open the link');
}

Future<bool> confirm(BuildContext context, String title, String message,
        {String action = 'Confirm'}) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go back')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action))
            ])) ??
    false;

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.width = 1050});
  final List<Widget> children;
  final double width;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        Center(
            child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children)))
      ]);
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 8),
        Text(subtitle),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: action)
      ]));
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(padding: const EdgeInsets.all(20), child: child));
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: action)
      ]));
}

class FormFieldBox extends StatelessWidget {
  const FormFieldBox(this.controller, this.label,
      {super.key,
      this.hint,
      this.keyboard,
      this.lines = 1,
      this.required = true});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final int lines;
  final bool required;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: lines,
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
          validator: (v) => required && (v == null || v.trim().isEmpty)
              ? 'Enter $label'
              : null));
}

class ActionButton extends StatelessWidget {
  const ActionButton(this.store, this.label, this.action,
      {super.key, this.icon});
  final AppStore store;
  final String label;
  final Future<void> Function() action;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
      onPressed: store.busy ? null : () => store.run(action),
      icon: Icon(icon ?? Icons.arrow_forward, size: 18),
      label: Text(label));
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel(
      {super.key, required this.future, required this.builder, this.retry});
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Notice(friendlyError(snapshot.error!),
              action: retry == null
                  ? null
                  : TextButton(
                      onPressed: retry, child: const Text('Try again')));
        if (!snapshot.hasData)
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator()));
        return builder(snapshot.data as T);
      });
}
