#include "doomkeys.h"
#include "doomgeneric.h"
#include "libc/libc.h"



void DG_Init()
{

}

void DG_DrawFrame()
{
    printf("frame\n");
}

void DG_SleepMs(uint32_t ms)
{
  usleep(ms * 1000);
}

uint32_t DG_GetTicksMs()
{
    struct timeval  tp;
    struct timezone tzp;

    gettimeofday(&tp, &tzp);

    return (tp.tv_sec * 1000) + (tp.tv_usec / 1000); /* return milliseconds */
}

int DG_GetKey(int* pressed, unsigned char* doomKey)
{
    return 0;
}



void DG_SetWindowTitle(const char * title) {}

int main(int argc, char **argv)
{
    doomgeneric_Create(argc, argv);
    for (int i = 0; ; i++)
    {
        doomgeneric_Tick();
    }
    return 0;
}