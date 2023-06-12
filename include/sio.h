#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>


typedef struct RustString {
  uint8_t *buf;
  size_t len;
  size_t capacity;
} RustString;

typedef struct BinaryBlob {
  const void *data;
  size_t len;
} BinaryBlob;

typedef enum SioPayload_Tag {
  Binary,
  String,
} SioPayload_Tag;

typedef struct SioPayload {
  SioPayload_Tag tag;
  union {
    struct {
      struct BinaryBlob binary;
    };
    struct {
      struct RustString string;
    };
  };
} SioPayload;

typedef struct AckCallbackData {
  void *data;
} AckCallbackData;

typedef void (*AckCallback)(const struct SioPayload*, struct AckCallbackData);

typedef struct SioClient {
  const void *_inner;
  AckCallback on_ack;
  struct AckCallbackData on_ack_data;
} SioClient;

typedef enum SioEvent_Tag {
  Message,
  Error,
  Custom,
  Connect,
  Close,
} SioEvent_Tag;

typedef struct SioEvent {
  SioEvent_Tag tag;
  union {
    struct {
      struct RustString custom;
    };
  };
} SioEvent;

typedef struct SioEmitData {
  struct SioEvent event;
  struct SioPayload payload;
  bool ack;
  uint64_t ack_timeout;
} SioEmitData;

typedef struct SioRawClient {
  const void *_inner;
} SioRawClient;

typedef struct SioEventData {
  struct SioEvent event;
  struct SioPayload payload;
  struct SioRawClient client;
  bool wants_ack;
  int32_t message_id;
} SioEventData;

typedef struct EventCallbackData {
  void *data;
} EventCallbackData;

typedef void (*EventCallback)(const struct SioEventData*, struct EventCallbackData);

typedef struct ClientSettings {
  const char *address;
  const char *namespace_;
  const char *auth;
  bool reconnect;
  uint64_t reconnect_delay_min;
  uint64_t reconnect_delay_max;
  EventCallback on;
  struct EventCallbackData on_data;
  AckCallback on_ack;
  struct AckCallbackData on_ack_data;
} ClientSettings;

void rust_string_free(struct RustString *old_string);

struct RustString rust_string_new(size_t initial_size);

struct RustString rust_string_resize(struct RustString *old_string, size_t additional);

void sio_client_ack(const struct SioClient *client, int32_t message_id, struct SioPayload data);

void sio_client_disconnect(struct SioClient *client);

void sio_client_emit(const struct SioClient *client, struct SioEmitData data);

void sio_client_free(struct SioClient *client);

struct SioClient sio_client_new(struct ClientSettings settings);
