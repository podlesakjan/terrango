export const ATTACK_PREPARATION_MS = 15_000;
export const ENEMY_COLOR = '#E53935';
export const H3_RESOLUTION = 9;
export const HOME_COLOR = '#2196F3';
export const LOCATION_TTL_MS = 5 * 60_000;
export const MAX_SPEED_KMH = 300;

export type SoldierType = 'WARRIOR' | 'SUPPORT';
export type SoldierRarity = 'STANDARD' | 'ADVANCED' | 'PROTOTYPE';
export type SoldierSkill = 'SCOUT' | 'JAMMER' | 'DECOY' | null;
export type TerritoryType = 'HOME' | 'OUTPOST';
export type HexState = 'FREE' | 'OWNED' | 'ENEMY';
export type GarrisonAction = 'DEPLOY' | 'WITHDRAW';
export type RecruitStatus = 'SUCCESS' | 'SKIPPED';
export type ScoutStatus = 'SUCCESS' | 'JAMMED';
export type BattleResult = 'VICTORY' | 'DEFEAT';

export interface AuthenticatedPlayer {
  id: string;
  nickname: string;
}

export interface PlayerLocation {
  latitude: number;
  longitude: number;
  h3Index: string;
  updatedAt: string;
  isMocked: boolean;
}

export interface PlayerStats {
  biggestBattleBs: number;
  hexesClaimed: number;
  scannedDevices: number;
}

export interface UserState extends AuthenticatedPlayer {
  createdAt: string;
  email: string;
  homeCenterH3Index: string | null;
  lastLocation: PlayerLocation | null;
  providerId: string;
  scannedBluetoothIds: Set<string>;
  stats: PlayerStats;
}

export interface ReserveLocation {
  kind: 'RESERVE';
}

export interface GarrisonLocation {
  h3Index: string;
  kind: 'GARRISON';
}

export interface LockedAttackLocation {
  battleId: string;
  kind: 'LOCKED_ATTACK';
  targetH3Index: string;
}

export type SoldierLocation = ReserveLocation | GarrisonLocation | LockedAttackLocation;

export interface Soldier {
  bs: number;
  createdAt: string;
  id: string;
  location: SoldierLocation;
  ownerId: string;
  rarity: SoldierRarity;
  skill: SoldierSkill;
  type: SoldierType;
}

export interface SoldierView {
  bs: number;
  id: string;
  rarity: SoldierRarity;
  skill: SoldierSkill;
  type: SoldierType;
}

export interface HexRecord {
  changedAt: string;
  garrisonSoldierIds: Set<string>;
  h3Index: string;
  ownerId: string | null;
  territoryId: string | null;
}

export interface TerritoryRecord {
  centerH3Index: string | null;
  createdAt: string;
  hexIndexes: Set<string>;
  id: string;
  name: string;
  ownerId: string;
  representativeH3Index: string;
  type: TerritoryType;
  updatedAt: string;
}

export interface AttackLogEntry {
  h3Index: string;
  id: string;
  myDead: number;
  mySurvivors: number;
  result: BattleResult;
  timestamp: string;
  type: 'ATTACK';
}

export interface ScoutLogEntry {
  h3Index: string;
  id: string;
  result: ScoutStatus;
  revealedBs: number;
  timestamp: string;
  type: 'SCOUT';
}

export type BattleLogEntry = AttackLogEntry | ScoutLogEntry;

export interface PendingBattle {
  attackerSoldierIds: string[];
  attackerUserId: string;
  createdAt: string;
  defenderUserId: string;
  id: string;
  resolveAt: string;
  targetH3Index: string;
  timeoutHandle: NodeJS.Timeout;
}

export interface MapHexagonView {
  color: string | null;
  hasGarrison: boolean;
  h3Index: string;
  isCenter: boolean;
  ownerName: string | null;
}

export interface ArmyUpdatePayload {
  patrolCount: number;
  reserveBs: number;
  reserveCount: number;
}

export interface TerritoryUpdatePayload {
  home: {
    centerH3Index: string;
    hexCount: number;
    id: string;
  } | null;
  outposts: Array<{
    hexCount: number;
    id: string;
    name: string;
  }>;
}

export interface RecruitResultPayload {
  bluetoothId: string;
  message: string;
  status: RecruitStatus;
}

export interface ScoutResultPayload {
  revealedBs: number;
  status: ScoutStatus;
  targetH3Index: string;
}

export interface BattleResultPayload {
  battleId: string;
  h3Index: string;
  myDeadCount: number;
  mySurvivors: Array<{
    bs: number;
    id: string;
  }>;
  result: BattleResult;
}

export interface IncomingAttackAlertPayload {
  attackerName: string;
  defendingH3Index: string;
  territoryName: string;
}

export interface HexGarrisonPayload {
  soldierCount: number;
  soldiers: SoldierView[];
  totalBs: number;
}

export interface HexDetailFreePayload {
  canOccupy: boolean;
  h3Index: string;
  state: 'FREE';
}

export interface HexDetailOwnedPayload {
  backgroundBonusPercent: number;
  garrison: HexGarrisonPayload;
  h3Index: string;
  isCenter: boolean;
  reserve: SoldierView[];
  state: 'OWNED';
  territory: {
    id: string;
    name: string;
    type: TerritoryType;
  };
}

export interface HexDetailEnemyPayload {
  canAttack: boolean;
  canScout: boolean;
  fogOfWar: '??? BS';
  h3Index: string;
  ownerName: string;
  state: 'ENEMY';
}

export type HexDetailPayload =
  | HexDetailEnemyPayload
  | HexDetailFreePayload
  | HexDetailOwnedPayload;
