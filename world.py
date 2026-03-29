"""World map generation and camera."""
import pygame
import math
import random
from constants import *

# Tile type constants
TILE_GRASS = 0
TILE_DIRT  = 1
TILE_TREE  = 2
TILE_ROCK  = 3
TILE_WATER = 4

SOLID_TILES = {TILE_TREE, TILE_ROCK, TILE_WATER}


class Camera:
    def __init__(self):
        self.x = 0.0
        self.y = 0.0

    def update(self, target_x: float, target_y: float) -> None:
        tx = target_x - SCREEN_WIDTH  // 2
        ty = target_y - SCREEN_HEIGHT // 2
        # Smooth follow
        self.x += (tx - self.x) * 0.12
        self.y += (ty - self.y) * 0.12
        # Clamp to world
        self.x = max(0.0, min(float(WORLD_WIDTH  - SCREEN_WIDTH),  self.x))
        self.y = max(0.0, min(float(WORLD_HEIGHT - SCREEN_HEIGHT), self.y))

    def apply(self, wx: float, wy: float):
        return wx - self.x, wy - self.y


class WorldMap:
    def __init__(self, seed: int = 42):
        self._rng = random.Random(seed)
        self.tiles: list[list[int]] = []
        self._color_map: list[list[tuple]] = []
        self._generate()
        self.surface: pygame.Surface | None = None  # built after pygame.init()

    # ------------------------------------------------------------------
    # Generation
    # ------------------------------------------------------------------
    def _generate(self) -> None:
        rng = self._rng
        W, H = WORLD_TILES_W, WORLD_TILES_H

        # Base layer: grass
        self.tiles = [[TILE_GRASS] * W for _ in range(H)]

        # Dirt patches
        for _ in range(25):
            cx = rng.randint(4, W - 5)
            cy = rng.randint(4, H - 5)
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    if rng.random() < 0.55:
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H:
                            self.tiles[ny][nx] = TILE_DIRT

        # Tree clusters — keep centre clear
        centre_x, centre_y = W // 2, H // 2
        for _ in range(45):
            cx = rng.randint(3, W - 4)
            cy = rng.randint(3, H - 4)
            if math.hypot(cx - centre_x, cy - centre_y) < 9:
                continue
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    if math.hypot(dx, dy) <= 3.0 and rng.random() < 0.55:
                        nx, ny = cx + dx, cy + dy
                        if 1 <= nx < W - 1 and 1 <= ny < H - 1:
                            self.tiles[ny][nx] = TILE_TREE

        # Rocks
        for _ in range(70):
            rx = rng.randint(2, W - 3)
            ry = rng.randint(2, H - 3)
            if math.hypot(rx - centre_x, ry - centre_y) < 6:
                continue
            if self.tiles[ry][rx] in (TILE_TREE,):
                continue
            self.tiles[ry][rx] = TILE_ROCK
            if rng.random() < 0.45 and rx + 1 < W:
                self.tiles[ry][rx + 1] = TILE_ROCK

        # Water pools
        for _ in range(10):
            cx = rng.randint(5, W - 6)
            cy = rng.randint(5, H - 6)
            if math.hypot(cx - centre_x, cy - centre_y) < 11:
                continue
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if math.hypot(dx, dy) <= 2.0:
                        nx, ny = cx + dx, cy + dy
                        if 1 <= nx < W - 1 and 1 <= ny < H - 1:
                            self.tiles[ny][nx] = TILE_WATER

        # Pre-compute per-tile colour variant
        grass_cols = [GRASS_A, GRASS_B, GRASS_C]
        dirt_cols  = [DIRT_A,  DIRT_B]
        self._color_map = []
        for row in self.tiles:
            crow = []
            for tile in row:
                if tile == TILE_GRASS:
                    crow.append(rng.choice(grass_cols))
                elif tile == TILE_DIRT:
                    crow.append(rng.choice(dirt_cols))
                elif tile == TILE_TREE:
                    crow.append(TREE_LEAF)
                elif tile == TILE_ROCK:
                    crow.append(ROCK_DARK)
                else:
                    crow.append(WATER_DEEP)
            self._color_map.append(crow)

    # ------------------------------------------------------------------
    # Surface (call after pygame.init)
    # ------------------------------------------------------------------
    def build_surface(self) -> None:
        rng = self._rng
        self.surface = pygame.Surface((WORLD_WIDTH, WORLD_HEIGHT))

        for ty in range(WORLD_TILES_H):
            for tx in range(WORLD_TILES_W):
                tile  = self.tiles[ty][tx]
                color = self._color_map[ty][tx]
                px, py = tx * TILE_SIZE, ty * TILE_SIZE
                rect   = (px, py, TILE_SIZE, TILE_SIZE)

                pygame.draw.rect(self.surface, color, rect)

                if tile == TILE_GRASS:
                    if rng.random() < 0.18:
                        gx = px + rng.randint(6, TILE_SIZE - 6)
                        gy = py + rng.randint(6, TILE_SIZE - 6)
                        pygame.draw.line(self.surface, GRASS_C,
                                         (gx, gy), (gx - 2, gy - 9), 1)
                        pygame.draw.line(self.surface, GRASS_C,
                                         (gx + 4, gy), (gx + 2, gy - 8), 1)

                elif tile == TILE_DIRT:
                    # subtle pebble
                    if rng.random() < 0.12:
                        ex = px + rng.randint(8, TILE_SIZE - 8)
                        ey = py + rng.randint(8, TILE_SIZE - 8)
                        pygame.draw.ellipse(self.surface, DIRT_A,
                                            (ex, ey, 6, 4))

                elif tile == TILE_TREE:
                    # Trunk
                    tw = 10
                    pygame.draw.rect(self.surface, TREE_TRUNK,
                                     (px + TILE_SIZE//2 - tw//2,
                                      py + TILE_SIZE//2,
                                      tw, TILE_SIZE//2 + 4))
                    # Canopy
                    cx2 = px + TILE_SIZE // 2
                    cy2 = py + TILE_SIZE // 2 - 6
                    pygame.draw.circle(self.surface, TREE_LEAF,  (cx2, cy2), 24)
                    pygame.draw.circle(self.surface, TREE_LEAF2, (cx2, cy2), 16)

                elif tile == TILE_ROCK:
                    pygame.draw.ellipse(self.surface, ROCK_DARK,
                                        (px + 6, py + 12,
                                         TILE_SIZE - 12, TILE_SIZE - 24))
                    pygame.draw.ellipse(self.surface, ROCK_LIGHT,
                                        (px + 12, py + 18,
                                         TILE_SIZE - 28, TILE_SIZE - 36))

                elif tile == TILE_WATER:
                    pygame.draw.ellipse(self.surface, WATER_LIGHT,
                                        (px + 8, py + 18,
                                         TILE_SIZE - 16, TILE_SIZE // 2 - 8))

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------
    def is_solid(self, x: float, y: float) -> bool:
        tx = int(x // TILE_SIZE)
        ty = int(y // TILE_SIZE)
        if tx < 0 or tx >= WORLD_TILES_W or ty < 0 or ty >= WORLD_TILES_H:
            return True
        return self.tiles[ty][tx] in SOLID_TILES

    def get_open_pos(self) -> tuple[float, float]:
        """Return a random walkable world-space position."""
        rng = self._rng
        while True:
            tx = rng.randint(1, WORLD_TILES_W - 2)
            ty = rng.randint(1, WORLD_TILES_H - 2)
            if self.tiles[ty][tx] not in SOLID_TILES:
                return (tx * TILE_SIZE + TILE_SIZE // 2,
                        ty * TILE_SIZE + TILE_SIZE // 2)

    # ------------------------------------------------------------------
    # Rendering
    # ------------------------------------------------------------------
    def draw(self, surface: pygame.Surface, camera: Camera) -> None:
        if self.surface is None:
            return
        src = pygame.Rect(int(camera.x), int(camera.y),
                          SCREEN_WIDTH, SCREEN_HEIGHT)
        surface.blit(self.surface, (0, 0), src)
