#pragma once
#import <GCDWebServers/GCDWebsocketServer.h>

// Device loopback port. USBMux connects without a host listener or Wi-Fi.
#define PM_CONTROL_PORT 27185

void PMControlStartServer(void);
void PMControlInitHandlers(GCDWebsocketServer *server);
