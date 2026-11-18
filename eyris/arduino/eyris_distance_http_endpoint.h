#pragma once

#include <stdio.h>
#include "esp_http_server.h"

// The pointer passed to registration must refer to a live, shared centimeter
// reading (for example, a global volatile int updated by the sensor loop).
inline esp_err_t eyrisDistanceHttpHandler(httpd_req_t *request) {
  const volatile int *distanceCm =
      static_cast<const volatile int *>(request->user_ctx);
  if (distanceCm == nullptr) {
    httpd_resp_send_err(request, HTTPD_500_INTERNAL_SERVER_ERROR,
                        "Distance sensor unavailable");
    return ESP_FAIL;
  }

  char body[48];
  const int centimeters = *distanceCm;
  snprintf(body, sizeof(body), "{\"distance\":%d}", centimeters);
  httpd_resp_set_type(request, "application/json");
  httpd_resp_set_hdr(request, "Cache-Control", "no-store");
  return httpd_resp_send(request, body, HTTPD_RESP_USE_STRLEN);
}

inline esp_err_t eyrisRegisterDistanceHttpEndpoint(
    httpd_handle_t cameraHttpServer, volatile int *distanceCm) {
  if (cameraHttpServer == nullptr || distanceCm == nullptr) return ESP_ERR_INVALID_ARG;

  httpd_uri_t uri = {};
  uri.uri = "/distance";
  uri.method = HTTP_GET;
  uri.handler = eyrisDistanceHttpHandler;
  uri.user_ctx = distanceCm;
  return httpd_register_uri_handler(cameraHttpServer, &uri);
}
