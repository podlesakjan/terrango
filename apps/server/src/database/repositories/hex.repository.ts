import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { HexEntity } from '../entities';

@Injectable()
export class HexRepository {
  constructor(
    @InjectRepository(HexEntity)
    private repo: Repository<HexEntity>,
  ) {}

  async findByH3Index(h3Index: string): Promise<HexEntity | null> {
    return this.repo.findOne({ where: { h3Index } });
  }

  async findByH3Indexes(h3Indexes: string[]): Promise<HexEntity[]> {
    if (h3Indexes.length === 0) return [];
    return this.repo.find({ where: h3Indexes.map((h3Index) => ({ h3Index })) });
  }

  async findByOwner(ownerId: string): Promise<HexEntity[]> {
    return this.repo.find({ where: { ownerId } });
  }

  async create(hex: Omit<HexEntity, 'createdAt' | 'changedAt'>): Promise<HexEntity> {
    const entity = this.repo.create(hex);
    return this.repo.save(entity);
  }

  async update(h3Index: string, data: Partial<HexEntity>): Promise<void> {
    await this.repo.update(h3Index, {
      ...data,
      changedAt: new Date(),
    });
  }

  async addGarrisonSoldier(h3Index: string, soldierId: string): Promise<void> {
    const hex = await this.findByH3Index(h3Index);
    if (!hex) return;

    const soldiers = new Set(hex.garrisonSoldierIds || []);
    soldiers.add(soldierId);
    await this.update(h3Index, { garrisonSoldierIds: Array.from(soldiers) });
  }

  async removeGarrisonSoldier(h3Index: string, soldierId: string): Promise<void> {
    const hex = await this.findByH3Index(h3Index);
    if (!hex) return;

    const soldiers = new Set(hex.garrisonSoldierIds || []);
    soldiers.delete(soldierId);
    await this.update(h3Index, { garrisonSoldierIds: Array.from(soldiers) });
  }

  async getOrCreate(h3Index: string): Promise<HexEntity> {
    const existing = await this.findByH3Index(h3Index);
    if (existing) return existing;

    return this.create({
      h3Index,
      ownerId: null,
      territoryId: null,
      garrisonSoldierIds: [],
    });
  }
}

