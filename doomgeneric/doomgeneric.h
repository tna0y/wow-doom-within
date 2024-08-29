#ifndef DOOM_GENERIC
#define DOOM_GENERIC

#include "libc/libc.h"
#ifndef DOOMGENERIC_RESX
#define DOOMGENERIC_RESX 320
#endif  // DOOMGENERIC_RESX

#ifndef DOOMGENERIC_RESY
#define DOOMGENERIC_RESY 200
#endif  // DOOMGENERIC_RESY


#ifdef CMAP256

typedef uint8_t pixel_t;

#else  // CMAP256

typedef uint32_t pixel_t;

#endif  // CMAP256


extern pixel_t* DG_ScreenBuffer;

void doomgeneric_Create(int argc, char **argv);
void doomgeneric_Tick();


//Implement below functions for your platform
void DG_Init();
void DG_DrawFrame();
void DG_SleepMs(uint32_t ms);
uint32_t DG_GetTicksMs();
int DG_GetKey(int* pressed, unsigned char* key);
void DG_SetWindowTitle(const char * title);
void DG_DrawColumn(uint8_t* dest, uint8_t* dc_colormap, uint8_t* dc_source, int frac, int frac_step, int count);
void DG_DrawSpan(uint8_t* dest, uint8_t* ds_colormap, uint8_t* ds_source, unsigned int position, unsigned int step, int count);
void DG_DrawPatch(int col, int is_screen_buffer, int x, uint8_t *desttop, uint8_t* source, uint8_t *m_col, uint8_t *m_patch);
void DG_CopyRect(int srcx, int srcy, uint8_t *source, int width, int height, int destx, int desty);
void* DG_memcpy(uint8_t *dest, uint8_t* src, size_t len);
#endif //DOOM_GENERIC
