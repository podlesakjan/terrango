import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
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
        HexEntity,
        PlayerArmyEntity,
        TerritoryEntity,
        BluetoothScanEntity,
        BattleLogEntity,
      ],
      synchronize: process.env.NODE_ENV !== 'production',
      logging: process.env.NODE_ENV === 'development',
    }),
    TypeOrmModule.forFeature([
      UserEntity,
      HexEntity,
      PlayerArmyEntity,
      TerritoryEntity,
      BluetoothScanEntity,
      BattleLogEntity,
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


