#ifndef WEB_API_H
#define WEB_API_H

#include <WebServer.h>

extern WebServer server;

void setupAPI();
void setupServer();

void handlePendingScan();

#endif
