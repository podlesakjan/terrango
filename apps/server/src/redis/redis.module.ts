import { Global, Logger, Module, OnModuleDestroy, Provider } from '@nestjs/common';
import Redis from 'ioredis';

export class RedisService implements OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private publisher: Redis | null = null;
  private subscriber: Redis | null = null;
  private unavailable = false;

  constructor(redisUrl?: string) {
    const url = redisUrl ?? process.env.REDIS_URL ?? null;
    if (!url) {
      return;
    }

    this.publisher = this.createClient(url);
    this.subscriber = this.createClient(url);
  }

  get isEnabled(): boolean {
    return !this.unavailable && this.publisher !== null && this.subscriber !== null;
  }

  private createClient(url: string): Redis {
    const client = new Redis(url, {
      lazyConnect: true,
      maxRetriesPerRequest: 1,
      retryStrategy: () => null,
    });
    client.on('error', () => this.disable());
    return client;
  }

  private disable(): void {
    if (this.unavailable) return;

    this.unavailable = true;
    this.logger.warn('Redis is unavailable; using local in-process game events.');
    this.publisher?.disconnect();
    this.subscriber?.disconnect();
    this.publisher = null;
    this.subscriber = null;
  }

  async publish(channel: string, message: string) {
    if (!this.publisher) return false;
    try {
      await this.publisher.publish(channel, message);
      return true;
    } catch {
      this.disable();
      return false;
    }
  }

  async pSubscribe(
    pattern: string,
    callback: (channel: string, message: string) => void,
  ) {
    if (!this.subscriber) return false;
    try {
      await (this.subscriber as any).psubscribe(
        pattern,
        (_patternMatch: string, channel: string, message: string) => {
          try {
            callback(channel, message);
          } catch {
            // Do not crash the Redis listener due to a consumer error.
          }
        },
      );
      return true;
    } catch {
      this.disable();
      return false;
    }
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


