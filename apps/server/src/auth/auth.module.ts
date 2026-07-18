import { forwardRef, Module } from '@nestjs/common';
import { AuthService } from './auth.service';
import { BearerAuthGuard } from './bearer-auth.guard';
import { AuthController } from './auth.controller';
import { GameModule } from '../game/game.module';

@Module({
  imports: [forwardRef(() => GameModule)],
  providers: [AuthService, BearerAuthGuard],
  controllers: [AuthController],
  exports: [AuthService, BearerAuthGuard],
})
export class AuthModule {}

