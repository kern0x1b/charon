// **The 0.75 filter and the host's own answers at 0.75, as one text file for recover075.py to read.**
//
// Nothing is decided here. The sixty-four Q14 rows and their sums are read out of the object
// `vImageNewResamplingFilter(0.75f, kvImageNoFlags)` returns, and the destinations out of the caller's own
// `vImageVerticalShear_ARGB16U` - so the file is the release's own numbers on both sides and the analysis that
// reads it is the only place a conclusion is drawn.
//
// The source is the harness's own ramp, `1 + ((r*7 + c*13 + ch*29) % 61) * (30000/61)` stored as uint16, five
// rows by nine columns, which is the ramp `tests/backports/host/shear/differential.m` fills - every channel
// distinct, inside the layout's range, no sum saturating. Channel 0 is dumped with the filter so the recovery
// has the source it needs in the same file.
//
// Usage: ./dump075 > dump075.txt, then python3 recover075.py dump075.txt <translate-index> <slope-index> <mode>
// where the four translates are 0, 0.5, -1, 0.0078125 and the four slopes are 0, 1, -0.5, 2.
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <Accelerate/Accelerate.h>

static uint64_t slot(const void *o, unsigned i){return *(const uintptr_t*)((const char*)o+(size_t)i*sizeof(uintptr_t));}

int main(void)
{
    ResamplingFilter f = vImageNewResamplingFilter(0.75f, kvImageNoFlags);
    double recip; uint64_t bits = slot(f,0); memcpy(&recip,&bits,sizeof recip);
    unsigned taps=(unsigned)slot(f,1), istride=(unsigned)slot(f,3), phases=(unsigned)slot(f,4);
    const int16_t *table=(const int16_t*)(uintptr_t)slot(f,7);
    unsigned width=istride/2; int best=-(1<<30); unsigned K0=0;
    for(unsigned k=0;k<width;k++) if(table[k]>best){best=table[k];K0=k;}
    printf("FILTER recip %.17g taps %u int16Stride %u phases %u width %u K0 %u\n",
           recip,taps,istride,phases,width,K0);
    for(unsigned p=0;p<phases;p++){
        const int16_t *row=table+(size_t)p*width; long sum=0;
        printf("ROW %u",p);
        for(unsigned k=0;k<width;k++){printf(" %d",row[k]); sum+=row[k];}
        printf(" %ld\n",sum);
    }
    const int SW=9, SH=5;
    // The source, in the file: the recovery needs it and it is this program's own fill, so printing it keeps the
    // analysis and the dump from having two copies of the ramp in them.
    for(int r=0;r<SH;r++){
        printf("SRC");
        for(int c=0;c<SW;c++)
            printf(" %d",(int)(uint16_t)(1.0+(double)((r*7+c*13+0*29)%61)*(30000.0/61.0)));
        printf("\n");
    }
    {
        printf("RAMP 1 + ((r*7 + c*13 + ch*29) %% 61) * (30000/61), stored as uint16, %d rows by %d columns\n", SH, SW);
    }
    double translates[]={0.0,0.5,-1.0,0.0078125};
    double slopes[]={0.0,1.0,-0.5,2.0};
    for(unsigned t=0;t<4;t++) for(unsigned sl=0;sl<4;sl++) for(int m=0;m<2;m++){
        uint16_t *src=calloc((size_t)SW*SH*4,sizeof(uint16_t));
        uint16_t *dst=calloc((size_t)SW*SH*4,sizeof(uint16_t));
        for(int r=0;r<SH;r++) for(int c=0;c<SW;c++) for(int ch=0;ch<4;ch++)
            src[(r*SW+c)*4+ch]=(uint16_t)(1.0+(double)((r*7+c*13+ch*29)%61)*(30000.0/61.0));
        vImage_Buffer in={0},out={0};
        in.width=SW;in.height=SH;in.rowBytes=SW*8;in.data=src;
        out.width=SW;out.height=SH;out.rowBytes=SW*8;out.data=dst;
        Pixel_ARGB_16U back; memset(&back,0,sizeof back);
        vImageVerticalShear_ARGB16U(&in,&out,0,0,(float)translates[t],(float)slopes[sl],f,
                                    (const uint16_t*)&back,
                                    m?kvImageEdgeExtend:kvImageBackgroundColorFill);
        printf("CASE %u %u %d\n",t,sl,m);
        for(int r=0;r<SH;r++){printf("DEST");
            for(int c=0;c<SW;c++) printf(" %d",(int)dst[(size_t)r*SW*4+(size_t)c*4]);
            printf("\n");}
        free(src);free(dst);
    }
    vImageDestroyResamplingFilter(f);
    return 0;
}
