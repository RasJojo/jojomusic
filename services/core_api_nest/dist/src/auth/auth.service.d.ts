import { JwtService } from '@nestjs/jwt';
import { type User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AppConfigService } from '../common/app-config.service';
import { AuthResponse } from '../common/payloads';
import { LoginDto, RegisterDto } from './dto/auth.dto';
export declare class AuthService {
    private readonly prisma;
    private readonly jwtService;
    private readonly appConfig;
    constructor(prisma: PrismaService, jwtService: JwtService, appConfig: AppConfigService);
    register(payload: RegisterDto): Promise<AuthResponse>;
    login(payload: LoginDto): Promise<AuthResponse>;
    getCurrentUser(userId: string): Promise<User | null>;
    createToken(payload: Record<string, unknown>, expiresMinutes: number): string;
    createAccessToken(subject: string): string;
    decodeToken<T extends Record<string, unknown>>(token: string): T;
    private buildAuthResponse;
}
