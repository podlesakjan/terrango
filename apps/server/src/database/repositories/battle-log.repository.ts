import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { BattleLogEntity } from '../entities';

@Injectable()
export class BattleLogRepository {
  constructor(
    @InjectRepository(BattleLogEntity)
    private repo: Repository<BattleLogEntity>,
  ) {}

  async findByUserId(userId: string): Promise<BattleLogEntity[]> {
    return this.repo.find({
      where: { userId },
      order: { timestamp: 'DESC' },
    });
  }

  async findAll(): Promise<BattleLogEntity[]> {
    return this.repo.find({ order: { timestamp: 'DESC' } });
  }

  async create(log: Omit<BattleLogEntity, 'timestamp'>): Promise<BattleLogEntity> {
    const entity = this.repo.create(log);
    return this.repo.save(entity);
  }

  async save(log: BattleLogEntity): Promise<void> {
    await this.repo.save(log);
  }
}
