import { Module } from '@nestjs/common';
import { TypeOrmModule, type TypeOrmModuleOptions } from '@nestjs/typeorm';
import {
  BattleLogEntity,
  BluetoothScanEntity,
  HexEntity,
  PlayerArmyEntity,
  TerritoryEntity,
  UserEntity,
} from './entities';
import {
  BattleLogRepository,
  BluetoothScanRepository,
  HexRepository,
  PlayerArmyRepository,
  TerritoryRepository,
  UserRepository,
} from './repositories';

const ENTITIES = [
  UserEntity,
  HexEntity,
  PlayerArmyEntity,
  TerritoryEntity,
  BluetoothScanEntity,
  BattleLogEntity,
] as const;

function parseBoolean(value?: string): boolean {
  return value === 'true' || value === '1' || value === 'yes';
}

function createTypeOrmOptions(): TypeOrmModuleOptions {
  const isProduction = process.env.NODE_ENV === 'production';
  const databaseUrl = process.env.DATABASE_URL ?? process.env.DB_URL;
  const sslEnabled = parseBoolean(process.env.DB_SSL ?? process.env.DATABASE_SSL);

  const baseOptions: TypeOrmModuleOptions = {
    type: 'postgres',
    entities: [...ENTITIES],
    synchronize: !isProduction,
    logging: process.env.NODE_ENV === 'development',
  };

  if (databaseUrl) {
    return {
      ...baseOptions,
      url: databaseUrl,
      ...(sslEnabled ? { ssl: { rejectUnauthorized: false } } : {}),
    };
  }

  const host = process.env.DB_HOST;
  const port = process.env.DB_PORT;
  const username = process.env.DB_USER;
  const password = process.env.DB_PASSWORD;
  const database = process.env.DB_NAME;

  if (isProduction) {
    const missing = [
      !host && 'DB_HOST',
      !port && 'DB_PORT',
      !username && 'DB_USER',
      !password && 'DB_PASSWORD',
      !database && 'DB_NAME',
    ].filter(Boolean);

    if (missing.length > 0) {
      throw new Error(
        `Missing database configuration for production: ${missing.join(', ')}. ` +
          'Set DATABASE_URL or provide all DB_* variables explicitly.',
      );
    }
  }

  return {
    ...baseOptions,
    host: host ?? 'localhost',
    port: parseInt(port ?? '5432', 10),
    username: username ?? 'terrango',
    password: password ?? 'terrango',
    database: database ?? 'terrango',
    ...(sslEnabled ? { ssl: { rejectUnauthorized: false } } : {}),
  };
}

@Module({
  imports: [
    TypeOrmModule.forRoot(createTypeOrmOptions()),
    TypeOrmModule.forFeature([
      ...ENTITIES,
    ]),
  ],
  providers: [
    UserRepository,
    HexRepository,
    PlayerArmyRepository,
    TerritoryRepository,
    BattleLogRepository,
    BluetoothScanRepository,
  ],
  exports: [
    TypeOrmModule,
    UserRepository,
    HexRepository,
    PlayerArmyRepository,
    TerritoryRepository,
    BattleLogRepository,
    BluetoothScanRepository,
  ],
})
export class DatabaseModule {}


