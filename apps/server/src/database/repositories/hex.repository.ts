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
    throw new Error('addGarrisonSoldier is deprecated; use addGarrisonComposition');
  }

  async removeGarrisonSoldier(h3Index: string, soldierId: string): Promise<void> {
    throw new Error('removeGarrisonSoldier is deprecated; use removeGarrisonComposition');
  }

  async getOrCreate(h3Index: string): Promise<HexEntity> {
    const existing = await this.findByH3Index(h3Index);
    if (existing) return existing;

    return this.create({
      h3Index,
      ownerId: null,
      territoryId: null,
      garrisonComposition: [],
    });
  }

  // New API for aggregated composition buckets
  async addGarrisonComposition(h3Index: string, bucket: { type: string; rarity: string; skill: string | null; count: number; totalBs: number; }): Promise<void> {
    const hex = await this.getOrCreate(h3Index);
    const list: any[] = Array.isArray(hex.garrisonComposition) ? hex.garrisonComposition : [];

    const idx = list.findIndex(
      (b) => b.type === bucket.type && b.rarity === bucket.rarity && b.skill === bucket.skill,
    );

    if (idx === -1) {
      list.push({ ...bucket });
    } else {
      list[idx].count = (list[idx].count || 0) + bucket.count;
      list[idx].totalBs = (list[idx].totalBs || 0) + bucket.totalBs;
    }

    await this.update(h3Index, { garrisonComposition: list });
  }

  async removeGarrisonComposition(h3Index: string, bucketKey: { type: string; rarity: string; skill: string | null; }, removeCount: number, removeTotalBs?: number): Promise<void> {
    const hex = await this.findByH3Index(h3Index);
    if (!hex) return;

    const list: any[] = Array.isArray(hex.garrisonComposition) ? hex.garrisonComposition : [];
    const idx = list.findIndex((b) => b.type === bucketKey.type && b.rarity === bucketKey.rarity && b.skill === bucketKey.skill);
    if (idx === -1) return;

    list[idx].count = (list[idx].count || 0) - removeCount;
    if (removeTotalBs) list[idx].totalBs = (list[idx].totalBs || 0) - removeTotalBs;

    if (list[idx].count <= 0) {
      list.splice(idx, 1);
    }

    await this.update(h3Index, { garrisonComposition: list });
  }
}

