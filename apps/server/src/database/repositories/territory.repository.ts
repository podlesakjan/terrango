import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TerritoryEntity } from '../entities';

@Injectable()
export class TerritoryRepository {
  constructor(
    @InjectRepository(TerritoryEntity)
    private repo: Repository<TerritoryEntity>,
  ) {}

  async findById(id: string): Promise<TerritoryEntity | null> {
    return this.repo.findOne({ where: { id } });
  }

  async findByOwner(ownerId: string): Promise<TerritoryEntity[]> {
    return this.repo.find({ where: { ownerId }, order: { name: 'ASC' } });
  }

  async findByOwnerAndType(ownerId: string, type: 'HOME' | 'OUTPOST'): Promise<TerritoryEntity[]> {
    return this.repo.find({ where: { ownerId, type }, order: { name: 'ASC' } });
  }

  async create(territory: Omit<TerritoryEntity, 'createdAt' | 'updatedAt'>): Promise<TerritoryEntity> {
    const entity = this.repo.create(territory);
    return this.repo.save(entity);
  }

  async update(id: string, data: Partial<TerritoryEntity>): Promise<void> {
    await this.repo.update(id, {
      ...data,
      updatedAt: new Date(),
    });
  }

  async remove(id: string): Promise<void> {
    await this.repo.delete(id);
  }

  async removeMany(ids: string[]): Promise<void> {
    if (ids.length === 0) return;
    await this.repo.delete(ids);
  }
}

