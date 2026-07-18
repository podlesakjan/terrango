import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';

class GameSessionController extends ChangeNotifier {
  GameSessionController() {
    _seedMockData();
  }

  final Map<String, HexDetail> _hexDetails = <String, HexDetail>{};
  final Set<String> _knownBluetoothIds = <String>{};
  final Random _random = Random(7);

  late ProfileStats _profile;
  late TerritoryListState _territories;
  late BarracksState _barracks;
  late List<BattleLogEntry> _battleLogs;
  late List<MapHexTile> _visibleHexes;
  late List<RecruitmentFeedItem> _recruitmentFeed;

  bool onboardingComplete = false;
  bool wakeLockEnabled = true;
  bool backgroundServiceEnabled = false;
  bool notificationsEnabled = true;
  int selectedTab = 0;
  String connectionStatus = 'Connected to mock gateway';
  String? authToken;
  String currentLocationH3Index = '891f1a1c62fffff';
  HexDetail? selectedHex;

  ProfileStats get profile => _profile;
  TerritoryListState get territories => _territories;
  BarracksState get barracks => _barracks;
  List<BattleLogEntry> get battleLogs => List.unmodifiable(_battleLogs);
  List<MapHexTile> get visibleHexes => List.unmodifiable(_visibleHexes);
  List<RecruitmentFeedItem> get recruitmentFeed => List.unmodifiable(_recruitmentFeed);
  int get reserveCount => _barracks.reserves.fold<int>(0, (sum, item) => sum + item.count);
  int get reserveBs => _barracks.reserves.fold<int>(0, (sum, item) => sum + item.totalBs);
  int get patrolCount => _barracks.patrols.fold<int>(0, (sum, item) => sum + item.soldierCount);

  Future<AuthSession> register(String nickname, {String? idToken}) async {
    onboardingComplete = true;
    authToken = 'jwt-${nickname.toLowerCase().replaceAll(' ', '-')}-${_random.nextInt(9999)}';
    _profile = _profile.copyWith(nickname: nickname);
    connectionStatus = 'Authenticated as $nickname';
    notifyListeners();
    return AuthSession(
      userId: 'user-${_random.nextInt(999999)}',
      token: authToken!,
      nickname: nickname,
    );
  }

  void selectTab(int index) {
    selectedTab = index;
    notifyListeners();
  }

  void selectHex(String h3Index) {
    selectedHex = detailFor(h3Index);
    notifyListeners();
  }

  HexDetail detailFor(String h3Index) {
    return _hexDetails[h3Index] ?? _buildFreeHexDetail(h3Index);
  }

  int backgroundBonusFor(String h3Index) {
    final ownedNeighbours = _ownedNeighborsFor(h3Index).length;
    return ownedNeighbours * 100;
  }

  List<String> _ownedNeighborsFor(String h3Index) {
    final neighbours = <String, List<String>>{
      '891f1a1c62fffff': ['891f1a1c62ffffe', '891f1a1c62ffffd'],
      '891f1a1c62ffffe': ['891f1a1c62fffff', '891f1a1c62ffffc'],
      '891f1a1c62ffffd': ['891f1a1c62fffff', '891f1a1c62ffffb'],
      '891f1a1c62ffffc': ['891f1a1c62ffffe', '891f1a1c62ffffa'],
      '891f1a1c62ffffb': ['891f1a1c62ffffd'],
      '891f1a1c62ffffa': ['891f1a1c62ffffc'],
    };
    final ownIndices = _hexDetails.values.where((hex) => hex.state == HexOwnershipState.owned).map((hex) => hex.h3Index).toSet();
    return neighbours[h3Index]?.where(ownIndices.contains).toList() ?? const <String>[];
  }

  Future<HexDetail> establishTerritory({required String h3Index, required String name}) async {
    final updated = _buildOwnedHexDetail(
      h3Index: h3Index,
      territory: TerritorySummary(
        id: 'home-id',
        name: name,
        type: TerritoryType.home,
        hexCount: 1,
        centerH3Index: h3Index,
      ),
      isCenter: true,
      garrison: const GarrisonView(
        soldierCount: 1,
        totalBs: 50,
        composition: [
          ArmyBucket(
            type: ArmyUnitType.support,
            rarity: SoldierRarity.standard,
            skill: 'SCOUT',
            count: 1,
            totalBs: 50,
          ),
        ],
      ),
    );
    _hexDetails[h3Index] = updated;
    _territories = TerritoryListState(home: updated.territory!, outposts: _territories.outposts);
    _syncVisibleHexes();
    notifyListeners();
    return updated;
  }

  Future<HexDetail> occupyHex({
    required String h3Index,
    required String territoryName,
    required List<ArmyBucket> garrisonComposition,
  }) async {
    final createdNewTerritory = !_isAdjacentToOwnedTerritory(h3Index);
    final territory = TerritorySummary(
      id: createdNewTerritory ? 'outpost-${_random.nextInt(999)}' : _territories.home.id,
      name: territoryName,
      type: createdNewTerritory ? TerritoryType.outpost : TerritoryType.home,
      hexCount: 1,
      centerH3Index: createdNewTerritory ? null : _territories.home.centerH3Index,
      representativeH3Index: h3Index,
    );
    final totalSoldiers = garrisonComposition.fold<int>(0, (sum, item) => sum + item.count);
    final totalBs = garrisonComposition.fold<int>(0, (sum, item) => sum + item.totalBs);
    final updated = _buildOwnedHexDetail(
      h3Index: h3Index,
      territory: territory,
      isCenter: false,
      garrison: GarrisonView(soldierCount: totalSoldiers, totalBs: totalBs, composition: garrisonComposition),
    );
    _hexDetails[h3Index] = updated;
    _territories = createdNewTerritory
        ? TerritoryListState(home: _territories.home, outposts: [..._territories.outposts, territory])
        : TerritoryListState(
            home: TerritorySummary(
              id: _territories.home.id,
              name: _territories.home.name,
              type: TerritoryType.home,
              hexCount: _territories.home.hexCount + 1,
              centerH3Index: _territories.home.centerH3Index,
            ),
            outposts: _territories.outposts,
          );
    _recruitmentFeed = [
      RecruitmentFeedItem(
        timestamp: DateTime.now(),
        message: 'Hex $h3Index occupied and garrison established.',
        success: true,
        bluetoothId: h3Index,
      ),
      ..._recruitmentFeed,
    ];
    _syncVisibleHexes();
    notifyListeners();
    return updated;
  }

  Future<HexDetail> changeCenter({required String territoryId, required String h3Index}) async {
    final current = _hexDetails[h3Index];
    if (current != null) {
      _hexDetails[h3Index] = current.copyWith(isCenter: true);
    }
    _territories = TerritoryListState(
      home: TerritorySummary(
        id: territoryId,
        name: _territories.home.name,
        type: TerritoryType.home,
        hexCount: _territories.home.hexCount,
        centerH3Index: h3Index,
      ),
      outposts: _territories.outposts,
    );
    selectedHex = _hexDetails[h3Index];
    _syncVisibleHexes();
    notifyListeners();
    return selectedHex!;
  }

  Future<void> renameTerritory({required String territoryId, required String name}) async {
    if (_territories.home.id == territoryId) {
      _territories = TerritoryListState(
        home: TerritorySummary(
          id: _territories.home.id,
          name: name,
          type: _territories.home.type,
          hexCount: _territories.home.hexCount,
          centerH3Index: _territories.home.centerH3Index,
        ),
        outposts: _territories.outposts,
      );
    } else {
      _territories = TerritoryListState(
        home: _territories.home,
        outposts: _territories.outposts
            .map(
              (territory) => territory.id == territoryId
                  ? TerritorySummary(
                      id: territory.id,
                      name: name,
                      type: territory.type,
                      hexCount: territory.hexCount,
                      representativeH3Index: territory.representativeH3Index,
                    )
                  : territory,
            )
            .toList(growable: false),
      );
    }
    notifyListeners();
  }

  Future<BarracksState> getBarracks() async => _barracks;

  Future<TerritoryListState> getTerritories() async => _territories;

  Future<List<BattleLogEntry>> getBattleLogs() async => battleLogs;

  Future<ProfileStats> getProfile() async => _profile;

  Future<ProfileStats> updateNickname(String nickname) async {
    _profile = _profile.copyWith(nickname: nickname);
    notifyListeners();
    return _profile;
  }

  Future<void> recruitDevice({
    required String bluetoothId,
    required ArmyUnitType type,
    required SoldierRarity rarity,
    required int bs,
    String? skill,
  }) async {
    final duplicate = !_knownBluetoothIds.add(bluetoothId);
    final message = duplicate
        ? 'ID již dříve naskenováno -> Přeskočeno 🚫'
        : 'Rekrutován ${type.label} (${rarity.label}, $bs BS) ⚔️';

    _recruitmentFeed = [
      RecruitmentFeedItem(
        timestamp: DateTime.now(),
        message: message,
        success: !duplicate,
        bluetoothId: bluetoothId,
      ),
      ..._recruitmentFeed,
    ].take(24).toList(growable: false);

    if (!duplicate) {
      _mergeReserve(ArmyBucket(type: type, rarity: rarity, skill: skill, count: 1, totalBs: bs));
      _profile = _profile.copyWith(scannedDevices: _profile.scannedDevices + 1);
    }
    notifyListeners();
  }

  Future<void> garrisonModify({
    required String h3Index,
    required String action,
    required List<ArmyBucket> composition,
  }) async {
    final current = detailFor(h3Index);
    if (action == 'DEPLOY') {
      for (final bucket in composition) {
        _removeReserveBucket(_barracks.reserves, bucket);
      }
      final totalSoldiers = composition.fold<int>(0, (sum, item) => sum + item.count);
      final totalBs = composition.fold<int>(0, (sum, item) => sum + item.totalBs);
      _hexDetails[h3Index] = current.copyWith(
        garrison: GarrisonView(
          soldierCount: (current.garrison?.soldierCount ?? 0) + totalSoldiers,
          totalBs: (current.garrison?.totalBs ?? 0) + totalBs,
          composition: [...?current.garrison?.composition, ...composition],
        ),
      );
    } else {
      for (final bucket in composition) {
        _mergeReserve(bucket);
      }
      final currentGarrison = current.garrison;
      if (currentGarrison != null) {
        final remainingComposition = [...currentGarrison.composition];
        for (final bucket in composition) {
          final index = remainingComposition.indexWhere(
            (item) => item.type == bucket.type && item.rarity == bucket.rarity && item.skill == bucket.skill,
          );
          if (index == -1) continue;
          final existing = remainingComposition[index];
          if (existing.count <= bucket.count) {
            remainingComposition.removeAt(index);
          } else {
            remainingComposition[index] = existing.copyWith(
              count: existing.count - bucket.count,
              totalBs: max(0, existing.totalBs - bucket.totalBs),
            );
          }
        }
        final soldiers = remainingComposition.fold<int>(0, (sum, item) => sum + item.count);
        final totalBs = remainingComposition.fold<int>(0, (sum, item) => sum + item.totalBs);
        _hexDetails[h3Index] = current.copyWith(
          garrison: GarrisonView(soldierCount: soldiers, totalBs: totalBs, composition: remainingComposition),
        );
      }
    }
    _rebuildBarracksSnapshot();
    notifyListeners();
  }

  Future<void> sendReinforcements({
    required String targetH3Index,
    required List<ArmyBucket> composition,
    int? burnSupportCount,
  }) async {
    for (final bucket in composition) {
      _removeReserveBucket(_barracks.reserves, bucket);
    }
    final target = detailFor(targetH3Index);
    final updatedGarrison = GarrisonView(
      soldierCount: (target.garrison?.soldierCount ?? 0) + composition.fold<int>(0, (sum, item) => sum + item.count),
      totalBs: (target.garrison?.totalBs ?? 0) + composition.fold<int>(0, (sum, item) => sum + item.totalBs),
      composition: [...?target.garrison?.composition, ...composition],
    );
    _hexDetails[targetH3Index] = target.copyWith(garrison: updatedGarrison);
    if (burnSupportCount != null && burnSupportCount > 0) {
      final support = ArmyBucket(
        type: ArmyUnitType.support,
        rarity: SoldierRarity.standard,
        skill: null,
        count: burnSupportCount,
        totalBs: 0,
      );
      _removeReserveBucket(_barracks.reserves, support);
    }
    _rebuildBarracksSnapshot();
    notifyListeners();
  }

  Future<void> scoutHex({required String targetH3Index}) async {
    _removeReserveBucket(
      _barracks.reserves,
      const ArmyBucket(
        type: ArmyUnitType.support,
        rarity: SoldierRarity.standard,
        skill: 'SCOUT',
        count: 1,
        totalBs: 50,
      ),
    );
    _battleLogs = [
      BattleLogEntry(
        id: 'log-${_random.nextInt(9999)}',
        timestamp: DateTime.now(),
        type: BattleLogType.scout,
        h3Index: targetH3Index,
        result: BattleResult.success,
        revealedBs: 1250,
        details: 'Support scout reported 1250 BS at $targetH3Index',
      ),
      ..._battleLogs,
    ];
    notifyListeners();
  }

  Future<void> attackHex({required String targetH3Index, required List<ArmyBucket> attackerComposition}) async {
    for (final bucket in attackerComposition) {
      _removeReserveBucket(_barracks.reserves, bucket);
    }
    final attackerBs = attackerComposition.fold<int>(0, (sum, item) => sum + item.totalBs);
    final targetBs = detailFor(targetH3Index).garrison?.totalBs ?? 600;
    final result = attackerBs >= targetBs ? BattleResult.victory : BattleResult.defeat;
    _battleLogs = [
      BattleLogEntry(
        id: 'log-${_random.nextInt(9999)}',
        timestamp: DateTime.now(),
        type: BattleLogType.attack,
        h3Index: targetH3Index,
        result: result,
        myDead: result == BattleResult.victory ? 2 : attackerComposition.fold<int>(0, (sum, item) => sum + item.count),
        mySurvivors: result == BattleResult.victory ? max(0, attackerComposition.fold<int>(0, (sum, item) => sum + item.count) - 2) : 0,
        details: 'Authoritative combat resolved for $targetH3Index',
      ),
      ..._battleLogs,
    ];
    notifyListeners();
  }

  void toggleWakeLock(bool value) {
    wakeLockEnabled = value;
    notifyListeners();
  }

  void toggleBackgroundService(bool value) {
    backgroundServiceEnabled = value;
    notifyListeners();
  }

  void toggleNotifications(bool value) {
    notificationsEnabled = value;
    notifyListeners();
  }

  void setCurrentLocation(String h3Index, {bool isMocked = false}) {
    currentLocationH3Index = h3Index;
    connectionStatus = isMocked ? 'Location mocked by client' : 'Live GPS verified';
    notifyListeners();
  }

  void pushMockRecruitment() {
    final ids = <String>['4A:5F:6E:7D:8C:9B', '1C:2D:3E:4F:5A:6B', 'AA:BB:CC:DD:EE:FF'];
    final id = ids[_random.nextInt(ids.length)];
    final type = _random.nextBool() ? ArmyUnitType.warrior : ArmyUnitType.support;
    final rarity = switch (_random.nextInt(3)) {
      0 => SoldierRarity.standard,
      1 => SoldierRarity.advanced,
      _ => SoldierRarity.prototype,
    };
    final bs = switch (rarity) {
      SoldierRarity.standard => 50,
      SoldierRarity.advanced => 180,
      SoldierRarity.prototype => 250,
    };
    recruitDevice(bluetoothId: id, type: type, rarity: rarity, bs: bs, skill: type == ArmyUnitType.support ? 'SCOUT' : null);
  }

  void _seedMockData() {
    _profile = const ProfileStats(
      nickname: 'Válečník99',
      email: 'user@email.com',
      hexesClaimed: 42,
      biggestBattleBs: 1850,
      scannedDevices: 341,
    );

    _territories = const TerritoryListState(
      home: TerritorySummary(
        id: 'home-id',
        name: 'Domovská základna',
        type: TerritoryType.home,
        hexCount: 14,
        centerH3Index: '891f1a1c62fffff',
      ),
      outposts: [
        TerritorySummary(
          id: 'outpost-1',
          name: 'Chata u lesa',
          type: TerritoryType.outpost,
          hexCount: 3,
          representativeH3Index: '891f1a1c62ffffe',
        ),
      ],
    );

    _barracks = const BarracksState(
      reserves: [
        ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.prototype, count: 1, totalBs: 250),
        ArmyBucket(type: ArmyUnitType.support, rarity: SoldierRarity.standard, skill: 'SCOUT', count: 1, totalBs: 50),
      ],
      patrols: [
        PatrolEntry(
          h3Index: '891f1a1c62fffff',
          territoryName: 'Domovská základna',
          soldierCount: 5,
          totalBs: 650,
        ),
      ],
    );

    _battleLogs = [
      BattleLogEntry(
        id: 'log-1',
        timestamp: DateTime.parse('2026-07-17T14:30:00Z'),
        type: BattleLogType.attack,
        h3Index: '891f1a1c62fffff',
        result: BattleResult.victory,
        myDead: 3,
        mySurvivors: 8,
      ),
      BattleLogEntry(
        id: 'log-2',
        timestamp: DateTime.parse('2026-07-17T12:15:00Z'),
        type: BattleLogType.scout,
        h3Index: '891f1a1c62ffffb',
        result: BattleResult.success,
        revealedBs: 450,
      ),
    ];

    _recruitmentFeed = [
      RecruitmentFeedItem(
        timestamp: DateTime.parse('2026-07-17T15:00:00Z'),
        message: 'Weak signal detected -> Recruited Support (Jammer, Standard, 50 BS) 📡',
        success: true,
        bluetoothId: '1C:2D:3E:4F:5A:6B',
      ),
      RecruitmentFeedItem(
        timestamp: DateTime.parse('2026-07-17T14:55:00Z'),
        message: 'ID already scanned previously -> Recruitment skipped 🚫',
        success: false,
        bluetoothId: 'AA:AA:AA:AA:AA:AA',
      ),
    ];

    _hexDetails.addAll({
      '891f1a1c62fffff': _buildOwnedHexDetail(
        h3Index: '891f1a1c62fffff',
        territory: _territories.home,
        isCenter: true,
        garrison: const GarrisonView(
          soldierCount: 6,
          totalBs: 830,
          composition: [
            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.prototype, count: 1, totalBs: 250),
            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.advanced, count: 1, totalBs: 180),
            ArmyBucket(type: ArmyUnitType.support, rarity: SoldierRarity.standard, skill: 'JAMMER', count: 1, totalBs: 50),
          ],
        ),
        reserve: const [ArmyBucket(type: ArmyUnitType.support, rarity: SoldierRarity.standard, skill: 'SCOUT', count: 1, totalBs: 50)],
      ),
      '891f1a1c62ffffe': _buildOwnedHexDetail(
        h3Index: '891f1a1c62ffffe',
        territory: _territories.outposts.first,
        isCenter: false,
        garrison: const GarrisonView(
          soldierCount: 5,
          totalBs: 650,
          composition: [
            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.standard, count: 3, totalBs: 600),
            ArmyBucket(type: ArmyUnitType.support, rarity: SoldierRarity.standard, skill: 'SCOUT', count: 1, totalBs: 50),
          ],
        ),
      ),
      '891f1a1c62ffffd': HexDetail(
        h3Index: '891f1a1c62ffffd',
        state: HexOwnershipState.enemy,
        isCenter: false,
        backgroundBonusPercent: 0,
        garrison: const GarrisonView(
          soldierCount: 8,
          totalBs: 1200,
          composition: [
            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.advanced, count: 4, totalBs: 800),
            ArmyBucket(type: ArmyUnitType.support, rarity: SoldierRarity.standard, skill: 'DECOY', count: 1, totalBs: 50),
          ],
        ),
        reserve: const [],
        ownerName: 'Ragnarok',
        fogOfWarLabel: '??? BS',
        canAttackWhilePresent: true,
      ),
      '891f1a1c62ffffc': const HexDetail(
        h3Index: '891f1a1c62ffffc',
        state: HexOwnershipState.free,
        isCenter: false,
        backgroundBonusPercent: 0,
        garrison: null,
        reserve: [],
      ),
      '891f1a1c62ffffb': HexDetail(
        h3Index: '891f1a1c62ffffb',
        state: HexOwnershipState.enemy,
        isCenter: false,
        backgroundBonusPercent: 0,
        garrison: const GarrisonView(
          soldierCount: 5,
          totalBs: 450,
          composition: [
            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.standard, count: 5, totalBs: 450),
          ],
        ),
        reserve: const [],
        ownerName: 'Nepřítel01',
        fogOfWarLabel: '??? BS',
        canAttackWhilePresent: false,
      ),
      '891f1a1c62ffffa': HexDetail(
        h3Index: '891f1a1c62ffffa',
        state: HexOwnershipState.enemy,
        isCenter: false,
        backgroundBonusPercent: 0,
        garrison: const GarrisonView(
          soldierCount: 7,
          totalBs: 800,
          composition: [
            ArmyBucket(type: ArmyUnitType.warrior, rarity: SoldierRarity.standard, count: 4, totalBs: 800),
          ],
        ),
        reserve: const [],
        ownerName: 'Ragnarok',
        fogOfWarLabel: '??? BS',
        canAttackWhilePresent: false,
      ),
    });

    _visibleHexes = _hexDetails.values
        .map(
          (hex) => MapHexTile(
            h3Index: hex.h3Index,
            state: hex.state,
            color: switch (hex.state) {
              HexOwnershipState.free => Colors.white24,
              HexOwnershipState.owned => Colors.lightBlueAccent.withValues(alpha: 0.7),
              HexOwnershipState.enemy => Colors.redAccent.withValues(alpha: 0.6),
            },
            hasGarrison: hex.garrison != null,
            isCenter: hex.isCenter,
            ownerName: hex.ownerName,
          ),
        )
        .toList(growable: false);

    selectedHex = _hexDetails[currentLocationH3Index];
  }

  HexDetail _buildOwnedHexDetail({
    required String h3Index,
    required TerritorySummary territory,
    required bool isCenter,
    required GarrisonView garrison,
    List<ArmyBucket> reserve = const [],
  }) {
    return HexDetail(
      h3Index: h3Index,
      state: HexOwnershipState.owned,
      isCenter: isCenter,
      backgroundBonusPercent: backgroundBonusFor(h3Index),
      garrison: garrison,
      reserve: reserve,
      territory: territory,
      ownerName: _profile.nickname,
      fogOfWarLabel: null,
      canAttackWhilePresent: false,
    );
  }

  HexDetail _buildFreeHexDetail(String h3Index) {
    return HexDetail(
      h3Index: h3Index,
      state: HexOwnershipState.free,
      isCenter: false,
      backgroundBonusPercent: 0,
      garrison: null,
      reserve: const [],
    );
  }

  void _mergeReserve(ArmyBucket bucket) {
    final index = _barracks.reserves.indexWhere(
      (item) => item.type == bucket.type && item.rarity == bucket.rarity && item.skill == bucket.skill,
    );
    if (index == -1) {
      _barracks = BarracksState(reserves: [..._barracks.reserves, bucket], patrols: _barracks.patrols);
      return;
    }
    final existing = _barracks.reserves[index];
    final updated = existing.copyWith(count: existing.count + bucket.count, totalBs: existing.totalBs + bucket.totalBs);
    final reserves = [..._barracks.reserves]..[index] = updated;
    _barracks = BarracksState(reserves: reserves, patrols: _barracks.patrols);
  }

  void _removeReserveBucket(List<ArmyBucket> reserves, ArmyBucket bucket) {
    final index = reserves.indexWhere(
      (item) => item.type == bucket.type && item.rarity == bucket.rarity && item.skill == bucket.skill,
    );
    if (index == -1) {
      return;
    }
    final existing = reserves[index];
    if (existing.count <= bucket.count) {
      reserves.removeAt(index);
      return;
    }
    reserves[index] = existing.copyWith(
      count: existing.count - bucket.count,
      totalBs: max(0, existing.totalBs - bucket.totalBs),
    );
  }

  void _rebuildBarracksSnapshot() {
    _barracks = BarracksState(reserves: _barracks.reserves, patrols: _barracks.patrols);
  }

  void _syncVisibleHexes() {
    _visibleHexes = _hexDetails.values
        .map(
          (hex) => MapHexTile(
            h3Index: hex.h3Index,
            state: hex.state,
            color: switch (hex.state) {
              HexOwnershipState.free => Colors.white24,
              HexOwnershipState.owned => Colors.lightBlueAccent.withValues(alpha: 0.7),
              HexOwnershipState.enemy => Colors.redAccent.withValues(alpha: 0.6),
            },
            hasGarrison: hex.garrison != null,
            isCenter: hex.isCenter,
            ownerName: hex.ownerName,
          ),
        )
        .toList(growable: false);
  }

  bool _isAdjacentToOwnedTerritory(String h3Index) {
    final neighbours = <String, List<String>>{
      '891f1a1c62fffff': ['891f1a1c62ffffe', '891f1a1c62ffffd'],
      '891f1a1c62ffffe': ['891f1a1c62fffff', '891f1a1c62ffffc'],
      '891f1a1c62ffffd': ['891f1a1c62fffff', '891f1a1c62ffffb'],
      '891f1a1c62ffffc': ['891f1a1c62ffffe', '891f1a1c62ffffa'],
      '891f1a1c62ffffb': ['891f1a1c62ffffd'],
      '891f1a1c62ffffa': ['891f1a1c62ffffc'],
    };
    final owned = _hexDetails.values.where((hex) => hex.state == HexOwnershipState.owned).map((hex) => hex.h3Index).toSet();
    return neighbours[h3Index]?.any(owned.contains) ?? false;
  }
}







