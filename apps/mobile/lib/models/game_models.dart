import 'package:flutter/material.dart';

enum ArmyUnitType { warrior, support }

enum SoldierRarity { standard, advanced, prototype }

enum TerritoryType { home, outpost }

enum HexOwnershipState { free, owned, enemy }

enum BattleLogType { attack, scout }

enum BattleResult { victory, defeat, success, jammed, skipped }

extension ArmyUnitTypeX on ArmyUnitType {
  String get apiName => switch (this) {
		ArmyUnitType.warrior => 'WARRIOR',
		ArmyUnitType.support => 'SUPPORT',
	  };

  String get label => switch (this) {
		ArmyUnitType.warrior => 'Warrior',
		ArmyUnitType.support => 'Support',
	  };

  IconData get icon => switch (this) {
		ArmyUnitType.warrior => Icons.brightness_5_rounded,
		ArmyUnitType.support => Icons.sensors_rounded,
	  };
}

extension SoldierRarityX on SoldierRarity {
  String get apiName => switch (this) {
		SoldierRarity.standard => 'STANDARD',
		SoldierRarity.advanced => 'ADVANCED',
		SoldierRarity.prototype => 'PROTOTYPE',
	  };

  String get label => switch (this) {
		SoldierRarity.standard => 'Standard',
		SoldierRarity.advanced => 'Advanced',
		SoldierRarity.prototype => 'Prototype',
	  };
}

extension TerritoryTypeX on TerritoryType {
  String get apiName => switch (this) {
		TerritoryType.home => 'HOME',
		TerritoryType.outpost => 'OUTPOST',
	  };
}

class ArmyBucket {
  const ArmyBucket({
	required this.type,
	required this.rarity,
	required this.count,
	required this.totalBs,
	this.skill,
  });

  final ArmyUnitType type;
  final SoldierRarity rarity;
  final String? skill;
  final int count;
  final int totalBs;

  ArmyBucket copyWith({
	ArmyUnitType? type,
	SoldierRarity? rarity,
	String? skill,
	int? count,
	int? totalBs,
  }) {
	return ArmyBucket(
	  type: type ?? this.type,
	  rarity: rarity ?? this.rarity,
	  skill: skill ?? this.skill,
	  count: count ?? this.count,
	  totalBs: totalBs ?? this.totalBs,
	);
  }

  Map<String, Object?> toApiJson() => {
		'type': type.apiName,
		'rarity': rarity.apiName,
		'skill': skill,
		'count': count,
		'totalBs': totalBs,
	  };
}

class PatrolEntry {
  const PatrolEntry({
	required this.h3Index,
	required this.territoryName,
	required this.soldierCount,
	required this.totalBs,
  });

  final String h3Index;
  final String territoryName;
  final int soldierCount;
  final int totalBs;
}

class TerritorySummary {
  const TerritorySummary({
	required this.id,
	required this.name,
	required this.type,
	required this.hexCount,
	this.centerH3Index,
	this.representativeH3Index,
  });

  final String id;
  final String name;
  final TerritoryType type;
  final int hexCount;
  final String? centerH3Index;
  final String? representativeH3Index;
}

class GarrisonView {
  const GarrisonView({
	required this.soldierCount,
	required this.totalBs,
	required this.composition,
  });

  final int soldierCount;
  final int totalBs;
  final List<ArmyBucket> composition;
}

class HexDetail {
  const HexDetail({
	required this.h3Index,
	required this.state,
	required this.isCenter,
	required this.backgroundBonusPercent,
	required this.garrison,
	required this.reserve,
	this.territory,
	this.ownerName,
	this.fogOfWarLabel,
	this.canAttackWhilePresent = false,
  });

  final String h3Index;
  final HexOwnershipState state;
  final bool isCenter;
  final int backgroundBonusPercent;
  final GarrisonView? garrison;
  final List<ArmyBucket> reserve;
  final TerritorySummary? territory;
  final String? ownerName;
  final String? fogOfWarLabel;
  final bool canAttackWhilePresent;

  HexDetail copyWith({
	String? h3Index,
	HexOwnershipState? state,
	bool? isCenter,
	int? backgroundBonusPercent,
	GarrisonView? garrison,
	List<ArmyBucket>? reserve,
	TerritorySummary? territory,
	String? ownerName,
	String? fogOfWarLabel,
	bool? canAttackWhilePresent,
  }) {
	return HexDetail(
	  h3Index: h3Index ?? this.h3Index,
	  state: state ?? this.state,
	  isCenter: isCenter ?? this.isCenter,
	  backgroundBonusPercent: backgroundBonusPercent ?? this.backgroundBonusPercent,
	  garrison: garrison ?? this.garrison,
	  reserve: reserve ?? this.reserve,
	  territory: territory ?? this.territory,
	  ownerName: ownerName ?? this.ownerName,
	  fogOfWarLabel: fogOfWarLabel ?? this.fogOfWarLabel,
	  canAttackWhilePresent: canAttackWhilePresent ?? this.canAttackWhilePresent,
	);
  }
}

class MapHexTile {
  const MapHexTile({
	required this.h3Index,
	required this.state,
	required this.color,
	required this.hasGarrison,
	required this.isCenter,
	this.ownerName,
  });

  final String h3Index;
  final HexOwnershipState state;
  final Color? color;
  final bool hasGarrison;
  final bool isCenter;
  final String? ownerName;
}

class BattleLogEntry {
  const BattleLogEntry({
	required this.id,
	required this.timestamp,
	required this.type,
	required this.h3Index,
	required this.result,
	this.myDead,
	this.mySurvivors,
	this.revealedBs,
	this.details,
  });

  final String id;
  final DateTime timestamp;
  final BattleLogType type;
  final String h3Index;
  final BattleResult result;
  final int? myDead;
  final int? mySurvivors;
  final int? revealedBs;
  final String? details;
}

class ProfileStats {
  const ProfileStats({
	required this.nickname,
	required this.email,
	required this.hexesClaimed,
	required this.biggestBattleBs,
	required this.scannedDevices,
  });

  final String nickname;
  final String email;
  final int hexesClaimed;
  final int biggestBattleBs;
  final int scannedDevices;

  ProfileStats copyWith({
	String? nickname,
	String? email,
	int? hexesClaimed,
	int? biggestBattleBs,
	int? scannedDevices,
  }) {
	return ProfileStats(
	  nickname: nickname ?? this.nickname,
	  email: email ?? this.email,
	  hexesClaimed: hexesClaimed ?? this.hexesClaimed,
	  biggestBattleBs: biggestBattleBs ?? this.biggestBattleBs,
	  scannedDevices: scannedDevices ?? this.scannedDevices,
	);
  }
}

class AuthSession {
  const AuthSession({
	required this.userId,
	required this.token,
	required this.nickname,
  });

  final String userId;
  final String token;
  final String nickname;
}

class RecruitmentFeedItem {
  const RecruitmentFeedItem({
	required this.timestamp,
	required this.message,
	required this.success,
	required this.bluetoothId,
  });

  final DateTime timestamp;
  final String message;
  final bool success;
  final String bluetoothId;
}

class TerritoryListState {
  const TerritoryListState({
	required this.home,
	required this.outposts,
  });

  final TerritorySummary home;
  final List<TerritorySummary> outposts;
}

class BarracksState {
  const BarracksState({
	required this.reserves,
	required this.patrols,
  });

  final List<ArmyBucket> reserves;
  final List<PatrolEntry> patrols;
}

