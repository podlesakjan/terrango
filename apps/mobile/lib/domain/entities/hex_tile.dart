enum HexState { free, owned, enemy }

class HexTile {
  const HexTile({
    required this.h3Index,
    required this.state,
    this.ownerName,
    this.hasGarrison = false,
    this.isCenter = false,
  });

  final String h3Index;
  final HexState state;
  final String? ownerName;
  final bool hasGarrison;
  final bool isCenter;
}
