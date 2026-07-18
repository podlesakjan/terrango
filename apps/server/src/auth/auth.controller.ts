import { Body, Controller, Post } from '@nestjs/common';

import { GameService } from '../game/game.service';

@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly gameService: GameService) {}

  @Post('register')
  register(@Body() body: Record<string, unknown>) {
    return this.gameService.register(body);
  }
}
