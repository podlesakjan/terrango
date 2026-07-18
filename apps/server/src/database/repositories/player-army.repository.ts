import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PlayerArmyEntity } from '../entities/player-army.entity';

@Injectable()
export class PlayerArmyRepository {
  constructor(
    @InjectRepository(PlayerArmyEntity)
    private repo: Repository<PlayerArmyEntity>,
  ) {}

  async findByOwner(ownerId: string): Promise<PlayerArmyEntity | null> {
    return this.repo.findOne({ where: { ownerId } });
  }

  async create(army: Omit<PlayerArmyEntity, 'createdAt' | 'updatedAt'>): Promise<PlayerArmyEntity> {
    const entity = this.repo.create(army);
    return this.repo.save(entity);
  }

  async update(ownerId: string, data: Partial<PlayerArmyEntity>): Promise<void> {
    const existing = await this.findByOwner(ownerId);
    if (!existing) return;
    await this.repo.update(existing.id, data);
  }

  async upsertReserves(ownerId: string, reservesComposition: any[]): Promise<void> {
    const existing = await this.findByOwner(ownerId);
    if (!existing) {
      await this.create({ id: cryptoRandomUuid(), ownerId, reservesComposition });
      return;
    }
    await this.update(ownerId, { reservesComposition });
  }
}

function cryptoRandomUuid() {
  // lightweight UUID generator for repository usage; replace with proper uuid generation in production
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

