import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';

import { BearerAuthGuard } from '../auth/bearer-auth.guard';
import { CurrentPlayer } from '../auth/current-player.decorator';
import { AuthenticatedPlayer } from './domain';
import { GameService } from './game.service';

@UseGuards(BearerAuthGuard)
@Controller('api/v1')
export class GameController {
  constructor(private readonly gameService: GameService) {}

  @Post('territory/establish')
  establishTerritory(
    @CurrentPlayer() player: AuthenticatedPlayer,
    @Body() body: Record<string, unknown>,
  ) {
    return this.gameService.establishTerritory(player.id, body);
  }

  @Post('territory/occupy')
  occupyHex(
    @CurrentPlayer() player: AuthenticatedPlayer,
    @Body() body: Record<string, unknown>,
  ) {
    return this.gameService.occupyHex(player.id, body);
  }

  @Get('hex/:h3Index')
  getHexDetail(
    @CurrentPlayer() player: AuthenticatedPlayer,
    @Param('h3Index') h3Index: string,
  ) {
    return this.gameService.getHexDetail(player.id, h3Index);
  }

  @Patch('territory/:id/center')
  changeCenter(
    @CurrentPlayer() player: AuthenticatedPlayer,
    @Param('id') territoryId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.gameService.changeCenter(player.id, territoryId, body);
  }

  @Get('barracks')
  getBarracks(@CurrentPlayer() player: AuthenticatedPlayer) {
    return this.gameService.getBarracks(player.id);
  }

  @Get('territory/list')
  listTerritories(@CurrentPlayer() player: AuthenticatedPlayer) {
    return this.gameService.listTerritories(player.id);
  }

  @Patch('territory/:id/rename')
  renameTerritory(
    @CurrentPlayer() player: AuthenticatedPlayer,
    @Param('id') territoryId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.gameService.renameTerritory(player.id, territoryId, body);
  }

  @Get('battle-logs')
  getBattleLogs(@CurrentPlayer() player: AuthenticatedPlayer) {
    return this.gameService.getBattleLogs(player.id);
  }

  @Get('profile')
  getProfile(@CurrentPlayer() player: AuthenticatedPlayer) {
    return this.gameService.getProfile(player.id);
  }

  @Patch('profile/nickname')
  changeNickname(
    @CurrentPlayer() player: AuthenticatedPlayer,
    @Body() body: Record<string, unknown>,
  ) {
    return this.gameService.changeNickname(player.id, body);
  }
}
