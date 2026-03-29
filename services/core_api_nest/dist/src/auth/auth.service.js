"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const prisma_service_1 = require("../prisma/prisma.service");
const app_config_service_1 = require("../common/app-config.service");
const password_util_1 = require("../common/password.util");
const payloads_1 = require("../common/payloads");
let AuthService = class AuthService {
    prisma;
    jwtService;
    appConfig;
    constructor(prisma, jwtService, appConfig) {
        this.prisma = prisma;
        this.jwtService = jwtService;
        this.appConfig = appConfig;
    }
    async register(payload) {
        const email = payload.email.toLowerCase();
        const existing = await this.prisma.user.findUnique({ where: { email } });
        if (existing) {
            throw new common_1.ConflictException('Email already in use');
        }
        const user = await this.prisma.user.create({
            data: {
                id: (0, payloads_1.generateId)(),
                name: payload.name.trim(),
                email,
                passwordHash: (0, password_util_1.hashPassword)(payload.password),
            },
        });
        return this.buildAuthResponse(user);
    }
    async login(payload) {
        const user = await this.prisma.user.findUnique({
            where: { email: payload.email.toLowerCase() },
        });
        if (!user || !(0, password_util_1.verifyPassword)(payload.password, user.passwordHash)) {
            throw new common_1.UnauthorizedException('Invalid credentials');
        }
        return this.buildAuthResponse(user);
    }
    async getCurrentUser(userId) {
        return this.prisma.user.findUnique({ where: { id: userId } });
    }
    createToken(payload, expiresMinutes) {
        return this.jwtService.sign(payload, {
            algorithm: this.appConfig.jwtAlgorithm,
            secret: this.appConfig.jwtSecret,
            expiresIn: `${expiresMinutes}m`,
        });
    }
    createAccessToken(subject) {
        return this.createToken({
            sub: subject,
            kind: 'access',
        }, this.appConfig.accessTokenMinutes);
    }
    decodeToken(token) {
        return this.jwtService.verify(token, {
            secret: this.appConfig.jwtSecret,
            algorithms: [this.appConfig.jwtAlgorithm],
        });
    }
    buildAuthResponse(user) {
        return {
            access_token: this.createAccessToken(user.id),
            token_type: 'bearer',
            user: (0, payloads_1.toUserOut)(user),
        };
    }
};
exports.AuthService = AuthService;
exports.AuthService = AuthService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        jwt_1.JwtService,
        app_config_service_1.AppConfigService])
], AuthService);
//# sourceMappingURL=auth.service.js.map