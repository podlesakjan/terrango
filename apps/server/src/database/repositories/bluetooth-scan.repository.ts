import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { BluetoothScanEntity } from '../entities';

@Injectable()
export class BluetoothScanRepository {
  constructor(
    @InjectRepository(BluetoothScanEntity)
    private repo: Repository<BluetoothScanEntity>,
  ) {}

  async hasScanned(userId: string, deviceId: string): Promise<boolean> {
    const record = await this.repo.findOne({
      where: { userId, deviceId },
    });
    return !!record;
  }

  async recordScan(userId: string, deviceId: string): Promise<void> {
    // Use upsert pattern or just insert (unique constraint will prevent duplicates)
    const existing = await this.hasScanned(userId, deviceId);
    if (!existing) {
      const entity = this.repo.create({
        id: this.generateUuid(),
        userId,
        deviceId,
      });
      await this.repo.save(entity);
    }
  }

  async countScanned(userId: string): Promise<number> {
    return this.repo.count({ where: { userId } });
  }

  private generateUuid(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }
}

