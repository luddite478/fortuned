import 'dart:math';

class ThreadNameGenerator {
  // Emoji pool for thread names
  static const List<String> _emojiPool = [
    // nature
    "🌲","🌳","🌴","🌵","🌾","🍀","🌸","🌼","🌻","🌺","🍄","🌊","⛰️","🏞️","🌅","🌄","🌠","☀️","🌤️","🌧️","⛈️","🌩️","🌪️","❄️","🦁","🐯","🐻","🐼","🐨","🐸","🐍","🦅","🦉","🦋","🐞","🐝","🐌",
    // heroes
    "⚔️","🛡️","🏹","🗡️","🪄","🪓","🪙","💎","🪶","👑","🏰","🏯","🐉","🧙‍♂️","🧝‍♀️","🧛‍♂️","🧟‍♀️","🧞‍♂️","🧜‍♀️","🔥","💫","✨"
  ];

  /// Generate a consistent 3-emoji name based on a seed string (like thread ID)
  static String generate(String seed) {
    final random = Random(seed.hashCode);
    final emojis = <String>[];
    
    for (int i = 0; i < 3; i++) {
      emojis.add(_emojiPool[random.nextInt(_emojiPool.length)]);
    }
    
    return emojis.join(' ');
  }
}

