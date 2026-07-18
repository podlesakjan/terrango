import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { RedisService } from '../redis/redis.module';
import { gridDisk, isValidCell, latLngToCell } from 'h3-js';
import { AuthService } from '../auth/auth.service';
import {
  UserRepository,
  HexRepository,
  TerritoryRepository,
  BattleLogRepository,
  BluetoothScanRepository,
} from '../database/repositories';
import { PlayerArmyRepository } from '../database/repositories/player-army.repository';

import {
  ATTACK_PREPARATION_MS,
  ArmyUpdatePayload,
  AuthenticatedPlayer,
  BattleLogEntry,
  BattleResult,
  BattleResultPayload,
  ENEMY_COLOR,
  GarrisonAction,
  H3_RESOLUTION,
  HOME_COLOR,
  HexDetailPayload,
  HexRecord,
  IncomingAttackAlertPayload,
  LOCATION_TTL_MS,
  MapHexagonView,
  MAX_SPEED_KMH,
  PendingBattle,
  RecruitResultPayload,
  ScoutResultPayload,
  ScoutStatus,
  SoldierBucket,
  SoldierRarity,
  SoldierSkill,
  SoldierType,
  TerritoryRecord,
  TerritoryUpdatePayload,
  UserState,
} from './domain';

interface TerritoryHint {
  createdHex?: string;
  name?: string;
}

@Injectable()
export class GameService {
  public readonly events = new EventEmitter();

  private readonly battleLogs = new Map<string, BattleLogEntry[]>();
  private readonly hexes = new Map<string, HexRecord>();
  private readonly nicknameOwners = new Map<string, string>();
  private readonly pendingBattles = new Map<string, PendingBattle>();
  private readonly pendingBattleByHex = new Map<string, string>();
  private readonly territories = new Map<string, TerritoryRecord>();
  private readonly users = new Map<string, UserState>();
  // Aggregated player armies: ownerId -> composition buckets
  private readonly playerArmies = new Map<string, SoldierBucket[]>();

  constructor(
    private readonly authService: AuthService,
    private readonly userRepository: UserRepository,
    private readonly hexRepository: HexRepository,
    private readonly territoryRepository: TerritoryRepository,
    private readonly battleLogRepository: BattleLogRepository,
    private readonly bluetoothScanRepository: BluetoothScanRepository,
    private readonly redisService?: RedisService,
  ) {
    this.events.setMaxListeners(0);
  }
  private playerArmyRepository!: PlayerArmyRepository;

  setPlayerArmyRepository(repo: PlayerArmyRepository): void {
    this.playerArmyRepository = repo;
  }

  async register(body: Record<string, unknown>) {
    const nickname = this.requireNickname(body.nickname);
    const idToken = this.requireString(body.idToken, 'idToken');
    const providerId = this.authService.hashIdToken(idToken);

    // Check if provider already registered
    const existingUser = await this.userRepository.findByProviderId(providerId);
    if (existingUser) {
      // Load user into in-memory cache
      this.loadUserToMemory(existingUser);
      return {
        userId: existingUser.id,
        token: this.authService.issueToken(existingUser.id),
      };
    }

    // Check nickname availability
    const existingNickname = await this.userRepository.findByNickname(nickname);
    if (existingNickname) {
      throw new BadRequestException('Nickname is already in use.');
    }

    // Create new user
    const userId = randomUUID();
    const userEntity = await this.userRepository.create({
      id: userId,
      providerId,
      nickname,
      email: `player-${providerId.slice(0, 12)}@terrango.local`,
      homeCenterH3Index: null,
      stats: {
        hexesClaimed: 0,
        biggestBattleBs: 0,
        scannedDevices: 0,
      },
    });

    // Load into memory
    this.loadUserToMemory(userEntity);
    this.battleLogs.set(userId, []);
    await this.loadPlayerArmyToMemory(userId);

    return {
      userId,
      token: this.authService.issueToken(userId),
    };
  }

  private loadUserToMemory(userEntity: any): void {
    const userId = userEntity.id;
    const user: UserState = {
      createdAt: userEntity.createdAt?.toISOString?.() ?? new Date().toISOString(),
      email: userEntity.email,
      homeCenterH3Index: userEntity.homeCenterH3Index,
      id: userId,
      lastLocation: null,
      nickname: userEntity.nickname,
      providerId: userEntity.providerId,
      scannedBluetoothIds: new Set<string>(),
      stats: userEntity.stats,
    };
    this.users.set(userId, user);
    this.nicknameOwners.set(this.normalizeNickname(userEntity.nickname), userId);
  }

  async loadPlayerArmyToMemory(userId: string): Promise<void> {
    if (this.playerArmyRepository) {
      const playerArmy = await this.playerArmyRepository.findByOwner(userId);
      if (playerArmy) {
        const composition: SoldierBucket[] = Array.isArray(playerArmy.reservesComposition)
          ? playerArmy.reservesComposition
          : [];
        this.playerArmies.set(userId, composition);
        return;
      }
    }
    // Initialize empty army if not found
    this.playerArmies.set(userId, []);
  }

  private async getUserOrThrowAsync(userId: string): Promise<UserState> {
    // Try memory first
    const cached = this.users.get(userId);
    if (cached) return cached;

    // Load from DB
    const userEntity = await this.userRepository.findById(userId);
    if (!userEntity) {
      throw new UnauthorizedException('Unknown player.');
    }

    this.loadUserToMemory(userEntity);
    await this.loadPlayerArmyToMemory(userId);
    return this.users.get(userId)!;
  }

  normalizeVisibleH3Indexes(value: unknown): string[] {
    if (!Array.isArray(value)) {
      return [];
    }

    return Array.from(
      new Set(
        value
          .filter((entry): entry is string => typeof entry === 'string')
          .map((entry) => entry.trim())
          .filter((entry) => entry.length > 0 && isValidCell(entry)),
      ),
    );
  }

  getMapSnapshot(userId: string, visibleH3Indexes: string[]) {
    return {
      hexagons: this.normalizeVisibleH3Indexes(visibleH3Indexes).map((h3Index) =>
        this.buildMapHexagonView(userId, h3Index),
      ),
    };
  }

  resumeSession(
    userId: string,
    lastSyncTimestamp: unknown,
    visibleH3Indexes: string[],
  ) {
    const lastSync = this.parseTimestamp(
      this.requireString(lastSyncTimestamp, 'lastSyncTimestamp'),
      'lastSyncTimestamp',
    );
    const changedVisibleHexes = this.normalizeVisibleH3Indexes(
      visibleH3Indexes,
    ).filter((h3Index) => {
      const hex = this.hexes.get(h3Index);
      return hex ? this.parseTimestamp(hex.changedAt, 'changedAt') > lastSync : false;
    });

    return this.getMapSnapshot(userId, changedVisibleHexes);
  }

  establishTerritory(userId: string, body: Record<string, unknown>) {
    const player = this.getUserOrThrow(userId);
    const h3Index = this.requireH3Index(body.h3Index, 'h3Index');
    const name = this.requireTerritoryName(body.name);

    if (this.getOwnedHexes(userId).length > 0) {
      throw new BadRequestException('The player has already established a home base.');
    }

    const hex = this.ensureHexRecord(h3Index);
    if (hex.ownerId) {
      throw new BadRequestException('The selected hexagon is already occupied.');
    }

    hex.ownerId = userId;
    hex.territoryId = null;
    this.touchHex(h3Index);
    player.homeCenterH3Index = h3Index;
    player.stats.hexesClaimed += 1;

    this.reconcilePlayerTerritories(userId);
    const homeTerritory = this.getHomeTerritory(userId);
    if (!homeTerritory) {
      throw new BadRequestException('Failed to establish the home territory.');
    }

    homeTerritory.name = name;
    homeTerritory.centerH3Index = h3Index;
    homeTerritory.updatedAt = this.nowIso();

    this.emitMapChanged([h3Index]);
    this.emitHexDetailUpdate(userId, h3Index);
    this.emitTerritoryUpdate(userId);

    return {
      status: 'success',
      territoryId: homeTerritory.id,
    };
  }

  occupyHex(userId: string, body: Record<string, unknown>) {
    const player = this.getUserOrThrow(userId);
    if (!this.getHomeTerritory(userId)) {
      throw new BadRequestException('Establish a home territory before occupying more hexagons.');
    }

    const h3Index = this.requireH3Index(body.h3Index, 'h3Index');
    const latitude = this.requireNumber(body.latitude, 'latitude');
    const longitude = this.requireNumber(body.longitude, 'longitude');
    const garrisonComposition = this.requireCompositionArray(
      body.garrisonComposition,
      'garrisonComposition',
      { minItems: 1 },
    );
    const territoryName = this.optionalTerritoryName(body.territoryName);

    this.assertCoordinatesInHex(latitude, longitude, h3Index);
    player.lastLocation = {
      h3Index,
      isMocked: false,
      latitude,
      longitude,
      updatedAt: this.nowIso(),
    };

    const hex = this.ensureHexRecord(h3Index);
    if (hex.ownerId) {
      throw new BadRequestException('The selected hexagon is not free.');
    }

    // Validate composition exists in reserves and copy for removal
    const toGarrison = this.requireReserveComposition(userId, garrisonComposition, 'garrisonComposition');

    const createsNewTerritory = !this.getNeighborIndexes(h3Index).some(
      (neighbor) => this.hexes.get(neighbor)?.ownerId === userId,
    );

    hex.ownerId = userId;
    hex.territoryId = null;
    this.addToGarrisonComposition(h3Index, toGarrison);
    this.removeFromReserveComposition(userId, toGarrison,
      toGarrison.reduce((s, b) => s + b.count, 0),
      this.sumCompositionBs(toGarrison)
    );
    this.touchHex(h3Index);

    player.stats.hexesClaimed += 1;
    this.reconcilePlayerTerritories(
      userId,
      createsNewTerritory ? { createdHex: h3Index, name: territoryName ?? undefined } : undefined,
    );

    const territory = this.getTerritoryForHex(h3Index);
    if (!territory) {
      throw new BadRequestException('Failed to assign the occupied hex to a territory.');
    }

    this.emitMapChanged([h3Index]);
    this.emitArmyUpdate(userId);
    this.emitHexDetailUpdate(userId, h3Index);
    this.emitTerritoryUpdate(userId);

    return {
      createdNewTerritory: createsNewTerritory,
      status: 'success',
      territoryId: territory.id,
    };
  }

  getHexDetail(userId: string, h3Index: string): HexDetailPayload {
    return this.buildHexDetailPayload(userId, this.requireH3Index(h3Index, 'h3Index'));
  }

  changeCenter(
    userId: string,
    territoryId: string,
    body: Record<string, unknown>,
  ) {
    const territory = this.getOwnedTerritoryOrThrow(userId, territoryId);
    if (territory.type !== 'HOME') {
      throw new BadRequestException('Only the home territory can have a center.');
    }

    const h3Index = this.requireH3Index(body.h3Index, 'h3Index');
    if (!territory.hexIndexes.has(h3Index)) {
      throw new BadRequestException('The selected center must belong to the home territory.');
    }

    const player = this.getUserOrThrow(userId);
    const previousCenter = player.homeCenterH3Index;
    player.homeCenterH3Index = h3Index;

    this.reconcilePlayerTerritories(userId);
    this.touchHexes([previousCenter, h3Index]);
    this.emitMapChanged([previousCenter, h3Index]);
    this.emitHexDetailUpdate(userId, h3Index);
    this.emitTerritoryUpdate(userId);

    return { status: 'success' };
  }

  getBarracks(userId: string) {
    return {
      patrols: this.getOwnedHexes(userId)
        .filter((hex) => hex.garrisonComposition.length > 0)
        .map((hex) => {
          const composition = hex.garrisonComposition;
          const territory = this.getTerritoryForHex(hex.h3Index);
          const totalBs = this.sumCompositionBs(composition);
          const soldierCount = composition.reduce((sum, bucket) => sum + bucket.count, 0);
          return {
            h3Index: hex.h3Index,
            soldierCount,
            territoryName: territory?.name ?? 'Unknown Territory',
            totalBs,
          };
        })
        .sort((left, right) => left.h3Index.localeCompare(right.h3Index)),
      reserves: this.playerArmies.get(userId) ?? [],
    };
  }

  listTerritories(userId: string) {
    const home = this.getHomeTerritory(userId);
    const outposts = this.getOutpostTerritories(userId);

    return {
      home: home
        ? {
            centerH3Index: home.centerH3Index ?? home.representativeH3Index,
            hexCount: home.hexIndexes.size,
            id: home.id,
            name: home.name,
          }
        : null,
      outposts: outposts
        .map((territory) => ({
          hexCount: territory.hexIndexes.size,
          id: territory.id,
          name: territory.name,
          representativeH3Index: territory.representativeH3Index,
        }))
        .sort((left, right) => left.name.localeCompare(right.name)),
    };
  }

  renameTerritory(
    userId: string,
    territoryId: string,
    body: Record<string, unknown>,
  ) {
    const territory = this.getOwnedTerritoryOrThrow(userId, territoryId);
    territory.name = this.requireTerritoryName(body.name);
    territory.updatedAt = this.nowIso();

    this.emitTerritoryUpdate(userId);
    return { status: 'success' };
  }

  getBattleLogs(userId: string): BattleLogEntry[] {
    const logs = this.battleLogs.get(userId) ?? [];
    return [...logs].sort((left, right) => right.timestamp.localeCompare(left.timestamp));
  }

  getProfile(userId: string) {
    const player = this.getUserOrThrow(userId);
    return {
      email: player.email,
      nickname: player.nickname,
      stats: {
        biggestBattleBs: player.stats.biggestBattleBs,
        hexesClaimed: player.stats.hexesClaimed,
        scannedDevices: player.stats.scannedDevices,
      },
    };
  }

  changeNickname(userId: string, body: Record<string, unknown>) {
    const player = this.getUserOrThrow(userId);
    const nickname = this.requireNickname(body.nickname);
    this.ensureNicknameAvailable(nickname, userId);

    this.nicknameOwners.delete(this.normalizeNickname(player.nickname));
    player.nickname = nickname;
    this.nicknameOwners.set(this.normalizeNickname(nickname), userId);

    this.emitMapChanged(this.getOwnedHexes(userId).map((hex) => hex.h3Index));
    return { status: 'success' };
  }

  updateLocation(userId: string, body: Record<string, unknown>) {
    const latitude = this.requireNumber(body.latitude, 'latitude');
    const longitude = this.requireNumber(body.longitude, 'longitude');
    const h3Index = this.requireH3Index(body.h3Index, 'h3Index');
    const isMocked = this.requireBoolean(body.isMocked, 'isMocked');

    if (isMocked) {
      throw new BadRequestException('Mocked locations are not allowed.');
    }

    this.assertCoordinatesInHex(latitude, longitude, h3Index);

    const player = this.getUserOrThrow(userId);
    const now = Date.now();
    if (player.lastLocation) {
      const previousTimestamp = this.parseTimestamp(
        player.lastLocation.updatedAt,
        'lastLocation.updatedAt',
      );
      const elapsedMs = now - previousTimestamp;
      if (elapsedMs > 0) {
        const distanceMeters = this.computeDistanceMeters(
          player.lastLocation.latitude,
          player.lastLocation.longitude,
          latitude,
          longitude,
        );
        const speedKmH = (distanceMeters / 1000) / (elapsedMs / 3_600_000);
        if (speedKmH > MAX_SPEED_KMH) {
          throw new BadRequestException('Movement speed exceeded the anti-cheat threshold.');
        }
      }
    }

    player.lastLocation = {
      h3Index,
      isMocked: false,
      latitude,
      longitude,
      updatedAt: new Date(now).toISOString(),
    };

    return {
      h3Index,
      status: 'success',
    };
  }

  recruitDevice(userId: string, body: Record<string, unknown>) {
    const player = this.getUserOrThrow(userId);
    const bluetoothId = this.requireString(body.bluetoothId, 'bluetoothId');
    const calculatedSoldier = this.requireCalculatedSoldier(
      body.calculatedSoldier,
      'calculatedSoldier',
    );

    if (player.scannedBluetoothIds.has(bluetoothId)) {
      const skippedPayload: RecruitResultPayload = {
        bluetoothId,
        message: 'Device already scanned. Recruitment skipped.',
        status: 'SKIPPED',
      };
      this.emitUserEvent(userId, 'recruit_result', skippedPayload);
      return skippedPayload;
    }

    player.scannedBluetoothIds.add(bluetoothId);
    player.stats.scannedDevices += 1;

    // Find or create bucket in reserves and increment count/totalBs
    const bucket = this.getOrCreateReserveBucket(userId, {
      type: calculatedSoldier.type,
      rarity: calculatedSoldier.rarity,
      skill: calculatedSoldier.skill,
    });
    bucket.count += 1;
    bucket.totalBs += calculatedSoldier.bs;

    const recruitPayload: RecruitResultPayload = {
      bluetoothId,
      message: `Recruited ${calculatedSoldier.type} (${calculatedSoldier.rarity}, ${calculatedSoldier.bs} BS).`,
      status: 'SUCCESS',
    };

    this.emitUserEvent(userId, 'recruit_result', recruitPayload);
    this.emitArmyUpdate(userId);

    return recruitPayload;
  }

  modifyGarrison(userId: string, body: Record<string, unknown>) {
    const h3Index = this.requireH3Index(body.h3Index, 'h3Index');
    const action = this.requireEnum<GarrisonAction>(
      body.action,
      ['DEPLOY', 'WITHDRAW'],
      'action',
    );
    const composition = this.requireCompositionArray(body.composition, 'composition', {
      minItems: 1,
    });
    const hex = this.getOwnedHexOrThrow(userId, h3Index);

    if (this.pendingBattleByHex.has(h3Index)) {
      throw new BadRequestException(
        'The hexagon is under attack. Use send_reinforcements for active defense.',
      );
    }

    this.assertPlayerStandingInHex(userId, h3Index);

    if (action === 'DEPLOY') {
      const toGarrison = this.requireReserveComposition(userId, composition, 'composition');
      this.addToGarrisonComposition(h3Index, toGarrison);
      this.removeFromReserveComposition(userId, toGarrison,
        toGarrison.reduce((s, b) => s + b.count, 0),
        this.sumCompositionBs(toGarrison)
      );
    } else {
      const toReserve = this.requireGarrisonComposition(userId, h3Index, composition, 'composition');
      this.removeFromGarrisonComposition(h3Index, toReserve);
      this.addToReserveComposition(userId, toReserve);
    }

    this.touchHex(h3Index);
    this.emitMapChanged([h3Index]);
    this.emitArmyUpdate(userId);
    this.emitHexDetailUpdate(userId, h3Index);

    return { status: 'success' };
  }

  sendReinforcements(userId: string, body: Record<string, unknown>) {
    const targetH3Index = this.requireH3Index(body.targetH3Index, 'targetH3Index');
    const battle = this.getPendingBattleForHexOrThrow(targetH3Index);
    if (battle.defenderUserId !== userId) {
      throw new BadRequestException('Only the defending player can reinforce this hexagon.');
    }

    const composition = this.requireCompositionArray(body.composition, 'composition', {
      minItems: 1,
    });
    const burnSupportCount = this.optionalPositiveInteger(body.burnSupportCount);
    const territory = this.getTerritoryForHex(targetH3Index);
    if (!territory) {
      throw new BadRequestException('The target hexagon is not assigned to a territory.');
    }

    const toMove = this.requireReserveComposition(userId, composition, 'composition');
    const movedComposition: SoldierBucket[] = [];
    const lostComposition: SoldierBucket[] = [];
    let burnedSupportCount = 0;

    if (territory.type === 'OUTPOST') {
      if (burnSupportCount && burnSupportCount > 0) {
        // Burn support units from reserves and move rest
        let toBurn = burnSupportCount;
        const reserves = this.playerArmies.get(userId) ?? [];

        for (const bucket of reserves.filter((b) => b.type === 'SUPPORT')) {
          const burned = Math.min(toBurn, bucket.count);
          if (burned > 0) {
            burnedSupportCount += burned;
            bucket.count -= burned;
            bucket.totalBs = Math.max(0, bucket.totalBs - (burned * bucket.totalBs) / Math.max(1, bucket.count + burned));
            if (bucket.count <= 0) {
              const idx = reserves.indexOf(bucket);
              if (idx >= 0) reserves.splice(idx, 1);
            }
            toBurn -= burned;
          }
          if (toBurn <= 0) break;
        }
        movedComposition.push(...toMove);
      } else {
        // Apply 40% random losses (distributed by BS ratio)
        const totalMoveBs = this.sumCompositionBs(toMove);
        const lossBs = Math.ceil(totalMoveBs * 0.4);
        const moveBs = totalMoveBs - lossBs;

        // Allocate remaining BS proportionally across buckets
        for (const bucket of toMove) {
          const bucketShare = (bucket.totalBs / totalMoveBs) * moveBs;
          const movedCount = Math.round((bucketShare / bucket.totalBs) * bucket.count);
          const movedTotal = Math.round(bucketShare);
          movedComposition.push({
            type: bucket.type,
            rarity: bucket.rarity,
            skill: bucket.skill,
            count: Math.max(0, movedCount),
            totalBs: Math.max(0, movedTotal),
          });

          const lostCount = bucket.count - movedCount;
          const lostTotal = bucket.totalBs - movedTotal;
          if (lostCount > 0) {
            lostComposition.push({
              type: bucket.type,
              rarity: bucket.rarity,
              skill: bucket.skill,
              count: Math.max(0, lostCount),
              totalBs: Math.max(0, lostTotal),
            });
          }
        }
      }
    } else {
      // HOME territory: move all
      movedComposition.push(...toMove);
    }

    // Remove losses and moved from reserves
    if (lostComposition.length > 0) {
      this.removeFromReserveComposition(userId, lostComposition,
        lostComposition.reduce((s, b) => s + b.count, 0),
        this.sumCompositionBs(lostComposition)
      );
    }
    if (movedComposition.length > 0) {
      this.removeFromReserveComposition(userId, movedComposition,
        movedComposition.reduce((s, b) => s + b.count, 0),
        this.sumCompositionBs(movedComposition)
      );
      // Add to garrison
      this.addToGarrisonComposition(targetH3Index, movedComposition);
    }

    this.touchHex(targetH3Index);
    this.emitMapChanged([targetH3Index]);
    this.emitArmyUpdate(userId);
    this.emitHexDetailUpdate(userId, targetH3Index);

    return {
      burnedSupportCount,
      lostComposition,
      movedComposition,
      status: 'success',
    };
  }

  scoutHex(userId: string, body: Record<string, unknown>) {
    const targetH3Index = this.requireH3Index(body.targetH3Index, 'targetH3Index');
    const hex = this.ensureHexRecord(targetH3Index);

    if (!hex.ownerId) {
      throw new BadRequestException('Free hexagons cannot be scouted.');
    }
    if (hex.ownerId === userId) {
      throw new BadRequestException('You cannot scout your own hexagons.');
    }
    if (this.pendingBattleByHex.has(targetH3Index)) {
      throw new BadRequestException('Scouting is unavailable while a battle is already in progress.');
    }

    this.assertPlayerStandingInHex(userId, targetH3Index);

    // Consume one SCOUT support unit from reserves
    const reserves = this.playerArmies.get(userId) ?? [];
    const scoutBucket = reserves.find((b) => b.type === 'SUPPORT' && b.skill === 'SCOUT');
    if (!scoutBucket || scoutBucket.count < 1) {
      throw new BadRequestException('No SCOUT support unit available in reserve.');
    }
    const scoutBs = Math.floor(scoutBucket.totalBs / scoutBucket.count);
    scoutBucket.count -= 1;
    scoutBucket.totalBs -= scoutBs;
    if (scoutBucket.count <= 0) {
      reserves.splice(reserves.indexOf(scoutBucket), 1);
    }

    const garrisonComposition = hex.garrisonComposition;
    const hasJammer = garrisonComposition.some((b) => b.skill === 'JAMMER');
    const hasDecoy = garrisonComposition.some((b) => b.skill === 'DECOY');
    const actualDefenseBs = this.getEffectiveDefenseBs(targetH3Index);

    const payload: ScoutResultPayload = hasJammer
      ? {
          revealedBs: 0,
          status: 'JAMMED',
          targetH3Index,
        }
      : {
          revealedBs: hasDecoy ? actualDefenseBs * 5 : actualDefenseBs,
          status: 'SUCCESS',
          targetH3Index,
        };

    this.recordScoutLog(userId, targetH3Index, payload.status, payload.revealedBs);
    this.emitUserEvent(userId, 'scout_result', payload);

    return payload;
  }

  startAttack(userId: string, body: Record<string, unknown>) {
    const targetH3Index = this.requireH3Index(body.targetH3Index, 'targetH3Index');
    const attackerComposition = this.requireCompositionArray(
      body.attackerComposition,
      'attackerComposition',
      { minItems: 1 },
    );
    const hex = this.ensureHexRecord(targetH3Index);

    if (!hex.ownerId) {
      throw new BadRequestException('Use occupyHex for free hexagons.');
    }
    if (hex.ownerId === userId) {
      throw new BadRequestException('You cannot attack your own hexagon.');
    }
    if (this.pendingBattleByHex.has(targetH3Index)) {
      throw new BadRequestException('There is already an attack in progress on this hexagon.');
    }

    this.assertPlayerStandingInHex(userId, targetH3Index);

    // Validate and immediately deduct from reserves (no per-soldier locking)
    const toAttack = this.requireReserveComposition(userId, attackerComposition, 'attackerComposition');
    this.removeFromReserveComposition(
      userId,
      toAttack,
      toAttack.reduce((s, b) => s + b.count, 0),
      this.sumCompositionBs(toAttack),
    );

    const battleId = randomUUID();
    const now = this.nowIso();
    const resolveAt = new Date(Date.now() + ATTACK_PREPARATION_MS).toISOString();

    const timeoutHandle = setTimeout(() => {
      this.resolvePendingBattle(battleId);
    }, ATTACK_PREPARATION_MS);

    const pendingBattle: PendingBattle = {
      attackerComposition: toAttack,
      attackerUserId: userId,
      createdAt: now,
      defenderUserId: hex.ownerId,
      id: battleId,
      resolveAt,
      targetH3Index,
      timeoutHandle,
    };

    this.pendingBattles.set(battleId, pendingBattle);
    this.pendingBattleByHex.set(targetH3Index, battleId);

    const territory = this.getTerritoryForHex(targetH3Index);
    const attacker = this.getUserOrThrow(userId);
    const alertPayload: IncomingAttackAlertPayload = {
      attackerName: attacker.nickname,
      defendingH3Index: targetH3Index,
      territoryName: territory?.name ?? 'Unknown Territory',
    };

    this.emitArmyUpdate(userId);
    this.emitUserEvent(hex.ownerId, 'incoming_attack_alert', alertPayload);

    return {
      battleId,
      resolveAt,
      status: 'PENDING',
    };
  }

  getArmyUpdate(userId: string): ArmyUpdatePayload {
    const reserveComposition = this.playerArmies.get(userId) ?? [];
    const reserveCount = reserveComposition.reduce((sum, b) => sum + b.count, 0);
    const reserveBs = this.sumCompositionBs(reserveComposition);

    let patrolCount = 0;
    let patrolBs = 0;
    for (const hex of this.getOwnedHexes(userId)) {
      for (const bucket of hex.garrisonComposition) {
        patrolCount += bucket.count;
        patrolBs += bucket.totalBs;
      }
    }

    return {
      patrolCount,
      reserveBs,
      reserveCount,
    };
  }

  getTerritoryUpdate(userId: string): TerritoryUpdatePayload {
    const home = this.getHomeTerritory(userId);
    return {
      home: home
        ? {
            centerH3Index: home.centerH3Index ?? home.representativeH3Index,
            hexCount: home.hexIndexes.size,
            id: home.id,
          }
        : null,
      outposts: this.getOutpostTerritories(userId)
        .map((territory) => ({
          hexCount: territory.hexIndexes.size,
          id: territory.id,
          name: territory.name,
        }))
        .sort((left, right) => left.name.localeCompare(right.name)),
    };
  }

  private buildHexDetailPayload(userId: string, h3Index: string): HexDetailPayload {
    const hex = this.hexes.get(h3Index);
    if (!hex?.ownerId) {
      return {
        canOccupy: true,
        h3Index,
        state: 'FREE',
      };
    }

    if (hex.ownerId === userId) {
      const territory = this.getTerritoryForHex(h3Index);
      if (!territory) {
        throw new NotFoundException('Owned hexagon is missing a territory assignment.');
      }

      const garrisonComposition = hex.garrisonComposition;
      const reserveComposition = this.playerArmies.get(userId) ?? [];
      return {
        backgroundBonusPercent: this.countOwnedNeighbors(userId, h3Index) * 100,
        garrison: {
          soldierCount: garrisonComposition.reduce((sum, b) => sum + b.count, 0),
          composition: garrisonComposition,
          totalBs: this.sumCompositionBs(garrisonComposition),
        },
        h3Index,
        isCenter: this.getUserOrThrow(userId).homeCenterH3Index === h3Index,
        reserve: reserveComposition,
        state: 'OWNED',
        territory: {
          id: territory.id,
          name: territory.name,
          type: territory.type,
        },
      };
    }

    const owner = this.getUserOrThrow(hex.ownerId);
    const reserveComposition = this.playerArmies.get(userId) ?? [];
    const reserveScouts = reserveComposition.some(
      (bucket) => bucket.type === 'SUPPORT' && bucket.skill === 'SCOUT',
    );
    const reserveCount = reserveComposition.reduce((sum, b) => sum + b.count, 0);

    return {
      canAttack: this.isPlayerStandingInHex(userId, h3Index) && reserveCount > 0,
      canScout: this.isPlayerStandingInHex(userId, h3Index) && reserveScouts,
      fogOfWar: '??? BS',
      h3Index,
      ownerName: owner.nickname,
      state: 'ENEMY',
    };
  }

  private buildMapHexagonView(userId: string, h3Index: string): MapHexagonView {
    const hex = this.hexes.get(h3Index);
    if (!hex?.ownerId) {
      return {
        color: null,
        hasGarrison: false,
        h3Index,
        isCenter: false,
        ownerName: null,
      };
    }

    const owner = this.getUserOrThrow(hex.ownerId);
    return {
      color: owner.id === userId ? HOME_COLOR : ENEMY_COLOR,
      hasGarrison: hex.garrisonComposition.length > 0,
      h3Index,
      isCenter: owner.homeCenterH3Index === h3Index,
      ownerName: owner.nickname,
    };
  }

  private reconcilePlayerTerritories(userId: string, territoryHint?: TerritoryHint): void {
    const player = this.getUserOrThrow(userId);
    const ownedHexIndexes = this.getOwnedHexes(userId)
      .map((hex) => hex.h3Index)
      .sort((left, right) => left.localeCompare(right));
    const previousTerritories = this.getPlayerTerritories(userId);
    const previousHome = previousTerritories.find((territory) => territory.type === 'HOME');
    const previousOutposts = previousTerritories.filter(
      (territory) => territory.type === 'OUTPOST',
    );

    for (const territory of previousTerritories) {
      this.territories.delete(territory.id);
    }

    if (ownedHexIndexes.length === 0) {
      player.homeCenterH3Index = null;
      return;
    }

    const components = this.buildConnectedComponents(ownedHexIndexes);
    if (
      !player.homeCenterH3Index ||
      !ownedHexIndexes.includes(player.homeCenterH3Index)
    ) {
      player.homeCenterH3Index = this.chooseRepresentativeHex(components[0]);
    }

    let homeComponentIndex = components.findIndex((component) =>
      component.includes(player.homeCenterH3Index as string),
    );
    if (homeComponentIndex === -1) {
      homeComponentIndex = 0;
      player.homeCenterH3Index = this.chooseRepresentativeHex(components[0]);
    }

    const now = this.nowIso();
    const homeComponent = components[homeComponentIndex];
    const nextTerritories: TerritoryRecord[] = [
      {
        centerH3Index: player.homeCenterH3Index,
        createdAt: previousHome?.createdAt ?? now,
        hexIndexes: new Set(homeComponent),
        id: previousHome?.id ?? randomUUID(),
        name: previousHome?.name ?? 'Home Base',
        ownerId: userId,
        representativeH3Index: this.chooseRepresentativeHex(homeComponent),
        type: 'HOME',
        updatedAt: now,
      },
    ];

    const remainingComponents = components.filter(
      (_component, index) => index !== homeComponentIndex,
    );
    const usedOutpostIds = new Set<string>();
    let outpostOrdinal = 1;

    for (const component of remainingComponents) {
      const previousMatch = this.findBestOverlappingOutpost(
        component,
        previousOutposts,
        usedOutpostIds,
      );
      if (previousMatch) {
        usedOutpostIds.add(previousMatch.id);
      }

      const generatedName =
        territoryHint?.createdHex &&
        component.includes(territoryHint.createdHex) &&
        territoryHint.name
          ? territoryHint.name
          : `Outpost ${outpostOrdinal}`;

      nextTerritories.push({
        centerH3Index: null,
        createdAt: previousMatch?.createdAt ?? now,
        hexIndexes: new Set(component),
        id: previousMatch?.id ?? randomUUID(),
        name: previousMatch?.name ?? generatedName,
        ownerId: userId,
        representativeH3Index: this.chooseRepresentativeHex(component),
        type: 'OUTPOST',
        updatedAt: now,
      });

      outpostOrdinal += 1;
    }

    for (const territory of nextTerritories) {
      this.territories.set(territory.id, territory);
      for (const h3Index of territory.hexIndexes) {
        const hex = this.ensureHexRecord(h3Index);
        hex.ownerId = userId;
        hex.territoryId = territory.id;
      }
    }
  }

  private resolvePendingBattle(battleId: string): void {
    const battle = this.pendingBattles.get(battleId);
    if (!battle) {
      return;
    }

    clearTimeout(battle.timeoutHandle);
    this.pendingBattles.delete(battleId);
    this.pendingBattleByHex.delete(battle.targetH3Index);

    const attacker = this.getUserOrThrow(battle.attackerUserId);
    const defender = this.getUserOrThrow(battle.defenderUserId);
    const targetHex = this.ensureHexRecord(battle.targetH3Index);

    const attackerComposition = battle.attackerComposition;
    const defenderComposition = [...targetHex.garrisonComposition];

    const attackerTotalBs = this.sumCompositionBs(attackerComposition);
    const defenseMultiplier = this.countOwnedNeighbors(defender.id, battle.targetH3Index) + 1;
    const defenderBaseBs = this.sumCompositionBs(defenderComposition);
    const defenderEffectiveBs = defenderBaseBs * defenseMultiplier;
    const attackerWins = attackerTotalBs > defenderEffectiveBs;

    const attackerCenterBefore = attacker.homeCenterH3Index;
    const defenderCenterBefore = defender.homeCenterH3Index;

    const attackerTotalCount = attackerComposition.reduce((s, b) => s + b.count, 0);
    const defenderTotalCount = defenderComposition.reduce((s, b) => s + b.count, 0);

    if (attackerWins) {
      const remainingAttackerBs = Math.max(1, attackerTotalBs - defenderEffectiveBs);
      const attackerSurvivorComposition = this.projectSurvivorsComposition(
        attackerComposition,
        remainingAttackerBs,
      );
      const attackerSurvivorCount = attackerSurvivorComposition.reduce((s, b) => s + b.count, 0);
      const attackerDeadCount = attackerTotalCount - attackerSurvivorCount;
      const defenderDeadCount = defenderTotalCount;

      // Defender garrison fully wiped
      targetHex.garrisonComposition = [];
      // Attacker survivors placed in garrison
      targetHex.ownerId = attacker.id;
      targetHex.territoryId = null;
      targetHex.garrisonComposition = attackerSurvivorComposition;
      this.touchHex(battle.targetH3Index);

      attacker.stats.hexesClaimed += 1;
      this.updateWinningBattleStat(
        attacker.id,
        Math.max(attackerTotalBs, defenderEffectiveBs),
      );

      const createsOutpost = !this.getNeighborIndexes(battle.targetH3Index).some(
        (neighbor) => this.hexes.get(neighbor)?.ownerId === attacker.id,
      );
      this.reconcilePlayerTerritories(defender.id);
      this.reconcilePlayerTerritories(
        attacker.id,
        createsOutpost ? { createdHex: battle.targetH3Index } : undefined,
      );

      this.recordAttackLog(attacker.id, battle.targetH3Index, 'VICTORY', attackerDeadCount, attackerSurvivorCount);
      this.recordAttackLog(defender.id, battle.targetH3Index, 'DEFEAT', defenderDeadCount, 0);

      this.emitUserEvent(attacker.id, 'battle_result', {
        battleId,
        h3Index: battle.targetH3Index,
        myDeadCount: attackerDeadCount,
        mySurvivors: attackerSurvivorComposition,
        result: 'VICTORY',
      } satisfies BattleResultPayload);
      this.emitUserEvent(defender.id, 'battle_result', {
        battleId,
        h3Index: battle.targetH3Index,
        myDeadCount: defenderDeadCount,
        mySurvivors: [],
        result: 'DEFEAT',
      } satisfies BattleResultPayload);

      this.emitTerritoryUpdate(attacker.id);
      this.emitTerritoryUpdate(defender.id);
    } else {
      const remainingDefenderBs = Math.max(
        1,
        Math.ceil((defenderEffectiveBs - attackerTotalBs) / defenseMultiplier),
      );
      const defenderSurvivorComposition = this.projectSurvivorsComposition(
        defenderComposition,
        remainingDefenderBs,
      );
      const defenderSurvivorCount = defenderSurvivorComposition.reduce((s, b) => s + b.count, 0);
      const defenderDeadCount = defenderTotalCount - defenderSurvivorCount;
      const attackerDeadCount = attackerTotalCount;

      // Replace garrison with survivors
      targetHex.garrisonComposition = defenderSurvivorComposition;
      this.touchHex(battle.targetH3Index);

      this.updateWinningBattleStat(
        defender.id,
        Math.max(attackerTotalBs, defenderEffectiveBs),
      );

      this.recordAttackLog(attacker.id, battle.targetH3Index, 'DEFEAT', attackerDeadCount, 0);
      this.recordAttackLog(defender.id, battle.targetH3Index, 'VICTORY', defenderDeadCount, defenderSurvivorCount);

      this.emitUserEvent(attacker.id, 'battle_result', {
        battleId,
        h3Index: battle.targetH3Index,
        myDeadCount: attackerDeadCount,
        mySurvivors: [],
        result: 'DEFEAT',
      } satisfies BattleResultPayload);
      this.emitUserEvent(defender.id, 'battle_result', {
        battleId,
        h3Index: battle.targetH3Index,
        myDeadCount: defenderDeadCount,
        mySurvivors: defenderSurvivorComposition,
        result: 'VICTORY',
      } satisfies BattleResultPayload);
    }

    this.touchHexes([
      attackerCenterBefore,
      attacker.homeCenterH3Index,
      defenderCenterBefore,
      defender.homeCenterH3Index,
    ]);

    this.emitMapChanged([
      battle.targetH3Index,
      attackerCenterBefore,
      attacker.homeCenterH3Index,
      defenderCenterBefore,
      defender.homeCenterH3Index,
    ]);
    this.emitArmyUpdate(attacker.id);
    this.emitArmyUpdate(defender.id);
    this.emitHexDetailUpdate(attacker.id, battle.targetH3Index);
    this.emitHexDetailUpdate(defender.id, battle.targetH3Index);
  }

  private projectSurvivorsComposition(
    composition: SoldierBucket[],
    remainingTotalBs: number,
  ): SoldierBucket[] {
    const totalBs = this.sumCompositionBs(composition);
    if (totalBs <= 0 || composition.length === 0) return [];

    const clamped = Math.max(1, Math.min(Math.round(remainingTotalBs), totalBs));

    // Allocate remaining BS proportionally across buckets
    let assigned = 0;
    const result: Array<{ bucket: SoldierBucket; newTotalBs: number; fraction: number }> = [];

    for (const bucket of composition) {
      const exact = (bucket.totalBs / totalBs) * clamped;
      const floor = Math.floor(exact);
      result.push({ bucket, newTotalBs: floor, fraction: exact - floor });
      assigned += floor;
    }

    // Distribute remainder by largest fractional parts
    const remainder = clamped - assigned;
    result.sort((a, b) => b.fraction - a.fraction || b.bucket.totalBs - a.bucket.totalBs);
    for (let i = 0; i < remainder; i++) {
      result[i % result.length].newTotalBs += 1;
    }

    return result
      .map(({ bucket, newTotalBs }) => {
        if (newTotalBs <= 0) return null;
        // Proportionally scale count
        const newCount = Math.max(1, Math.round((newTotalBs / bucket.totalBs) * bucket.count));
        return {
          type: bucket.type,
          rarity: bucket.rarity,
          skill: bucket.skill,
          count: newCount,
          totalBs: newTotalBs,
        } satisfies SoldierBucket;
      })
      .filter((b): b is SoldierBucket => b !== null);
  }

  private recordAttackLog(
    userId: string,
    h3Index: string,
    result: BattleResult,
    myDead: number,
    mySurvivors: number,
  ): void {
    const logs = this.battleLogs.get(userId) ?? [];
    logs.push({
      h3Index,
      id: randomUUID(),
      myDead,
      mySurvivors,
      result,
      timestamp: this.nowIso(),
      type: 'ATTACK',
    });
    this.battleLogs.set(userId, logs);
  }

  private recordScoutLog(
    userId: string,
    h3Index: string,
    result: ScoutStatus,
    revealedBs: number,
  ): void {
    const logs = this.battleLogs.get(userId) ?? [];
    logs.push({
      h3Index,
      id: randomUUID(),
      result,
      revealedBs,
      timestamp: this.nowIso(),
      type: 'SCOUT',
    });
    this.battleLogs.set(userId, logs);
  }

  private emitArmyUpdate(userId: string): void {
    this.emitUserEvent(userId, 'army_update', this.getArmyUpdate(userId));
  }

  private emitHexDetailUpdate(userId: string, h3Index: string): void {
    this.emitUserEvent(userId, 'hex_detail_update', this.getHexDetail(userId, h3Index));
  }

  private emitMapChanged(h3Indexes: Array<string | null | undefined>): void {
    const uniqueIndexes = Array.from(
      new Set(h3Indexes.filter((h3Index): h3Index is string => Boolean(h3Index))),
    );
    if (uniqueIndexes.length > 0) {
      // Prefer Redis pub/sub when available for cross-instance distribution
      if (this.redisService) {
        try {
          void this.redisService.publish(
            'map_hexes_changed',
            JSON.stringify({ hexIndexes: uniqueIndexes }),
          );
        } catch {
          this.events.emit('map_hexes_changed', { hexIndexes: uniqueIndexes });
        }
      } else {
        this.events.emit('map_hexes_changed', { hexIndexes: uniqueIndexes });
      }
    }
  }

  private emitTerritoryUpdate(userId: string): void {
    this.emitUserEvent(userId, 'territory_update', this.getTerritoryUpdate(userId));
  }

  private emitUserEvent(userId: string, event: string, payload: unknown): void {
    if (this.redisService) {
      try {
        void this.redisService.publish(
          `user_event:${userId}`,
          JSON.stringify({ event, payload, userId }),
        );
        return;
      } catch {
        // fallback to local event emitter
      }
    }

    this.events.emit('user_event', {
      event,
      payload,
      userId,
    });
  }

  private getPendingBattleForHexOrThrow(h3Index: string): PendingBattle {
    const battleId = this.pendingBattleByHex.get(h3Index);
    if (!battleId) {
      throw new BadRequestException('There is no active attack on the selected hexagon.');
    }

    const battle = this.pendingBattles.get(battleId);
    if (!battle) {
      throw new BadRequestException('The pending battle could not be found.');
    }

    return battle;
  }

  private countOwnedNeighbors(ownerId: string, h3Index: string): number {
    return this.getNeighborIndexes(h3Index).filter(
      (neighbor) => this.hexes.get(neighbor)?.ownerId === ownerId,
    ).length;
  }

  private findBestOverlappingOutpost(
    component: string[],
    candidates: TerritoryRecord[],
    usedOutpostIds: Set<string>,
  ): TerritoryRecord | undefined {
    let bestMatch: TerritoryRecord | undefined;
    let bestOverlap = 0;

    for (const candidate of candidates) {
      if (usedOutpostIds.has(candidate.id)) {
        continue;
      }

      const overlap = component.filter((h3Index) => candidate.hexIndexes.has(h3Index)).length;
      if (overlap > bestOverlap) {
        bestMatch = candidate;
        bestOverlap = overlap;
      }
    }

    return bestOverlap > 0 ? bestMatch : undefined;
  }

  private buildConnectedComponents(h3Indexes: string[]): string[][] {
    const remaining = new Set(h3Indexes);
    const owned = new Set(h3Indexes);
    const components: string[][] = [];

    while (remaining.size > 0) {
      const iterator = remaining.values().next();
      const start = iterator.value as string;
      remaining.delete(start);

      const queue = [start];
      const component: string[] = [];

      while (queue.length > 0) {
        const current = queue.shift() as string;
        component.push(current);

        for (const neighbor of this.getNeighborIndexes(current)) {
          if (owned.has(neighbor) && remaining.has(neighbor)) {
            remaining.delete(neighbor);
            queue.push(neighbor);
          }
        }
      }

      component.sort((left, right) => left.localeCompare(right));
      components.push(component);
    }

    return components.sort(
      (left, right) => right.length - left.length || left[0].localeCompare(right[0]),
    );
  }

  private chooseRepresentativeHex(h3Indexes: string[]): string {
    return [...h3Indexes].sort((left, right) => left.localeCompare(right))[0];
  }

  private getNeighborIndexes(h3Index: string): string[] {
    return gridDisk(h3Index, 1).filter((candidate) => candidate !== h3Index);
  }

  private getEffectiveDefenseBs(h3Index: string): number {
    const hex = this.ensureHexRecord(h3Index);
    if (!hex.ownerId) return 0;
    const baseBs = this.sumCompositionBs(hex.garrisonComposition);
    return baseBs * (this.countOwnedNeighbors(hex.ownerId, h3Index) + 1);
  }

  private getHomeTerritory(userId: string): TerritoryRecord | null {
    return (
      this.getPlayerTerritories(userId).find((territory) => territory.type === 'HOME') ??
      null
    );
  }

  private getOutpostTerritories(userId: string): TerritoryRecord[] {
    return this.getPlayerTerritories(userId)
      .filter((territory) => territory.type === 'OUTPOST')
      .sort((left, right) => left.name.localeCompare(right.name));
  }

  private getOwnedHexes(userId: string): HexRecord[] {
    return [...this.hexes.values()]
      .filter((hex) => hex.ownerId === userId)
      .sort((left, right) => left.h3Index.localeCompare(right.h3Index));
  }

  private getOwnedHexOrThrow(userId: string, h3Index: string): HexRecord {
    const hex = this.ensureHexRecord(h3Index);
    if (hex.ownerId !== userId) {
      throw new BadRequestException('The selected hexagon does not belong to the player.');
    }

    return hex;
  }

  private getOwnedTerritoryOrThrow(
    userId: string,
    territoryId: string,
  ): TerritoryRecord {
    const territory = this.territories.get(territoryId);
    if (!territory || territory.ownerId !== userId) {
      throw new NotFoundException('Territory not found.');
    }

    return territory;
  }

  private getPlayerTerritories(userId: string): TerritoryRecord[] {
    return [...this.territories.values()]
      .filter((territory) => territory.ownerId === userId)
      .sort((left, right) => left.name.localeCompare(right.name));
  }

  private getTerritoryForHex(h3Index: string): TerritoryRecord | null {
    const territoryId = this.hexes.get(h3Index)?.territoryId;
    return territoryId ? this.territories.get(territoryId) ?? null : null;
  }

  private getUserOrThrow(userId: string): UserState {
    const user = this.users.get(userId);
    if (!user) {
      throw new UnauthorizedException('Unknown player.');
    }

    return user;
  }

  private updateWinningBattleStat(userId: string, battleBs: number): void {
    const player = this.getUserOrThrow(userId);
    player.stats.biggestBattleBs = Math.max(player.stats.biggestBattleBs, battleBs);
  }

  private assertCoordinatesInHex(
    latitude: number,
    longitude: number,
    h3Index: string,
  ): void {
    const computedIndex = latLngToCell(latitude, longitude, H3_RESOLUTION);
    if (computedIndex !== h3Index) {
      throw new BadRequestException('Coordinates do not match the selected H3 cell.');
    }
  }

  private assertPlayerStandingInHex(userId: string, h3Index: string): void {
    if (!this.isPlayerStandingInHex(userId, h3Index)) {
      throw new BadRequestException('The player is not physically present in the target hexagon.');
    }
  }

  private isPlayerStandingInHex(userId: string, h3Index: string): boolean {
    const player = this.getUserOrThrow(userId);
    if (!player.lastLocation || player.lastLocation.h3Index !== h3Index) {
      return false;
    }

    const ageMs = Date.now() - this.parseTimestamp(player.lastLocation.updatedAt, 'updatedAt');
    return ageMs <= LOCATION_TTL_MS && !player.lastLocation.isMocked;
  }

  private computeDistanceMeters(
    latitudeA: number,
    longitudeA: number,
    latitudeB: number,
    longitudeB: number,
  ): number {
    const earthRadiusMeters = 6_371_000;
    const toRadians = (value: number) => (value * Math.PI) / 180;
    const dLatitude = toRadians(latitudeB - latitudeA);
    const dLongitude = toRadians(longitudeB - longitudeA);
    const a =
      Math.sin(dLatitude / 2) ** 2 +
      Math.cos(toRadians(latitudeA)) *
        Math.cos(toRadians(latitudeB)) *
        Math.sin(dLongitude / 2) ** 2;
    return 2 * earthRadiusMeters * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  private ensureHexRecord(h3Index: string): HexRecord {
    const existingHex = this.hexes.get(h3Index);
    if (existingHex) {
      return existingHex;
    }

    const createdHex: HexRecord = {
      changedAt: this.nowIso(),
      garrisonComposition: [],
      h3Index,
      ownerId: null,
      territoryId: null,
    };
    this.hexes.set(h3Index, createdHex);
    return createdHex;
  }

  private ensureNicknameAvailable(nickname: string, ignoredUserId?: string): void {
    const nicknameOwner = this.nicknameOwners.get(this.normalizeNickname(nickname));
    if (nicknameOwner && nicknameOwner !== ignoredUserId) {
      throw new BadRequestException('Nickname is already in use.');
    }
  }


  private normalizeNickname(nickname: string): string {
    return nickname.trim().toLocaleLowerCase();
  }

  private nowIso(): string {
    return new Date().toISOString();
  }

  private optionalString(value: unknown): string | null {
    if (value === undefined || value === null) {
      return null;
    }

    if (typeof value !== 'string') {
      throw new BadRequestException('Expected a string value.');
    }

    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private optionalPositiveInteger(value: unknown): number | null {
    if (value === undefined || value === null) {
      return null;
    }

    if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
      throw new BadRequestException('Expected a positive integer value.');
    }

    return value;
  }

  private optionalTerritoryName(value: unknown): string | null {
    const name = this.optionalString(value);
    if (!name) {
      return null;
    }

    if (name.length > 48) {
      throw new BadRequestException('Territory name must be 48 characters or shorter.');
    }

    return name;
  }

  private parseTimestamp(value: string, fieldName: string): number {
    const timestamp = Date.parse(value);
    if (Number.isNaN(timestamp)) {
      throw new BadRequestException(`${fieldName} must be a valid ISO timestamp.`);
    }

    return timestamp;
  }

  private requireBoolean(value: unknown, fieldName: string): boolean {
    if (typeof value !== 'boolean') {
      throw new BadRequestException(`${fieldName} must be a boolean.`);
    }

    return value;
  }

  private requireCalculatedSoldier(
    value: unknown,
    fieldName: string,
  ): { bs: number; rarity: SoldierRarity; skill: SoldierSkill; type: SoldierType } {
    if (!value || typeof value !== 'object') {
      throw new BadRequestException(`${fieldName} must be an object.`);
    }

    const payload = value as Record<string, unknown>;
    const type = this.requireEnum<SoldierType>(
      payload.type,
      ['WARRIOR', 'SUPPORT'],
      `${fieldName}.type`,
    );
    const rarity = this.requireEnum<SoldierRarity>(
      payload.rarity,
      ['STANDARD', 'ADVANCED', 'PROTOTYPE'],
      `${fieldName}.rarity`,
    );
    const bs = this.requirePositiveInteger(payload.bs, `${fieldName}.bs`);
    const skill = this.requireSoldierSkill(payload.skill, `${fieldName}.skill`);

    if (type === 'WARRIOR' && skill !== null) {
      throw new BadRequestException('Warrior units must not define a support skill.');
    }

    return {
      bs,
      rarity,
      skill,
      type,
    };
  }

  private requireEnum<T extends string>(
    value: unknown,
    allowed: readonly T[],
    fieldName: string,
  ): T {
    if (typeof value !== 'string' || !allowed.includes(value as T)) {
      throw new BadRequestException(
        `${fieldName} must be one of: ${allowed.join(', ')}.`,
      );
    }

    return value as T;
  }

  private requireSoldierSkill(value: unknown, fieldName: string): SoldierSkill {
    if (value === null || value === undefined) {
      return null;
    }

    return this.requireEnum<Exclude<SoldierSkill, null>>(
      value,
      ['SCOUT', 'JAMMER', 'DECOY'],
      fieldName,
    );
  }

  private requireH3Index(value: unknown, fieldName: string): string {
    if (typeof value !== 'string' || !isValidCell(value.trim())) {
      throw new BadRequestException(`${fieldName} must be a valid H3 cell index.`);
    }

    return value.trim();
  }

  private requireNickname(value: unknown): string {
    const nickname = this.requireString(value, 'nickname');
    if (nickname.length < 3 || nickname.length > 24) {
      throw new BadRequestException('Nickname must be between 3 and 24 characters long.');
    }

    return nickname;
  }

  private requireNumber(value: unknown, fieldName: string): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw new BadRequestException(`${fieldName} must be a valid number.`);
    }

    return value;
  }

  private requirePositiveInteger(value: unknown, fieldName: string): number {
    if (
      typeof value !== 'number' ||
      !Number.isInteger(value) ||
      !Number.isFinite(value) ||
      value <= 0
    ) {
      throw new BadRequestException(`${fieldName} must be a positive integer.`);
    }

    return value;
  }

  private requireString(value: unknown, fieldName: string): string {
    if (typeof value !== 'string' || value.trim().length === 0) {
      throw new BadRequestException(`${fieldName} must be a non-empty string.`);
    }

    return value.trim();
  }

  private requireStringArray(
    value: unknown,
    fieldName: string,
    options?: { minLength?: number },
  ): string[] {
    if (!Array.isArray(value) || value.some((entry) => typeof entry !== 'string')) {
      throw new BadRequestException(`${fieldName} must be an array of strings.`);
    }

    const normalized = Array.from(
      new Set(value.map((entry) => entry.trim()).filter((entry) => entry.length > 0)),
    );
    if (options?.minLength && normalized.length < options.minLength) {
      throw new BadRequestException(
        `${fieldName} must contain at least ${options.minLength} item(s).`,
      );
    }

    return normalized;
  }

  private requireTerritoryName(value: unknown): string {
    const name = this.requireString(value, 'name');
    if (name.length > 48) {
      throw new BadRequestException('Territory name must be 48 characters or shorter.');
    }

    return name;
  }

  private requireCompositionArray(
    value: unknown,
    fieldName: string,
    options?: { minItems?: number },
  ): SoldierBucket[] {
    if (!Array.isArray(value)) {
      throw new BadRequestException(`${fieldName} must be an array of composition buckets.`);
    }

    const composition: SoldierBucket[] = [];
    for (const item of value) {
      if (!item || typeof item !== 'object') {
        throw new BadRequestException(`${fieldName} contains invalid bucket.`);
      }

      const bucket = item as Record<string, unknown>;
      const type = this.requireEnum<SoldierType>(
        bucket.type,
        ['WARRIOR', 'SUPPORT'],
        `${fieldName}[].type`,
      );
      const rarity = this.requireEnum<SoldierRarity>(
        bucket.rarity,
        ['STANDARD', 'ADVANCED', 'PROTOTYPE'],
        `${fieldName}[].rarity`,
      );
      const skill = this.requireSoldierSkill(bucket.skill, `${fieldName}[].skill`);
      const count = this.requirePositiveInteger(bucket.count, `${fieldName}[].count`);
      const totalBs = this.requirePositiveInteger(bucket.totalBs, `${fieldName}[].totalBs`);

      if (type === 'WARRIOR' && skill !== null) {
        throw new BadRequestException(`${fieldName}: Warrior units must not define a support skill.`);
      }

      composition.push({ type, rarity, skill, count, totalBs });
    }

    if (options?.minItems && composition.length < options.minItems) {
      throw new BadRequestException(
        `${fieldName} must contain at least ${options.minItems} item(s).`,
      );
    }

    return composition;
  }

  private requireReserveComposition(
    userId: string,
    requested: SoldierBucket[],
    fieldName: string,
  ): SoldierBucket[] {
    const reserves = this.playerArmies.get(userId) ?? [];
    const result: SoldierBucket[] = [];

    for (const requestBucket of requested) {
      const matchingBucket = reserves.find(
        (b) => b.type === requestBucket.type && b.rarity === requestBucket.rarity && b.skill === requestBucket.skill,
      );

      if (!matchingBucket || matchingBucket.count < requestBucket.count || matchingBucket.totalBs < requestBucket.totalBs) {
        throw new BadRequestException(
          `${fieldName}: insufficient soldiers of type ${requestBucket.type} / ${requestBucket.rarity} / ${requestBucket.skill}.`,
        );
      }

      result.push({ ...requestBucket });
    }

    return result;
  }

  private requireGarrisonComposition(
    userId: string,
    h3Index: string,
    requested: SoldierBucket[],
    fieldName: string,
  ): SoldierBucket[] {
    const hex = this.hexes.get(h3Index);
    if (!hex) {
      throw new BadRequestException(`${fieldName}: hexagon not found.`);
    }

    const result: SoldierBucket[] = [];

    for (const requestBucket of requested) {
      const matchingBucket = hex.garrisonComposition.find(
        (b) => b.type === requestBucket.type && b.rarity === requestBucket.rarity && b.skill === requestBucket.skill,
      );

      if (!matchingBucket || matchingBucket.count < requestBucket.count || matchingBucket.totalBs < requestBucket.totalBs) {
        throw new BadRequestException(
          `${fieldName}: insufficient soldiers of type ${requestBucket.type} / ${requestBucket.rarity} / ${requestBucket.skill} in garrison.`,
        );
      }

      result.push({ ...requestBucket });
    }

    return result;
  }

  private addToReserveComposition(userId: string, composition: SoldierBucket[]): void {
    let reserves = this.playerArmies.get(userId);
    if (!reserves) {
      reserves = [];
      this.playerArmies.set(userId, reserves);
    }

    for (const bucket of composition) {
      const existing = reserves.find(
        (b) => b.type === bucket.type && b.rarity === bucket.rarity && b.skill === bucket.skill,
      );
      if (existing) {
        existing.count += bucket.count;
        existing.totalBs += bucket.totalBs;
      } else {
        reserves.push({ ...bucket });
      }
    }
  }

  private sumCompositionBs(composition: SoldierBucket[]): number {
    return composition.reduce((sum, bucket) => sum + bucket.totalBs, 0);
  }

  private getOrCreateReserveBucket(userId: string, key: { type: SoldierType; rarity: SoldierRarity; skill: SoldierSkill }): SoldierBucket {
    let composition = this.playerArmies.get(userId);
    if (!composition) {
      composition = [];
      this.playerArmies.set(userId, composition);
    }

    let bucket = composition.find(
      (b) => b.type === key.type && b.rarity === key.rarity && b.skill === key.skill,
    );

    if (!bucket) {
      bucket = {
        type: key.type,
        rarity: key.rarity,
        skill: key.skill,
        count: 0,
        totalBs: 0,
      };
      composition.push(bucket);
    }

    return bucket;
  }

  private removeFromReserveComposition(userId: string, composition: SoldierBucket[], removeCount: number, removeTotalBs: number): void {
    if (removeCount <= 0 || composition.length === 0) return;

    const reserves = this.playerArmies.get(userId);
    if (!reserves) return;

    // Find and remove from matching composition
    for (const bucket of composition) {
      const idx = reserves.findIndex(
        (b) => b.type === bucket.type && b.rarity === bucket.rarity && b.skill === bucket.skill,
      );
      if (idx >= 0) {
        reserves[idx].count = Math.max(0, reserves[idx].count - bucket.count);
        reserves[idx].totalBs = Math.max(0, reserves[idx].totalBs - bucket.totalBs);
        if (reserves[idx].count <= 0) {
          reserves.splice(idx, 1);
        }
      }
    }
  }

  private addToGarrisonComposition(h3Index: string, composition: SoldierBucket[]): void {
    const hex = this.ensureHexRecord(h3Index);
    for (const bucket of composition) {
      const existing = hex.garrisonComposition.find(
        (b) => b.type === bucket.type && b.rarity === bucket.rarity && b.skill === bucket.skill,
      );
      if (existing) {
        existing.count += bucket.count;
        existing.totalBs += bucket.totalBs;
      } else {
        hex.garrisonComposition.push({ ...bucket });
      }
    }
  }

  private removeFromGarrisonComposition(h3Index: string, composition: SoldierBucket[]): void {
    const hex = this.hexes.get(h3Index);
    if (!hex) return;

    for (const bucket of composition) {
      const idx = hex.garrisonComposition.findIndex(
        (b) => b.type === bucket.type && b.rarity === bucket.rarity && b.skill === bucket.skill,
      );
      if (idx >= 0) {
        hex.garrisonComposition[idx].count = Math.max(0, hex.garrisonComposition[idx].count - bucket.count);
        hex.garrisonComposition[idx].totalBs = Math.max(0, hex.garrisonComposition[idx].totalBs - bucket.totalBs);
        if (hex.garrisonComposition[idx].count <= 0) {
          hex.garrisonComposition.splice(idx, 1);
        }
      }
    }
  }


  private touchHex(h3Index: string): void {
    this.ensureHexRecord(h3Index).changedAt = this.nowIso();
  }

  private touchHexes(h3Indexes: Array<string | null | undefined>): void {
    for (const h3Index of h3Indexes) {
      if (h3Index) {
        this.touchHex(h3Index);
      }
    }
  }
}
