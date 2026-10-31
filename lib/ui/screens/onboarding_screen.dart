import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/settings_store.dart';
import '../../domain/cycle_engine.dart';
import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/profile.dart';
import '../../domain/quiz.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/partner_invite.dart';
import '../widgets/wordmark.dart';
import '../../l10n/ui.dart';

/// How the quiz was opened.
enum OnboardingEntry {
  /// Shown by the gate in `main.dart` until it has been completed once.
  firstRun,

  /// Pushed from Settings to choose a journey again.
  retake,

  /// Pushed from Settings to answer the questions she left for later, with
  /// her earlier answers filled in.
  resume,
}

/// The onboarding quiz: pick a journey, answer its questions (any can be
/// skipped), then a summary of what was set up. The questions live in
/// `lib/domain/quiz.dart`; how the answers change the app is in [_plan].
///
/// Her journeys use the Dawn colours. "Support my partner" switches to
/// Night as soon as it is chosen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.entry = OnboardingEntry.firstRun});

  final OnboardingEntry entry;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _inviteMessage = partnerInviteMessage;

  /// Her journeys offer "finish the rest later" from this question on: the
  /// first three are the ones predictions need.
  static const _finishLaterFrom = 3;

  Journey? _journey;

  /// She chose "Track my cycle" and is picking one of her journeys.
  bool _tracking = false;

  /// Her partner's two screens: 0 the questions, 1 connecting.
  int _partnerStep = 0;
  int _step = 0;
  bool _extrasAdded = false;
  final Map<String, Object> _answers = {};

  /// Where she chose "finish the rest later", until she goes back to it.
  int? _resumeAt;

  final _days = TextEditingController();
  final _code = TextEditingController();
  bool _saving = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.entry == OnboardingEntry.resume) {
      final profile = ref.read(profileProvider);
      final journey = journeyById(profile.journey);
      final at = profile.quizResumeAt;
      if (journey != null && at != null) {
        _journey = journey;
        _step = at.clamp(0, journey.questions.length);
        for (final MapEntry(:key, :value) in profile.quizAnswers.entries) {
          if (value != null) _answers[key] = value;
        }
        _syncDays();
      }
    }
  }

  @override
  void dispose() {
    _days.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Opened from Settings rather than by the gate.
  bool get _retaking => widget.entry != OnboardingEntry.firstRun;

  List<QuizQuestion> get _questions => [
        ...?_journey?.questions,
        if (_extrasAdded) ...?_journey?.extras,
      ];

  QuizQuestion? get _current =>
      _journey != null && _step < _questions.length ? _questions[_step] : null;

  // ---- Navigation -----------------------------------------------------------

  void _begin(Journey journey) => setState(() {
        _journey = journey;
        _partnerStep = 0;
        _step = 0;
        _extrasAdded = false;
        _resumeAt = null;
        _answers.clear();
        _error = null;
        _syncDays();
      });

  void _next() {
    _commitDays();
    final question = _current;
    if (question?.kind == QuizKind.consent &&
        !_answers.containsKey(question!.id)) {
      _answers[question.id] = _privateConsent;
    }
    setState(() {
      _error = null;
      _step++;
      _syncDays();
    });
  }

  /// Skipping the consent question leaves partner sharing as it is: off on a
  /// first run, and whatever she set on the Partner tab when coming back.
  void _skip() {
    final question = _current;
    if (question != null) _answers.remove(question.id);
    setState(() {
      _error = null;
      _step++;
      _syncDays();
    });
  }

  /// Straight to the summary. What she answered is saved, and Settings
  /// offers the rest until she finishes it.
  void _finishLater() {
    _commitDays();
    setState(() {
      _error = null;
      _resumeAt = _step;
      _step = _questions.length;
    });
  }

  /// One step back, from anywhere in the quiz. On the very first screen it
  /// closes the quiz when it was opened from Settings.
  void _back() {
    _commitDays();
    if (_journey == null) {
      if (_tracking) {
        setState(() => _tracking = false);
      } else if (_retaking) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _error = null;
      if (_journey!.partner && _partnerStep == 1) {
        _partnerStep = 0;
        _answers
          ..remove('understand')
          ..remove('tone');
      } else if (_step == 0) {
        _journey = null;
      } else {
        _step--;
        // Back undoes the choice: the answer on the question she returns
        // to, and every answer after it, so nothing she changed her mind
        // about stays behind (e.g. "Trying to conceive" after she went back
        // and chose "Understand fertility"). She picks again from nothing.
        for (final question in _questions.skip(_step)) {
          _answers.remove(question.id);
        }
        if (_resumeAt != null && _step < _resumeAt!) _resumeAt = null;
      }
      _syncDays();
    });
  }

  /// The number field belongs to whichever question is on screen.
  void _syncDays() {
    final question = _current;
    final value = question == null ? null : _answers[question.id];
    _days.text = question?.kind == QuizKind.days &&
            value is String &&
            int.tryParse(value) != null
        ? value
        : '';
  }

  void _commitDays() {
    final question = _current;
    if (question == null || question.kind != QuizKind.days) return;
    final n = int.tryParse(_days.text.trim());
    if (n != null) _answers[question.id] = '$n';
  }

  // ---- Answers --------------------------------------------------------------

  static const Map<String, Object> _privateConsent = {
    'connect': 'no',
    'share': <String>[],
  };

  /// Rebuilt on every read: answers loaded back from storage come as plain
  /// JSON maps and lists.
  Map<String, Object> get _consent {
    final value = _answers['consent'];
    if (value is! Map) return _privateConsent;
    final share = value['share'];
    return {
      'connect': value['connect'] == 'yes' ? 'yes' : 'no',
      'share': share is List ? share.whereType<String>().toList() : <String>[],
    };
  }

  void _setConsent(String connect, List<String> share) => setState(
        () => _answers['consent'] = {'connect': connect, 'share': share},
      );

  void _toggleShare(String key) {
    final share = [...(_consent['share'] as List).whereType<String>()];
    if (!share.remove(key)) share.add(key);
    _setConsent('yes', share);
  }

  void _pick(QuizQuestion question, String option) => setState(() {
        _error = null;
        if (question.kind == QuizKind.days) _days.clear();
        _answers[question.id] = option;
      });

  void _toggle(QuizQuestion question, String option) => setState(() {
        final current = _answers[question.id];
        final list = current is List
            ? [...current.whereType<String>()]
            : <String>[];
        if (!list.remove(option)) list.add(option);
        _answers[question.id] = list;
      });

  Future<void> _pickDate(QuizQuestion question) async {
    final now = DateTime.now();
    final current = _answers[question.id];
    final picked = await showDatePicker(
      context: context,
      initialDate: current is String && _isIsoDate(current)
          ? DayKey.parse(current).toDateTime()
          : now,
      firstDate: now.subtract(const Duration(days: 365 * 3)),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _answers[question.id] = DayKey.fromDateTime(picked).iso);
  }

  static bool _isIsoDate(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);

  Future<void> _joinPartner() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = tr('Enter the code first.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(partnerLinkServiceProvider).join(_code.text);
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- What the answers change ----------------------------------------------

  _Plan _plan() {
    final journey = _journey!;
    String? one(String id) {
      final value = _answers[id];
      return value is String ? value : null;
    }

    List<String> many(String id) {
      final value = _answers[id];
      return value is List ? value.whereType<String>().toList() : const [];
    }

    final date = one('lastPeriod');
    final lastPeriod =
        date != null && _isIsoDate(date) ? DayKey.parse(date) : null;

    final periodAnswer = one('periodLength');
    final periodDays =
        periodAnswer == '8+' ? 8 : int.tryParse(periodAnswer ?? '');
    final periodLength =
        periodDays != null && periodDays >= 1 && periodDays <= 15
            ? periodDays
            : null;
    final cycleDays = int.tryParse(one('cycleLength') ?? '');
    final cycleLength = cycleDays != null && cycleDays >= 15 && cycleDays <= 90
        ? cycleDays
        : null;

    final regularity = switch (one('predictability')) {
      'Very regular' || 'Mostly regular' || 'Regular' =>
        CycleRegularity.regular,
      'Sometimes early/late' || 'Sometimes vary' => CycleRegularity.varies,
      'Unpredictable' || 'Irregular' => CycleRegularity.unpredictable,
      'Not sure' => CycleRegularity.unsure,
      _ => switch (one('cycleLength')) {
          'Varies' => CycleRegularity.varies,
          'Irregular' => CycleRegularity.unpredictable,
          _ => null,
        },
    };

    // Anything that makes calendar estimates of fertile days meaningless.
    final condition = one('affects') ??
        one('circumstances') ??
        one('bleedingFactors') ??
        one('hrtOrContraception');
    final blockedBy = one('hysterectomy') == 'Yes'
        ? 'a hysterectomy or ovary removal'
        : switch (condition) {
            'Hormonal contraception' || 'Both' => 'hormonal birth control',
            'Pregnant/breastfeeding' ||
            'Pregnancy/breastfeeding' =>
              'pregnancy or breastfeeding',
            'Hysterectomy/ovary removal' => 'a hysterectomy or ovary removal',
            'HRT (Hormone Replacement Therapy)' => 'HRT',
            _ => null,
          };

    final fertilityGoal = one('fertilityGoal');
    final conceive = journey.id == 'fertility' &&
        (fertilityGoal == 'Preparing for pregnancy' ||
            fertilityGoal == 'Trying to conceive');
    final wantsFertileDays = journey.id == 'fertility' ||
        (journey.id == 'cycle' &&
            many('helpWith').contains('Fertility awareness'));

    const symptomNames = {
      'Cramps': 'Cramps',
      'Bloating': 'Bloating',
      'Headaches': 'Headache',
      'Breast tenderness': 'Breast tenderness',
      'Fatigue': 'Fatigue',
      'Hot flushes': 'Hot flush',
    };
    const tryingNames = {
      'Not started': 'start',
      'Under 6 months': 'lt6',
      '6–12 months': '6to12',
      'Over 12 months': 'year',
    };
    const focusNames = {
      'Period predictions': 'period',
      'Mood and symptoms': 'mood',
    };

    final cycleReminders = one('reminders');
    final checkIns = one('optionalReminders') ??
        one('checkInFrequency') ??
        one('checkIns');
    final periodReminder = journey.id == 'menopause'
        ? false
        : cycleReminders == null
            ? null
            : cycleReminders == 'Upcoming period' || cycleReminders == 'Both';
    final dailyReminder = cycleReminders != null
        ? cycleReminders == 'Symptom check-ins' || cycleReminders == 'Both'
        : checkIns == null
            ? null
            : checkIns == 'Daily';

    final consent = _consent;
    final share = (consent['share'] as List).whereType<String>().toSet();
    final inviting = consent['connect'] == 'yes';

    return _Plan(
      consentAnswered: _answers.containsKey('consent'),
      goal: conceive ? TrackingGoal.conceive : TrackingGoal.track,
      lastPeriod: lastPeriod,
      periodLength: periodLength,
      cycleLength: cycleLength,
      regularity: regularity,
      blockedBy: blockedBy,
      showFertileDays: wantsFertileDays && blockedBy == null,
      usualSymptoms: [
        for (final s in [...many('symptoms'), ...many('changesNoticed')])
          if (symptomNames[s] case final name?) name,
      ],
      tryingSince: tryingNames[one('tryingSince')],
      trackedSigns: one('fertilitySigns') == 'Yes' ? const ['fluid'] : const [],
      focus: [
        for (final f in many('helpWith'))
          if (focusNames[f] case final name?) name,
      ],
      periodReminder: periodReminder,
      dailyReminder: dailyReminder,
      inviting: inviting,
      share: share,
    );
  }

  Future<void> _finish() async {
    _commitDays();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_journey!.partner) {
        await _finishPartner();
      } else {
        await _finishTracker();
      }
      if (mounted && _retaking) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '${tr('Could not save your answers.')} $e';
        });
      }
    }
  }

  Future<void> _finishTracker() async {
    final plan = _plan();
    final logs = ref.read(logsProvider.notifier);
    final today = DayKey.today();

    final start = plan.lastPeriod;
    if (start != null) {
      for (var i = 0; i < (plan.periodLength ?? 5); i++) {
        final day = start.addDays(i);
        if (day.isAfter(today)) break;
        final existing = ref.read(logByDayProvider(day)) ?? DayLog(date: day);
        await logs.save(
          existing.copyWith(
            // A flow she logged herself wins over the quiz's estimate, which
            // matters when she comes back to finish the quiz.
            flow: existing.flow == FlowIntensity.none
                ? FlowIntensity.medium
                : existing.flow,
            isPeriodStartOverride: i == 0 ? true : null,
          ),
        );
      }
    }

    // She chose reminders in the quiz: ask the phone to allow them now,
    // before saving, because saving closes this screen.
    if (plan.periodReminder == true || plan.dailyReminder == true) {
      try {
        await ref.read(notificationServiceProvider).requestPermissions();
      } catch (_) {}
    }

    final current =
        ref.read(settingsProvider).value ?? const AppSettings();
    // Saved last: on first run, completing onboarding replaces this screen.
    await ref.read(settingsProvider.notifier).replaceAll(
          current.copyWith(
            onboardingComplete: true,
            reminders: current.reminders.copyWith(
              periodReminder: plan.periodReminder,
              dailyLogReminder: plan.dailyReminder,
            ),
            sharing: !plan.consentAnswered
                ? current.sharing
                : current.sharing.copyWith(
                    enabled: plan.inviting,
                    sharePhase: plan.share.contains('cycle'),
                    shareNextPeriodDate: plan.share.contains('cycle'),
                    shareMood: plan.share.contains('mood'),
                    sharePain: plan.share.contains('pain'),
                    allowRequests: plan.share.contains('requests'),
                    // Older switches, replaced by mood and pain.
                    shareSymptoms: false,
                    shareEnergy: false,
                  ),
            profile: UserProfile(
              journey: _journey!.id,
              quizAnswers: Map.of(_answers),
              quizResumeAt: _resumeAt,
              goal: plan.goal,
              cycleLength: plan.cycleLength,
              periodLength: plan.periodLength,
              regularity: plan.regularity,
              showFertileDays: plan.showFertileDays,
              tryingSince: plan.tryingSince,
              trackedSigns: plan.trackedSigns,
              focus: plan.focus,
              usualSymptoms: plan.usualSymptoms,
            ),
          ),
        );
  }

  Future<void> _finishPartner() async {
    final current =
        ref.read(settingsProvider).value ?? const AppSettings();
    final previous = current.profile;
    // On first run this replaces the quiz with his home screen. His name for
    // her and his tone are set from his menu; until then, "a little humour".
    final toneAnswer = _answers['tone'];
    final answers = <String, Object?>{
      ...Map.of(_answers),
      // The home screen asks "How do you like your tips?" only if he skipped.
      if (toneAnswer is String) 'toneChosen': true,
    };
    await ref.read(settingsProvider.notifier).replaceAll(
          current.copyWith(
            onboardingComplete: true,
            profile: UserProfile(
              role: AppRole.partner,
              journey: _journey!.id,
              quizAnswers: answers,
              partnerNickname: previous.partnerNickname,
              partnerTone: toneAnswer is String
                  ? PartnerTone.fromName(toneAnswer)
                  : previous.role == AppRole.partner
                      ? previous.partnerTone
                      : PartnerTone.light,
            ),
          ),
        );
  }

  // ---- Layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final partner = _journey?.partner ?? false;
    return Theme(
      data: partner ? nightTheme : dawnTheme,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color ?? theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1C6C3454),
                            blurRadius: 60,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Back from every step, so a wrong tap is
                              // easy to undo. Not on the first screen.
                              if (_journey != null || _tracking) ...[
                                _RewindButton(onPressed: _saving ? null : _back),
                                const SizedBox(width: 10),
                              ],
                              const Wordmark(size: 27),
                              const Spacer(),
                              if (_retaking)
                                IconButton(
                                  tooltip: tr('Close'),
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                            ],
                          ),
                          ...(_journey == null
                              ? (_tracking
                                  ? _chooseJourney(context)
                                  : _choose(context))
                              : _journey!.partner
                                  ? (_partnerStep == 0
                                      ? _partnerQuestions(context)
                                      : _partnerConnect(context))
                                  : _current == null
                                      ? _summary(context)
                                      : _questionView(context, _current!)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  TextStyle _headline(ThemeData theme) => headingFont(
        fontSize: 27,
        height: 1.2,
        color: theme.colorScheme.onSurface,
      );

  TextStyle? _muted(ThemeData theme) => theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      );

  /// Screen 1: two clear choices. Nothing is chosen for them.
  List<Widget> _choose(BuildContext context) {
    final theme = Theme.of(context);
    final partner = journeys.firstWhere((journey) => journey.partner);
    return [
      const SizedBox(height: 25),
      Text(tr('How will you use MoonCycle?'), style: _headline(theme)),
      const SizedBox(height: 14),
      _Option(
        title: 'Track my cycle',
        subtitle: 'Periods, symptoms and fertility, all in one place.',
        icon: Icons.calendar_month_outlined,
        trailing: Icons.female,
        trailingColor: _femalePink,
        selected: false,
        onTap: () => setState(() => _tracking = true),
      ),
      _PartnerChoice(onTap: () => _begin(partner)),
    ];
  }

  /// After "Track my cycle": which of her journeys.
  List<Widget> _chooseJourney(BuildContext context) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 20),
      Text(tr('What would you like MoonCycle to help with?'),
          style: _headline(theme)),
      const SizedBox(height: 14),
      for (final journey in journeys)
        if (!journey.hidden && !journey.partner)
          _Option(
            title: journey.name,
            subtitle: journey.category,
            selected: false,
            onTap: () => _begin(journey),
          ),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerLeft,
        child: _Button(label: tr('Back'), secondary: true, onPressed: _back),
      ),
    ];
  }

  // ---- Her partner: two screens, in his Night colours ----------------------

  // Pick any; "All of the above" is added under the list.
  static const _partnerUnderstand = [
    'When her period is coming',
    "How she's feeling",
    'How to support her day to day',
  ];

  Widget _partnerHeader(ThemeData theme, int step, String title, String lead) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _Progress(count: 2, current: step),
          const SizedBox(height: 10),
          Text(
            trf('{n} of {total}', {'n': step + 1, 'total': 2}),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Text(tr(title), style: _headline(theme)),
          const SizedBox(height: 6),
          Text(tr(lead), style: _muted(theme)),
        ],
      );

  Widget _partnerQuestion(ThemeData theme, String number, String id,
      String text, List<String> options) {
    final value = _answers[id];
    final chosen = value is List ? value.whereType<String>().toSet() : <String>{};
    final all = options.every(chosen.contains);
    // Saved in the order shown; nothing saved when nothing is ticked.
    void save(Set<String> next) => setState(() {
          if (next.isEmpty) {
            _answers.remove(id);
          } else {
            _answers[id] = [for (final o in options) if (next.contains(o)) o];
          }
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('$number. ${tr(text)}', style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(tr('Choose any'), style: _muted(theme)),
        const SizedBox(height: 6),
        for (final option in options)
          _Option(
            title: option,
            multi: true,
            selected: chosen.contains(option),
            onTap: () => save(
              chosen.contains(option)
                  ? ({...chosen}..remove(option))
                  : {...chosen, option},
            ),
          ),
        _Option(
          title: 'All of the above',
          multi: true,
          selected: all,
          onTap: () => save(all ? <String>{} : options.toSet()),
        ),
      ],
    );
  }

  /// Question 2: how funny his tips are. One choice; skipping it keeps "a
  /// little humour" and his home screen asks again.
  Widget _partnerToneQuestion(ThemeData theme) {
    final chosen = _answers['tone'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('2. ${tr('How do you like your tips?')}',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(tr('Choose one'), style: _muted(theme)),
        const SizedBox(height: 6),
        for (final tone in PartnerTone.values)
          _Option(
            title: tone.label,
            subtitle: tone.hint,
            radio: true,
            selected: chosen == tone.name,
            onTap: () => setState(() {
              if (chosen == tone.name) {
                _answers.remove('tone');
              } else {
                _answers['tone'] = tone.name;
              }
            }),
          ),
      ],
    );
  }

  /// 1 of 2: two quick questions, both optional, nothing chosen for him.
  List<Widget> _partnerQuestions(BuildContext context) {
    final theme = Theme.of(context);
    return [
      _partnerHeader(theme, 0, 'Support starts with understanding',
          'Two quick questions to make MoonCycle yours.'),
      _partnerQuestion(theme, '1', 'understand',
          'What would you like to understand better?', _partnerUnderstand),
      _partnerToneQuestion(theme),
      const SizedBox(height: 22),
      Row(
        children: [
          _Button(label: tr('Back'), secondary: true, onPressed: _back),
          const SizedBox(width: 9),
          Expanded(
            child: _Button(
              label: tr('Continue →'),
              onPressed: () => setState(() {
                _partnerStep = 1;
                _error = null;
              }),
            ),
          ),
        ],
      ),
    ];
  }

  /// 2 of 2: connect with her code, or send her an invitation from his own
  /// phone (WhatsApp, SMS, email...). MoonCycle sends nothing itself.
  List<Widget> _partnerConnect(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(18);
    BoxDecoration card() => BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: radius,
        );
    return [
      _partnerHeader(theme, 1, 'Connect with your partner',
          "Choose how you'd like to connect."),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Have an invitation code?'),
                style: _headline(theme).copyWith(fontSize: 21)),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: !_saving && !_connected,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 4),
              decoration: InputDecoration(
                hintText: tr('Enter her code'),
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  letterSpacing: 0,
                  color: scheme.onSurfaceVariant,
                ),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _joinPartner(),
            ),
            const SizedBox(height: 12),
            if (_connected)
              Row(
                children: [
                  Icon(Icons.check_circle, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('Connected with her.'))),
                ],
              )
            else
              _Button(
                label: _saving ? tr('Connecting…') : tr('Connect'),
                onPressed: _saving ? null : _joinPartner,
              ),
          ],
        ),
      ),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error, style: TextStyle(color: scheme.error)),
        ),
      if (!_connected) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(tr('or'), style: _muted(theme)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Invite her'),
                  style: _headline(theme).copyWith(fontSize: 21)),
              const SizedBox(height: 6),
              Text(
                tr('Send her a message from your phone. She creates a code on '
                    'her Partner tab and sends it back to you.'),
                style: _muted(theme),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(color: scheme.primary),
                  foregroundColor: scheme.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: sharePartnerInvite,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(tr('Send invitation')),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: radius,
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr("You'll only see what she chooses to share. She can stop "
                    'sharing at any time.'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (_connected)
        _Button(
          label: tr('Start using MoonCycle'),
          onPressed: _saving ? null : _finish,
        )
      else
        Center(
          child: TextButton(
            onPressed: _saving ? null : _finish,
            child: Text(
              tr('Skip for now'),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _questionView(BuildContext context, QuizQuestion question) {
    final theme = Theme.of(context);
    final journey = _journey!;
    final total = _questions.length;
    final optional = _extrasAdded && _step >= journey.questions.length;
    final last = _step == total - 1;
    final canFinishLater = !journey.partner &&
        _step >= _finishLaterFrom &&
        question.kind != QuizKind.consent;
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);

    return [
      const SizedBox(height: 20),
      _Progress(count: total, current: _step),
      const SizedBox(height: 10),
      Text(
        '${tr(journey.name)} · ${optional ? tr('Optional preferences · ') : ''}'
        '${trf('Question {n} of {total}', {'n': _step + 1, 'total': total})}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(tr(question.text), style: _headline(theme)),
      const SizedBox(height: 4),
      for (final (title, body) in quizNotes(question))
        _InfoBox(title: title, body: body),
      if (journey.partner && _step >= 1)
        _InfoBox(
          title: tr('Privacy first'),
          body: tr('She decides whether to connect and exactly which cycle, '
              'mood or pain details to share. Choosing an alert here does '
              'not grant access or send any notification.'),
        ),
      const SizedBox(height: 8),
      Text(
        tr('Choose the answer that feels right for you. You can skip any '
        'question.'),
        style: _muted(theme),
      ),
      const SizedBox(height: 6),
      ..._input(context, question),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ),
      const SizedBox(height: 22),
      Row(
        children: [
          _Button(label: tr('Back'), secondary: true, onPressed: _back),
          const SizedBox(width: 9),
          Expanded(
            child: _Button(
              label: last ? tr('See my summary') : tr('Continue →'),
              onPressed: _next,
            ),
          ),
        ],
      ),
      Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: _skip,
              child: Text(tr('Skip for now'), style: muted),
            ),
            if (canFinishLater)
              TextButton(
                onPressed: _finishLater,
                child: Text(tr('Finish the rest later'), style: muted),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _input(BuildContext context, QuizQuestion question) {
    final theme = Theme.of(context);
    final answer = _answers[question.id];

    switch (question.kind) {
      case QuizKind.consent:
        return _consentInput(context);

      case QuizKind.multi:
        final chosen = answer is List ? answer : const [];
        return [
          for (final option in question.options)
            _Option(
              title: option,
              multi: true,
              selected: chosen.contains(option),
              onTap: () => _toggle(question, option),
            ),
        ];

      case QuizKind.date:
        final date = answer is String && _isIsoDate(answer)
            ? DateFormat('d MMMM yyyy').format(DayKey.parse(answer).toDateTime())
            : null;
        return [
          _Option(
            title: date ?? 'Choose a date',
            icon: Icons.calendar_today_outlined,
            selected: date != null,
            onTap: () => _pickDate(question),
          ),
          for (final option in question.options)
            _Option(
              title: option,
              selected: answer == option,
              onTap: () => _pick(question, option),
            ),
        ];

      case QuizKind.days:
        return [
          const SizedBox(height: 6),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: question.id == 'cycleLength'
                  ? tr('Enter number of days (typically 21–35)')
                  : tr('Enter number of days'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) {
              if (question.options.contains(_answers[question.id])) {
                setState(() => _answers.remove(question.id));
              }
            },
          ),
          for (final option in question.options)
            _Option(
              title: option,
              selected: answer == option,
              onTap: () => _pick(question, option),
            ),
        ];

      case QuizKind.single:
        return [
          for (final option in question.options)
            _Option(
              title: option,
              selected: answer == option,
              onTap: () => _pick(question, option),
            ),
          if (question.id == 'connect' &&
              answer == 'I have an invitation code') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              enabled: !_saving && !_connected,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 4),
              decoration: InputDecoration(
                hintText: tr('ABCD2345'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_connected)
              Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(tr('Connected with her.')),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _saving ? null : _joinPartner,
                  child: Text(_saving ? tr('Connecting…') : tr('Connect')),
                ),
              ),
          ],
          if (question.id == 'connect' &&
              answer == 'Send a connection invitation') ...[
            _InfoBox(
              title: tr('How connecting works'),
              body: tr('She creates a code in her MoonCycle app (Partner tab) and '
                  'sends it to you. Send her this message to ask for it:'),
            ),
            _StatusBox(text: tr(_inviteMessage)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(
                    ClipboardData(text: tr(_inviteMessage)),
                  );
                  messenger.showSnackBar(
                    SnackBar(content: Text(tr('Message copied'))),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
                label: Text(tr('Copy message')),
              ),
            ),
          ],
        ];
    }
  }

  List<Widget> _consentInput(BuildContext context) {
    final theme = Theme.of(context);
    final consent = _consent;
    final inviting = consent['connect'] == 'yes';
    final share = (consent['share'] as List).whereType<String>().toList();

    return [
      _InfoBox(
        title: tr('Your body. Your choice.'),
        body: tr('Nothing is shared by default. You can connect accounts without '
            'sharing health information, choose individual categories, and '
            'withdraw access at any time. Your partner must also accept the '
            'invitation.'),
      ),
      _Option(
        title: tr('Keep my information private'),
        subtitle: tr('Do not invite a partner or share any health updates.'),
        radio: true,
        selected: !inviting,
        onTap: () => _setConsent('no', const []),
      ),
      _Option(
        title: "I'd like to invite my partner",
        subtitle: tr('I will choose exactly what can be shared.'),
        radio: true,
        selected: inviting,
        onTap: () => _setConsent('yes', inviting ? share : const []),
      ),
      if (inviting) ...[
        _InfoBox(
          title: tr('Choose what to share'),
          body: tr('Tick only what feels comfortable. No boxes are preselected.'),
        ),
        for (final (key, title, subtitle) in sharingCategories)
          _Option(
            title: title,
            subtitle: subtitle,
            multi: true,
            selected: share.contains(key),
            onTap: () => _toggleShare(key),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            tr('Choosing a category allows only that type of update. Mood and '
            'pain show what you log for the day; support requests go only '
            'when you send one. You can change or revoke access at any time '
            'on the Partner tab.'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
      _StatusBox(
        text: inviting
            ? tr('Next, the Partner tab gives you the code your partner needs. '
                'Nothing is shared until they enter it.')
            : tr('Private by default. You can set up sharing later.'),
      ),
    ];
  }

  List<Widget> _summary(BuildContext context) {
    final theme = Theme.of(context);
    final journey = _journey!;
    final rows = journey.partner ? _partnerRows() : _trackerRows();

    return [
      const SizedBox(height: 25),
      Text(
        tr('YOUR MOONCYCLE EXPERIENCE'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 6),
      Text(tr(journey.name), style: _headline(theme)),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr("What's set up"),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            for (final (icon, text) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon,
                        size: 18, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(tr('Your answers'), style: theme.textTheme.titleMedium),
      for (final question in _questions)
        if (_answers[question.id] case final answer?)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(question.text), style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(_describe(answer), style: _muted(theme)),
              ],
            ),
          ),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ),
      const SizedBox(height: 22),
      Row(
        children: [
          _Button(
            label: tr('Back'),
            secondary: true,
            onPressed: _saving
                ? null
                : () => setState(() {
                      _step = _resumeAt ?? _questions.length - 1;
                      _resumeAt = null;
                      _syncDays();
                    }),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _Button(
              label: _saving ? tr('Saving…') : tr('Start using MoonCycle'),
              onPressed: _saving ? null : _finish,
            ),
          ),
        ],
      ),
      if (journey.partner && !_extrasAdded && journey.extras.isNotEmpty)
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _extrasAdded = true;
              _syncDays();
            }),
            child: Text(tr('Would you like to personalise more? (optional)')),
          ),
        ),
      Center(
        child: TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                    _journey = null;
                    _answers.clear();
                    _extrasAdded = false;
                    _resumeAt = null;
                  }),
          child: Text(
            tr('Choose a different journey'),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    ];
  }

  String _describe(Object answer) {
    if (answer is String && _isIsoDate(answer)) {
      return DateFormat('d MMMM yyyy').format(DayKey.parse(answer).toDateTime());
    }
    if (answer is List) return answer.map((a) => tr('$a')).join(', ');
    if (answer is Map) {
      if (answer['connect'] != 'yes') return tr('Keep private');
      final share = (answer['share'] as List).whereType<String>().toList();
      final names = [
        for (final (key, title, _) in sharingCategories)
          if (share.contains(key)) tr(title).toLowerCase(),
      ];
      return trf('Invite partner; share: {what}', {
        'what': names.isEmpty ? tr('no health categories') : names.join(', '),
      });
    }
    return tr('$answer');
  }

  /// Built with the real engine, so the dates match what the home screen
  /// will show.
  List<(IconData, String)> _trackerRows() {
    final plan = _plan();
    final journey = _journey!;
    final format = DateFormat('d MMMM');
    final rows = <(IconData, String)>[
      (
        Icons.explore_outlined,
        trf('Journey: {name}. You can change it any time in Settings.',
            {'name': tr(journey.name)}),
      ),
    ];

    final lastPeriod = plan.lastPeriod;
    if (journey.id != 'menopause') {
      final status = CycleEngine(
        defaultCycleLength: plan.cycleLength ?? 28,
        defaultPeriodLength: plan.periodLength ?? 5,
      ).status([
        ...?ref.read(logsProvider).value,
        if (lastPeriod != null)
          DayLog(
            date: lastPeriod,
            flow: FlowIntensity.medium,
            isPeriodStartOverride: true,
          ),
      ]);
      final next = status.predictedNextStart;
      if (next != null) {
        final rough = plan.regularity == CycleRegularity.unpredictable ||
            plan.regularity == CycleRegularity.unsure ||
            plan.cycleLength == null;
        rows.add((
          Icons.calendar_month_outlined,
          trf(
            rough
                ? 'Next period expected around {date}. Treat it as rough for '
                    'the first few cycles.'
                : 'Next period expected around {date}.',
            {'date': format.format(next.toDateTime())},
          ),
        ));
      }

      final blockedBy = plan.blockedBy;
      final start = status.fertileWindowStart;
      final end = status.fertileWindowEnd;
      if (blockedBy != null) {
        rows.add((
          Icons.visibility_off_outlined,
          trf(
            'Fertile days hidden: calendar estimates do not apply with '
            '{reason}.',
            {'reason': tr(blockedBy)},
          ),
        ));
      } else if (plan.showFertileDays && start != null && end != null) {
        rows.add((
          Icons.visibility_outlined,
          trf(
            'Estimated fertile days this cycle: {start} to {end}. An '
            'estimate, not contraception.',
            {
              'start': format.format(start.toDateTime()),
              'end': format.format(end.toDateTime()),
            },
          ),
        ));
      } else if (!plan.showFertileDays) {
        rows.add((
          Icons.visibility_off_outlined,
          tr('Fertile days hidden. You can turn them on in Settings.'),
        ));
      }
    }

    final reminders = [
      if (plan.periodReminder == true) tr('a reminder before your period'),
      if (plan.dailyReminder == true) tr('a daily check-in'),
    ];
    if (plan.periodReminder != null || plan.dailyReminder != null) {
      rows.add((
        Icons.notifications_outlined,
        reminders.isEmpty
            ? tr('No reminders.')
            : trf('Reminders: {list}.',
                {'list': reminders.join(' ${tr('and')} ')}),
      ));
    }

    if (plan.tryingSince == 'year') {
      rows.add((
        Icons.medical_services_outlined,
        // NHS guidance: https://www.nhs.uk/conditions/infertility/
        tr('The NHS suggests seeing a GP after a year of trying, or sooner '
            "if you're 36 or over. Worth a conversation when you feel ready."),
      ));
    }

    final sharingNow =
        ref.read(settingsProvider).value?.sharing.enabled ?? false;
    if (plan.inviting) {
      final names = [
        for (final (key, title, _) in sharingCategories)
          if (plan.share.contains(key)) tr(title).toLowerCase(),
      ];
      rows.add((
        Icons.favorite_border,
        trf(
          'Partner sharing: {what}. Get the code for your partner on the '
          'Partner tab.',
          {
            'what': names.isEmpty
                ? tr('connected, no health details')
                : names.join(', '),
          },
        ),
      ));
    } else if (!plan.consentAnswered && sharingNow) {
      rows.add((
        Icons.favorite_border,
        tr('Partner sharing stays as you set it on the Partner tab.'),
      ));
    } else {
      rows.add((
        Icons.lock_outline,
        tr('Private: nothing is shared with anyone.'),
      ));
    }

    if (_resumeAt case final at?) {
      final left = _questions.length - at;
      rows.add((
        Icons.more_time,
        trCount(
          left,
          '{n} more question for later. Pick up where you left off from '
          'Settings.',
          '{n} more questions for later. Pick up where you left off from '
          'Settings.',
        ),
      ));
    }
    return rows;
  }

  List<(IconData, String)> _partnerRows() => [
        _connected
            ? (Icons.link, tr('Connected with her.'))
            : (
                Icons.link_off,
                tr('Not connected yet. You can enter her code on your home '
                    'screen once she sends it.'),
              ),
        (
          Icons.tune,
          tr('Your tips come with "a little humour" until you change it. Set '
              'her name and the tone from the menu on your home screen.'),
        ),
        (
          Icons.lock_outline,
          tr('You only ever see what she chooses to share, and she can stop '
              'sharing at any time.'),
        ),
      ];
}

/// What the answers turn into.
class _Plan {
  const _Plan({
    required this.consentAnswered,
    required this.goal,
    required this.lastPeriod,
    required this.periodLength,
    required this.cycleLength,
    required this.regularity,
    required this.blockedBy,
    required this.showFertileDays,
    required this.usualSymptoms,
    required this.tryingSince,
    required this.trackedSigns,
    required this.focus,
    required this.periodReminder,
    required this.dailyReminder,
    required this.inviting,
    required this.share,
  });

  final TrackingGoal goal;
  final DayKey? lastPeriod;
  final int? periodLength;
  final int? cycleLength;
  final CycleRegularity? regularity;

  /// Why fertile days are hidden, when a health circumstance rules them out.
  final String? blockedBy;
  final bool showFertileDays;
  final List<String> usualSymptoms;
  final String? tryingSince;
  final List<String> trackedSigns;
  final List<String> focus;

  /// Null when the journey did not ask, so the current setting stays.
  final bool? periodReminder;
  final bool? dailyReminder;

  /// False when she skipped the consent question or left it for later;
  /// partner sharing then stays as it is.
  final bool consentAnswered;
  final bool inviting;
  final Set<String> share;
}

class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Container(
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i <= current ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

/// One answer. Single choices highlight; [multi] answers show a tick box;
/// [radio] answers show a round selector.
class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.multi = false,
    this.radio = false,
    this.icon,
    this.trailing,
    this.trailingColor,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool multi;
  final bool radio;
  final IconData? icon;

  /// A symbol on the right, such as ♀ on "Track my cycle".
  final IconData? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(15);
    final leading = icon ??
        (multi
            ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
            : radio
                ? (selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked)
                : null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  Icon(leading, size: 20, color: scheme.primary),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(title),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: subtitle == null ? null : FontWeight.w600,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          tr(subtitle!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  Icon(trailing, size: 30, color: trailingColor ?? scheme.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The symbols on the first screen: soft pink for her, light blue for him.
const _femalePink = Color(0xFFE5809A);
const _maleBlue = Color(0xFF8CC4FF);

/// "I'm her partner" on the first screen, in the partner's Night colours so
/// it reads at once as a different side of the app.
class _PartnerChoice extends StatelessWidget {
  const _PartnerChoice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(15);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Material(
        color: MoonColors.nightCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: MoonColors.nightLine),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.favorite_border,
                    size: 20, color: MoonColors.moonGold),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr("I'm her partner"),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: MoonColors.nightInk,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tr('Understand her cycle and discover little ways to '
                            'be there for her.'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: MoonColors.nightMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.male, size: 30, color: _maleBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back, as a small round rewind button in the top-left corner.
class _RewindButton extends StatelessWidget {
  const _RewindButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr('Back'),
      child: Material(
        color: scheme.primaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(Icons.fast_rewind_rounded, size: 20, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(title),
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            tr(body),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  const _StatusBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
      backgroundColor: secondary ? scheme.surfaceContainerHighest : null,
      foregroundColor: secondary ? scheme.onSurface : null,
    );
    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
