import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { type User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AppConfigService } from '../common/app-config.service';
import { hashPassword, verifyPassword } from '../common/password.util';
import { AuthResponse, generateId, toUserOut } from '../common/payloads';
import { LoginDto, RegisterDto } from './dto/auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly appConfig: AppConfigService,
  ) {}

  async register(payload: RegisterDto): Promise<AuthResponse> {
    const email = payload.email.toLowerCase();
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already in use');
    }

    const user = await this.prisma.user.create({
      data: {
        id: generateId(),
        name: payload.name.trim(),
        email,
        passwordHash: hashPassword(payload.password),
      },
    });
    return this.buildAuthResponse(user);
  }

  async login(payload: LoginDto): Promise<AuthResponse> {
    const user = await this.prisma.user.findUnique({
      where: { email: payload.email.toLowerCase() },
    });
    if (!user || !verifyPassword(payload.password, user.passwordHash)) {
      throw new UnauthorizedException('Invalid credentials');
    }
    return this.buildAuthResponse(user);
  }

  async getCurrentUser(userId: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { id: userId } });
  }

  createToken(payload: Record<string, unknown>, expiresMinutes: number): string {
    return this.jwtService.sign(payload, {
      algorithm: this.appConfig.jwtAlgorithm as never,
      secret: this.appConfig.jwtSecret,
      expiresIn: `${expiresMinutes}m`,
    });
  }

  createAccessToken(subject: string): string {
    return this.createToken(
      {
        sub: subject,
        kind: 'access',
      },
      this.appConfig.accessTokenMinutes,
    );
  }

  decodeToken<T extends Record<string, unknown>>(token: string): T {
    return this.jwtService.verify<T>(token, {
      secret: this.appConfig.jwtSecret,
      algorithms: [this.appConfig.jwtAlgorithm as never],
    });
  }

  private buildAuthResponse(user: User): AuthResponse {
    return {
      access_token: this.createAccessToken(user.id),
      token_type: 'bearer',
      user: toUserOut(user),
    };
  }
}
