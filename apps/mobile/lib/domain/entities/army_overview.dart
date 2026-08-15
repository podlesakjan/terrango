class SoldierBucketSummary {
  const SoldierBucketSummary({
    required this.type,
    required this.rarity,
    required this.skill,
    required this.count,
    required this.totalBs,
  });

  final String type;
  final String rarity;
  final String? skill;
  final int count;
  final int totalBs;

  int get averageBs => count <= 0 ? 0 : (totalBs / count).round();

  String get key => '$type|$rarity|${skill ?? ''}';

  factory SoldierBucketSummary.fromServer(Map<String, dynamic> data) {
    final skill = data['skill']?.toString().trim();
    return SoldierBucketSummary(
      type: (data['type'] as String? ?? '').toUpperCase(),
      rarity: (data['rarity'] as String? ?? '').toUpperCase(),
      skill: skill == null || skill.isEmpty ? null : skill.toUpperCase(),
      count: (data['count'] as num?)?.toInt() ?? 0,
      totalBs: (data['totalBs'] as num?)?.toInt() ?? 0,
    );
  }
}

class PatrolSummary {
  const PatrolSummary({
    required this.h3Index,
    required this.territoryName,
    required this.soldierCount,
    required this.totalBs,
  });

  final String h3Index;
  final String territoryName;
  final int soldierCount;
  final int totalBs;

  factory PatrolSummary.fromServer(Map<String, dynamic> data) {
    return PatrolSummary(
      h3Index: (data['h3Index'] as String? ?? '').trim(),
      territoryName: (data['territoryName'] as String? ?? 'Unknown Territory').trim(),
      soldierCount: (data['soldierCount'] as num?)?.toInt() ?? 0,
      totalBs: (data['totalBs'] as num?)?.toInt() ?? 0,
    );
  }
}

class ArmyOverview {
  const ArmyOverview({
    required this.reserveBs,
    required this.reserveCount,
    required this.warriorCount,
    required this.supportCount,
    required this.patrolCount,
    required this.reserves,
    required this.patrols,
  });

  final int reserveBs;
  final int reserveCount;
  final int warriorCount;
  final int supportCount;
  final int patrolCount;
  final List<SoldierBucketSummary> reserves;
  final List<PatrolSummary> patrols;

  static const empty = ArmyOverview(
    reserveBs: 0,
    reserveCount: 0,
    warriorCount: 0,
    supportCount: 0,
    patrolCount: 0,
    reserves: <SoldierBucketSummary>[],
    patrols: <PatrolSummary>[],
  );

  ArmyOverview copyWith({
    int? reserveBs,
    int? reserveCount,
    int? warriorCount,
    int? supportCount,
    int? patrolCount,
    List<SoldierBucketSummary>? reserves,
    List<PatrolSummary>? patrols,
  }) {
    return ArmyOverview(
      reserveBs: reserveBs ?? this.reserveBs,
      reserveCount: reserveCount ?? this.reserveCount,
      warriorCount: warriorCount ?? this.warriorCount,
      supportCount: supportCount ?? this.supportCount,
      patrolCount: patrolCount ?? this.patrolCount,
      reserves: reserves ?? this.reserves,
      patrols: patrols ?? this.patrols,
    );
  }

  factory ArmyOverview.fromServer(Map<String, dynamic> data) {
    final reserves = (data['reserves'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(SoldierBucketSummary.fromServer)
        .where((bucket) => bucket.count > 0)
        .toList(growable: false)
      ..sort((left, right) => right.totalBs.compareTo(left.totalBs));

    final patrols = (data['patrols'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(PatrolSummary.fromServer)
        .where((patrol) => patrol.soldierCount > 0)
        .toList(growable: false)
      ..sort((left, right) => right.totalBs.compareTo(left.totalBs));

    var reserveBs = 0;
    var reserveCount = 0;
    var warriorCount = 0;
    var supportCount = 0;

    for (final bucket in reserves) {
      reserveBs += bucket.totalBs;
      final count = bucket.count;
      reserveCount += count;
      if (bucket.type == 'WARRIOR') {
        warriorCount += count;
      } else if (bucket.type == 'SUPPORT') {
        supportCount += count;
      }
    }

    return ArmyOverview(
      reserveBs: reserveBs,
      reserveCount: reserveCount,
      warriorCount: warriorCount,
      supportCount: supportCount,
      patrolCount: patrols.fold<int>(0, (sum, patrol) => sum + patrol.soldierCount),
      reserves: List<SoldierBucketSummary>.unmodifiable(reserves),
      patrols: List<PatrolSummary>.unmodifiable(patrols),
    );
  }
}

