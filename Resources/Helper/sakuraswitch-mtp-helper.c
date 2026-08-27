#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/stat.h>
#include <libusb-1.0/libusb.h>
#include <libmtp.h>

#define NINTENDO_VID 0x057E
#define DBI_MTP_PID  0x201D
#define STAGING_PREFIX "/private/tmp/sakuraswitch_install_"

static int valid_path(const char *path) {
    if (!path) return 0;
    if (strncmp(path, STAGING_PREFIX, strlen(STAGING_PREFIX)) != 0) return 0;
    if (strstr(path, "/../") || strstr(path, "/./")) return 0;

    struct stat st;
    if (lstat(path, &st) != 0) return 0;
    if (!S_ISREG(st.st_mode)) return 0;
    if (S_ISLNK(st.st_mode)) return 0;

    return 1;
}

static const char *filename_only(const char *path) {
    const char *p = strrchr(path, '/');
    return p ? p + 1 : path;
}

static void print_folders(LIBMTP_folder_t *folder) {
    while (folder) {
        const char *name = folder->name ? folder->name : "";

        printf("FOLDER:%u:%u:%u:%s\n",
               folder->folder_id,
               folder->parent_id,
               folder->storage_id,
               name);
        fflush(stdout);

        if (folder->child)
            print_folders(folder->child);

        folder = folder->sibling;
    }
}

static int detach_switch(void) {
    libusb_context *ctx = NULL;
    libusb_device_handle *handle = NULL;

    if (libusb_init(&ctx) != 0)
        return -1;

    handle = libusb_open_device_with_vid_pid(ctx, NINTENDO_VID, DBI_MTP_PID);

    if (!handle) {
        libusb_exit(ctx);
        return -2;
    }

    libusb_set_auto_detach_kernel_driver(handle, 1);

    int active = libusb_kernel_driver_active(handle, 0);
    if (active == 1)
        libusb_detach_kernel_driver(handle, 0);

    libusb_close(handle);
    libusb_exit(ctx);

    return 0;
}


static int print_object_info_line(
    libusb_device_handle *h,
    uint32_t *tx,
    uint32_t handle
) {
    uint8_t cmd[20] = {0};

    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } mtp_header_t_local;

    mtp_header_t_local *hdr = (mtp_header_t_local *)cmd;

    hdr->length = 16;
    hdr->type = 1;
    hdr->code = 0x1008; /* GetObjectInfo */
    hdr->transaction = (*tx)++;

    *(uint32_t *)(cmd + 12) = handle;

    int transferred = 0;

    if (libusb_bulk_transfer(
        h, 0x01, cmd, 16, &transferred, 3000
    ) != 0) {
        return -1;
    }

    uint8_t data[4096] = {0};

    if (libusb_bulk_transfer(
        h, 0x81, data, sizeof(data), &transferred, 3000
    ) != 0 || transferred < 64) {
        return -1;
    }

    mtp_header_t_local *dh = (mtp_header_t_local *)data;

    if (dh->type != 2 || dh->code != 0x1008)
        return -1;

    uint8_t *d = data + 12;

    uint16_t format = *(uint16_t *)(d + 4);
    uint32_t size   = *(uint32_t *)(d + 8);

    uint8_t *pstr = d + 52;
    uint8_t chars = pstr[0];

    char name[512] = {0};
    int pos = 0;

    for (int i = 0; i < chars - 1 && pos < 510; i++) {
        uint16_t ch =
            (uint16_t)pstr[1 + i * 2] |
            ((uint16_t)pstr[2 + i * 2] << 8);

        name[pos++] = (ch < 128) ? (char)ch : '?';
    }

    uint8_t resp[512] = {0};

    if (libusb_bulk_transfer(
        h, 0x81, resp, sizeof(resp), &transferred, 3000
    ) != 0 || transferred < 12) {
        return -1;
    }

    mtp_header_t_local *rh = (mtp_header_t_local *)resp;

    if (rh->code != 0x2001)
        return -1;

    printf("ITEM:%u:0x%04x:%u:%s\n",
           handle,
           format,
           size,
           name);

    fflush(stdout);
    return 0;
}


static int run_raw_browse(uint32_t storage_id, uint32_t parent_id) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } mtp_header_t_local;

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        printf("ERROR:DBI MTP device not found\n");
        libusb_exit(ctx);
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        libusb_close(usb);
        libusb_exit(ctx);
        return 1;
    }

    uint32_t tx = 1;

    /* Ѓ�акру�ваем возможну�у� завису�у�у� MTP-сессиу� */
    {
        uint8_t cmd[12] = {0};
        mtp_header_t_local *h = (mtp_header_t_local *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003; /* CloseSession */
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};
        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

    /* Ѓ�ткру�ваем нову�у� MTP-сессиу� */
    {
        uint8_t cmd[16] = {0};
        mtp_header_t_local *h = (mtp_header_t_local *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002; /* OpenSession */
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:OpenSession OUT failed\n");
            goto cleanup;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12) {
            printf("ERROR:OpenSession IN failed\n");
            goto cleanup;
        }

        mtp_header_t_local *rh =
            (mtp_header_t_local *)response;

        if (rh->code != 0x2001) {
            printf("ERROR:OpenSession response 0x%04x\n", rh->code);
            goto cleanup;
        }
    }

    /* GetObjectHandles */
    {
        uint8_t cmd[24] = {0};
        mtp_header_t_local *h = (mtp_header_t_local *)cmd;

        h->length = 24;
        h->type = 1;
        h->code = 0x1007;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = storage_id;
        *(uint32_t *)(cmd + 16) = 0;
        *(uint32_t *)(cmd + 20) = parent_id;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:GetObjectHandles OUT failed\n");
            goto cleanup;
        }

        uint8_t data[65536] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, data, sizeof(data),
            &transferred, 3000
        ) != 0 || transferred < 16) {
            printf("ERROR:GetObjectHandles IN failed\n");
            goto cleanup;
        }

        mtp_header_t_local *dh =
            (mtp_header_t_local *)data;

        if (dh->type != 2 || dh->code != 0x1007) {
            printf("ERROR:Unexpected GetObjectHandles response\n");
            goto cleanup;
        }

        uint32_t count = *(uint32_t *)(data + 12);

        /*
         * MTP transaction order is strict:
         * COMMAND -> DATA -> RESPONSE.
         * Consume GetObjectHandles RESPONSE before starting GetObjectInfo.
         */
        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12) {
            printf("ERROR:GetObjectHandles response missing\n");
            goto cleanup;
        }

        mtp_header_t_local *rh =
            (mtp_header_t_local *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf("ERROR:GetObjectHandles response type=%u code=0x%04x\n",
                   rh->type, rh->code);
            goto cleanup;
        }

        for (uint32_t i = 0; i < count; i++) {
            uint32_t handle =
                *(uint32_t *)(data + 16 + i * 4);

            if (print_object_info_line(
                usb,
                &tx,
                handle
            ) != 0) {
                printf("ERROR:GetObjectInfo failed for handle %u\n", handle);
                goto cleanup;
            }
        }
    }

    printf("OK\n");
    fflush(stdout);
    result = 0;

    /* Ѓ�орректно закру�ваем Ѓ�Ѓ�ШУ сессиу� */
    {
        uint8_t cmd[12] = {0};
        mtp_header_t_local *h = (mtp_header_t_local *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};
        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    libusb_release_interface(usb, 0);
    libusb_close(usb);
    libusb_exit(ctx);

    return result;
}


static int raw_get_handles(
    libusb_device_handle *usb,
    uint32_t *tx,
    uint32_t storage_id,
    uint32_t parent_id,
    uint32_t **handles_out,
    uint32_t *count_out
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    int transferred = 0;
    uint8_t cmd[24] = {0};
    hdr_t *h = (hdr_t *)cmd;

    h->length = 24;
    h->type = 1;
    h->code = 0x1007;
    h->transaction = (*tx)++;

    *(uint32_t *)(cmd + 12) = storage_id;
    *(uint32_t *)(cmd + 16) = 0;
    *(uint32_t *)(cmd + 20) = parent_id;

    if (libusb_bulk_transfer(
        usb, 0x01, cmd, sizeof(cmd),
        &transferred, 3000
    ) != 0)
        return -1;

    uint8_t data[65536] = {0};

    if (libusb_bulk_transfer(
        usb, 0x81, data, sizeof(data),
        &transferred, 3000
    ) != 0 || transferred < 16)
        return -1;

    hdr_t *dh = (hdr_t *)data;

    if (dh->type != 2 || dh->code != 0x1007)
        return -1;

    uint32_t count = *(uint32_t *)(data + 12);

    uint32_t *handles = NULL;

    if (count > 0) {
        handles = calloc(count, sizeof(uint32_t));
        if (!handles)
            return -1;

        for (uint32_t i = 0; i < count; i++)
            handles[i] = *(uint32_t *)(data + 16 + i * 4);
    }

    /* RESPONSE */
    uint8_t response[512] = {0};

    if (libusb_bulk_transfer(
        usb, 0x81, response, sizeof(response),
        &transferred, 3000
    ) != 0 || transferred < 12) {
        free(handles);
        return -1;
    }

    hdr_t *rh = (hdr_t *)response;

    if (rh->type != 3 || rh->code != 0x2001) {
        free(handles);
        return -1;
    }

    *handles_out = handles;
    *count_out = count;

    return 0;
}


static int append_utf8_codepoint(
    char *out,
    size_t out_size,
    size_t *pos,
    uint32_t cp
) {
    if (!out || !pos || out_size == 0)
        return -1;

    if (cp <= 0x7F) {
        if (*pos + 1 >= out_size)
            return -1;

        out[(*pos)++] = (char)cp;
        return 0;
    }

    if (cp <= 0x7FF) {
        if (*pos + 2 >= out_size)
            return -1;

        out[(*pos)++] = (char)(0xC0 | (cp >> 6));
        out[(*pos)++] = (char)(0x80 | (cp & 0x3F));
        return 0;
    }

    if (cp <= 0xFFFF) {
        if (*pos + 3 >= out_size)
            return -1;

        out[(*pos)++] = (char)(0xE0 | (cp >> 12));
        out[(*pos)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[(*pos)++] = (char)(0x80 | (cp & 0x3F));
        return 0;
    }

    if (cp <= 0x10FFFF) {
        if (*pos + 4 >= out_size)
            return -1;

        out[(*pos)++] = (char)(0xF0 | (cp >> 18));
        out[(*pos)++] = (char)(0x80 | ((cp >> 12) & 0x3F));
        out[(*pos)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[(*pos)++] = (char)(0x80 | (cp & 0x3F));
        return 0;
    }

    return -1;
}


static int raw_get_object_info(
    libusb_device_handle *usb,
    uint32_t *tx,
    uint32_t handle,
    uint16_t *format_out,
    uint32_t *size_out,
    char *name_out,
    size_t name_size
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    int transferred = 0;
    uint8_t cmd[16] = {0};
    hdr_t *h = (hdr_t *)cmd;

    h->length = 16;
    h->type = 1;
    h->code = 0x1008;
    h->transaction = (*tx)++;

    *(uint32_t *)(cmd + 12) = handle;

    if (libusb_bulk_transfer(
        usb, 0x01, cmd, sizeof(cmd),
        &transferred, 3000
    ) != 0)
        return -1;

    uint8_t data[4096] = {0};

    if (libusb_bulk_transfer(
        usb, 0x81, data, sizeof(data),
        &transferred, 3000
    ) != 0 || transferred < 64)
        return -1;

    hdr_t *dh = (hdr_t *)data;

    if (dh->type != 2 || dh->code != 0x1008)
        return -1;

    uint8_t *d = data + 12;

    uint16_t format = *(uint16_t *)(d + 4);
    uint32_t size = *(uint32_t *)(d + 8);

    uint8_t *pstr = d + 52;
    uint8_t chars = pstr[0];

    size_t pos = 0;

    if (name_size > 0)
        name_out[0] = '\0';

    for (int i = 0; i < chars - 1; i++) {
        uint16_t ch =
            (uint16_t)pstr[1 + i * 2] |
            ((uint16_t)pstr[2 + i * 2] << 8);

        uint32_t cp;

        /*
         * UTF-16 surrogate pair.
         */
        if (ch >= 0xD800 && ch <= 0xDBFF) {
            if (i + 1 < chars - 1) {
                uint16_t low =
                    (uint16_t)pstr[1 + (i + 1) * 2] |
                    ((uint16_t)pstr[2 + (i + 1) * 2] << 8);

                if (low >= 0xDC00 && low <= 0xDFFF) {
                    cp =
                        0x10000 +
                        (((uint32_t)ch - 0xD800) << 10) +
                        ((uint32_t)low - 0xDC00);

                    i++;
                } else {
                    cp = 0xFFFD;
                }
            } else {
                cp = 0xFFFD;
            }

        } else if (ch >= 0xDC00 && ch <= 0xDFFF) {
            cp = 0xFFFD;

        } else {
            cp = ch;
        }

        if (append_utf8_codepoint(
            name_out,
            name_size,
            &pos,
            cp
        ) != 0) {
            break;
        }
    }

    if (name_size > 0)
        name_out[pos] = '\0';

    /* RESPONSE */
    uint8_t response[512] = {0};

    if (libusb_bulk_transfer(
        usb, 0x81, response, sizeof(response),
        &transferred, 3000
    ) != 0 || transferred < 12)
        return -1;

    hdr_t *rh = (hdr_t *)response;

    if (rh->type != 3 || rh->code != 0x2001)
        return -1;

    *format_out = format;
    *size_out = size;

    return 0;
}


static int run_raw_browse_path(
    uint32_t storage_id,
    const char *path
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        printf("ERROR:DBI MTP device not found\n");
        libusb_exit(ctx);
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        goto cleanup;
    }

    uint32_t tx = 1;

    /* Close stale session */
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

    /* Open session */
    {
        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0)
            goto cleanup;

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12)
            goto cleanup;

        hdr_t *rh = (hdr_t *)response;

        if (rh->code != 0x2001)
            goto cleanup;
    }

    uint32_t parent = 0xFFFFFFFF;

    char path_copy[2048];
    snprintf(path_copy, sizeof(path_copy), "%s", path ? path : "/");

    char *saveptr = NULL;
    char *part = strtok_r(path_copy, "/", &saveptr);

    /* Resolve every directory component using fresh handles
       from this SAME session. */
    while (part) {
        uint32_t *handles = NULL;
        uint32_t count = 0;

        if (raw_get_handles(
            usb, &tx, storage_id, parent,
            &handles, &count
        ) != 0) {
            printf("ERROR:Unable to read path component %s\n", part);
            goto close_session;
        }

        uint32_t found = 0;

        for (uint32_t i = 0; i < count; i++) {
            uint16_t format = 0;
            uint32_t size = 0;
            char name[512];

            if (raw_get_object_info(
                usb, &tx, handles[i],
                &format, &size,
                name, sizeof(name)
            ) != 0)
                continue;

            if (format == 0x3001 && strcmp(name, part) == 0) {
                found = handles[i];
                break;
            }
        }

        free(handles);

        if (!found) {
            printf("ERROR:Folder not found: %s\n", part);
            goto close_session;
        }

        parent = found;
        part = strtok_r(NULL, "/", &saveptr);
    }

    /* List final directory */
    {
        uint32_t *handles = NULL;
        uint32_t count = 0;

        if (raw_get_handles(
            usb, &tx, storage_id, parent,
            &handles, &count
        ) != 0) {
            printf("ERROR:Unable to browse requested path\n");
            goto close_session;
        }

        for (uint32_t i = 0; i < count; i++) {
            uint16_t format = 0;
            uint32_t size = 0;
            char name[512];

            if (raw_get_object_info(
                usb, &tx, handles[i],
                &format, &size,
                name, sizeof(name)
            ) == 0) {
                printf(
                    "ITEM:%u:0x%04x:%u:%s\n",
                    handles[i],
                    format,
                    size,
                    name
                );
            }
        }

        free(handles);
    }

    printf("OK\n");
    fflush(stdout);
    result = 0;

close_session:
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    if (usb) {
        libusb_release_interface(usb, 0);
        libusb_close(usb);
    }

    if (ctx)
        libusb_exit(ctx);

    return result;
}


static int raw_resolve_directory(
    libusb_device_handle *usb,
    uint32_t *tx,
    uint32_t storage_id,
    const char *path,
    uint32_t *parent_out
) {
    uint32_t parent = 0xFFFFFFFF;

    char path_copy[2048];
    snprintf(path_copy, sizeof(path_copy), "%s", path ? path : "/");

    char *saveptr = NULL;
    char *part = strtok_r(path_copy, "/", &saveptr);

    while (part) {
        uint32_t *handles = NULL;
        uint32_t count = 0;

        if (raw_get_handles(
            usb, tx, storage_id, parent,
            &handles, &count
        ) != 0) {
            return -1;
        }

        uint32_t found = 0;

        for (uint32_t i = 0; i < count; i++) {
            uint16_t format = 0;
            uint32_t size = 0;
            char name[512];

            if (raw_get_object_info(
                usb, tx, handles[i],
                &format, &size,
                name, sizeof(name)
            ) != 0)
                continue;

            if (format == 0x3001 && strcmp(name, part) == 0) {
                found = handles[i];
                break;
            }
        }

        free(handles);

        if (!found)
            return -1;

        parent = found;
        part = strtok_r(NULL, "/", &saveptr);
    }

    *parent_out = parent;
    return 0;
}


static size_t write_ptp_string(
    uint8_t *dst,
    size_t capacity,
    const char *text
) {
    size_t len = strlen(text);

    if (len > 254)
        len = 254;

    size_t needed = 1 + (len + 1) * 2;

    if (needed > capacity)
        return 0;

    dst[0] = (uint8_t)(len + 1);

    for (size_t i = 0; i < len; i++) {
        dst[1 + i * 2] = (uint8_t)text[i];
        dst[2 + i * 2] = 0;
    }

    /* terminating UTF-16 NUL */
    dst[1 + len * 2] = 0;
    dst[2 + len * 2] = 0;

    return needed;
}


static int run_raw_upload_path(
    uint32_t storage_id,
    const char *remote_path,
    const char *local_path
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    /*
     * Root helper must not be usable to read arbitrary user files.
     * Upload source is restricted to our private staging prefix.
     */
    const char *upload_prefix = "/private/tmp/sakuraswitch_upload_";

    if (strncmp(
        local_path,
        upload_prefix,
        strlen(upload_prefix)
    ) != 0) {
        printf("ERROR:Rejected upload path\n");
        return 1;
    }

    struct stat st;

    if (lstat(local_path, &st) != 0 ||
        !S_ISREG(st.st_mode) ||
        S_ISLNK(st.st_mode)) {
        printf("ERROR:Invalid upload file\n");
        return 1;
    }

    /*
     * First test implementation intentionally limits one object to <4 GiB.
     * We will handle large-object transport separately after verification.
     */
    if ((uint64_t)st.st_size > 0xFFFFFF00ULL) {
        printf("ERROR:Test uploader currently supports files below 4 GiB\n");
        return 1;
    }

    FILE *fp = fopen(local_path, "rb");

    if (!fp) {
        printf("ERROR:Unable to open upload file\n");
        return 1;
    }

    const char *name = filename_only(local_path);

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        fclose(fp);
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        fclose(fp);
        libusb_exit(ctx);
        printf("ERROR:DBI MTP device not found\n");
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        goto cleanup;
    }

    uint32_t tx = 1;

    /* Close stale session */
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

    /* OpenSession */
    {
        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:OpenSession OUT failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12) {
            printf("ERROR:OpenSession IN failed\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->code != 0x2001) {
            printf("ERROR:OpenSession response 0x%04x\n", rh->code);
            goto close_session;
        }
    }

    uint32_t parent = 0xFFFFFFFF;

    if (raw_resolve_directory(
        usb,
        &tx,
        storage_id,
        remote_path,
        &parent
    ) != 0) {
        printf("ERROR:Destination folder not found: %s\n", remote_path);
        goto close_session;
    }

    uint32_t new_handle = 0;

    /* SendObjectInfo */
    {
        uint32_t transaction = tx++;

        uint8_t cmd[20] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 20;
        h->type = 1;
        h->code = 0x100C;
        h->transaction = transaction;

        *(uint32_t *)(cmd + 12) = storage_id;
        *(uint32_t *)(cmd + 16) = parent;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SendObjectInfo command failed\n");
            goto close_session;
        }

        uint8_t dataset[2048] = {0};

        *(uint32_t *)(dataset + 0) = storage_id;
        *(uint16_t *)(dataset + 4) = 0x3000; /* Undefined/file */
        *(uint16_t *)(dataset + 6) = 0;      /* Protection */
        *(uint32_t *)(dataset + 8) = (uint32_t)st.st_size;

        /* thumbnail fields 12..25 stay zero */
        /* image fields 26..37 stay zero */

        *(uint32_t *)(dataset + 38) = parent;
        *(uint16_t *)(dataset + 42) = 0; /* AssociationType */
        *(uint32_t *)(dataset + 44) = 0; /* AssociationDesc */
        *(uint32_t *)(dataset + 48) = 0; /* SequenceNumber */

        size_t filename_len = write_ptp_string(
            dataset + 52,
            sizeof(dataset) - 52,
            name
        );

        if (!filename_len) {
            printf("ERROR:Filename encoding failed\n");
            goto close_session;
        }

        size_t pos = 52 + filename_len;

        /* CaptureDate, ModificationDate, Keywords = empty PTP strings */
        dataset[pos++] = 0;
        dataset[pos++] = 0;
        dataset[pos++] = 0;

        size_t dataset_len = pos;

        uint8_t data_header[12] = {0};
        hdr_t *dh = (hdr_t *)data_header;

        dh->length = (uint32_t)(12 + dataset_len);
        dh->type = 2;
        dh->code = 0x100C;
        dh->transaction = transaction;

        if (libusb_bulk_transfer(
            usb, 0x01,
            data_header, sizeof(data_header),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SendObjectInfo DATA header failed\n");
            goto close_session;
        }

        if (libusb_bulk_transfer(
            usb, 0x01,
            dataset, (int)dataset_len,
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SendObjectInfo DATA failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 5000
        ) != 0 || transferred < 12) {
            printf("ERROR:SendObjectInfo response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf("ERROR:SendObjectInfo response 0x%04x\n", rh->code);
            goto close_session;
        }

        /*
         * Standard SendObjectInfo response:
         * param1 StorageID, param2 ParentObject, param3 ObjectHandle
         */
        if (transferred >= 24)
            new_handle = *(uint32_t *)(response + 20);
    }

    /* SendObject */
    {
        uint32_t transaction = tx++;

        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x100D;
        h->transaction = transaction;

        if (libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SendObject command failed\n");
            goto close_session;
        }

        uint8_t data_header[12] = {0};
        hdr_t *dh = (hdr_t *)data_header;

        dh->length = (uint32_t)(12 + st.st_size);
        dh->type = 2;
        dh->code = 0x100D;
        dh->transaction = transaction;

        if (libusb_bulk_transfer(
            usb, 0x01,
            data_header, sizeof(data_header),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SendObject DATA header failed\n");
            goto close_session;
        }

        uint8_t buffer[1024 * 1024];
        uint64_t sent_total = 0;

        while (!feof(fp)) {
            size_t n = fread(buffer, 1, sizeof(buffer), fp);

            if (n == 0)
                break;

            int offset = 0;

            while (offset < (int)n) {
                int chunk_sent = 0;

                int r = libusb_bulk_transfer(
                    usb,
                    0x01,
                    buffer + offset,
                    (int)n - offset,
                    &chunk_sent,
                    10000
                );

                if (r != 0 || chunk_sent <= 0) {
                    printf("ERROR:SendObject transfer failed\n");
                    goto close_session;
                }

                offset += chunk_sent;
                sent_total += (uint64_t)chunk_sent;
            }

            printf("PROGRESS:%llu:%llu\n",
                   (unsigned long long)sent_total,
                   (unsigned long long)st.st_size);
            fflush(stdout);
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 10000
        ) != 0 || transferred < 12) {
            printf("ERROR:SendObject response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf("ERROR:SendObject response 0x%04x\n", rh->code);
            goto close_session;
        }
    }

    printf("UPLOADED:%u:%s\n", new_handle, name);
    printf("OK\n");
    fflush(stdout);
    result = 0;

close_session:
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    fclose(fp);

    if (usb) {
        libusb_release_interface(usb, 0);
        libusb_close(usb);
    }

    if (ctx)
        libusb_exit(ctx);

    return result;
}


static int raw_find_object(
    libusb_device_handle *usb,
    uint32_t *tx,
    uint32_t storage_id,
    uint32_t parent,
    const char *wanted_name,
    uint32_t *handle_out,
    uint32_t *size_out,
    uint16_t *format_out
) {
    uint32_t *handles = NULL;
    uint32_t count = 0;

    if (raw_get_handles(
        usb, tx, storage_id, parent,
        &handles, &count
    ) != 0)
        return -1;

    int found = -1;

    for (uint32_t i = 0; i < count; i++) {
        uint16_t format = 0;
        uint32_t size = 0;
        char name[512];

        if (raw_get_object_info(
            usb, tx, handles[i],
            &format, &size,
            name, sizeof(name)
        ) != 0)
            continue;

        if (strcmp(name, wanted_name) == 0) {
            *handle_out = handles[i];
            *size_out = size;
            *format_out = format;
            found = 0;
            break;
        }
    }

    free(handles);
    return found;
}


static int run_raw_download_path(
    uint32_t storage_id,
    const char *remote_directory,
    const char *remote_name,
    const char *local_path
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    const char *allowed_prefix =
        "/private/tmp/sakuraswitch_download_";

    if (strncmp(
        local_path,
        allowed_prefix,
        strlen(allowed_prefix)
    ) != 0) {
        printf("ERROR:Rejected download destination\n");
        return 1;
    }

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    FILE *fp = NULL;

    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        printf("ERROR:DBI MTP device not found\n");
        goto cleanup;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        goto cleanup;
    }

    uint32_t tx = 1;

    /* Close stale session */
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        );
    }

    /* OpenSession */
    {
        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:OpenSession command failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12) {
            printf("ERROR:OpenSession response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf("ERROR:OpenSession response 0x%04x\n", rh->code);
            goto close_session;
        }
    }

    uint32_t parent = 0xFFFFFFFF;

    if (raw_resolve_directory(
        usb,
        &tx,
        storage_id,
        remote_directory,
        &parent
    ) != 0) {
        printf(
            "ERROR:Remote directory not found: %s\n",
            remote_directory
        );
        goto close_session;
    }

    uint32_t object_handle = 0;
    uint32_t object_size = 0;
    uint16_t object_format = 0;

    if (raw_find_object(
        usb,
        &tx,
        storage_id,
        parent,
        remote_name,
        &object_handle,
        &object_size,
        &object_format
    ) != 0) {
        printf("ERROR:Remote file not found: %s\n", remote_name);
        goto close_session;
    }

    if (object_format == 0x3001) {
        printf("ERROR:Object is a directory\n");
        goto close_session;
    }

    fp = fopen(local_path, "wb");

    if (!fp) {
        printf("ERROR:Unable to create local file\n");
        goto close_session;
    }

    /* GetObject */
    {
        uint32_t transaction = tx++;

        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1009; /* GetObject */
        h->transaction = transaction;

        *(uint32_t *)(cmd + 12) = object_handle;

        if (libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:GetObject command failed\n");
            goto close_session;
        }

        uint8_t buffer[1024 * 1024];

        if (libusb_bulk_transfer(
            usb, 0x81,
            buffer, sizeof(buffer),
            &transferred, 10000
        ) != 0 || transferred < 12) {
            printf("ERROR:GetObject data missing\n");
            goto close_session;
        }

        hdr_t *dh = (hdr_t *)buffer;

        if (dh->type != 2 ||
            dh->code != 0x1009 ||
            dh->transaction != transaction) {
            printf("ERROR:Unexpected GetObject container\n");
            goto close_session;
        }

        uint64_t payload_total =
            (uint64_t)dh->length - 12;

        uint64_t received = 0;

        int first_payload = transferred - 12;

        if (first_payload > 0) {
            uint64_t useful =
                (uint64_t)first_payload > payload_total
                ? payload_total
                : (uint64_t)first_payload;

            if (fwrite(
                buffer + 12,
                1,
                (size_t)useful,
                fp
            ) != useful) {
                printf("ERROR:Local file write failed\n");
                goto close_session;
            }

            received += useful;
        }

        while (received < payload_total) {
            if (libusb_bulk_transfer(
                usb, 0x81,
                buffer, sizeof(buffer),
                &transferred, 10000
            ) != 0 || transferred <= 0) {
                printf("ERROR:GetObject transfer failed\n");
                goto close_session;
            }

            uint64_t remaining =
                payload_total - received;

            size_t useful =
                (uint64_t)transferred > remaining
                ? (size_t)remaining
                : (size_t)transferred;

            if (fwrite(
                buffer,
                1,
                useful,
                fp
            ) != useful) {
                printf("ERROR:Local file write failed\n");
                goto close_session;
            }

            received += useful;

            printf(
                "PROGRESS:%llu:%llu\n",
                (unsigned long long)received,
                (unsigned long long)payload_total
            );
            fflush(stdout);
        }

        fflush(fp);

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 10000
        ) != 0 || transferred < 12) {
            printf("ERROR:GetObject response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf(
                "ERROR:GetObject response 0x%04x\n",
                rh->code
            );
            goto close_session;
        }
    }

    fclose(fp);
    fp = NULL;

    /*
     * Helper работает от root, но скау�анну�й у�айл должен принадлежату�
     * полу�зователу� macOS, запу�стиву�ему� sudo, у�тобу� его можно бу�ло
     * откру�вату� и редактировату� обу�у�ну�ми приложениу�ми.
     */
    const char *sudo_uid = getenv("SUDO_UID");
    const char *sudo_gid = getenv("SUDO_GID");

    if (sudo_uid && sudo_gid) {
        uid_t uid = (uid_t)strtoul(sudo_uid, NULL, 10);
        gid_t gid = (gid_t)strtoul(sudo_gid, NULL, 10);

        chown(local_path, uid, gid);
        chmod(local_path, 0644);
    }

    printf(
        "DOWNLOADED:%u:%u:%s\n",
        object_handle,
        object_size,
        remote_name
    );
    printf("OK\n");
    fflush(stdout);

    result = 0;

close_session:
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    if (fp)
        fclose(fp);

    if (result != 0)
        unlink(local_path);

    if (usb) {
        libusb_release_interface(usb, 0);
        libusb_close(usb);
    }

    if (ctx)
        libusb_exit(ctx);

    return result;
}


static int run_raw_delete_path(
    uint32_t storage_id,
    const char *remote_directory,
    const char *object_name
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;

    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        printf("ERROR:DBI MTP device not found\n");
        libusb_exit(ctx);
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        goto cleanup;
    }

    uint32_t tx = 1;

    /* Close stale session */
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        );
    }

    /* OpenSession */
    {
        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:OpenSession command failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12) {
            printf("ERROR:OpenSession response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf("ERROR:OpenSession response 0x%04x\n", rh->code);
            goto close_session;
        }
    }

    uint32_t parent = 0xFFFFFFFF;

    if (raw_resolve_directory(
        usb,
        &tx,
        storage_id,
        remote_directory,
        &parent
    ) != 0) {
        printf(
            "ERROR:Remote directory not found: %s\n",
            remote_directory
        );
        goto close_session;
    }

    uint32_t object_handle = 0;
    uint32_t object_size = 0;
    uint16_t object_format = 0;

    if (raw_find_object(
        usb,
        &tx,
        storage_id,
        parent,
        object_name,
        &object_handle,
        &object_size,
        &object_format
    ) != 0) {
        printf(
            "ERROR:Object not found: %s\n",
            object_name
        );
        goto close_session;
    }

    /* DeleteObject 0x100B */
    {
        uint8_t cmd[20] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 20;
        h->type = 1;
        h->code = 0x100B;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = object_handle;
        *(uint32_t *)(cmd + 16) = 0;

        if (libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 5000
        ) != 0) {
            printf("ERROR:DeleteObject command failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 10000
        ) != 0 || transferred < 12) {
            printf("ERROR:DeleteObject response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf(
                "ERROR:DeleteObject response 0x%04x\n",
                rh->code
            );
            goto close_session;
        }
    }

    printf(
        "DELETED:%u:%s:%s\n",
        object_handle,
        object_format == 0x3001 ? "DIR" : "FILE",
        object_name
    );

    printf("OK\n");
    fflush(stdout);

    result = 0;

close_session:
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    if (usb) {
        libusb_release_interface(usb, 0);
        libusb_close(usb);
    }

    if (ctx)
        libusb_exit(ctx);

    return result;
}


static int valid_object_name(const char *name) {
    if (!name || !*name)
        return 0;

    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
        return 0;

    if (strchr(name, '/') || strchr(name, '\\'))
        return 0;

    return 1;
}


static int run_raw_mkdir_path(
    uint32_t storage_id,
    const char *remote_directory,
    const char *folder_name
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    if (!valid_object_name(folder_name)) {
        printf("ERROR:Invalid folder name\n");
        return 1;
    }

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        printf("ERROR:DBI MTP device not found\n");
        libusb_exit(ctx);
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        goto cleanup;
    }

    uint32_t tx = 1;

    /* Close stale session */
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

    /* OpenSession */
    {
        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0)
            goto close_session;

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12)
            goto close_session;

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001)
            goto close_session;
    }

    uint32_t parent = 0xFFFFFFFF;

    if (raw_resolve_directory(
        usb,
        &tx,
        storage_id,
        remote_directory,
        &parent
    ) != 0) {
        printf("ERROR:Parent folder not found: %s\n", remote_directory);
        goto close_session;
    }

    /* Ѓ�е создау�м ду�блу� */
    {
        uint32_t handle = 0;
        uint32_t size = 0;
        uint16_t format = 0;

        if (raw_find_object(
            usb,
            &tx,
            storage_id,
            parent,
            folder_name,
            &handle,
            &size,
            &format
        ) == 0) {
            printf("ERROR:Object already exists: %s\n", folder_name);
            goto close_session;
        }
    }


    /* SendObjectInfo длу� Association / Generic Folder */
    {
        uint32_t transaction = tx++;

        uint8_t cmd[20] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 20;
        h->type = 1;
        h->code = 0x100C;
        h->transaction = transaction;

        *(uint32_t *)(cmd + 12) = storage_id;
        *(uint32_t *)(cmd + 16) = parent;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SendObjectInfo command failed\n");
            goto close_session;
        }

        uint8_t dataset[2048] = {0};

        *(uint32_t *)(dataset + 0) = storage_id;
        *(uint16_t *)(dataset + 4) = 0x3001; /* Association */
        *(uint16_t *)(dataset + 6) = 0;
        *(uint32_t *)(dataset + 8) = 0;

        *(uint32_t *)(dataset + 38) = parent;
        *(uint16_t *)(dataset + 42) = 0x0001; /* Generic Folder */
        *(uint32_t *)(dataset + 44) = 0;
        *(uint32_t *)(dataset + 48) = 0;

        size_t filename_len = write_ptp_string(
            dataset + 52,
            sizeof(dataset) - 52,
            folder_name
        );

        if (!filename_len) {
            printf("ERROR:Folder name encoding failed\n");
            goto close_session;
        }

        size_t pos = 52 + filename_len;

        dataset[pos++] = 0; /* CaptureDate */
        dataset[pos++] = 0; /* ModificationDate */
        dataset[pos++] = 0; /* Keywords */

        size_t dataset_len = pos;

        uint8_t packet[4096] = {0};
        hdr_t *dh = (hdr_t *)packet;

        dh->length = (uint32_t)(12 + dataset_len);
        dh->type = 2;
        dh->code = 0x100C;
        dh->transaction = transaction;

        memcpy(packet + 12, dataset, dataset_len);

        if (libusb_bulk_transfer(
            usb, 0x01,
            packet, (int)(12 + dataset_len),
            &transferred, 5000
        ) != 0) {
            printf("ERROR:SendObjectInfo data failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 5000
        ) != 0 || transferred < 12) {
            printf("ERROR:SendObjectInfo response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf("ERROR:Create folder response 0x%04x\n", rh->code);
            goto close_session;
        }
    }

    printf("CREATED:DIR:%s\n", folder_name);
    printf("OK\n");
    fflush(stdout);
    result = 0;

close_session:
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};
        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    if (usb) {
        libusb_release_interface(usb, 0);
        libusb_close(usb);
    }

    if (ctx)
        libusb_exit(ctx);

    return result;
}


static int run_raw_rename_path(
    uint32_t storage_id,
    const char *remote_directory,
    const char *old_name,
    const char *new_name
) {
    typedef struct __attribute__((packed)) {
        uint32_t length;
        uint16_t type;
        uint16_t code;
        uint32_t transaction;
    } hdr_t;

    if (!valid_object_name(old_name) ||
        !valid_object_name(new_name)) {
        printf("ERROR:Invalid object name\n");
        return 1;
    }

    if (strcmp(old_name, new_name) == 0) {
        printf("RENAMED:%s:%s\n", old_name, new_name);
        printf("OK\n");
        return 0;
    }

    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    int transferred = 0;
    int result = 1;

    if (libusb_init(&ctx) != 0) {
        printf("ERROR:libusb init failed\n");
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(
        ctx, NINTENDO_VID, DBI_MTP_PID
    );

    if (!usb) {
        printf("ERROR:DBI MTP device not found\n");
        libusb_exit(ctx);
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(usb, 1);

    if (libusb_claim_interface(usb, 0) != 0) {
        printf("ERROR:Unable to claim DBI MTP interface\n");
        goto cleanup;
    }

    uint32_t tx = 1;

    /* Close stale */
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        );
    }

    /* OpenSession */
    {
        uint8_t cmd[16] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 16;
        h->type = 1;
        h->code = 0x1002;
        h->transaction = tx++;

        *(uint32_t *)(cmd + 12) = 1;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0)
            goto close_session;

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, response, sizeof(response),
            &transferred, 3000
        ) != 0 || transferred < 12)
            goto close_session;

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001)
            goto close_session;
    }

    uint32_t parent = 0xFFFFFFFF;

    if (raw_resolve_directory(
        usb,
        &tx,
        storage_id,
        remote_directory,
        &parent
    ) != 0) {
        printf("ERROR:Parent folder not found\n");
        goto close_session;
    }

    uint32_t object_handle = 0;
    uint32_t object_size = 0;
    uint16_t object_format = 0;

    if (raw_find_object(
        usb,
        &tx,
        storage_id,
        parent,
        old_name,
        &object_handle,
        &object_size,
        &object_format
    ) != 0) {
        printf("ERROR:Object not found: %s\n", old_name);
        goto close_session;
    }

    /* Ѓ�роверу�ем кону�ликт нового имени */
    {
        uint32_t h2 = 0;
        uint32_t s2 = 0;
        uint16_t f2 = 0;

        if (raw_find_object(
            usb,
            &tx,
            storage_id,
            parent,
            new_name,
            &h2,
            &s2,
            &f2
        ) == 0) {
            printf("ERROR:Object already exists: %s\n", new_name);
            goto close_session;
        }
    }

    /*
     * SetObjectPropValue (0x9804)
     * ObjectFileName property = 0xDC07
     */
    {
        uint32_t transaction = tx++;

        uint8_t cmd[20] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 20;
        h->type = 1;
        h->code = 0x9804;
        h->transaction = transaction;

        *(uint32_t *)(cmd + 12) = object_handle;
        *(uint32_t *)(cmd + 16) = 0xDC07;

        if (libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        ) != 0) {
            printf("ERROR:SetObjectPropValue command failed\n");
            goto close_session;
        }

        uint8_t value[1024] = {0};

        size_t value_len = write_ptp_string(
            value,
            sizeof(value),
            new_name
        );

        if (!value_len) {
            printf("ERROR:New name encoding failed\n");
            goto close_session;
        }

        uint8_t packet[2048] = {0};
        hdr_t *dh = (hdr_t *)packet;

        dh->length = (uint32_t)(12 + value_len);
        dh->type = 2;
        dh->code = 0x9804;
        dh->transaction = transaction;

        memcpy(packet + 12, value, value_len);

        if (libusb_bulk_transfer(
            usb, 0x01,
            packet, (int)(12 + value_len),
            &transferred, 5000
        ) != 0) {
            printf("ERROR:SetObjectPropValue data failed\n");
            goto close_session;
        }

        uint8_t response[512] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 5000
        ) != 0 || transferred < 12) {
            printf("ERROR:SetObjectPropValue response missing\n");
            goto close_session;
        }

        hdr_t *rh = (hdr_t *)response;

        if (rh->type != 3 || rh->code != 0x2001) {
            printf(
                "ERROR:SetObjectPropValue response 0x%04x\n",
                rh->code
            );
            goto close_session;
        }
    }

    printf(
        "RENAMED:%s:%s:%s\n",
        object_format == 0x3001 ? "DIR" : "FILE",
        old_name,
        new_name
    );

    printf("OK\n");
    fflush(stdout);
    result = 0;

close_session:
    {
        uint8_t cmd[12] = {0};
        hdr_t *h = (hdr_t *)cmd;

        h->length = 12;
        h->type = 1;
        h->code = 0x1003;
        h->transaction = tx++;

        libusb_bulk_transfer(
            usb, 0x01,
            cmd, sizeof(cmd),
            &transferred, 3000
        );

        uint8_t response[512] = {0};

        libusb_bulk_transfer(
            usb, 0x81,
            response, sizeof(response),
            &transferred, 3000
        );
    }

cleanup:
    if (usb) {
        libusb_release_interface(usb, 0);
        libusb_close(usb);
    }

    if (ctx)
        libusb_exit(ctx);

    return result;
}

int main(int argc, char **argv) {
    if (geteuid() != 0) {
        printf("ERROR:Helper must run as root\n");
        return 1;
    }

    if (argc >= 2 && strcmp(argv[1], "--claim-only") == 0) {
        int r = detach_switch();
        if (r != 0) {
            printf("ERROR:Unable to claim Nintendo Switch USB device (%d)\n", r);
            return 1;
        }

        printf("OK\n");
        return 0;
    }

    if (argc < 2) {
        printf("ERROR:Missing storage ID\n");
        return 1;
    }

    /*
     * Файлову�й брау�зер работает напру�му�у� у�ерез raw MTP.
     * Ѓ�о libmtp у�правление вообу�е не доу�одит.
     */
    if (argc >= 4 && strcmp(argv[1], "--browse") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        uint32_t parent_id =
            (uint32_t)strtoul(argv[3], NULL, 0);

        return run_raw_browse(storage_id, parent_id);
    }

    if (argc >= 4 && strcmp(argv[1], "--browse-path") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        return run_raw_browse_path(storage_id, argv[3]);
    }

    if (argc >= 5 && strcmp(argv[1], "--upload-path") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        return run_raw_upload_path(
            storage_id,
            argv[3],
            argv[4]
        );
    }

    if (argc >= 6 && strcmp(argv[1], "--download-path") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        return run_raw_download_path(
            storage_id,
            argv[3],
            argv[4],
            argv[5]
        );
    }

    if (argc >= 5 && strcmp(argv[1], "--delete-path") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        return run_raw_delete_path(
            storage_id,
            argv[3],
            argv[4]
        );
    }

    if (argc >= 5 && strcmp(argv[1], "--mkdir-path") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        return run_raw_mkdir_path(
            storage_id,
            argv[3],
            argv[4]
        );
    }

    if (argc >= 6 && strcmp(argv[1], "--rename-path") == 0) {
        uint32_t storage_id =
            (uint32_t)strtoul(argv[2], NULL, 10);

        return run_raw_rename_path(
            storage_id,
            argv[3],
            argv[4],
            argv[5]
        );
    }

    uint32_t requested_storage = (uint32_t)strtoul(argv[1], NULL, 10);

    /* Validate file paths only for installation mode.
       Browser commands (--storages / --folders) use arguments that are not paths. */
    if (argv[1][0] != '-') {
        for (int i = 2; i < argc; i++) {
            if (!valid_path(argv[i])) {
                printf("ERROR:Rejected file path\n");
                return 1;
            }
        }
    }

    int dr = detach_switch();
    printf("LOG:Kernel driver release: %d\n", dr);
    fflush(stdout);

    LIBMTP_Init();

    LIBMTP_raw_device_t *raw = NULL;
    int count = 0;

    LIBMTP_error_number_t detect =
        LIBMTP_Detect_Raw_Devices(&raw, &count);

    if (detect != LIBMTP_ERROR_NONE || count == 0) {
        printf("ERROR:No MTP devices found\n");
        return 1;
    }

    int index = -1;

    for (int i = 0; i < count; i++) {
        if (raw[i].device_entry.vendor_id == NINTENDO_VID &&
            raw[i].device_entry.product_id == DBI_MTP_PID) {
            index = i;
            break;
        }
    }

    if (index < 0) {
        free(raw);
        printf("ERROR:Nintendo Switch DBI MTP device not found\n");
        return 1;
    }

    LIBMTP_mtpdevice_t *device =
        LIBMTP_Open_Raw_Device_Uncached(&raw[index]);

    free(raw);

    if (!device) {
        printf("ERROR:Unable to open Switch through libmtp\n");
        return 1;
    }

    printf("LOG:Switch opened through libmtp\n");
    fflush(stdout);

    LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED);

    /* Browser command: dump complete object map */
    if (argc >= 2 && strcmp(argv[1], "--all") == 0) {

        /* Folders */
        LIBMTP_folder_t *folders =
            LIBMTP_Get_Folder_List_For_Storage(device, 65537);

        if (folders) {
            print_folders(folders);
            LIBMTP_destroy_folder_t(folders);
        }

        /* Files */
        LIBMTP_file_t *files = LIBMTP_Get_Filelisting(device);
        LIBMTP_file_t *file = files;

        while (file) {
            if (file->storage_id == 65537) {
                const char *name = file->filename ? file->filename : "";

                printf("FILE:%u:%u:%u:%llu:%d:%s\n",
                       file->item_id,
                       file->parent_id,
                       file->storage_id,
                       (unsigned long long)file->filesize,
                       file->filetype,
                       name);
            }

            file = file->next;
        }

        if (files)
            LIBMTP_destroy_file_t(files);

        LIBMTP_Release_Device(device);
        printf("OK\n");
        fflush(stdout);
        return 0;
    }

    /* Browser command: list one directory with object metadata */
    if (argc >= 4 && strcmp(argv[1], "--browse") == 0) {
        uint32_t storage_id = (uint32_t)strtoul(argv[2], NULL, 10);
        uint32_t parent_id  = (uint32_t)strtoul(argv[3], NULL, 0);

        /*
         * Raw GetObjectHandles is used here because DBI's dynamic object
         * handles must be consumed inside the same MTP session.
         */
        uint8_t cmd[32] = {0};

        typedef struct __attribute__((packed)) {
            uint32_t length;
            uint16_t type;
            uint16_t code;
            uint32_t transaction;
        } mtp_header_t_local;

        static uint32_t tx = 1;

        mtp_header_t_local *hdr = (mtp_header_t_local *)cmd;
        hdr->length = 24;
        hdr->type = 1;
        hdr->code = 0x1007; /* GetObjectHandles */
        hdr->transaction = tx++;

        *(uint32_t *)(cmd + 12) = storage_id;
        *(uint32_t *)(cmd + 16) = 0;
        *(uint32_t *)(cmd + 20) = parent_id;

        int transferred = 0;

        /*
         * libmtp is intentionally NOT used for nested browsing here.
         * We open raw libusb directly from the device handle below.
         */

        libusb_context *ctx = NULL;
        libusb_device_handle *usb = NULL;

        if (libusb_init(&ctx) != 0) {
            LIBMTP_Release_Device(device);
            printf("ERROR:libusb init failed\n");
            return 1;
        }

        usb = libusb_open_device_with_vid_pid(
            ctx, NINTENDO_VID, DBI_MTP_PID
        );

        if (!usb) {
            libusb_exit(ctx);
            LIBMTP_Release_Device(device);
            printf("ERROR:Unable to reopen DBI via libusb\n");
            return 1;
        }

        libusb_set_auto_detach_kernel_driver(usb, 1);

        if (libusb_claim_interface(usb, 0) != 0) {
            libusb_close(usb);
            libusb_exit(ctx);
            LIBMTP_Release_Device(device);
            printf("ERROR:Unable to claim DBI MTP interface\n");
            return 1;
        }

        uint32_t session_tx = 1;

        /* Close stale session */
        {
            uint8_t close_cmd[12] = {0};
            mtp_header_t_local *h = (mtp_header_t_local *)close_cmd;

            h->length = 12;
            h->type = 1;
            h->code = 0x1003;
            h->transaction = session_tx++;

            libusb_bulk_transfer(
                usb, 0x01, close_cmd, 12,
                &transferred, 3000
            );

            uint8_t tmp[512];
            libusb_bulk_transfer(
                usb, 0x81, tmp, sizeof(tmp),
                &transferred, 3000
            );
        }

        /* Open session */
        {
            uint8_t open_cmd[16] = {0};
            mtp_header_t_local *h = (mtp_header_t_local *)open_cmd;

            h->length = 16;
            h->type = 1;
            h->code = 0x1002;
            h->transaction = session_tx++;

            *(uint32_t *)(open_cmd + 12) = 1;

            libusb_bulk_transfer(
                usb, 0x01, open_cmd, 16,
                &transferred, 3000
            );

            uint8_t tmp[512];
            libusb_bulk_transfer(
                usb, 0x81, tmp, sizeof(tmp),
                &transferred, 3000
            );
        }

        /* GetObjectHandles */
        memset(cmd, 0, sizeof(cmd));
        hdr = (mtp_header_t_local *)cmd;

        hdr->length = 24;
        hdr->type = 1;
        hdr->code = 0x1007;
        hdr->transaction = session_tx++;

        *(uint32_t *)(cmd + 12) = storage_id;
        *(uint32_t *)(cmd + 16) = 0;
        *(uint32_t *)(cmd + 20) = parent_id;

        if (libusb_bulk_transfer(
            usb, 0x01, cmd, 24,
            &transferred, 3000
        ) != 0) {
            printf("ERROR:GetObjectHandles OUT failed\n");
            goto browse_cleanup;
        }

        uint8_t data[65536] = {0};

        if (libusb_bulk_transfer(
            usb, 0x81, data, sizeof(data),
            &transferred, 3000
        ) != 0 || transferred < 16) {
            printf("ERROR:GetObjectHandles IN failed\n");
            goto browse_cleanup;
        }

        mtp_header_t_local *dh = (mtp_header_t_local *)data;

        if (dh->type != 2 || dh->code != 0x1007) {
            printf("ERROR:Unexpected GetObjectHandles response\n");
            goto browse_cleanup;
        }

        uint32_t count = *(uint32_t *)(data + 12);

        for (uint32_t i = 0; i < count; i++) {
            uint32_t handle =
                *(uint32_t *)(data + 16 + i * 4);

            print_object_info_line(
                usb,
                &session_tx,
                handle
            );
        }

        /* consume command response */
        {
            uint8_t resp[512];
            libusb_bulk_transfer(
                usb, 0x81, resp, sizeof(resp),
                &transferred, 3000
            );
        }

        printf("OK\n");

browse_cleanup:
        libusb_release_interface(usb, 0);
        libusb_close(usb);
        libusb_exit(ctx);
        LIBMTP_Release_Device(device);
        return 0;
    }

    /* Browser command: list files and folders for one parent */
    if (argc >= 4 && strcmp(argv[1], "--list") == 0) {
        uint32_t storage_id = (uint32_t)strtoul(argv[2], NULL, 10);
        uint32_t parent_id = (uint32_t)strtoul(argv[3], NULL, 0);

        LIBMTP_file_t *items =
            LIBMTP_Get_Files_And_Folders(device, storage_id, parent_id);

        LIBMTP_file_t *item = items;

        while (item) {
            const char *name = item->filename ? item->filename : "";

            printf("ITEM:%u:%u:%u:%llu:%d:%s\n",
                   item->item_id,
                   item->parent_id,
                   item->storage_id,
                   (unsigned long long)item->filesize,
                   item->filetype,
                   name);

            item = item->next;
        }

        if (items)
            LIBMTP_destroy_file_t(items);

        LIBMTP_Release_Device(device);
        printf("OK\n");
        fflush(stdout);
        return 0;
    }

    /* Browser command: list folder tree for one storage */
    if (argc >= 3 && strcmp(argv[1], "--folders") == 0) {
        uint32_t storage_id = (uint32_t)strtoul(argv[2], NULL, 10);

        LIBMTP_folder_t *folders =
            LIBMTP_Get_Folder_List_For_Storage(device, storage_id);

        if (folders) {
            print_folders(folders);
            LIBMTP_destroy_folder_t(folders);
        }

        LIBMTP_Release_Device(device);
        printf("OK\n");
        fflush(stdout);
        return 0;
    }

    /* Browser command: list all storages exposed by DBI */
    if (argc >= 2 && strcmp(argv[1], "--storages") == 0) {
        LIBMTP_devicestorage_t *storage = device->storage;

        while (storage) {
            const char *desc =
                storage->StorageDescription ?
                storage->StorageDescription : "Unknown";

            printf("STORAGE:%u:%llu:%llu:%s\n",
                   storage->id,
                   (unsigned long long)storage->FreeSpaceInBytes,
                   (unsigned long long)storage->MaxCapacity,
                   desc);

            storage = storage->next;
        }

        LIBMTP_Release_Device(device);
        printf("OK\n");
        fflush(stdout);
        return 0;
    }

    LIBMTP_devicestorage_t *selected = NULL;
    LIBMTP_devicestorage_t *s = device->storage;

    if (requested_storage != 0) {
        while (s) {
            if (s->id == requested_storage) {
                selected = s;
                break;
            }
            s = s->next;
        }
    }

    if (!selected) {
        s = device->storage;

        while (s) {
            const char *desc =
                s->StorageDescription ? s->StorageDescription : "";

            size_t len = strlen(desc);

            if (len >= 7 &&
                strcasecmp(desc + len - 7, "install") == 0) {

                selected = s;

                if (strcasestr(desc, "sd"))
                    break;
            }

            s = s->next;
        }
    }

    if (!selected) {
        LIBMTP_Release_Device(device);
        printf("ERROR:No DBI install storage found\n");
        return 1;
    }

    printf("LOG:Using storage %u: %s\n",
           selected->id,
           selected->StorageDescription ?
           selected->StorageDescription : "?");
    fflush(stdout);

    /* argc == 2 = connection/handshake test */
    for (int i = 2; i < argc; i++) {
        const char *path = argv[i];
        const char *name = filename_only(path);

        struct stat st;
        if (stat(path, &st) != 0) {
            printf("ERROR:Unable to stat file\n");
            LIBMTP_Release_Device(device);
            return 1;
        }

        printf("LOG:Installing %s\n", name);
        fflush(stdout);

        LIBMTP_file_t *meta = LIBMTP_new_file_t();

        meta->filename = strdup(name);
        meta->filesize = (uint64_t)st.st_size;
        meta->filetype = LIBMTP_FILETYPE_UNKNOWN;
        meta->parent_id = 0xFFFFFFFF;
        meta->storage_id = selected->id;

        int r = LIBMTP_Send_File_From_File(
            device,
            path,
            meta,
            NULL,
            NULL
        );

        LIBMTP_destroy_file_t(meta);

        if (r != 0) {
            LIBMTP_error_t *es = LIBMTP_Get_Errorstack(device);

            printf("ERROR:Transfer failed for %s: %s\n",
                   name,
                   es ? es->error_text : "unknown error");

            LIBMTP_Clear_Errorstack(device);
            LIBMTP_Release_Device(device);
            return 1;
        }

        printf("PROGRESS:%s:%llu:%llu\n",
               name,
               (unsigned long long)st.st_size,
               (unsigned long long)st.st_size);

        fflush(stdout);
    }

    LIBMTP_Release_Device(device);

    printf("OK\n");
    fflush(stdout);

    return 0;
}
