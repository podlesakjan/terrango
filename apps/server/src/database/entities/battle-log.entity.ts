import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('battle_logs')
@Index('idx_user_id_timestamp', { synchronize: false })
export class BattleLogEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  userId!: string;

  @Column('text')
  type!: 'ATTACK' | 'SCOUT';

  @Column('text')
  h3Index!: string;

  @Column('text')
  result!: 'VICTORY' | 'DEFEAT' | 'SUCCESS' | 'JAMMED';

  @Column('integer', { nullable: true })
  myDead!: number | null;

  @Column('integer', { nullable: true })
  mySurvivors!: number | null;

  @Column('integer', { nullable: true })
  revealedBs!: number | null;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  timestamp!: Date;
}


