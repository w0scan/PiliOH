class Subtitle {
  final String first;
  final String second;

  const Subtitle.raw([this.first = '', this.second = '']);

  Subtitle(String first, String second)
    : first = first.trim(),
      second = second.trim();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Subtitle && first == other.first && second == other.second;
  }

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() {
    if (second.isEmpty) return first;
    if (first.isEmpty) return second;
    return '$first\n$second';
  }

  Subtitle copyWith({String? first, String? second}) =>
      Subtitle.raw(first?.trim() ?? this.first, second?.trim() ?? this.second);

  bool get isEmpty => first.isEmpty && second.isEmpty;
}
