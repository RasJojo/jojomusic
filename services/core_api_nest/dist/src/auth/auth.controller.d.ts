import type { User } from '@prisma/client';
import { AuthService } from './auth.service';
import { LoginDto, RegisterDto } from './dto/auth.dto';
export declare class AuthController {
    private readonly authService;
    constructor(authService: AuthService);
    register(payload: RegisterDto): Promise<import("../common/payloads").AuthResponse>;
    login(payload: LoginDto): Promise<import("../common/payloads").AuthResponse>;
    me(currentUser: User): import("../common/payloads").UserOut;
}
