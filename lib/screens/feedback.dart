import 'package:flutter/material.dart';

import '../data/store.dart';
import 'app.dart';
import 'common.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final message = TextEditingController();
  final form = GlobalKey<FormState>();
  bool sent = false;
  String? formUser;
  int? formSession;
  String? error;
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (form.currentState?.validate() != true) return;
    final store = widget.store;
    final session = store.sessionRevision;
    final user = store.backend?.userId;
    setState(() => error = null);
    try {
      await store.backend!.rpc('submit_feedback', {
        'p_message': message.text.trim(),
      });
      if (!mounted || !store.isCurrentSession(session, user)) return;
      setState(() {
        sent = true;
        message.clear();
      });
    } catch (_) {
      if (mounted && store.isCurrentSession(session, user)) {
        setState(
          () => error =
              'Your feedback couldn’t be sent. Please try again shortly.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      if (formUser != store.backend?.userId ||
          formSession != store.sessionRevision) {
        formUser = store.backend?.userId;
        formSession = store.sessionRevision;
        message.clear();
        sent = false;
        error = null;
      }
      return PageBody(
        width: 560,
        children: [
          const SizedBox(height: 16),
          const PageHeading(
            'We’re listening',
            'Ideas, problems, or a little praise — all feedback is welcome. Help us make spicyself better.',
          ),
          if (!store.signedIn)
            Notice(
              'Sign in to send your feedback to the spicyself team.',
              action: FilledButton(
                onPressed: () => openAccount(context, store),
                child: const Text('Sign in'),
              ),
            )
          else if (sent)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle_outline, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'Thank you for helping us improve!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your feedback has been sent to the spicyself team.',
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => setState(() => sent = false),
                    child: const Text('Send more feedback'),
                  ),
                ],
              ),
            )
          else
            Panel(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: message,
                      minLines: 5,
                      maxLines: 9,
                      maxLength: 2000,
                      enabled: !store.busy,
                      decoration: const InputDecoration(
                        labelText: 'Your feedback',
                        hintText: 'What’s working well? What could be better?',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').trim().length < 10
                          ? 'Please add a little more detail (at least 10 characters).'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please don’t include passwords, payment details, or sign-in codes.',
                    ),
                    const SizedBox(height: 20),
                    if (error != null) Notice(error!),
                    ActionButton(
                      store,
                      'Send feedback',
                      submit,
                      busyLabel: 'Sending feedback…',
                      icon: Icons.send_outlined,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
