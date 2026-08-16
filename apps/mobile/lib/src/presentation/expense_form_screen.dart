import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dhaka_time.dart';
import '../domain/expense.dart';
import '../domain/money.dart';
import '../providers.dart';

final class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({
    required this.defaultPayer,
    this.expense,
    super.key,
  });

  final HouseholdMember defaultPayer;
  final Expense? expense;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

final class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late ExpenseCategory _category;
  late HouseholdMember _payer;
  late CalendarDate _date;
  late TimeOfDay _time;
  bool _saving = false;

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    final local = DhakaTime.initialize().local(
      expense?.occurredAt ?? DateTime.now().toUtc(),
    );
    _amountController = TextEditingController(
      text: expense == null ? '' : formatBdtInput(expense.amountMinor),
    );
    _noteController = TextEditingController(text: expense?.note ?? '');
    _category = expense?.category ?? ExpenseCategory.groceries;
    _payer = expense?.payer ?? widget.defaultPayer;
    _date = CalendarDate(local.year, local.month, local.day);
    _time = TimeOfDay(hour: local.hour, minute: local.minute);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Edit expense' : 'Add expense';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: <Widget>[
              TextFormField(
                key: const Key('amount-field'),
                controller: _amountController,
                autofocus: !_isEditing,
                // Whole taka only, so the field refuses a decimal point outright
                // rather than validating one away after the fact.
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
              DropdownButtonFormField<ExpenseCategory>(
                key: const Key('category-field'),
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: ExpenseCategory.values
                    .map(
                      (category) => DropdownMenuItem<ExpenseCategory>(
                        value: category,
                        child: Text(category.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _category = value);
                        }
                      },
              ),
              const SizedBox(height: 20),
              Text('Paid by', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<HouseholdMember>(
                key: const Key('payer-selector'),
                segments: HouseholdMember.values
                    .map(
                      (member) => ButtonSegment<HouseholdMember>(
                        value: member,
                        label: Text(member.displayName),
                      ),
                    )
                    .toList(growable: false),
                selected: <HouseholdMember>{_payer},
                onSelectionChanged: _saving
                    ? null
                    : (selection) => setState(() => _payer = selection.first),
              ),
              const SizedBox(height: 20),
              Text(
                'Date and time',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('expense-date-button'),
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_displayDate),
                  ),
                  OutlinedButton.icon(
                    key: const Key('expense-time-button'),
                    onPressed: _saving ? null : _pickTime,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(_time.format(context)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('note-field'),
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const Key('save-expense-button'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_saving ? 'Saving…' : 'Save expense'),
        ),
      ),
    );
  }

  String get _displayDate {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[_date.month - 1]} ${_date.day}, ${_date.year}';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Expense date in Asia/Dhaka',
    );
    if (selected != null && mounted) {
      setState(() {
        _date = CalendarDate(selected.year, selected.month, selected.day);
      });
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Expense time in Asia/Dhaka',
    );
    if (selected != null && mounted) {
      setState(() => _time = selected);
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    final draft = ExpenseDraft(
      amountMinor: parseBdtToMinor(_amountController.text),
      category: _category,
      payer: _payer,
      occurredAt: DhakaTime.initialize().toUtc(
        date: _date,
        hour: _time.hour,
        minute: _time.minute,
      ),
      note: _noteController.text,
    );
    try {
      final repository = ref.read(expenseRepositoryProvider);
      if (_isEditing) {
        await repository.edit(widget.expense!.id, draft);
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
            content: Text('Could not save this expense. Please try again.'),
          ),
        );
      }
    }
  }
}
