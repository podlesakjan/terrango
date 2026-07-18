import { Global, Module, OnModuleDestroy, Provider } from '@nestjs/common';
import Redis from 'ioredis';

export class RedisService implements OnModuleDestroy {
  private publisher: Redis | null = null;
  private subscriber: Redis | null = null;

  constructor(redisUrl?: string) {
    const url = redisUrl ?? process.env.REDIS_URL ?? null;
    if (!url) {
      return;
    }

    this.publisher = new Redis(url);
    this.subscriber = new Redis(url);
  }

  async publish(channel: string, message: string) {
    if (!this.publisher) return;
    await this.publisher.publish(channel, message);
  }

  async pSubscribe(
    pattern: string,
    callback: (channel: string, message: string) => void,
  ) {
    if (!this.subscriber) return;
    await (this.subscriber as any).psubscribe(
      pattern,
      (patternMatch: string, channel: string, message: string) => {
        try {
          callback(channel, message);
        } catch (e) {
          // swallow to avoid crashing subscriber
        }
      },
    );
  }

  onModuleDestroy() {
    this.publisher?.disconnect();
    this.subscriber?.disconnect();
  }
}

const redisProvider: Provider = {
  provide: RedisService,
  useFactory: () => {
    try {
      return new RedisService(process.env.REDIS_URL);
    } catch {
      return new RedisService(undefined);
    }
  },
};

@Global()
@Module({
  providers: [redisProvider],
  exports: [RedisService],
})
export class RedisModule {}



