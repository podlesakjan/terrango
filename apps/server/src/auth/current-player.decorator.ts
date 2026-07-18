import { createParamDecorator, ExecutionContext } from '@nestjs/common';

import { AuthenticatedPlayer } from '../game/domain';

export const CurrentPlayer = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthenticatedPlayer => {
    const request = context.switchToHttp().getRequest<{ player: AuthenticatedPlayer }>();
    return request.player;
  },
);
