import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('territories')
@Index('idx_owner_id', { synchronize: false })
export class TerritoryEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  ownerId!: string;

  @Column('text')
  name!: string;

  @Column('text')
  type!: 'HOME' | 'OUTPOST';

  @Column('text', { nullable: true })
  centerH3Index!: string | null;

  @Column('simple-array')
  hexIndexes!: string[];

  @Column('text')
  representativeH3Index!: string;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  createdAt!: Date;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP', onUpdate: 'CURRENT_TIMESTAMP' })
  updatedAt!: Date;
}


