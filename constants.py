import pygame

# Screen
SCREEN_WIDTH  = 1280
SCREEN_HEIGHT = 720
FPS           = 60
TITLE         = "Prismatic Templar"

# World (tiles)
TILE_SIZE      = 64
WORLD_TILES_W  = 60
WORLD_TILES_H  = 45
WORLD_WIDTH    = TILE_SIZE * WORLD_TILES_W   # 3840 px
WORLD_HEIGHT   = TILE_SIZE * WORLD_TILES_H   # 2880 px

# Player
PLAYER_SPEED          = 230    # px/s
PLAYER_MAX_HP         = 100
PLAYER_ATK_DAMAGE     = 28
PLAYER_ATK_RANGE      = 85     # px radius of swing arc
PLAYER_ATK_COOLDOWN   = 0.40   # seconds between attacks
PLAYER_ATK_DURATION   = 0.14   # how long hitbox stays active
PLAYER_ROLL_SPEED     = 520
PLAYER_ROLL_DURATION  = 0.22
PLAYER_ROLL_COOLDOWN  = 1.10
PLAYER_INVULN_FRAMES  = 0.55   # invincibility after taking damage

# Warriors
WARRIOR_DETECTION     = 260    # base detection radius
WARRIOR_ATK_RANGE     = 44
WARRIOR_ATK_COOLDOWN  = 1.30

# Colours
BLACK       = (  0,   0,   0)
WHITE       = (255, 255, 255)
GRASS_A     = ( 82, 130,  25)
GRASS_B     = ( 90, 140,  30)
GRASS_C     = ( 74, 120,  18)
DIRT_A      = (139, 115,  80)
DIRT_B      = (150, 125,  90)
TREE_TRUNK  = ( 90,  55,  20)
TREE_LEAF   = ( 30,  90,  30)
TREE_LEAF2  = ( 50, 120,  50)
ROCK_DARK   = ( 85,  85,  95)
ROCK_LIGHT  = (115, 115, 128)
WATER_DEEP  = ( 30,  90, 170)
WATER_LIGHT = ( 60, 140, 210)
RED         = (220,  50,  50)
DARK_RED    = (160,  20,  20)
ORANGE      = (240, 130,   0)
GREEN_HP    = ( 50, 200,  80)
BLUE        = ( 50, 130, 220)
DARK_BLUE   = ( 20,  70, 170)
PURPLE      = (160,  40, 200)
GOLD        = (255, 200,  30)
DARK_GRAY   = ( 45,  55,  60)
GRAY        = (110, 120, 130)
CYAN        = (  0, 200, 220)
