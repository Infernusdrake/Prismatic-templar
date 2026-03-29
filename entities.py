"""Player and Warrior entities."""
import pygame
import math
import random
from constants import *


class Entity:
    def __init__(self, x: float, y: float, radius: int, max_hp: int):
        self.x         = x
        self.y         = y
        self.radius    = radius
        self.max_hp    = max_hp
        self.hp        = float(max_hp)
        self.vel_x     = 0.0
        self.vel_y     = 0.0
        self.alive     = True
        self.hit_timer = 0.0
        self.angle     = 0.0

    def take_damage(self, dmg: float,
                    kb_x: float = 0.0, kb_y: float = 0.0) -> None:
        self.hp -= dmg
        self.hit_timer = 0.18
        self.vel_x += kb_x
        self.vel_y += kb_y
        if self.hp <= 0:
            self.hp    = 0.0
            self.alive = False

    def _move_with_collision(self, dx: float, dy: float,
                              speed: float, dt: float, world) -> None:
        nx = self.x + dx * speed * dt
        ny = self.y + dy * speed * dt
        if not world.is_solid(nx, self.y):
            self.x = nx
        if not world.is_solid(self.x, ny):
            self.y = ny

    def _apply_velocity(self, dt: float, world) -> None:
        if abs(self.vel_x) < 1 and abs(self.vel_y) < 1:
            self.vel_x = self.vel_y = 0.0
            return
        nx = self.x + self.vel_x * dt
        ny = self.y + self.vel_y * dt
        if not world.is_solid(nx, self.y):
            self.x = nx
        if not world.is_solid(self.x, ny):
            self.y = ny
        friction = 1.0 - min(1.0, 9.0 * dt)
        self.vel_x *= friction
        self.vel_y *= friction

    def _clamp_to_world(self) -> None:
        self.x = max(float(self.radius),
                     min(float(WORLD_WIDTH  - self.radius), self.x))
        self.y = max(float(self.radius),
                     min(float(WORLD_HEIGHT - self.radius), self.y))

    def _draw_hp_bar(self, surface: pygame.Surface, camera) -> None:
        if self.hp >= self.max_hp:
            return
        bw = self.radius * 2 + 4
        bh = 6
        sx = int(self.x - camera.x) - bw // 2
        sy = int(self.y - camera.y) - self.radius - 16
        pygame.draw.rect(surface, DARK_GRAY, (sx, sy, bw, bh))
        ratio = self.hp / self.max_hp
        fill  = max(1, int(bw * ratio))
        col   = GREEN_HP if ratio > 0.5 else ORANGE if ratio > 0.25 else RED
        pygame.draw.rect(surface, col, (sx, sy, fill, bh))
        pygame.draw.rect(surface, WHITE, (sx, sy, bw, bh), 1)


# ======================================================================
class Player(Entity):
    def __init__(self, x: float, y: float):
        super().__init__(x, y, 18, PLAYER_MAX_HP)
        self.atk_damage    = float(PLAYER_ATK_DAMAGE)
        self.atk_range     = float(PLAYER_ATK_RANGE)
        self.atk_cooldown  = PLAYER_ATK_COOLDOWN
        self.atk_timer     = 0.0
        self.atk_active    = False
        self.atk_id        = 0
        self.atk_angle     = 0.0
        # Roll
        self.roll_timer    = 0.0
        self.roll_cooldown = 0.0
        self.roll_dx       = 0.0
        self.roll_dy       = 0.0
        # Invincibility after being hit
        self.invuln_timer  = 0.0
        # Stats
        self.kills = 0
        self.score = 0

    # ------------------------------------------------------------------
    def update(self, dt: float, keys, mouse_buttons,
               mouse_pos: tuple, camera, world) -> None:

        # Movement input
        dx, dy = 0.0, 0.0
        if keys[pygame.K_w] or keys[pygame.K_UP]:    dy -= 1
        if keys[pygame.K_s] or keys[pygame.K_DOWN]:  dy += 1
        if keys[pygame.K_a] or keys[pygame.K_LEFT]:  dx -= 1
        if keys[pygame.K_d] or keys[pygame.K_RIGHT]: dx += 1
        if dx or dy:
            ln = math.hypot(dx, dy)
            dx /= ln
            dy /= ln

        # Roll cooldown tick
        if self.roll_cooldown > 0:
            self.roll_cooldown -= dt

        # Initiate roll
        if (keys[pygame.K_LSHIFT] or keys[pygame.K_q]) \
                and self.roll_cooldown <= 0 and self.roll_timer <= 0 \
                and (dx or dy):
            self.roll_dx       = dx
            self.roll_dy       = dy
            self.roll_timer    = PLAYER_ROLL_DURATION
            self.roll_cooldown = PLAYER_ROLL_COOLDOWN

        # Choose speed / direction
        if self.roll_timer > 0:
            self.roll_timer  -= dt
            self.invuln_timer = max(self.invuln_timer, self.roll_timer)
            mdx, mdy = self.roll_dx, self.roll_dy
            spd = PLAYER_ROLL_SPEED
        else:
            mdx, mdy = dx, dy
            spd = PLAYER_SPEED

        # Move
        self._move_with_collision(mdx, mdy, spd, dt, world)
        self._apply_velocity(dt, world)
        self._clamp_to_world()

        # Facing angle (used for sword line)
        if dx or dy:
            self.angle = math.atan2(dy, dx)

        # Attack direction → mouse cursor in world space
        wx = mouse_pos[0] + camera.x
        wy = mouse_pos[1] + camera.y
        adx, ady = wx - self.x, wy - self.y
        if math.hypot(adx, ady) > 0:
            self.atk_angle = math.atan2(ady, adx)

        # Attack input
        if self.atk_timer > 0:
            self.atk_timer -= dt
        if (mouse_buttons[0] or keys[pygame.K_SPACE]) and self.atk_timer <= 0:
            self.atk_timer  = self.atk_cooldown
            self.atk_active = True
            self.atk_id    += 1
        if self.atk_active:
            self.atk_active = (self.atk_timer
                               > self.atk_cooldown - PLAYER_ATK_DURATION)

        # Timers
        if self.invuln_timer > 0:
            self.invuln_timer -= dt
        if self.hit_timer > 0:
            self.hit_timer -= dt

    def get_atk_hitbox(self) -> tuple[float, float, float]:
        """(cx, cy, radius) of current swing hitbox."""
        reach = self.atk_range * 0.65
        cx = self.x + math.cos(self.atk_angle) * reach
        cy = self.y + math.sin(self.atk_angle) * reach
        return cx, cy, self.atk_range * 0.55

    # ------------------------------------------------------------------
    def draw(self, surface: pygame.Surface, camera) -> None:
        sx = int(self.x - camera.x)
        sy = int(self.y - camera.y)
        rolling = self.roll_timer > 0

        if self.hit_timer > 0:
            body_col = WHITE
        elif rolling:
            body_col = CYAN
        else:
            body_col = BLUE

        # Shadow
        pygame.draw.ellipse(surface, (0, 0, 0),
                            (sx - self.radius + 4, sy + self.radius - 5,
                             self.radius * 2 - 4, 9))
        # Body
        pygame.draw.circle(surface, body_col, (sx, sy), self.radius)
        pygame.draw.circle(surface, WHITE,    (sx, sy), self.radius, 2)

        # Sword direction line
        ex = sx + int(math.cos(self.atk_angle) * (self.radius + 10))
        ey = sy + int(math.sin(self.atk_angle) * (self.radius + 10))
        pygame.draw.line(surface, GOLD, (sx, sy), (ex, ey), 3)

        # Attack arc
        if self.atk_active:
            half = math.pi / 3.5
            r    = int(self.atk_range)
            arc_rect = pygame.Rect(sx - r, sy - r, r * 2, r * 2)
            try:
                pygame.draw.arc(surface, GOLD, arc_rect,
                                -self.atk_angle - half,
                                -self.atk_angle + half, 3)
            except Exception:
                pass

        # Roll ring
        if rolling:
            t   = self.roll_timer / PLAYER_ROLL_DURATION
            alp = int(200 * t)
            s   = pygame.Surface((self.radius * 4, self.radius * 4),
                                 pygame.SRCALPHA)
            pygame.draw.circle(s, (*CYAN, alp),
                               (self.radius * 2, self.radius * 2),
                               self.radius + 7, 3)
            surface.blit(s, (sx - self.radius * 2, sy - self.radius * 2))

        # Invincibility flash
        if self.invuln_timer > 0:
            if int(self.invuln_timer * 10) % 2 == 0:
                s = pygame.Surface((self.radius * 4, self.radius * 4),
                                   pygame.SRCALPHA)
                pygame.draw.circle(s, (255, 255, 255, 60),
                                   (self.radius * 2, self.radius * 2),
                                   self.radius + 3)
                surface.blit(s, (sx - self.radius * 2, sy - self.radius * 2))


# ======================================================================
TIERS = {
    "grunt": {
        "color":  (180,  55,  55),
        "hp":      45.0,
        "damage":  12.0,
        "speed":   78.0,
        "xp":      10,
        "radius":  16,
        "detect":  240.0,
        "atk_cd":  1.40,
    },
    "soldier": {
        "color":  ( 55, 110, 210),
        "hp":      90.0,
        "damage":  24.0,
        "speed":  100.0,
        "xp":      28,
        "radius":  19,
        "detect":  290.0,
        "atk_cd":  1.10,
    },
    "champion": {
        "color":  (170,  40, 200),
        "hp":     160.0,
        "damage":  40.0,
        "speed":  118.0,
        "xp":      55,
        "radius":  23,
        "detect":  340.0,
        "atk_cd":  0.85,
    },
}

TIER_DOT_COLOR = {
    "grunt":    (220,  60,  60),
    "soldier":  ( 60, 120, 220),
    "champion": (180,  50, 220),
}


class Warrior(Entity):
    def __init__(self, x: float, y: float, tier: str = "grunt"):
        d = TIERS[tier]
        super().__init__(x, y, d["radius"], int(d["hp"]))
        self.tier      = tier
        self.color     = d["color"]
        self.damage    = d["damage"]
        self.speed     = d["speed"]
        self.xp        = d["xp"]
        self.detect_r  = d["detect"]
        self.atk_range = float(WARRIOR_ATK_RANGE)
        self.atk_cd    = d["atk_cd"]
        self.atk_timer = random.uniform(0, self.atk_cd)

        self.state     = "wander"
        self.wander_t  = random.uniform(1.0, 3.5)
        self.wander_dx = random.uniform(-1, 1)
        self.wander_dy = random.uniform(-1, 1)
        self._normalise_wander()

        self.dying       = False
        self.death_timer = 0.0
        self.last_hit_id = -1   # which player attack_id last hit this warrior

    def _normalise_wander(self) -> None:
        l = math.hypot(self.wander_dx, self.wander_dy)
        if l > 0:
            self.wander_dx /= l
            self.wander_dy /= l

    # ------------------------------------------------------------------
    def update(self, dt: float, player, world) -> None:
        if self.dying:
            self.death_timer -= dt
            return

        dx = player.x - self.x
        dy = player.y - self.y
        dist = math.hypot(dx, dy)

        # State transitions
        if dist < self.detect_r and player.alive:
            self.state = "attack" if dist < self.atk_range + 2 else "chase"
        else:
            self.state = "wander"

        # Movement
        mdx = mdy = 0.0
        if self.state == "wander":
            self.wander_t -= dt
            if self.wander_t <= 0:
                self.wander_t  = random.uniform(1.0, 3.5)
                self.wander_dx = random.uniform(-1, 1)
                self.wander_dy = random.uniform(-1, 1)
                if random.random() < 0.25:
                    self.wander_dx = self.wander_dy = 0.0
                else:
                    self._normalise_wander()
            mdx, mdy = self.wander_dx, self.wander_dy

        elif self.state == "chase":
            if dist > 0:
                mdx = dx / dist
                mdy = dy / dist

        elif self.state == "attack":
            if dist > 0:
                self.angle = math.atan2(dy, dx)

        if mdx or mdy:
            l = math.hypot(mdx, mdy)
            if l > 0:
                mdx /= l
                mdy /= l
            self.angle = math.atan2(mdy, mdx)
            self._move_with_collision(mdx, mdy, self.speed, dt, world)

        self._apply_velocity(dt, world)
        self._clamp_to_world()

        # Cooldowns
        if self.atk_timer > 0:
            self.atk_timer -= dt
        if self.hit_timer > 0:
            self.hit_timer -= dt

        # Deal damage to player
        if (self.state == "attack"
                and self.atk_timer <= 0
                and player.alive
                and player.invuln_timer <= 0):
            kb  = 200.0
            kbx = (dx / dist * kb) if dist > 0 else 0.0
            kby = (dy / dist * kb) if dist > 0 else 0.0
            player.take_damage(self.damage, kbx, kby)
            player.invuln_timer = PLAYER_INVULN_FRAMES
            self.atk_timer      = self.atk_cd

    def start_dying(self) -> None:
        self.dying       = True
        self.death_timer = 0.35
        self.alive       = False

    # ------------------------------------------------------------------
    def draw(self, surface: pygame.Surface, camera) -> None:
        sx = int(self.x - camera.x)
        sy = int(self.y - camera.y)

        # Death fade-out
        if self.dying:
            t = max(0.0, self.death_timer / 0.35)
            r = int(self.radius * (1.0 + (1.0 - t) * 0.6))
            s = pygame.Surface((r * 4, r * 4), pygame.SRCALPHA)
            pygame.draw.circle(s, (*self.color, int(220 * t)),
                               (r * 2, r * 2), r)
            surface.blit(s, (sx - r * 2, sy - r * 2))
            return

        col = WHITE if self.hit_timer > 0 else self.color

        # Shadow
        pygame.draw.ellipse(surface, (0, 0, 0),
                            (sx - self.radius + 4, sy + self.radius - 5,
                             self.radius * 2 - 4, 9))
        # Body
        pygame.draw.circle(surface, col,   (sx, sy), self.radius)
        pygame.draw.circle(surface, WHITE, (sx, sy), self.radius, 2)

        # Weapon stub
        ex = sx + int(math.cos(self.angle) * (self.radius + 7))
        ey = sy + int(math.sin(self.angle) * (self.radius + 7))
        pygame.draw.line(surface, (200, 200, 200), (sx, sy), (ex, ey), 2)

        # Tier pip (above head)
        pygame.draw.circle(surface, TIER_DOT_COLOR[self.tier],
                           (sx, sy - self.radius - 18), 4)

        # HP bar
        self._draw_hp_bar(surface, camera)
