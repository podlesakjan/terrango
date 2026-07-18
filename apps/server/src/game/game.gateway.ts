import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
  WsException,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';

import { GameService } from './game.service';
import { RedisService } from '../redis/redis.module';
import { AuthService } from '../auth/auth.service';

interface SocketContext {
  userId: string;
  visibleH3Indexes: Set<string>;
}

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
export class GameGateway
  implements OnGatewayConnection, OnGatewayDisconnect, OnGatewayInit
{
  @WebSocketServer()
  private server!: Server;

  private readonly socketContexts = new Map<string, SocketContext>();
  private readonly userSockets = new Map<string, Set<string>>();

  constructor(
    private readonly gameService: GameService,
    private readonly authService: AuthService,
    private readonly redisService?: RedisService,
  ) {}

  afterInit(): void {
    // Local event emitter hook (in-process)
    this.gameService.events.on(
      'map_hexes_changed',
      (payload: { hexIndexes: string[] }) => {
        this.broadcastMapGridUpdate(payload.hexIndexes);
      },
    );

    this.gameService.events.on(
      'user_event',
      (payload: { event: string; payload: unknown; userId: string }) => {
        this.emitToUser(payload.userId, payload.event, payload.payload);
      },
    );

    // If Redis is configured, subscribe to cross-instance channels
    if (this.redisService) {
      void this.redisService.pSubscribe('map_hexes_changed', (_channel, message) => {
        try {
          const parsed = JSON.parse(message) as { hexIndexes: string[] };
          this.broadcastMapGridUpdate(parsed.hexIndexes);
        } catch {
          // ignore
        }
      });

      void this.redisService.pSubscribe('user_event:*', (channel, message) => {
        try {
          // channel will be like user_event:<userId> or user_event:123
          const m = JSON.parse(message) as { event: string; payload: unknown; userId: string };
          this.emitToUser(m.userId, m.event, m.payload);
        } catch {
          // ignore
        }
      });
    }
  }

  handleConnection(client: Socket): void {
    try {
      const token = this.extractSocketToken(client);
      // Verify token synchronously
      const authenticated = this.authService.verifyToken(token);
      const userId = authenticated.id;

      this.socketContexts.set(client.id, {
        userId,
        visibleH3Indexes: new Set<string>(),
      });

      if (!this.userSockets.has(userId)) {
        this.userSockets.set(userId, new Set<string>());
      }

      this.userSockets.get(userId)?.add(client.id);
      client.data.userId = userId;
    } catch {
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    const context = this.socketContexts.get(client.id);
    if (!context) {
      return;
    }

    this.socketContexts.delete(client.id);
    const sockets = this.userSockets.get(context.userId);
    sockets?.delete(client.id);

    if (sockets && sockets.size === 0) {
      this.userSockets.delete(context.userId);
    }
  }

  @SubscribeMessage('request_map_snapshot')
  handleRequestMapSnapshot(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ): void {
    try {
      const userId = this.getSocketUserId(client);
      const visibleH3Indexes = this.gameService.normalizeVisibleH3Indexes(
        body.visibleH3Indexes,
      );
      this.setVisibleHexes(client.id, userId, visibleH3Indexes);
      client.emit(
        'map_snapshot',
        this.gameService.getMapSnapshot(userId, visibleH3Indexes),
      );
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('resume_session')
  handleResumeSession(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ): void {
    try {
      const userId = this.getSocketUserId(client);
      const visibleH3Indexes = Array.from(
        this.socketContexts.get(client.id)?.visibleH3Indexes ?? [],
      );
      client.emit(
        'map_snapshot',
        this.gameService.resumeSession(userId, body.lastSyncTimestamp, visibleH3Indexes),
      );
      client.emit('army_update', this.gameService.getArmyUpdate(userId));
      client.emit('territory_update', this.gameService.getTerritoryUpdate(userId));
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('map_subscribe')
  handleMapSubscribe(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ): void {
    try {
      const userId = this.getSocketUserId(client);
      const visibleH3Indexes = this.gameService.normalizeVisibleH3Indexes(
        body.visibleH3Indexes,
      );
      this.setVisibleHexes(client.id, userId, visibleH3Indexes);
      client.emit(
        'map_snapshot',
        this.gameService.getMapSnapshot(userId, visibleH3Indexes),
      );
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('location_update')
  handleLocationUpdate(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ) {
    try {
      return this.gameService.updateLocation(this.getSocketUserId(client), body);
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('recruit_device')
  handleRecruitDevice(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ) {
    try {
      return this.gameService.recruitDevice(this.getSocketUserId(client), body);
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('garrison_modify')
  handleGarrisonModify(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ) {
    try {
      return this.gameService.modifyGarrison(this.getSocketUserId(client), body);
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('send_reinforcements')
  handleSendReinforcements(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ) {
    try {
      return this.gameService.sendReinforcements(this.getSocketUserId(client), body);
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('scout_hex')
  handleScoutHex(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ) {
    try {
      return this.gameService.scoutHex(this.getSocketUserId(client), body);
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  @SubscribeMessage('attack_hex')
  handleAttackHex(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: Record<string, unknown>,
  ) {
    try {
      return this.gameService.startAttack(this.getSocketUserId(client), body);
    } catch (error) {
      throw this.toWsException(error);
    }
  }

  private broadcastMapGridUpdate(changedHexIndexes: string[]): void {
    const uniqueHexIndexes = Array.from(new Set(changedHexIndexes));
    for (const [socketId, context] of this.socketContexts.entries()) {
      const visibleHexes = uniqueHexIndexes.filter((index) =>
        context.visibleH3Indexes.has(index),
      );
      if (visibleHexes.length === 0) {
        continue;
      }

      const socket = this.server.sockets.sockets.get(socketId);
      socket?.emit(
        'map_grid_update',
        this.gameService.getMapSnapshot(context.userId, visibleHexes),
      );
    }
  }

  private emitToUser(userId: string, eventName: string, payload: unknown): void {
    const socketIds = this.userSockets.get(userId);
    if (!socketIds) {
      return;
    }

    for (const socketId of socketIds) {
      const socket = this.server.sockets.sockets.get(socketId);
      socket?.emit(eventName, payload);
    }
  }

  private extractSocketToken(client: Socket): string | undefined {
    const authToken = client.handshake.auth.token;
    if (typeof authToken === 'string' && authToken.trim().length > 0) {
      return authToken.trim();
    }

    const authorizationHeader = client.handshake.headers.authorization;
    if (
      typeof authorizationHeader === 'string' &&
      authorizationHeader.startsWith('Bearer ')
    ) {
      return authorizationHeader.slice(7);
    }

    return undefined;
  }

  private getSocketUserId(client: Socket): string {
    const userId = client.data.userId;
    if (typeof userId !== 'string' || userId.length === 0) {
      throw new WsException('Unauthorized');
    }

    return userId;
  }

  private setVisibleHexes(
    socketId: string,
    userId: string,
    visibleH3Indexes: string[],
  ): void {
    this.socketContexts.set(socketId, {
      userId,
      visibleH3Indexes: new Set(visibleH3Indexes),
    });
  }

  private toWsException(error: unknown): WsException {
    if (error instanceof Error) {
      return new WsException(error.message);
    }

    return new WsException('Unknown websocket error.');
  }
}
