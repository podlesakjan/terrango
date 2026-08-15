enum HexState { free, owned, enemy }

class HexTile {
  const HexTile({
    required this.h3Index,
    required this.state,
    this.ownerName,
    this.hasGarrison = false,
    this.isCenter = false,
    this.territoryName,
    this.color,
    this.backgroundBonusPercent,
  });

  final String h3Index;
  final HexState state;
  final String? ownerName;
  final bool hasGarrison;
  final bool isCenter;
  final String? territoryName;
  final String? color;
  final int? backgroundBonusPercent;

  HexTile copyWith({
    String? h3Index,
    HexState? state,
    String? ownerName,
    bool? hasGarrison,
    bool? isCenter,
    String? territoryName,
    String? color,
    int? backgroundBonusPercent,
  }) {
    return HexTile(
      h3Index: h3Index ?? this.h3Index,
      state: state ?? this.state,
      ownerName: ownerName ?? this.ownerName,
      hasGarrison: hasGarrison ?? this.hasGarrison,
      isCenter: isCenter ?? this.isCenter,
      territoryName: territoryName ?? this.territoryName,
      color: color ?? this.color,
      backgroundBonusPercent: backgroundBonusPercent ?? this.backgroundBonusPercent,
    );
  }

  factory HexTile.fromGridPayload(Map<String, dynamic> payload) {
    final h3Index = (payload['h3Index'] as String?)?.trim() ?? '';
    final ownerName = _cleanString(payload['ownerName']);
    final color = _cleanString(payload['color']);
    final hasGarrison = payload['hasGarrison'] == true;
    final isCenter = payload['isCenter'] == true;
    return HexTile(
      h3Index: h3Index,
      state: _stateFromGrid(ownerName: ownerName, color: color),
      ownerName: ownerName,
      hasGarrison: hasGarrison,
      isCenter: isCenter,
      color: color,
    );
  }

  factory HexTile.fromDetailPayload(Map<String, dynamic> payload) {
    final h3Index = (payload['h3Index'] as String?)?.trim() ?? '';
    final state = _stateFromString(payload['state']) ?? HexState.free;
    final territory = payload['territory'] is Map<String, dynamic>
        ? payload['territory'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return HexTile(
      h3Index: h3Index,
      state: state,
      ownerName: _cleanString(payload['ownerName']),
      hasGarrison: payload['garrison'] is Map<String, dynamic>,
      isCenter: payload['isCenter'] == true,
      territoryName: _cleanString(territory['name']),
      backgroundBonusPercent: (payload['backgroundBonusPercent'] as num?)?.toInt(),
    );
  }

  static HexState _stateFromGrid({required String? ownerName, required String? color}) {
    if (color != null) {
      final normalized = color.toLowerCase();
      if (normalized == '#2196f3' || normalized == '#1976d2' || normalized == 'blue') {
        return HexState.owned;
      }
      if (normalized == '#e53935' || normalized == 'red') {
        return HexState.enemy;
      }
    }

    if (ownerName == null || ownerName.isEmpty) {
      return HexState.free;
    }

    return HexState.enemy;
  }

  static HexState? _stateFromString(dynamic value) {
    final raw = value?.toString().toUpperCase();
    return switch (raw) {
      'FREE' => HexState.free,
      'OWNED' => HexState.owned,
      'ENEMY' => HexState.enemy,
      _ => null,
    };
  }

  static String? _cleanString(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}
