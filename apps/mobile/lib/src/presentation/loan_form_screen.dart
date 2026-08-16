import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dhaka_time.dart';
import '../domain/expense.dart';
import '../domain/loan.dart';
import '../domain/money.dart';
import '../providers.dart';

/// The lending form asks for three things and stamps the fourth. Unlike an
/// expense, a loan never offers a date picker: the entry records when the money
/// changed hands, which is when it was written down.
final class LoanFormScreen extends ConsumerStatefulWidget {
  const LoanFormScreen({required this.defaultDebtor, this.loan, super.key});

  final HouseholdMember defaultDebtor;
  final Loan? loan;

  @override
  ConsumerState<LoanFormScreen> createState() => _LoanFormScreenState();
}

final class _LoanFormScreenState extends ConsumerState<LoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late HouseholdMember _debtor;
  bool _saving = false;

  bool get _isEditing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    _amountController = TextEditingController(
      text: loan == null ? '' : formatBdtInput(loan.amountMinor),
    );
    _noteController = TextEditingController(text: loan?.note ?? '');
    _debtor = loan?.debtor ?? widget.defaultDebtor;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final creditor = switch (_debtor) {
      HouseholdMember.sumon => HouseholdMember.ebrahim,
      HouseholdMember.ebrahim => HouseholdMember.sumon,
    };
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit loan' : 'Add loan')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: <Widget>[
              Text('Who owes?', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<HouseholdMember>(
                key: const Key('debtor-selector'),
                segments: HouseholdMember.values
                    .map(
                      (member) => ButtonSegment<HouseholdMember>(
                        value: member,
                        label: Text(member.displayName),
                      ),
                    )
                    .toList(growable: false),
                selected: <HouseholdMember>{_debtor},
                onSelectionChanged: _saving
                    ? null
                    : (selection) => setState(() => _debtor = selection.first),
              ),
              const SizedBox(height: 8),
              Text(
                '${_debtor.displayName} owes ${creditor.displayName}.',
                key: const Key('loan-direction-text'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('loan-amount-field'),
                controller: _amountController,
                autofocus: !_isEditing,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '৳ ',
                  helperText: 'Whole taka only',
                ),
                validator: (value) {
                  try {
                    parseBdtToMinor(value ?? '');
                    return null;
                  } on AmountValidationException catch (error) {
                    return error.message;
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('loan-note-field'),
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                maxLength: maximumNoteCodePoints,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  alignLabelWithHint: true,
                ),
                validator: (value) =>
                    (value ?? '').runes.length > maximumNoteCodePoints
                    ? 'Note must be $maximumNoteCodePoints characters or fewer.'
                    : null,
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Recorded'),
                  subtitle: Text(
                    loan == null
                        ? 'Stamped automatically when you save.'
                        : DhakaTime.initialize().formatDateTime(
                            loan.occurredAt,
                          ),
                    key: const Key('loan-timestamp-text'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const Key('save-loan-button'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_saving ? 'Saving…' : 'Save loan'),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    final draft = LoanDraft(
      debtor: _debtor,
      amountMinor: parseBdtToMinor(_amountController.text),
      note: _noteController.text,
    );
    try {
      final repository = ref.read(loanRepositoryProvider);
      if (_isEditing) {
        await repository.edit(widget.loan!.id, draft);
      } else {
        await repository.create(draft);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this loan. Please try again.'),
          ),
        );
      }
    }
  }
}
