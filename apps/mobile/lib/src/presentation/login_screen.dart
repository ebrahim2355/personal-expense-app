import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/remote/api_client.dart';
import '../data/remote/http_transport.dart';
import '../domain/expense.dart';
import '../providers.dart';

final class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

final class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  HouseholdMember _member = HouseholdMember.sumon;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Align(
                        child: CircleAvatar(
                          radius: 34,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Icon(
                            Icons.home_outlined,
                            size: 36,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Household Expenses',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in as one of the two household members.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Who are you?',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<HouseholdMember>(
                        key: const Key('login-member-selector'),
                        segments: HouseholdMember.values
                            .map(
                              (member) => ButtonSegment<HouseholdMember>(
                                value: member,
                                label: Text(member.displayName),
                              ),
                            )
                            .toList(growable: false),
                        selected: <HouseholdMember>{_member},
                        onSelectionChanged: _submitting
                            ? null
                            : (members) =>
                                  setState(() => _member = members.first),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('pin-field'),
                        controller: _pinController,
                        enabled: !_submitting,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[AutofillHints.password],
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'PIN',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) =>
                            RegExp(r'^\d{6,12}$').hasMatch(value ?? '')
                            ? null
                            : 'Enter your 6 to 12 digit PIN.',
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Material(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    Icons.error_outline,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_error!)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const Key('login-button'),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your first sign-in on this device needs an internet connection. '
                        'After that, saved expenses remain available offline.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    TextInput.finishAutofillContext();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .login(_member, _pinController.text);
      _pinController.clear();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _loginError(error);
        });
      }
    }
  }

  String _loginError(Object error) {
    if (error is NetworkException) {
      return 'Can’t reach the server. Check your connection and try again.';
    }
    if (error is ApiException && error.statusCode == 429) {
      return 'Too many sign-in attempts. Wait a moment and try again.';
    }
    if (error is ApiException && error.isAuthenticationFailure) {
      return 'Couldn’t sign in. Check the selected member and PIN.';
    }
    return 'Couldn’t sign in right now. Please try again.';
  }
}
