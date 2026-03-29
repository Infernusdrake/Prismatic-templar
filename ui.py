"""HUD, minimap, and overlay screens."""
import pygame
import math
from constants import *


def draw_bar(surface: pygame.Surface, x: int, y: int,
             w: int, h: int, value: float, maximum: float,
             fill_color, border: int = 2) -> None:
    pygame.draw.rect(surface, DARK_GRAY, (x, y, w, h))
    fill = max(0, int(w * value / maximum))
    if fill > 0:
        pygame.draw.rect(surface, fill_color, (x, y, fill, h))
    pygame.draw.rect(surface, WHITE, (x, y, w, h), border)


def draw_hud(surface: pygame.Surface, player, wave: int,
             font_sm, font_md) -> None:
    # ── Health bar ──
    bar_x, bar_y = 20, 24
    bar_w, bar_h = 260, 24
    ratio = player.hp / player.max_hp
    hp_col = GREEN_HP if ratio > 0.5 else ORANGE if ratio > 0.25 else RED

    label = font_sm.render("HP", True, WHITE)
    surface.blit(label, (bar_x, bar_y - 22))
    draw_bar(surface, bar_x, bar_y, bar_w, bar_h, player.hp, player.max_hp, hp_col)
    hp_txt = font_sm.render(f"{int(player.hp)} / {player.max_hp}", True, WHITE)
    surface.blit(hp_txt, (bar_x + bar_w + 10, bar_y + 2))

    # ── Roll cooldown bar (small, below HP) ──
    cd_w = 80
    cd_pct = 1.0 - max(0.0, player.roll_cooldown) / PLAYER_ROLL_COOLDOWN
    draw_bar(surface, bar_x, bar_y + bar_h + 6, cd_w, 8, cd_pct, 1.0,
             CYAN, border=1)
    roll_lbl = font_sm.render("Roll", True, GRAY)
    surface.blit(roll_lbl, (bar_x + cd_w + 6, bar_y + bar_h + 4))

    # ── Stats column ──
    stats = [
        (f"Score:  {player.score:,}", GOLD),
        (f"Kills:  {player.kills}",   WHITE),
        (f"Wave:   {wave}",           CYAN),
    ]
    for i, (txt, col) in enumerate(stats):
        surf = font_sm.render(txt, True, col)
        surface.blit(surf, (20, 80 + i * 28))

    # ── Controls hint (bottom centre) ──
    hint_txt = ("WASD: Move   LClick / Space: Attack   "
                "Shift / Q: Roll   P: Pause   ESC: Quit")
    hint = font_sm.render(hint_txt, True, (160, 160, 160))
    surface.blit(hint,
                 (SCREEN_WIDTH // 2 - hint.get_width() // 2,
                  SCREEN_HEIGHT - 26))


def draw_minimap(surface: pygame.Surface, player, warriors, camera) -> None:
    mm = 160
    mm_x = SCREEN_WIDTH  - mm - 12
    mm_y = 12
    sx   = mm / WORLD_WIDTH
    sy   = mm / WORLD_HEIGHT

    bg = pygame.Surface((mm, mm), pygame.SRCALPHA)
    bg.fill((0, 0, 0, 140))

    # Warriors
    tier_cols = {"grunt": RED, "soldier": BLUE, "champion": PURPLE}
    for w in warriors:
        if w.dying:
            continue
        wx = int(w.x * sx)
        wy = int(w.y * sy)
        pygame.draw.circle(bg, tier_cols[w.tier], (wx, wy), 3)

    # Player
    px = int(player.x * sx)
    py = int(player.y * sy)
    pygame.draw.circle(bg, GOLD, (px, py), 4)

    # Viewport rect
    vx = max(0, int(camera.x * sx))
    vy = max(0, int(camera.y * sy))
    vw = int(SCREEN_WIDTH  * sx)
    vh = int(SCREEN_HEIGHT * sy)
    pygame.draw.rect(bg, (255, 255, 255, 80), (vx, vy, vw, vh), 1)

    pygame.draw.rect(bg, WHITE, (0, 0, mm, mm), 2)
    surface.blit(bg, (mm_x, mm_y))


def draw_pause(surface: pygame.Surface, font_lg, font_sm) -> None:
    overlay = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT), pygame.SRCALPHA)
    overlay.fill((0, 0, 0, 160))
    surface.blit(overlay, (0, 0))

    t1 = font_lg.render("PAUSED", True, WHITE)
    t2 = font_sm.render("Press  P  to resume", True, (200, 200, 200))
    surface.blit(t1, (SCREEN_WIDTH // 2 - t1.get_width() // 2,
                      SCREEN_HEIGHT // 2 - 60))
    surface.blit(t2, (SCREEN_WIDTH // 2 - t2.get_width() // 2,
                      SCREEN_HEIGHT // 2 + 20))


def draw_game_over(surface: pygame.Surface, player, wave: int,
                   font_lg, font_md, font_sm) -> None:
    overlay = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT), pygame.SRCALPHA)
    overlay.fill((0, 0, 0, 185))
    surface.blit(overlay, (0, 0))

    cy = SCREEN_HEIGHT // 2
    lines = [
        (font_lg, "DEFEATED",                                RED,   cy - 110),
        (font_md, f"Score:  {player.score:,}",               GOLD,  cy - 30),
        (font_md, f"Kills:  {player.kills}   |   Wave:  {wave}", WHITE, cy + 30),
        (font_sm, "Press  R  to restart  or  ESC  to quit",
                                                (190,190,190), cy + 110),
    ]
    for font, text, color, y in lines:
        s = font.render(text, True, color)
        surface.blit(s, (SCREEN_WIDTH // 2 - s.get_width() // 2, y))


def draw_start_screen(surface: pygame.Surface, font_lg, font_md, font_sm) -> None:
    surface.fill((15, 25, 15))

    title = font_lg.render("PRISMATIC TEMPLAR", True, GOLD)
    sub   = font_md.render("Warrior Combat",    True, (180, 180, 50))
    start = font_sm.render("Press  ENTER  or  SPACE  to begin", True, WHITE)

    controls = [
        "WASD          Move",
        "Left Click / Space   Attack",
        "Shift / Q       Dodge Roll",
        "P             Pause",
        "ESC           Quit",
    ]

    cy = SCREEN_HEIGHT // 2
    surface.blit(title, (SCREEN_WIDTH // 2 - title.get_width() // 2, cy - 200))
    surface.blit(sub,   (SCREEN_WIDTH // 2 - sub.get_width()   // 2, cy - 130))

    for i, line in enumerate(controls):
        s = font_sm.render(line, True, (170, 200, 170))
        surface.blit(s, (SCREEN_WIDTH // 2 - 160, cy - 40 + i * 30))

    surface.blit(start, (SCREEN_WIDTH // 2 - start.get_width() // 2, cy + 140))
