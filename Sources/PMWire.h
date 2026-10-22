#ifndef PM_WIRE_H
#define PM_WIRE_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define PM_VIDEO_PORT 27184
#define PM_MAX_PACKET (16u * 1024u * 1024u)
#define PM_CONFIG_FLAG (UINT64_C(1) << 63)
#define PM_KEY_FLAG (UINT64_C(1) << 62)

static inline uint32_t PMRead32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static inline void PMWrite32(uint8_t *p, uint32_t value) {
    for (int i = 3; i >= 0; --i) { p[i] = (uint8_t)value; value >>= 8; }
}
static inline void PMWrite64(uint8_t *p, uint64_t value) {
    for (int i = 7; i >= 0; --i) { p[i] = (uint8_t)value; value >>= 8; }
}
// Identical to the scrcpy 12-byte packet envelope already used by GoScrcpy.
static inline int PMPacketHeader(uint8_t out[12], uint64_t ptsFlags, size_t length) {
    if (!length || length > PM_MAX_PACKET) return 0;
    PMWrite64(out, ptsFlags);
    PMWrite32(out + 8, (uint32_t)length);
    return 1;
}
static inline int PMValidRequest(const uint8_t request[16]) {
    uint32_t fps = PMRead32(request + 4), rate = PMRead32(request + 8), size = PMRead32(request + 12);
    return memcmp(request, "PMV1", 4) == 0 && fps >= 1 && fps <= 60 &&
        rate >= 100000 && rate <= 100000000 && (size == 0 || (size >= 64 && size <= 8192));
}
// VideoToolbox's 4-byte AVCC prefixes become equal-sized Annex B start codes.
static inline int PMAnnexB(uint8_t *data, size_t size) {
    if (!size || size > PM_MAX_PACKET) return 0;
    for (size_t offset = 0; offset < size;) {
        if (size - offset < 4) return 0;
        uint32_t length = PMRead32(data + offset);
        if (!length || length > size - offset - 4) return 0;
        PMWrite32(data + offset, 1);
        offset += 4 + length;
    }
    return 1;
}
#endif
