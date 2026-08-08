enum UnitType { warrior, support }

enum UnitRarity { standard, advanced, prototype }

enum SupportSkill { scout, jammer, decoy }

class ArmyBucket {
  const ArmyBucket({
    required this.type,
    required this.rarity,
    required this.count,
    required this.totalBs,
    this.skill,
  });

  final UnitType type;
  final UnitRarity rarity;
  final SupportSkill? skill;
  final int count;
  final int totalBs;
}
