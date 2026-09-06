/*
 * Links against every packaged library and initialises the two subsystems that
 * load their dependencies at run time, so a package that builds but cannot
 * actually resolve freetype or plutosvg still fails here.
 */
#include <SDL3/SDL.h>
#include <SDL3_image/SDL_image.h>
#include <SDL3_mixer/SDL_mixer.h>
#include <SDL3_net/SDL_net.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <stdio.h>

static void show(const char *name, int v)
{
    printf("  %-8s %d.%d.%d\n", name, v / 1000000, (v / 1000) % 1000, v % 1000);
}

int main(void)
{
    printf("linked versions:\n");
    printf("  %-8s %d.%d.%d\n", "sdl3",
           SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_MICRO_VERSION);
    show("image", IMG_Version());
    show("mixer", MIX_Version());
    show("net", NET_Version());
    show("ttf", TTF_Version());

    if (!SDL_Init(0)) {
        printf("SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    if (!TTF_Init()) {
        printf("TTF_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    TTF_Quit();
    if (!NET_Init()) {
        printf("NET_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    NET_Quit();
    SDL_Quit();
    printf("ok\n");
    return 0;
}
