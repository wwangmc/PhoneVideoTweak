#include "../Sources/PMWire.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    uint8_t request[16] = {'P','M','V','1'};
    PMWrite32(request + 4, 60); PMWrite32(request + 8, 8000000); PMWrite32(request + 12, 1280);
    assert(PMValidRequest(request));
    PMWrite32(request + 4, 61); assert(!PMValidRequest(request));
    PMWrite32(request + 4, 30); PMWrite32(request + 12, 0); assert(PMValidRequest(request));
    request[0] = 'X'; assert(!PMValidRequest(request));
    uint8_t header[12];
    assert(PMPacketHeader(header, PM_CONFIG_FLAG, 15));
    assert(header[0] == 0x80 && PMRead32(header + 8) == 15);
    assert(PMPacketHeader(header, PM_KEY_FLAG | 1234567, 120));
    const uint8_t expected[] = {0x40,0,0,0,0,0x12,0xd6,0x87,0,0,0,120};
    assert(memcmp(header, expected, sizeof(expected)) == 0);
    assert(!PMPacketHeader(header, 0, 0));
    assert(!PMPacketHeader(header, 0, PM_MAX_PACKET + 1));
    uint8_t avcc[] = {0,0,0,2,0x65,0xaa,0,0,0,1,0x41};
    assert(PMAnnexB(avcc, sizeof(avcc)));
    const uint8_t annex[] = {0,0,0,1,0x65,0xaa,0,0,0,1,0x41};
    assert(memcmp(avcc, annex, sizeof(avcc)) == 0);
    uint8_t truncated[] = {0,0,0,5,0x65};
    assert(!PMAnnexB(truncated, sizeof(truncated)));
    uint8_t empty[] = {0,0,0,0};
    assert(!PMAnnexB(empty, sizeof(empty)));
    assert(!PMAnnexB(empty, 3));
    puts("PhoneVideo wire protocol: PASS");
    return 0;
}
