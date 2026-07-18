import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { randomInt, randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { RedisService } from '../redis/redis.module';
import { gridDisk, isValidCell, latLngToCell } from 'h3-js';
import { AuthService } from '../auth/auth.service';
import {
  UserRepository,
  SoldierRepository,
  HexRepository,
  TerritoryRepository,
  BattleLogRepository,
  BluetoothScanRepository,
} from '../database/repositories';

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
  Soldier,
  SoldierLocation,
  SoldierRarity,
  SoldierSkill,
  SoldierType,
  SoldierView,
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
  private readonly soldiers = new Map<string, Soldier>();
  private readonly territories = new Map<string, TerritoryRecord>();
  private readonly users = new Map<string, UserState>();

  constructor(
    private readonly authService: AuthService,
    private readonly userRepository: UserRepository,
    private readonly soldierRepository: SoldierRepository,
    private readonly hexRepository: HexRepository,
    private readonly territoryRepository: TerritoryRepository,
    private readonly battleLogRepository: BattleLogRepository,
    private readonly bluetoothScanRepository: BluetoothScanRepository,
    private readonly redisService?: RedisService,
  ) {
    this.events.setMaxListeners(0);
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

  async resolveToken(token: string | undefined): Promise<AuthenticatedPlayer> {
    const authenticated = this.authService.verifyToken(token);
    const user = await this.getUserOrThrowAsync(authenticated.id);
    return {
      id: user.id,
      nickname: user.nickname,
    };
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
    const soldierIds = this.requireStringArray(
      body.garrisonSoldierIds,
      'garrisonSoldierIds',
      { minLength: 1 },
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

    const soldiers = this.requireReserveSoldiers(userId, soldierIds, 'garrisonSoldierIds');
    const createsNewTerritory = !this.getNeighborIndexes(h3Index).some(
      (neighbor) => this.hexes.get(neighbor)?.ownerId === userId,
    );

    hex.ownerId = userId;
    hex.territoryId = null;
    this.placeSoldiersIntoGarrison(soldiers, h3Index);
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
        .filter((hex) => hex.garrisonSoldierIds.size > 0)
        .map((hex) => {
          const garrison = this.getGarrisonSoldiers(hex.h3Index);
          const territory = this.getTerritoryForHex(hex.h3Index);
          return {
            h3Index: hex.h3Index,
            soldierCount: garrison.length,
            territoryName: territory?.name ?? 'Unknown Territory',
            totalBs: this.sumSoldierBs(garrison),
          };
        })
        .sort((left, right) => left.h3Index.localeCompare(right.h3Index)),
      reserves: this.getReserveSoldiers(userId).map((soldier) =>
        this.toSoldierView(soldier),
      ),
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

    const soldier: Soldier = {
      bs: calculatedSoldier.bs,
      createdAt: this.nowIso(),
      id: randomUUID(),
      location: { kind: 'RESERVE' },
      ownerId: userId,
      rarity: calculatedSoldier.rarity,
      skill: calculatedSoldier.skill,
      type: calculatedSoldier.type,
    };
    this.soldiers.set(soldier.id, soldier);

    const recruitPayload: RecruitResultPayload = {
      bluetoothId,
      message: `Recruited ${soldier.type} (${soldier.rarity}, ${soldier.bs} BS).`,
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
    const soldierIds = this.requireStringArray(body.soldierIds, 'soldierIds', {
      minLength: 1,
    });
    const hex = this.getOwnedHexOrThrow(userId, h3Index);

    if (this.pendingBattleByHex.has(h3Index)) {
      throw new BadRequestException(
        'The hexagon is under attack. Use send_reinforcements for active defense.',
      );
    }

    this.assertPlayerStandingInHex(userId, h3Index);

    if (action === 'DEPLOY') {
      const soldiers = this.requireReserveSoldiers(userId, soldierIds, 'soldierIds');
      this.placeSoldiersIntoGarrison(soldiers, h3Index);
    } else {
      const soldiers = this.requireGarrisonSoldiers(
        userId,
        h3Index,
        soldierIds,
        'soldierIds',
      );
      this.moveSoldiersToReserve(soldiers);
      for (const soldierId of soldierIds) {
        hex.garrisonSoldierIds.delete(soldierId);
      }
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

    const soldierIds = this.requireStringArray(body.soldierIds, 'soldierIds', {
      minLength: 1,
    });
    const burnSupportUnitId = this.optionalString(body.burnSupportUnitId);
    const territory = this.getTerritoryForHex(targetH3Index);
    if (!territory) {
      throw new BadRequestException('The target hexagon is not assigned to a territory.');
    }

    const selectedSoldiers = this.requireReserveSoldiers(
      userId,
      soldierIds,
      'soldierIds',
    );

    const movedSoldierIds: string[] = [];
    const lostSoldierIds: string[] = [];
    let burnedSupportId: string | null = null;

    if (territory.type === 'OUTPOST') {
      if (burnSupportUnitId) {
        if (soldierIds.includes(burnSupportUnitId)) {
          throw new BadRequestException('The burned support unit must not be part of soldierIds.');
        }

        const supportSoldier = this.requireReserveSupportSoldier(userId, burnSupportUnitId);
        this.destroySoldiers([supportSoldier.id]);
        burnedSupportId = supportSoldier.id;
        movedSoldierIds.push(...selectedSoldiers.map((soldier) => soldier.id));
      } else {
        for (const soldier of selectedSoldiers) {
          if (randomInt(100) < 40) {
            lostSoldierIds.push(soldier.id);
          } else {
            movedSoldierIds.push(soldier.id);
          }
        }
      }
    } else {
      movedSoldierIds.push(...selectedSoldiers.map((soldier) => soldier.id));
    }

    if (lostSoldierIds.length > 0) {
      this.destroySoldiers(lostSoldierIds);
    }

    if (movedSoldierIds.length > 0) {
      const soldiersToMove = movedSoldierIds
        .map((soldierId) => this.soldiers.get(soldierId))
        .filter((soldier): soldier is Soldier => Boolean(soldier));
      this.placeSoldiersIntoGarrison(soldiersToMove, targetH3Index);
    }

    this.touchHex(targetH3Index);
    this.emitMapChanged([targetH3Index]);
    this.emitArmyUpdate(userId);
    this.emitHexDetailUpdate(userId, targetH3Index);

    return {
      burnedSupportUnitId: burnedSupportId,
      lostSoldierIds,
      movedSoldierIds,
      status: 'success',
    };
  }

  scoutHex(userId: string, body: Record<string, unknown>) {
    const targetH3Index = this.requireH3Index(body.targetH3Index, 'targetH3Index');
    const scoutSoldierId = this.requireString(body.scoutSoldierId, 'scoutSoldierId');
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

    const scout = this.requireReserveSupportSoldier(userId, scoutSoldierId, 'SCOUT');
    if (scout.skill !== 'SCOUT') {
      throw new BadRequestException('The selected support unit does not have the SCOUT skill.');
    }

    const defendingSoldiers = this.getGarrisonSoldiers(targetH3Index);
    const hasJammer = defendingSoldiers.some((soldier) => soldier.skill === 'JAMMER');
    const hasDecoy = defendingSoldiers.some((soldier) => soldier.skill === 'DECOY');
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
    const attackerSoldierIds = this.requireStringArray(
      body.attackerSoldierIds,
      'attackerSoldierIds',
      { minLength: 1 },
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
    const attackerSoldiers = this.requireReserveSoldiers(
      userId,
      attackerSoldierIds,
      'attackerSoldierIds',
    );

    const battleId = randomUUID();
    const now = this.nowIso();
    const resolveAt = new Date(Date.now() + ATTACK_PREPARATION_MS).toISOString();
    for (const soldier of attackerSoldiers) {
      soldier.location = {
        battleId,
        kind: 'LOCKED_ATTACK',
        targetH3Index,
      };
    }

    const timeoutHandle = setTimeout(() => {
      this.resolvePendingBattle(battleId);
    }, ATTACK_PREPARATION_MS);

    const pendingBattle: PendingBattle = {
      attackerSoldierIds: attackerSoldierIds,
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
    const reserveSoldiers = this.getReserveSoldiers(userId);
    const patrolCount = Array.from(this.soldiers.values()).filter(
      (soldier) =>
        soldier.ownerId === userId && soldier.location.kind === 'GARRISON',
    ).length;

    return {
      patrolCount,
      reserveBs: this.sumSoldierBs(reserveSoldiers),
      reserveCount: reserveSoldiers.length,
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

      const garrisonSoldiers = this.getGarrisonSoldiers(h3Index);
      return {
        backgroundBonusPercent: this.countOwnedNeighbors(userId, h3Index) * 100,
        garrison: {
          soldierCount: garrisonSoldiers.length,
          soldiers: garrisonSoldiers.map((soldier) => this.toSoldierView(soldier)),
          totalBs: this.sumSoldierBs(garrisonSoldiers),
        },
        h3Index,
        isCenter: this.getUserOrThrow(userId).homeCenterH3Index === h3Index,
        reserve: this.getReserveSoldiers(userId).map((soldier) => this.toSoldierView(soldier)),
        state: 'OWNED',
        territory: {
          id: territory.id,
          name: territory.name,
          type: territory.type,
        },
      };
    }

    const owner = this.getUserOrThrow(hex.ownerId);
    const reserveScouts = this.getReserveSoldiers(userId).some(
      (soldier) => soldier.type === 'SUPPORT' && soldier.skill === 'SCOUT',
    );

    return {
      canAttack: this.isPlayerStandingInHex(userId, h3Index) && this.getReserveSoldiers(userId).length > 0,
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
      hasGarrison: hex.garrisonSoldierIds.size > 0,
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
    const attackerSoldiers = battle.attackerSoldierIds
      .map((soldierId) => this.soldiers.get(soldierId))
      .filter((soldier): soldier is Soldier => Boolean(soldier));
    const defenderSoldiers = this.getGarrisonSoldiers(battle.targetH3Index);
    const attackerTotalBs = this.sumSoldierBs(attackerSoldiers);
    const defenseMultiplier = this.countOwnedNeighbors(defender.id, battle.targetH3Index) + 1;
    const defenderBaseBs = this.sumSoldierBs(defenderSoldiers);
    const defenderEffectiveBs = defenderBaseBs * defenseMultiplier;
    const attackerWins = attackerTotalBs > defenderEffectiveBs;

    const attackerCenterBefore = attacker.homeCenterH3Index;
    const defenderCenterBefore = defender.homeCenterH3Index;

    if (attackerWins) {
      const remainingAttackerBs = Math.max(1, attackerTotalBs - defenderEffectiveBs);
      const attackerSurvivors = this.projectSurvivors(
        attackerSoldiers,
        remainingAttackerBs,
      );
      const attackerSurvivorIds = new Set(attackerSurvivors.map((soldier) => soldier.id));
      const attackerDeadCount = attackerSoldiers.length - attackerSurvivors.length;
      const defenderDeadCount = defenderSoldiers.length;

      this.destroySoldiers(defenderSoldiers.map((soldier) => soldier.id));
      this.destroySoldiers(
        attackerSoldiers
          .filter((soldier) => !attackerSurvivorIds.has(soldier.id))
          .map((soldier) => soldier.id),
      );

      targetHex.ownerId = attacker.id;
      targetHex.territoryId = null;
      targetHex.garrisonSoldierIds = new Set<string>();
      for (const survivor of attackerSurvivors) {
        const soldier = this.soldiers.get(survivor.id);
        if (!soldier) {
          continue;
        }

        soldier.bs = survivor.bs;
        soldier.location = {
          h3Index: battle.targetH3Index,
          kind: 'GARRISON',
        };
        targetHex.garrisonSoldierIds.add(soldier.id);
      }
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

      this.recordAttackLog(
        attacker.id,
        battle.targetH3Index,
        'VICTORY',
        attackerDeadCount,
        attackerSurvivors.length,
      );
      this.recordAttackLog(
        defender.id,
        battle.targetH3Index,
        'DEFEAT',
        defenderDeadCount,
        0,
      );

      this.emitUserEvent(attacker.id, 'battle_result', {
        battleId,
        h3Index: battle.targetH3Index,
        myDeadCount: attackerDeadCount,
        mySurvivors: attackerSurvivors.map((survivor) => ({
          bs: survivor.bs,
          id: survivor.id,
        })),
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
      const defenderSurvivors = this.projectSurvivors(
        defenderSoldiers,
        remainingDefenderBs,
      );
      const defenderSurvivorIds = new Set(defenderSurvivors.map((soldier) => soldier.id));
      const defenderDeadCount = defenderSoldiers.length - defenderSurvivors.length;
      const attackerDeadCount = attackerSoldiers.length;

      this.destroySoldiers(attackerSoldiers.map((soldier) => soldier.id));
      this.destroySoldiers(
        defenderSoldiers
          .filter((soldier) => !defenderSurvivorIds.has(soldier.id))
          .map((soldier) => soldier.id),
      );

      targetHex.garrisonSoldierIds = new Set<string>();
      for (const survivor of defenderSurvivors) {
        const soldier = this.soldiers.get(survivor.id);
        if (!soldier) {
          continue;
        }

        soldier.bs = survivor.bs;
        soldier.location = {
          h3Index: battle.targetH3Index,
          kind: 'GARRISON',
        };
        targetHex.garrisonSoldierIds.add(soldier.id);
      }
      this.touchHex(battle.targetH3Index);

      this.updateWinningBattleStat(
        defender.id,
        Math.max(attackerTotalBs, defenderEffectiveBs),
      );

      this.recordAttackLog(
        attacker.id,
        battle.targetH3Index,
        'DEFEAT',
        attackerDeadCount,
        0,
      );
      this.recordAttackLog(
        defender.id,
        battle.targetH3Index,
        'VICTORY',
        defenderDeadCount,
        defenderSurvivors.length,
      );

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
        mySurvivors: defenderSurvivors.map((survivor) => ({
          bs: survivor.bs,
          id: survivor.id,
        })),
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

  private projectSurvivors(soldiers: Soldier[], remainingTotalBs: number): SoldierView[] {
    if (soldiers.length === 0) {
      return [];
    }

    const totalBs = this.sumSoldierBs(soldiers);
    if (totalBs <= 0) {
      return [];
    }

    const clampedRemainingBs = Math.max(
      1,
      Math.min(Math.round(remainingTotalBs), totalBs),
    );
    const allocations = soldiers.map((soldier) => {
      const exactShare = (soldier.bs / totalBs) * clampedRemainingBs;
      return {
        bs: Math.floor(exactShare),
        fraction: exactShare - Math.floor(exactShare),
        soldier,
      };
    });

    let assignedBs = allocations.reduce((sum, entry) => sum + entry.bs, 0);
    const ranked = [...allocations].sort(
      (left, right) =>
        right.fraction - left.fraction || right.soldier.bs - left.soldier.bs,
    );

    let cursor = 0;
    while (assignedBs < clampedRemainingBs && ranked.length > 0) {
      ranked[cursor % ranked.length].bs += 1;
      assignedBs += 1;
      cursor += 1;
    }

    return allocations
      .filter((entry) => entry.bs > 0)
      .map((entry) => ({
        bs: entry.bs,
        id: entry.soldier.id,
        rarity: entry.soldier.rarity,
        skill: entry.soldier.skill,
        type: entry.soldier.type,
      }))
      .sort((left, right) => right.bs - left.bs || left.id.localeCompare(right.id));
  }

  private placeSoldiersIntoGarrison(soldiers: Soldier[], h3Index: string): void {
    const hex = this.ensureHexRecord(h3Index);
    for (const soldier of soldiers) {
      soldier.location = {
        h3Index,
        kind: 'GARRISON',
      };
      hex.garrisonSoldierIds.add(soldier.id);
    }
  }

  private moveSoldiersToReserve(soldiers: Soldier[]): void {
    for (const soldier of soldiers) {
      soldier.location = { kind: 'RESERVE' };
    }
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

  private getEffectiveDefenseBs(h3Index: string): number {
    const hex = this.ensureHexRecord(h3Index);
    if (!hex.ownerId) {
      return 0;
    }

    const baseBs = this.sumSoldierBs(this.getGarrisonSoldiers(h3Index));
    return baseBs * (this.countOwnedNeighbors(hex.ownerId, h3Index) + 1);
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

  private getGarrisonSoldiers(h3Index: string): Soldier[] {
    const hex = this.ensureHexRecord(h3Index);
    return [...hex.garrisonSoldierIds]
      .map((soldierId) => this.soldiers.get(soldierId))
      .filter((soldier): soldier is Soldier => Boolean(soldier))
      .sort((left, right) => right.bs - left.bs || left.id.localeCompare(right.id));
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

  private getReserveSoldiers(userId: string): Soldier[] {
    return [...this.soldiers.values()]
      .filter(
        (soldier) =>
          soldier.ownerId === userId && soldier.location.kind === 'RESERVE',
      )
      .sort((left, right) => right.bs - left.bs || left.id.localeCompare(right.id));
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

  private destroySoldiers(soldierIds: string[]): void {
    for (const soldierId of new Set(soldierIds)) {
      const soldier = this.soldiers.get(soldierId);
      if (!soldier) {
        continue;
      }

      if (soldier.location.kind === 'GARRISON') {
        const hex = this.hexes.get(soldier.location.h3Index);
        hex?.garrisonSoldierIds.delete(soldierId);
      }

      this.soldiers.delete(soldierId);
    }
  }

  private ensureHexRecord(h3Index: string): HexRecord {
    const existingHex = this.hexes.get(h3Index);
    if (existingHex) {
      return existingHex;
    }

    const createdHex: HexRecord = {
      changedAt: this.nowIso(),
      garrisonSoldierIds: new Set<string>(),
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


  private moveLocationOrThrow(location: SoldierLocation, expectedKind: SoldierLocation['kind']) {
    if (location.kind !== expectedKind) {
      throw new BadRequestException(`Soldier is not in ${expectedKind.toLowerCase()}.`);
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
  ): Pick<Soldier, 'bs' | 'rarity' | 'skill' | 'type'> {
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

  private requireGarrisonSoldiers(
    userId: string,
    h3Index: string,
    soldierIds: string[],
    fieldName: string,
  ): Soldier[] {
    const soldiers = soldierIds.map((soldierId) => {
      const soldier = this.soldiers.get(soldierId);
      if (!soldier || soldier.ownerId !== userId) {
        throw new BadRequestException(`${fieldName} contains a soldier the player does not own.`);
      }

      if (soldier.location.kind !== 'GARRISON') {
        throw new BadRequestException(`${fieldName} contains a soldier that is not in a garrison.`);
      }
      if (soldier.location.h3Index !== h3Index) {
        throw new BadRequestException(`${fieldName} contains a soldier from a different garrison.`);
      }

      return soldier;
    });

    return soldiers;
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

  private requireReserveSoldiers(
    userId: string,
    soldierIds: string[],
    fieldName: string,
  ): Soldier[] {
    const soldiers = soldierIds.map((soldierId) => {
      const soldier = this.soldiers.get(soldierId);
      if (!soldier || soldier.ownerId !== userId) {
        throw new BadRequestException(`${fieldName} contains a soldier the player does not own.`);
      }

      this.moveLocationOrThrow(soldier.location, 'RESERVE');
      return soldier;
    });

    return soldiers;
  }

  private requireReserveSupportSoldier(
    userId: string,
    soldierId: string,
    requiredSkill?: Exclude<SoldierSkill, null>,
  ): Soldier {
    const soldier = this.soldiers.get(soldierId);
    if (!soldier || soldier.ownerId !== userId) {
      throw new BadRequestException('The support unit was not found in the player reserve.');
    }

    this.moveLocationOrThrow(soldier.location, 'RESERVE');
    if (soldier.type !== 'SUPPORT') {
      throw new BadRequestException('The selected soldier is not a support unit.');
    }
    if (requiredSkill && soldier.skill !== requiredSkill) {
      throw new BadRequestException(`The selected support unit must have the ${requiredSkill} skill.`);
    }

    return soldier;
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

  private sumSoldierBs(soldiers: Soldier[]): number {
    return soldiers.reduce((sum, soldier) => sum + soldier.bs, 0);
  }

  private toSoldierView(soldier: Soldier): SoldierView {
    return {
      bs: soldier.bs,
      id: soldier.id,
      rarity: soldier.rarity,
      skill: soldier.skill,
      type: soldier.type,
    };
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
