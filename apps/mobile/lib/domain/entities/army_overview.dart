class ArmyOverview {
  const ArmyOverview({
    required this.reserveBs,
    required this.reserveCount,
    required this.warriorCount,
    required this.supportCount,
  });

  final int reserveBs;
  final int reserveCount;
  final int warriorCount;
  final int supportCount;

  static const empty = ArmyOverview(
    reserveBs: 0,
    reserveCount: 0,
    warriorCount: 0,
    supportCount: 0,
  );

  ArmyOverview copyWith({
    int? reserveBs,
    int? reserveCount,
    int? warriorCount,
    int? supportCount,
  }) {
    return ArmyOverview(
      reserveBs: reserveBs ?? this.reserveBs,
      reserveCount: reserveCount ?? this.reserveCount,
      warriorCount: warriorCount ?? this.warriorCount,
      supportCount: supportCount ?? this.supportCount,
    );
  }
}

