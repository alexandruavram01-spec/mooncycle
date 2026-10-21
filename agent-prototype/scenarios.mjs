// Invented situations only. Never paste a real person's log in here: the
// privacy policy promises that personal data is not sent to AI services.
//
// Each summary is what her phone would work out on that day (the same facts
// the opening lines use), and `cards` is what the phone's rules would choose.
// The agent may only rephrase these; it never picks the medical content.

export const scenarios = [
  {
    id: 'heavy-painful-period',
    title: 'Day 2 of her period, cramps and a heavy flow',
    cards: ['C01'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 2,
      part_of_cycle: 'her period',
      logged_today: ['cramps', 'a heavy flow'],
      her_history: 'Her 3 recorded periods lasted between 4 and 6 days.',
    },
  },
  {
    id: 'headache-before-period',
    title: 'Headache 3 days running, period estimated in 2 days',
    cards: ['L05'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 26,
      part_of_cycle: 'the days before her period',
      period_estimate: 'estimated to start on Thursday, in 2 days',
      logged_today: ['a headache'],
      logged_recently: 'A headache on 3 days in a row.',
      her_history:
        'Headaches around the days before her period in 3 of her last 4 recorded cycles.',
    },
  },
  {
    id: 'ttc-stretchy-discharge',
    title: 'Trying to conceive, egg-white discharge on day 13',
    cards: ['I30'],
    summary: {
      goal: 'trying to conceive',
      fertility_content: 'on',
      cycle_day: 13,
      part_of_cycle: 'the middle of her cycle',
      estimated_fertile_window: '12 to 17 November',
      logged_today: ['egg-white discharge'],
    },
  },
  {
    id: 'premenstrual-mood-pattern',
    title: 'Mood changes before her period, 3 of 4 cycles',
    cards: ['L08'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 24,
      part_of_cycle: 'the days before her period',
      period_estimate: 'estimated to start in 4 days',
      logged_today: ['feeling irritable', 'feeling sad'],
      her_history:
        'Mood changes in the last 7 days before her period in 3 of her last 4 recorded cycles.',
    },
  },
  {
    id: 'good-day',
    title: 'A good day on day 9',
    cards: ['L06'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 9,
      part_of_cycle: 'the days after her period',
      logged_today: ['feeling happy', 'feeling confident'],
    },
  },
  {
    id: 'tired-short-nights',
    title: 'Tired after 3 short nights',
    cards: ['C06'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 19,
      part_of_cycle: 'the days before her period',
      logged_today: ['tiredness'],
      sleep: '5 hours last night; under 6 hours on each of the last 3 nights.',
    },
  },
  {
    id: 'ttc-period-started',
    title: 'Trying to conceive, her period has started',
    cards: ['M01'],
    summary: {
      goal: 'trying to conceive',
      fertility_content: 'on',
      cycle_day: 1,
      part_of_cycle: 'her period, which started today',
      her_history:
        'Her last recorded cycle was 27 days. Across 4 completed cycles, the median was 28 days.',
    },
  },
  {
    id: 'after-estimate',
    title: 'Period not logged, 4 days after the estimate',
    cards: ['I22'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 32,
      period_estimate: 'its estimated start was 4 days ago; no period logged yet',
    },
  },
  {
    id: 'bloating-cravings',
    title: 'Bloating and cravings 5 days before her period',
    cards: ['C04'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 23,
      part_of_cycle: 'the days before her period',
      period_estimate: 'estimated to start on Sunday, in 5 days',
      logged_today: ['bloating', 'food cravings'],
    },
  },
  {
    id: 'hot-flush',
    title: 'A hot flush, logged for the first time',
    cards: ['L12'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 11,
      part_of_cycle: 'the days after her period',
      logged_today: ['a hot flush'],
      logged_recently: 'The first time she has logged a hot flush in MoonCycle.',
    },
  },
  {
    id: 'low-desire',
    title: 'Low desire on day 16',
    cards: ['L19'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 16,
      part_of_cycle: 'the days after her period',
      logged_today: ['low desire'],
    },
  },
  {
    id: 'lighter-days',
    title: 'Day 4 of her period, medium flow',
    cards: ['M02'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 4,
      part_of_cycle: 'her period',
      logged_today: ['a medium flow'],
      her_history: 'Her 3 recorded periods lasted between 4 and 6 days.',
    },
  },
  {
    id: 'cramps-mid-cycle',
    title: 'Cramps on day 15, away from her period',
    cards: ['L01'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 15,
      part_of_cycle: 'the middle of her cycle',
      logged_today: ['cramps'],
    },
  },
  {
    id: 'busy-day',
    title: 'Several things logged, one card about bloating',
    cards: ['I17'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 25,
      part_of_cycle: 'the days before her period',
      period_estimate: 'estimated to start in 3 days',
      logged_today: ['a headache', 'bloating'],
      sleep: '5.5 hours last night.',
    },
  },
  {
    id: 'hormonal-contraception',
    title: 'On hormonal contraception, nothing logged today',
    cards: ['NEW02'],
    summary: {
      goal: 'tracking her cycle',
      contraception: 'hormonal, from her answers when she joined',
      note: 'Cycle-phase and ovulation estimates are switched off for her.',
    },
  },
  {
    id: 'new-user',
    title: 'Brand new: first period logged a week ago',
    cards: ['I06'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 7,
      part_of_cycle: 'the days after her period',
      her_history: 'This is her first cycle in MoonCycle; no completed cycles yet.',
    },
  },
  {
    id: 'ttc-over-a-year',
    title: 'Trying to conceive for over a year',
    cards: ['I28'],
    summary: {
      goal: 'trying to conceive',
      fertility_content: 'on',
      trying_for: 'over 12 months, from her answers when she joined',
      age: 'not known',
      cycle_day: 8,
    },
  },
  {
    id: 'low-mood-lingering',
    title: 'Feeling sad on 5 days over the past 16 days',
    cards: ['L07'],
    summary: {
      goal: 'tracking her cycle',
      cycle_day: 21,
      part_of_cycle: 'the days before her period',
      logged_today: ['feeling sad'],
      logged_recently: 'Feeling sad or anxious on 5 days over the past 16 days.',
    },
  },
];
