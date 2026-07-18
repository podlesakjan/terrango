import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UserEntity } from '../entities';

@Injectable()
export class UserRepository {
  constructor(
    @InjectRepository(UserEntity)
    private repo: Repository<UserEntity>,
  ) {}

  async findById(id: string): Promise<UserEntity | null> {
    return this.repo.findOne({ where: { id } });
  }

  async findByProviderId(providerId: string): Promise<UserEntity | null> {
    return this.repo.findOne({ where: { providerId } });
  }

  async findByNickname(nickname: string): Promise<UserEntity | null> {
    return this.repo
      .createQueryBuilder('u')
      .where('LOWER(u.nickname) = LOWER(:nickname)', { nickname })
      .getOne();
  }

  async create(user: Omit<UserEntity, 'createdAt' | 'updatedAt'>): Promise<UserEntity> {
    const entity = this.repo.create(user);
    return this.repo.save(entity);
  }

  async update(id: string, data: Partial<UserEntity>): Promise<void> {
    await this.repo.update(id, {
      ...data,
      updatedAt: new Date(),
    });
  }

  async updateHomeCenterH3Index(userId: string, h3Index: string | null): Promise<void> {
    await this.update(userId, { homeCenterH3Index: h3Index } as any);
  }

  async updateStats(
    userId: string,
    stats: { hexesClaimed?: number; biggestBattleBs?: number; scannedDevices?: number },
  ): Promise<void> {
    const user = await this.findById(userId);
    if (!user) return;

    const updated = {
      ...user.stats,
      ...stats,
    };
    await this.update(userId, { stats: updated } as any);
  }
}

