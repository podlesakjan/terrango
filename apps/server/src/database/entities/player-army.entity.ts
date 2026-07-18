import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('player_armies')
@Index('idx_owner_id', { synchronize: false })
export class PlayerArmyEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid', { unique: true })
  ownerId!: string;

  // Aggregated reserves composition: array of buckets { type, rarity, skill, count, totalBs }
  @Column('jsonb', { default: () => "'[]'::jsonb" })
  reservesComposition!: any[];

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  createdAt!: Date;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP', onUpdate: 'CURRENT_TIMESTAMP' })
  updatedAt!: Date;
}

