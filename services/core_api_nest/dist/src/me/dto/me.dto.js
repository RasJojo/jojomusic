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
exports.FollowPodcastDto = exports.PlaybackEventCreateDto = void 0;
const class_transformer_1 = require("class-transformer");
const class_validator_1 = require("class-validator");
class PlaybackEventCreateDto {
    event_type;
    listened_ms;
    completion_ratio;
    track;
}
exports.PlaybackEventCreateDto = PlaybackEventCreateDto;
__decorate([
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], PlaybackEventCreateDto.prototype, "event_type", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_transformer_1.Type)(() => Number),
    (0, class_validator_1.IsNumber)(),
    __metadata("design:type", Number)
], PlaybackEventCreateDto.prototype, "listened_ms", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_transformer_1.Type)(() => Number),
    (0, class_validator_1.IsNumber)(),
    __metadata("design:type", Number)
], PlaybackEventCreateDto.prototype, "completion_ratio", void 0);
__decorate([
    (0, class_validator_1.Allow)(),
    __metadata("design:type", Object)
], PlaybackEventCreateDto.prototype, "track", void 0);
class FollowPodcastDto {
    podcast;
}
exports.FollowPodcastDto = FollowPodcastDto;
__decorate([
    (0, class_validator_1.Allow)(),
    __metadata("design:type", Object)
], FollowPodcastDto.prototype, "podcast", void 0);
//# sourceMappingURL=me.dto.js.map