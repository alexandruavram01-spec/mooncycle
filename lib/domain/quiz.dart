/// The onboarding quiz: five journeys for someone tracking her own cycle and
/// one for a partner.
///
/// The wording follows the agreed designs: "MoonCycle Final Her and Partner
/// Quiz" for her five journeys, and the five-question partner version without
/// its second question, plus its optional "personalise more" questions.
/// Changes agreed since: the age question was dropped from every journey
/// (it changed nothing), and the perimenopause, menopause and wellbeing
/// journeys are hidden until they have their own home screen.

enum QuizKind {
  /// Pick one.
  single,

  /// Pick any.
  multi,

  /// A date, or one of [QuizQuestion.options] instead.
  date,

  /// A number of days, or one of [QuizQuestion.options] instead.
  days,

  /// Whether to invite a partner, and what to share.
  consent,
}

class QuizQuestion {
  const QuizQuestion(this.id, this.text, this.kind, [this.options = const []]);

  /// Stable key the answer is stored under.
  final String id;
  final String text;
  final QuizKind kind;
  final List<String> options;
}

class Journey {
  const Journey({
    required this.id,
    required this.name,
    required this.category,
    required this.questions,
    this.extras = const [],
    this.partner = false,
    this.hidden = false,
  });

  /// Not offered yet: its own home screen does not exist, so it would land
  /// on the cycle-tracking home, which does not fit it.
  final bool hidden;

  final String id;
  final String name;
  final String category;
  final List<QuizQuestion> questions;

  /// Optional questions offered on the summary ("personalise more").
  final List<QuizQuestion> extras;
  final bool partner;
}

const _consent = QuizQuestion(
  'consent',
  'Would you like to share selected updates with your partner?',
  QuizKind.consent,
);

const journeys = <Journey>[
  Journey(
    id: 'cycle',
    name: 'Understand my cycle',
    category: 'Menstrual tracking',
    questions: [
      QuizQuestion('lastPeriod', 'When did your last period start?',
          QuizKind.date, ["I'm not sure"]),
      QuizQuestion(
          'periodLength',
          'How many days does your period usually last?',
          QuizKind.single,
          ['2', '3', '4', '5', '6', '7', '8+', 'Not sure']),
      QuizQuestion('cycleLength', 'How long is your usual menstrual cycle?',
          QuizKind.days, ['Varies', 'Not sure']),
      QuizQuestion('predictability', 'How predictable are your periods?',
          QuizKind.single, [
        'Very regular',
        'Mostly regular',
        'Sometimes early/late',
        'Unpredictable',
        'Not sure',
      ]),
      QuizQuestion('symptoms', 'What symptoms would you like to track?',
          QuizKind.multi, [
        'Cramps',
        'Bloating',
        'Mood changes',
        'Headaches',
        'Breast tenderness',
        'Fatigue',
        'None',
        'Other',
      ]),
      QuizQuestion('helpWith', 'What would you like help with?',
          QuizKind.multi, [
        'Period predictions',
        'Cycle phases',
        'Mood and symptoms',
        'Fertility awareness',
        'General wellbeing',
      ]),
      QuizQuestion('affects', 'Is there anything that affects your periods?',
          QuizKind.single, [
        'Hormonal contraception',
        'Pregnant/breastfeeding',
        'Hysterectomy/ovary removal',
        'HRT (Hormone Replacement Therapy)',
        'None',
        'Prefer not to say',
      ]),
      QuizQuestion('reminders', 'Would you like gentle cycle reminders?',
          QuizKind.single, [
        'Upcoming period',
        'Symptom check-ins',
        'Both',
        'No reminders',
      ]),
      _consent,
    ],
  ),
  Journey(
    id: 'fertility',
    name: 'Explore my fertility',
    category: 'Fertility and pregnancy planning',
    questions: [
      QuizQuestion('lastPeriod', 'When did your last period start?',
          QuizKind.date, ['Not sure']),
      QuizQuestion('periodLength', 'How long does your period usually last?',
          QuizKind.days, ['Not sure']),
      QuizQuestion('cycleLength', 'How long is your usual cycle?',
          QuizKind.days, ['Irregular', 'Not sure']),
      QuizQuestion('fertilityGoal', 'What is your fertility goal?',
          QuizKind.single, [
        'Understand fertility',
        'Preparing for pregnancy',
        'Trying to conceive',
      ]),
      QuizQuestion('predictability', 'How predictable are your cycles?',
          QuizKind.single,
          ['Regular', 'Sometimes vary', 'Irregular', 'Not sure']),
      QuizQuestion(
          'tryingSince',
          'If trying to conceive, how long have you been trying?',
          QuizKind.single, [
        'Not started',
        'Under 6 months',
        '6–12 months',
        'Over 12 months',
        'Prefer not to say',
      ]),
      QuizQuestion(
          'fertilitySigns',
          'Would you like to record ovulation tests or other fertility signs?',
          QuizKind.single,
          ['Yes', 'Maybe later', 'No']),
      QuizQuestion('circumstances', 'Any relevant health circumstances?',
          QuizKind.single, [
        'Pregnancy/breastfeeding',
        'Hormonal contraception',
        'Fertility treatment',
        'None',
        'Prefer not to say',
      ]),
      _consent,
    ],
  ),
  Journey(
    id: 'perimenopause',
    name: "Navigate life's changes",
    category: 'Perimenopause support',
    hidden: true,
    questions: [
      QuizQuestion('periodChanges', 'How have your periods changed?',
          QuizKind.single, [
        'No change',
        'Less predictable',
        'Heavier/lighter',
        'Less frequent',
        'Stopped',
        'Not sure',
      ]),
      QuizQuestion('lastPeriod', 'When was your last period?', QuizKind.date,
          ['Cannot remember', 'Not applicable']),
      QuizQuestion('changesNoticed', 'What changes have you noticed?',
          QuizKind.multi, [
        'Hot flushes',
        'Night sweats',
        'Sleep difficulties',
        'Mood changes',
        'Brain fog',
        'Vaginal dryness',
        'None',
        'Other',
      ]),
      QuizQuestion('supportWith', 'What would you like support with?',
          QuizKind.multi, [
        'Sleep',
        'Mood',
        'Energy',
        'Symptom patterns',
        'Menopause education',
      ]),
      QuizQuestion(
          'bleedingFactors',
          'Do any health circumstances affect your bleeding pattern?',
          QuizKind.single, [
        'Hormonal contraception',
        'HRT (Hormone Replacement Therapy)',
        'Pregnancy/breastfeeding',
        'Hysterectomy/ovary removal',
        'None',
        'Prefer not to say',
      ]),
      QuizQuestion('dailyLog', 'Would you like to log symptoms each day?',
          QuizKind.single, ['Yes', 'Sometimes', 'Not now']),
      QuizQuestion('guidance', 'What kind of guidance feels most helpful?',
          QuizKind.multi, [
        'Practical comfort tips',
        'Emotional wellbeing',
        'Understanding hormone changes',
        'All of these',
      ]),
      QuizQuestion('optionalReminders', 'Would you like optional reminders?',
          QuizKind.single, ['Daily', 'Weekly', 'None']),
      _consent,
    ],
  ),
  Journey(
    id: 'menopause',
    name: 'Embrace my next chapter',
    category: 'Menopause and beyond',
    hidden: true,
    questions: [
      QuizQuestion('lastNaturalPeriod', 'When was your last natural period?',
          QuizKind.single, [
        'Within 12 months',
        'More than 12 months',
        'Unsure',
        'Not applicable',
      ]),
      QuizQuestion('hrtOrContraception',
          'Are you using HRT or hormonal contraception?', QuizKind.single, [
        'HRT (Hormone Replacement Therapy)',
        'Hormonal contraception',
        'Both',
        'Neither',
        'Not sure',
        'Prefer not to say',
      ]),
      QuizQuestion('hysterectomy',
          'Have you had a hysterectomy or ovary removal?', QuizKind.single,
          ['Yes', 'No', 'Prefer not to say']),
      QuizQuestion('manage', 'What would you like to understand or manage?',
          QuizKind.multi, [
        'Hot flushes',
        'Sleep',
        'Mood',
        'Intimate wellbeing',
        'Energy',
        'Bone health',
      ]),
      QuizQuestion('mattersMost', 'What matters most to you now?',
          QuizKind.single, [
        'Feeling comfortable',
        'Better sleep',
        'Staying active',
        'Understanding changes',
        'General wellbeing',
      ]),
      QuizQuestion('recordSleep', 'Would you like to record sleep and energy?',
          QuizKind.single, ['Yes', 'Maybe later', 'No']),
      QuizQuestion('education', 'Would you like menopause education?',
          QuizKind.single, [
        'Short daily tips',
        'Weekly insights',
        'Only when I ask',
        'No',
      ]),
      QuizQuestion('checkInFrequency', 'How often would you like to check in?',
          QuizKind.single, ['Daily', 'Weekly', 'Only when I choose']),
      _consent,
    ],
  ),
  Journey(
    id: 'wellbeing',
    name: 'Feel more like myself',
    category: 'General wellbeing',
    hidden: true,
    questions: [
      QuizQuestion('focus', 'What would you like to focus on?',
          QuizKind.multi,
          ['Sleep', 'Energy', 'Mood', 'Stress', 'General wellbeing']),
      QuizQuestion('feeling', 'How have you been feeling lately?',
          QuizKind.single, [
        'Great',
        'Good',
        'Up and down',
        'Tired',
        'Overwhelmed',
        'Prefer not to say',
      ]),
      QuizQuestion('sleep', 'How has your sleep been?', QuizKind.single, [
        'Restful',
        'Sometimes interrupted',
        'Often difficult',
        'Prefer not to say',
      ]),
      QuizQuestion('trackCycle', 'Would you also like to track your cycle?',
          QuizKind.single, ['Yes', 'No', 'Maybe later']),
      QuizQuestion('checkIns', 'Would you like gentle reminders to check in?',
          QuizKind.single, ['Daily', 'A few times a week', 'No reminders']),
      QuizQuestion('stressIdeas',
          'Would you like ideas for easing everyday stress?', QuizKind.single,
          ['Yes', 'Maybe later', 'No']),
      QuizQuestion('trackPain', 'Would you like to track pain or discomfort?',
          QuizKind.single, ['Yes', 'Sometimes', 'No']),
      QuizQuestion('adviceStyle', 'What kind of wellbeing advice do you prefer?',
          QuizKind.multi, [
        'Gentle movement',
        'Rest and sleep',
        'Emotional support',
        'All of these',
      ]),
      _consent,
    ],
  ),
  Journey(
    id: 'partner',
    name: 'Support my partner',
    category: 'Partner education, cycle awareness and thoughtful support',
    partner: true,
    questions: [
      QuizQuestion('understand', 'What would you like to understand better?',
          QuizKind.single, [
        'Her menstrual cycle',
        'Fertility and trying for a baby',
        'Perimenopause',
        'Menopause and beyond',
        'Everyday emotional support',
        "I'm not sure",
      ]),
      QuizQuestion('connect', 'Would you like to connect your MoonCycle accounts?',
          QuizKind.single, [
        'Send a connection invitation',
        'I have an invitation code',
        'Continue without connecting',
      ]),
      QuizQuestion(
          'cycleUpdates',
          'Would you like cycle updates when your partner chooses to share them?',
          QuizKind.multi, [
        'Upcoming period reminders',
        'Period started updates',
        'Cycle phase education',
        'No cycle notifications',
      ]),
      QuizQuestion('supportTips', 'What kind of support tips would you like to receive?',
          QuizKind.multi, [
        'Comfort tips for period pain',
        'Sweet messages and gestures',
        'Mood and emotional support',
        'Practical help and rest',
        'All of these',
      ]),
    ],
    extras: [
      QuizQuestion('moodUpdates',
          'Would you like to receive mood updates when she shares them?',
          QuizKind.single, [
        'Yes, gentle mood check-ins',
        'Only when she sends an update',
        'No mood notifications',
      ]),
      QuizQuestion(
          'painUpdates',
          'Would you like to receive pain or discomfort updates when she shares them?',
          QuizKind.single, [
        'Yes, when she asks for support',
        'Yes, for shared pain check-ins',
        'No pain notifications',
      ]),
      QuizQuestion('caringMessages', 'Would you like to exchange caring messages?',
          QuizKind.single, [
        'Yes, private messages between us',
        'Yes, with suggested kind messages',
        'No messages for now',
      ]),
      QuizQuestion('notifyWhen', 'When should MoonCycle send notifications?',
          QuizKind.single, [
        'Quiet, discreet notifications',
        'Daytime only',
        'Only when I open the app',
        'No push notifications',
      ]),
      QuizQuestion('otherSupport', 'What other support would you appreciate?',
          QuizKind.multi, [
        'Simple ways to help',
        'Communication tips',
        'Weekly educational insights',
        'None for now',
      ]),
    ],
  ),
];

/// The journey saved in her profile, including hidden ones: someone who
/// chose one before it was hidden keeps it.
Journey? journeyById(String? id) {
  for (final journey in journeys) {
    if (journey.id == id) return journey;
  }
  return null;
}

/// What a partner can be allowed to see, as offered on the consent question.
/// The descriptions say what actually happens in this app.
const sharingCategories = <(String, String, String)>[
  (
    'cycle',
    'Cycle dates and estimated upcoming periods',
    'Your cycle phase and when your next period is expected.',
  ),
  ('mood', 'Mood updates', 'The mood and energy you log for the day.'),
  (
    'pain',
    'Pain and discomfort updates',
    'The pain and discomfort you log for the day.',
  ),
  (
    'requests',
    'Personal support requests',
    'Messages you choose to send, such as "A hug would help today."',
  ),
];

/// Short explanations shown under questions that use medical terms.
List<(String, String)> quizNotes(QuizQuestion question) {
  final text = '${question.text} ${question.options.join(' ')}';
  bool has(String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);

  return [
    if (has(r'\bHRT\b|Hormone Replacement Therapy'))
      (
        'What is HRT?',
        'Hormone Replacement Therapy (HRT) is a treatment that replaces '
            'hormones that decline around menopause. It may help with hot '
            'flushes, night sweats and vaginal dryness, and may come as '
            'tablets, patches, gels or sprays.',
      ),
    if (has('perimenopause'))
      (
        'What is perimenopause?',
        'The transition towards menopause, when periods and symptoms may '
            'change. Experiences vary from person to person.',
      ),
    if (has('ovulation|fertile window'))
      (
        'What does this mean?',
        'Ovulation is when an ovary releases an egg. A fertile window is an '
            'estimate of the days when pregnancy may be more likely; calendar '
            'predictions are not reliable contraception.',
      ),
    if (has('hysterectomy|ovary removal'))
      (
        'What does this mean?',
        'A hysterectomy is surgery to remove the uterus (womb). Ovary removal '
            'is a different procedure and can affect hormones and bleeding '
            'patterns.',
      ),
    if (has('menstrual cycle|usual cycle'))
      (
        'What is cycle length?',
        'The number of days from the first day of one period to the first '
            'day of the next.',
      ),
  ];
}
