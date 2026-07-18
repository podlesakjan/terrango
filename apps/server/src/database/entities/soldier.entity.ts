import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

type SoldierType = 'WARRIOR' | 'SUPPORT';
type SoldierRarity = 'STANDARD' | 'ADVANCED' | 'PROTOTYPE';
type SoldierSkill = 'SCOUT' | 'JAMMER' | 'DECOY' | null;

type SoldierLocation =
  | { kind: 'RESERVE' }
  | { kind: 'GARRISON'; h3Index: string }
  | { kind: 'LOCKED_ATTACK'; targetH3Index: string; battleId: string };

@Entity('soldiers')
@Index('idx_owner_id', { synchronize: false })
export class SoldierEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  ownerId!: string;

  @Column('text')
  type!: SoldierType;

  @Column('text')
  rarity!: SoldierRarity;

  @Column('integer')
  bs!: number;

  @Column('text', { nullable: true })
  skill!: SoldierSkill;

  @Column('jsonb')
  location!: SoldierLocation;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  createdAt!: Date;
}

