#include "doomkeys.h"
#include "i_video.h"
#include "m_fixed.h"
#include "doomgeneric.h"
#include "libc/libc.h"

#define ENABLE_WOW_API

#define SYS_WOW_toggle_window     101
#define SYS_WOW_send_framebuffer  102
#define SYS_WOW_check_key_pressed 103
#define SYS_WOW_sleep             104
#define SYS_WOW_draw_column       105
#define SYS_WOW_draw_span         106
#define SYS_WOW_draw_patch        107
#define SYS_WOW_copy_rect         108
#define SYS_WOW_DG_memcpy         109

#define KEYQUEUE_SIZE 16

static unsigned short s_KeyQueue[KEYQUEUE_SIZE];
static unsigned int s_KeyQueueWriteIndex = 0;
static unsigned int s_KeyQueueReadIndex = 0;

#define RV32_KEYS_COUNT 30

#define RV32_KEY_W       0
#define RV32_KEY_A       1
#define RV32_KEY_S       2
#define RV32_KEY_D       3
#define RV32_KEY_R       4
#define RV32_KEY_F       5
#define RV32_KEY_LCTRL   6
#define RV32_KEY_LSHIFT  7
#define RV32_KEY_SPACE   8
#define RV32_KEY_LALT    9
#define RV32_KEY_ENTER   10
#define RV32_KEY_ESCAPE  11
#define RV32_KEY_UP      12
#define RV32_KEY_LEFT    13
#define RV32_KEY_DOWN    14
#define RV32_KEY_RIGHT   15
#define RV32_KEY_Y       16
#define RV32_KEY_N       17
#define RV32_KEY_COMMA   18
#define RV32_KEY_PERIOD  19
#define RV32_KEY_0       20
#define RV32_KEY_1       21
#define RV32_KEY_2       22
#define RV32_KEY_3       23
#define RV32_KEY_4       24
#define RV32_KEY_5       25
#define RV32_KEY_6       26
#define RV32_KEY_7       27
#define RV32_KEY_8       28
#define RV32_KEY_9       29



static unsigned char convertToDoomKey(unsigned char key)
{
	switch (key)
	{
	case RV32_KEY_ENTER:
		key = KEY_ENTER;
		break;
	case RV32_KEY_ESCAPE:
		key = KEY_ESCAPE;
		break;
	case RV32_KEY_A:
    case RV32_KEY_LEFT:
		key = KEY_LEFTARROW;
		break;
	case RV32_KEY_D:
    case RV32_KEY_RIGHT:
		key = KEY_RIGHTARROW;
		break;
	case RV32_KEY_W:
    case RV32_KEY_UP:
		key = KEY_UPARROW;
		break;
	case RV32_KEY_S:
    case RV32_KEY_DOWN:
		key = KEY_DOWNARROW;
		break;
	case RV32_KEY_LCTRL:
		key = KEY_FIRE;
		break;
	case RV32_KEY_SPACE:
		key = KEY_USE;
		break;
	case RV32_KEY_LSHIFT:
		key = KEY_RSHIFT;
		break;
    case RV32_KEY_Y:
        key = 'y';
        break;
    case RV32_KEY_N:
        key = 'n';
        break;
    case RV32_KEY_COMMA:
        key = ',';
        break;
    case RV32_KEY_PERIOD:
        key = '.';
        break;
    case RV32_KEY_0:
        key = '0';
        break;
    case RV32_KEY_1:
        key = '1';
        break;
    case RV32_KEY_2:
        key = '2';
        break;
    case RV32_KEY_3:
        key = '3';
        break;
    case RV32_KEY_4:
        key = '4';
        break;
    case RV32_KEY_5:
        key = '5';
        break;
    case RV32_KEY_6:
        key = '6';
        break;
    case RV32_KEY_7:
        key = '7';
        break;
    case RV32_KEY_8:
        key = '8';
        break;
    case RV32_KEY_9:
        key = '9';
        break;
	default:
		key = tolower(key);
		break;
	}

	return key;
}

void DG_Init()
{
#ifdef ENABLE_WOW_API
    asm volatile (
        "li a7, %0\n"
        "ecall\n"
        :
        : "i" (SYS_WOW_toggle_window)
        : "a7"
    );
#endif
}

void DG_DrawFrame()
{
#ifdef ENABLE_WOW_API
    asm volatile (
        "li a7, %0\n"
        "mv a0, %1\n"
        "ecall\n"
        : 
        : "i" (SYS_WOW_send_framebuffer), "r" (DG_ScreenBuffer)
        : "a0", "a7"
    );
#else
    printf("frame\n");
#endif
}

void DG_SleepMs(uint32_t ms)
{
    #ifdef ENABLE_WOW_API
    asm volatile (
        "li a7, %0\n"
        "mv a0, %1\n"
        "ecall\n"
        : 
        : "i" (SYS_WOW_sleep), "r" (ms)
        : "a0", "a7"
    );
#endif
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
    if (s_KeyQueueReadIndex == s_KeyQueueWriteIndex){
        //key queue is empty
        return 0;
    } else {
        unsigned short keyData = s_KeyQueue[s_KeyQueueReadIndex];

        s_KeyQueueReadIndex++;
        s_KeyQueueReadIndex %= KEYQUEUE_SIZE;

        *pressed = keyData >> 8;
        *doomKey = keyData & 0xFF;
        return 1;
    }

    return 0;
}

static void addKeyToQueue(int pressed, unsigned int keyCode){
    unsigned char key = convertToDoomKey(keyCode);
    unsigned short keyData = (pressed << 8) | key;
    s_KeyQueue[s_KeyQueueWriteIndex] = keyData;
    s_KeyQueueWriteIndex++;
    s_KeyQueueWriteIndex %= KEYQUEUE_SIZE;
}



int checkKeyPressed(int key) {
#ifdef ENABLE_WOW_API
    int result;
    asm volatile (
        "mv a0, %1\n"  
        "li a7, %2\n"  
        "ecall\n"      
        "mv %0, a0\n"  
        : "=r" (result)  
        : "r" (key), "i" (SYS_WOW_check_key_pressed)  
        : "a0", "a7"  
    );
    return result;  
#else
    return false;
#endif
}

static uint8_t key_state[RV32_KEYS_COUNT];

static void handleKeyInputs() {
    uint8_t cur, last;

    for (int i = 0; i < RV32_KEYS_COUNT; i++){
        cur = checkKeyPressed(i);
        last = key_state[i];
        if (cur != last){
            addKeyToQueue(cur > last, i);
            key_state[i] = cur;
        }
    }
}


void DG_SetWindowTitle(const char * title) {}

void DG_DrawColumn(uint8_t* dest, uint8_t* dc_colormap, uint8_t* dc_source, int frac, int frac_step, int count) {
#ifdef ENABLE_WOW_API
    asm volatile (
        "mv a0, %0\n"  
        "mv a1, %1\n"  
        "mv a2, %2\n"  
        "mv a3, %3\n"  
        "mv a4, %4\n"  
        "mv a5, %5\n"  
        "mv a6, %6\n"  
        "li a7, %7\n"  
        "ecall\n"      
        : 
        : "r" (dest), "r" (dc_colormap), "r" (dc_source), "r" (frac), "r" (frac_step), "r" (count), "r" (DG_ScreenBuffer), "i" (SYS_WOW_draw_column)  
        : "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"  
    );
#else
    // Inner loop that does the actual texture mapping,
    //  e.g. a DDA-lile scaling.
    // This is as fast as it gets.
    do 
    {
	// Re-map color indices from wall texture column
	//  using a lighting/special effects LUT.
	*dest = dc_colormap[dc_source[(frac>>FRACBITS)&127]];
	
	dest += SCREENWIDTH; 
	frac += frac_step;
	
    } while (count--);
#endif
}

void DG_DrawSpan(uint8_t* dest, uint8_t* ds_colormap, uint8_t* ds_source, unsigned int position, unsigned int step, int count) {
#ifdef ENABLE_WOW_API
    asm volatile (
        "mv a0, %0\n"  
        "mv a1, %1\n"  
        "mv a2, %2\n"  
        "mv a3, %3\n"  
        "mv a4, %4\n"  
        "mv a5, %5\n"  
        "mv a6, %6\n"  
        "li a7, %7\n"  
        "ecall\n"      
        : 
        : "r" (dest), "r" (ds_colormap), "r" (ds_source), "r" (position), "r" (step), "r" (count), "r" (DG_ScreenBuffer), "i" (SYS_WOW_draw_span)  
        : "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"  
    );
#else
    int spot;
    unsigned int xtemp, ytemp;
    do
    {
	// Calculate current texture index in u,v.
        ytemp = (position >> 4) & 0x0fc0;
        xtemp = (position >> 26);
        spot = xtemp | ytemp;

	// Lookup pixel from flat texture tile,
	//  re-index using light/colormap.
	*dest++ = ds_colormap[ds_source[spot]];

        position += step;

    } while (count--);
#endif
}

void DG_DrawPatch(int col, int is_screen_buffer, int x, uint8_t *desttop, uint8_t* source, uint8_t *m_col, uint8_t *m_patch) {
#ifdef ENABLE_WOW_API
    asm volatile (
        "mv a0, %0\n"  
        "mv a1, %1\n"  
        "mv a2, %2\n"  
        "mv a3, %3\n"  
        "mv a4, %4\n"  
        "mv a5, %5\n"  
        "mv a6, %6\n"  
        "mv t6, %7\n"  
        "li a7, %8\n"  
        "ecall\n"      
        : 
        : "r" (col), "r" (is_screen_buffer), "r" (x), "r" (desttop), "r" (source), "r" (m_col), "r" (m_patch), "r" (DG_ScreenBuffer), "i" (SYS_WOW_draw_patch)  
        : "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"  
    );
#else
    int count;
    uint8_t* dest;

    for ( ; col<w ; x++, col++, desttop++)
    {
        m_col = ((byte *)m_patch + LONG(*(int *)((char *)m_patch + 8 + col * 4))); // + (*(m_patch + 8 + 4 * col)) );

        // step through the posts in a column
        while (*(m_col) != 0xff )
        {
            source = m_col + 3;
            dest = desttop + (*m_col)*320;
            count = *(m_col + 1);

            while (count--)
            {
                *dest = *source++;
                dest += 320;
            }
            m_col = (m_col + *(m_col + 1) + 4);
        }
    }
#endif
}

void DG_CopyRect(int srcx, int srcy, uint8_t *source, int width, int height, int destx, int desty) {
#ifdef ENABLE_WOW_API
    asm volatile (
        "mv a0, %0\n"  
        "mv a1, %1\n"  
        "mv a2, %2\n"  
        "mv a3, %3\n"  
        "mv a4, %4\n"  
        "mv a5, %5\n"  
        "mv a6, %6\n"  
        "li a7, %7\n"  
        "ecall\n"      
        : 
        : "r" (srcx), "r" (srcy), "r" (source), "r" (width), "r" (height), "r" (destx), "r" (desty), "i" (SYS_WOW_copy_rect)  
        : "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"  
    );
#else
    src = source + SCREENWIDTH * srcy + srcx; 
    dest = dest_screen + SCREENWIDTH * desty + destx; 
    for ( ; height>0 ; height--) 
    { 
        
        DG_memcpy(dest, src, width); 
        src += SCREENWIDTH; 
        dest += SCREENWIDTH; 
    }
#endif
}



void* DG_memcpy(uint8_t *dest, uint8_t* src, size_t len) {
#ifdef ENABLE_WOW_API
    asm volatile (
        "mv a0, %0\n"  
        "mv a1, %1\n"  
        "mv a2, %2\n"  
        "li a7, %3\n"  
        "ecall\n"      
        : 
        : "r" (dest), "r" (src), "r" (len), "i" (SYS_WOW_DG_memcpy)  
        : "a0", "a1", "a2", "a7"  
    );
    return dest;
#else
    return memcpy(dest, src, len);
#endif
}



int main(int argc, char **argv)
{
    doomgeneric_Create(argc, argv);
    for (int i = 0; ; i++)
    {
        handleKeyInputs();
        doomgeneric_Tick();
    }
    return 0;
}