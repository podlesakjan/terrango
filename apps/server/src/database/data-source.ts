import 'reflect-metadata';
import * as path from 'path';
import { DataSource, DataSourceOptions } from 'typeorm';
import {
  BattleLogEntity,
  BluetoothScanEntity,
  HexEntity,
  PlayerArmyEntity,
  TerritoryEntity,
  UserEntity,
} from './entities';

const ENTITIES = [
  UserEntity,
  HexEntity,
  PlayerArmyEntity,
  TerritoryEntity,
  BluetoothScanEntity,
  BattleLogEntity,
];

const databaseUrl = process.env.DATABASE_URL ?? process.env.DB_URL;
const ssl =
  process.env.DB_SSL === 'true' || process.env.DATABASE_SSL === 'true'
    ? { rejectUnauthorized: false }
    : undefined;

const migrations = [path.join(__dirname, 'migrations', '*.{ts,js}')];

const baseOptions = {
  entities: ENTITIES,
  migrations,
  ...(ssl ? { ssl } : {}),
} satisfies Partial<DataSourceOptions>;

export const AppDataSource = new DataSource(
  databaseUrl
    ? ({
        type: 'postgres',
        url: databaseUrl,
        ...baseOptions,
      } as DataSourceOptions)
    : ({
        type: 'postgres',
        host: process.env.DB_HOST ?? 'localhost',
        port: parseInt(process.env.DB_PORT ?? '5432', 10),
        username: process.env.DB_USER ?? 'terrango',
        password: process.env.DB_PASSWORD ?? 'terrango',
        database: process.env.DB_NAME ?? 'terrango',
        ...baseOptions,
      } as DataSourceOptions),
);

