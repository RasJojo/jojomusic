"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const app_module_1 = require("./app.module");
async function bootstrap() {
    const app = await core_1.NestFactory.create(app_module_1.AppModule);
    const allowedOrigins = (process.env.CORS_ALLOW_ORIGINS ?? '')
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean);
    const vercelOriginRegex = /^https:\/\/.*\.vercel\.app$/;
    const localOriginRegex = /^http:\/\/(?:localhost|127\.0\.0\.1):\d+$/;
    app.enableCors({
        origin(origin, callback) {
            if (!origin ||
                allowedOrigins.includes(origin) ||
                vercelOriginRegex.test(origin) ||
                localOriginRegex.test(origin)) {
                callback(null, true);
                return;
            }
            callback(new Error('Not allowed by CORS'));
        },
        credentials: true,
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization'],
    });
    app.useGlobalPipes(new common_1.ValidationPipe({
        whitelist: true,
        transform: true,
    }));
    await app.listen(process.env.PORT ?? 8000, '0.0.0.0');
}
bootstrap();
//# sourceMappingURL=main.js.map