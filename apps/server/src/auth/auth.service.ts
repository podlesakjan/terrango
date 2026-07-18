import { Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, createHmac } from 'node:crypto';

export interface AuthenticatedPlayer {
  id: string;
  nickname: string;
}

@Injectable()
export class AuthService {
  private readonly jwtSecret = process.env.JWT_SECRET ?? 'terrango-dev-secret';

  /**
   * Verifies and decodes a JWT token.
   * In production, this should verify against a public key/certificate.
   */
  verifyToken(token: string | undefined): AuthenticatedPlayer {
    if (!token) {
      throw new UnauthorizedException('Missing token.');
    }

    try {
      const [encodedHeader, encodedPayload, signature] = token.split('.');
      if (!encodedHeader || !encodedPayload || !signature) {
        throw new UnauthorizedException('Malformed token.');
      }

      const expectedSignature = createHmac('sha256', this.jwtSecret)
        .update(`${encodedHeader}.${encodedPayload}`)
        .digest('base64url');

      if (signature !== expectedSignature) {
        throw new UnauthorizedException('Invalid token signature.');
      }

      const payload = JSON.parse(
        Buffer.from(encodedPayload, 'base64url').toString('utf8'),
      ) as { sub?: string; iat?: number };

      if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
        throw new UnauthorizedException('Invalid token payload.');
      }

      return {
        id: payload.sub,
        nickname: '', // Set by GameService when resolving from DB
      };
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }

      throw new UnauthorizedException('Invalid bearer token.');
    }
  }

  /**
   * Issues a new JWT token for a player.
   */
  issueToken(userId: string): string {
    const encodedHeader = Buffer.from(
      JSON.stringify({ alg: 'HS256', typ: 'JWT' }),
      'utf8',
    ).toString('base64url');

    const encodedPayload = Buffer.from(
      JSON.stringify({
        iat: Math.floor(Date.now() / 1000),
        sub: userId,
      }),
      'utf8',
    ).toString('base64url');

    const signature = createHmac('sha256', this.jwtSecret)
      .update(`${encodedHeader}.${encodedPayload}`)
      .digest('base64url');

    return `${encodedHeader}.${encodedPayload}.${signature}`;
  }

  /**
   * Hashes an idToken for storage (anti-duplication).
   * In production, use proper OAuth library to verify against provider.
   */
  hashIdToken(idToken: string): string {
    return createHash('sha256').update(idToken).digest('hex');
  }
}

