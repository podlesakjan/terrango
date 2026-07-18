import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  BattleLogEntity,
  BluetoothScanEntity,
  HexEntity,
  SoldierEntity,
  TerritoryEntity,
  UserEntity,
} from './entities';
import {
  BattleLogRepository,
  BluetoothScanRepository,
  HexRepository,
  SoldierRepository,
  TerritoryRepository,
  UserRepository,
} from './repositories';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST ?? 'localhost',
      port: parseInt(process.env.DB_PORT ?? '5432', 10),
      username: process.env.DB_USER ?? 'terrango',
      password: process.env.DB_PASSWORD ?? 'terrango',
      database: process.env.DB_NAME ?? 'terrango',
      entities: [
        UserEntity,
        SoldierEntity,
        HexEntity,
        TerritoryEntity,
        BluetoothScanEntity,
        BattleLogEntity,
      ],
      synchronize: process.env.NODE_ENV !== 'production',
      logging: process.env.NODE_ENV === 'development',
    }),
    TypeOrmModule.forFeature([
      UserEntity,
      SoldierEntity,
      HexEntity,
      TerritoryEntity,
      BluetoothScanEntity,
      BattleLogEntity,
    ]),
  ],
  providers: [
    UserRepository,
    SoldierRepository,
    HexRepository,
    TerritoryRepository,
    BattleLogRepository,
    BluetoothScanRepository,
  ],
  exports: [
    TypeOrmModule,
    UserRepository,
    SoldierRepository,
    HexRepository,
    TerritoryRepository,
    BattleLogRepository,
    BluetoothScanRepository,
  ],
})
export class DatabaseModule {}


