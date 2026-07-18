import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('hexes')
@Index('idx_owner_id', { synchronize: false })
@Index('idx_territory_id', { synchronize: false })
export class HexEntity {
  @PrimaryColumn('text')
  h3Index!: string;

  @Column('uuid', { nullable: true })
  ownerId!: string | null;

  @Column('uuid', { nullable: true })
  territoryId!: string | null;

  @Column('simple-array', { default: '[]' })
  garrisonSoldierIds!: string[];

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  changedAt!: Date;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  createdAt!: Date;
}


