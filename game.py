"""Main game class — state machine, loop, and logic."""
import pygame
import sys
import math
import random

from constants import *
from world    import WorldMap, Camera
from entities import Player, Warrior
from ui       import (draw_hud, draw_minimap, draw_pause,
                      draw_game_over, draw_start_screen)


class Particle:
    __slots__ = ("x", "y", "vx", "vy", "color", "life", "max_life", "size")

    def __init__(self, x, y, color):
        angle      = random.uniform(0, math.tau)
        speed      = random.uniform(60, 240)
        self.x     = x
        self.y     = y
        self.vx    = math.cos(angle) * speed
        self.vy    = math.sin(angle) * speed
        self.color = color
        self.life  = random.uniform(0.25, 0.70)
        self.max_life = self.life
        self.size  = random.randint(2, 6)

    def update(self, dt: float) -> bool:
        self.x    += self.vx * dt
        self.y    += self.vy * dt
        self.vx   *= (1.0 - 3.0 * dt)
        self.vy   *= (1.0 - 3.0 * dt)
        self.life -= dt
        return self.life > 0

    def draw(self, surface: pygame.Surface, camera: Camera) -> None:
        sx = int(self.x - camera.x)
        sy = int(self.y - camera.y)
        if not (0 <= sx < SCREEN_WIDTH and 0 <= sy < SCREEN_HEIGHT):
            return
        r = max(1, int(self.size * self.life / self.max_life))
        pygame.draw.circle(surface, self.color, (sx, sy), r)


# ======================================================================
class Game:
    STATE_START    = "start"
    STATE_PLAYING  = "playing"
    STATE_PAUSED   = "paused"
    STATE_GAMEOVER = "gameover"

    def __init__(self):
        pygame.init()
        pygame.display.set_caption(TITLE)
        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        self.clock  = pygame.time.Clock()

        self.font_lg = pygame.font.Font(None, 80)
        self.font_md = pygame.font.Font(None, 52)
        self.font_sm = pygame.font.Font(None, 32)

        self.state = self.STATE_START
        self._build_world()

    # ------------------------------------------------------------------
    # World / session setup
    # ------------------------------------------------------------------
    def _build_world(self) -> None:
        self.world  = WorldMap(seed=random.randint(0, 9999))
        self.world.build_surface()
        self.camera = Camera()

        cx = WORLD_WIDTH  // 2
        cy = WORLD_HEIGHT // 2
        self.player = Player(float(cx), float(cy))
        self.camera.x = float(cx - SCREEN_WIDTH  // 2)
        self.camera.y = float(cy - SCREEN_HEIGHT // 2)

        self.warriors:  list[Warrior]  = []
        self.particles: list[Particle] = []

        self.wave         = 1
        self.wave_timer   = 35.0      # seconds per wave
        self.spawn_timer  = 0.5
        self.max_warriors = 8

        # Initial spawn
        for _ in range(5):
            self._spawn_warrior()

    def _new_game(self) -> None:
        self._build_world()
        self.state = self.STATE_PLAYING

    # ------------------------------------------------------------------
    # Spawning
    # ------------------------------------------------------------------
    def _spawn_warrior(self) -> None:
        for _ in range(30):
            x, y = self.world.get_open_pos()
            if math.hypot(x - self.player.x, y - self.player.y) > 320:
                tier = self._pick_tier()
                self.warriors.append(Warrior(x, y, tier))
                return

    def _pick_tier(self) -> str:
        w = self.wave
        grunt_w    = max(0.1, 1.0 - w * 0.08)
        soldier_w  = min(0.6,       w * 0.10)
        champ_w    = max(0.0, min(0.30, (w - 2) * 0.07))
        tiers   = ["grunt",    "soldier",  "champion"]
        weights = [grunt_w,   soldier_w,  champ_w]
        return random.choices(tiers, weights=weights)[0]

    # ------------------------------------------------------------------
    # Particles
    # ------------------------------------------------------------------
    def _burst(self, x: float, y: float, color, count: int = 10) -> None:
        for _ in range(count):
            self.particles.append(Particle(x, y, color))

    # ------------------------------------------------------------------
    # Update
    # ------------------------------------------------------------------
    def update(self, dt: float) -> None:
        if self.state != self.STATE_PLAYING:
            return

        keys         = pygame.key.get_pressed()
        mouse_btns   = pygame.mouse.get_pressed()
        mouse_pos    = pygame.mouse.get_pos()

        # Player
        self.player.update(dt, keys, mouse_btns, mouse_pos,
                           self.camera, self.world)

        # Player attacks warriors
        if self.player.atk_active:
            ax, ay, ar = self.player.get_atk_hitbox()
            for w in self.warriors:
                if w.dying or not w.alive:
                    continue
                if w.last_hit_id == self.player.atk_id:
                    continue
                dx = w.x - ax
                dy = w.y - ay
                if math.hypot(dx, dy) < ar + w.radius:
                    w.last_hit_id = self.player.atk_id
                    dist = math.hypot(dx, dy) or 1.0
                    kb   = 280.0
                    w.take_damage(self.player.atk_damage,
                                  dx / dist * kb, dy / dist * kb)
                    self._burst(w.x, w.y, w.color, 8)
                    if not w.alive:
                        w.start_dying()
                        self.player.kills += 1
                        self.player.score += w.xp * self.wave
                        self._burst(w.x, w.y, GOLD, 16)

        # Warriors
        for w in self.warriors:
            w.update(dt, self.player, self.world)

        # Warrior separation (prevent stacking)
        for i in range(len(self.warriors)):
            w1 = self.warriors[i]
            if w1.dying:
                continue
            for j in range(i + 1, len(self.warriors)):
                w2 = self.warriors[j]
                if w2.dying:
                    continue
                dx = w2.x - w1.x
                dy = w2.y - w1.y
                d  = math.hypot(dx, dy)
                md = w1.radius + w2.radius + 3
                if 0 < d < md:
                    push = (md - d) / d * 0.5
                    w1.x -= dx * push
                    w1.y -= dy * push
                    w2.x += dx * push
                    w2.y += dy * push

        # Purge dead warriors
        self.warriors = [w for w in self.warriors
                         if not (w.dying and w.death_timer <= 0)]

        # Particles
        self.particles = [p for p in self.particles if p.update(dt)]

        # Spawning
        self.spawn_timer -= dt
        if self.spawn_timer <= 0 and len(self.warriors) < self.max_warriors:
            self._spawn_warrior()
            self.spawn_timer = max(1.8, 5.5 - self.wave * 0.3)

        # Wave progression
        self.wave_timer -= dt
        if self.wave_timer <= 0:
            self.wave        += 1
            self.max_warriors = min(24, 8 + self.wave * 2)
            self.wave_timer   = 35.0
            # Burst-spawn on new wave
            for _ in range(3):
                self._spawn_warrior()

        # Camera
        self.camera.update(self.player.x, self.player.y)

        # Game over?
        if not self.player.alive:
            self.state = self.STATE_GAMEOVER

    # ------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------
    def draw(self) -> None:
        if self.state == self.STATE_START:
            draw_start_screen(self.screen, self.font_lg, self.font_md, self.font_sm)
            pygame.display.flip()
            return

        # World
        self.world.draw(self.screen, self.camera)

        # Particles
        for p in self.particles:
            p.draw(self.screen, self.camera)

        # Warriors (only on-screen)
        for w in self.warriors:
            wx, wy = w.x - self.camera.x, w.y - self.camera.y
            if -60 < wx < SCREEN_WIDTH + 60 and -60 < wy < SCREEN_HEIGHT + 60:
                w.draw(self.screen, self.camera)

        # Player
        self.player.draw(self.screen, self.camera)

        # HUD
        draw_hud(self.screen, self.player, self.wave, self.font_sm, self.font_md)
        draw_minimap(self.screen, self.player, self.warriors, self.camera)

        # Overlays
        if self.state == self.STATE_PAUSED:
            draw_pause(self.screen, self.font_lg, self.font_sm)
        elif self.state == self.STATE_GAMEOVER:
            draw_game_over(self.screen, self.player, self.wave,
                           self.font_lg, self.font_md, self.font_sm)

        pygame.display.flip()

    # ------------------------------------------------------------------
    # Event handling
    # ------------------------------------------------------------------
    def handle_events(self) -> None:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit()

            elif event.type == pygame.KEYDOWN:
                k = event.key

                if k == pygame.K_ESCAPE:
                    pygame.quit()
                    sys.exit()

                elif k in (pygame.K_RETURN, pygame.K_SPACE) \
                        and self.state == self.STATE_START:
                    self._new_game()

                elif k == pygame.K_p and self.state == self.STATE_PLAYING:
                    self.state = self.STATE_PAUSED

                elif k == pygame.K_p and self.state == self.STATE_PAUSED:
                    self.state = self.STATE_PLAYING

                elif k == pygame.K_r and self.state == self.STATE_GAMEOVER:
                    self._new_game()

    # ------------------------------------------------------------------
    # Main loop
    # ------------------------------------------------------------------
    def run(self) -> None:
        while True:
            dt = self.clock.tick(FPS) / 1000.0
            dt = min(dt, 0.05)   # cap in case of lag spike

            self.handle_events()
            self.update(dt)
            self.draw()
