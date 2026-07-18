import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SoldierEntity } from '../entities';

@Injectable()
export class SoldierRepository {
  constructor(
    @InjectRepository(SoldierEntity)
    private repo: Repository<SoldierEntity>,
  ) {}

  async findById(id: string): Promise<SoldierEntity | null> {
    return this.repo.findOne({ where: { id } });
  }

  async findByIds(ids: string[]): Promise<SoldierEntity[]> {
    if (ids.length === 0) return [];
    return this.repo.find({ where: ids.map((id) => ({ id })) });
  }

  async findByOwner(ownerId: string): Promise<SoldierEntity[]> {
    return this.repo.find({ where: { ownerId } });
  }

  async findReserves(ownerId: string): Promise<SoldierEntity[]> {
    return this.repo.find({
      where: {
        ownerId,
      },
    });
  }

  async findByLocationGarrison(h3Index: string): Promise<SoldierEntity[]> {
    const soldiers = await this.repo.find({ where: { ownerId: undefined } }); // placeholder
    return soldiers.filter(
      (s) => s.location.kind === 'GARRISON' && (s.location as any).h3Index === h3Index,
    );
  }

  async create(soldier: Omit<SoldierEntity, 'createdAt'>): Promise<SoldierEntity> {
    const entity = this.repo.create(soldier);
    return this.repo.save(entity);
  }

  async update(id: string, data: Partial<SoldierEntity>): Promise<void> {
    await this.repo.update(id, data);
  }

  async remove(id: string): Promise<void> {
    await this.repo.delete(id);
  }

  async removeMany(ids: string[]): Promise<void> {
    if (ids.length === 0) return;
    await this.repo.delete(ids);
  }
}

