import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

@Entity('bluetooth_scans')
@Index('idx_user_id_device_id', ['userId', 'deviceId'], { unique: true })
export class BluetoothScanEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  userId!: string;

  @Column('text')
  deviceId!: string;

  @Column('timestamp', { default: () => 'CURRENT_TIMESTAMP' })
  scannedAt!: Date;
}


