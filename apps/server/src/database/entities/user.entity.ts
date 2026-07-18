import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('users')
@Index('idx_provider_id', { synchronize: false })
@Index('idx_nickname', { synchronize: false })
export class UserEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('text', { unique: true })
  providerId!: string;

  @Column('text', { unique: true })
  nickname!: string;

  @Column('text', { nullable: true })
  email!: string;

  @Column('uuid', { nullable: true })
  homeCenterH3Index!: string | null;

  @Column('jsonb', { default: '{"hexesClaimed":0,"biggestBattleBs":0,"scannedDevices":0}' })
  stats!: {
    hexesClaimed: number;
    biggestBattleBs: number;
    scannedDevices: number;
  };

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  createdAt!: Date;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP', onUpdate: 'CURRENT_TIMESTAMP' })
  updatedAt!: Date;
}


