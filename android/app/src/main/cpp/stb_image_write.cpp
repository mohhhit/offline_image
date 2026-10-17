#include "stb_image_write.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>

// Fast, portable CRC32 and Adler32 calculation for standard valid PNG encoding
static uint32_t crc32_table[256];
static bool crc32_table_computed = false;

static void make_crc32_table(void) {
    for (uint32_t n = 0; n < 256; n++) {
        uint32_t c = n;
        for (int k = 0; k < 8; k++) {
            if (c & 1) c = 0xedb88320L ^ (c >> 1);
            else c = c >> 1;
        }
        crc32_table[n] = c;
    }
    crc32_table_computed = true;
}

static uint32_t update_crc32(uint32_t crc, const uint8_t *buf, size_t len) {
    if (!crc32_table_computed) make_crc32_table();
    uint32_t c = crc ^ 0xffffffffL;
    for (size_t n = 0; n < len; n++) {
        c = crc32_table[(c ^ buf[n]) & 0xff] ^ (c >> 8);
    }
    return c ^ 0xffffffffL;
}

static void write_u32_be(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)(v);
}

static void write_chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len) {
    uint8_t len_bytes[4];
    write_u32_be(len_bytes, len);
    fwrite(len_bytes, 1, 4, f);
    fwrite(type, 1, 4, f);
    if (len > 0 && data != nullptr) {
        fwrite(data, 1, len, f);
    }
    uint32_t crc = update_crc32(0, (const uint8_t *)type, 4);
    if (len > 0 && data != nullptr) {
        crc = update_crc32(crc, data, len);
    }
    uint8_t crc_bytes[4];
    write_u32_be(crc_bytes, crc);
    fwrite(crc_bytes, 1, 4, f);
}

// Writes an RGB or RGBA uncompressed-deflate valid PNG file
int stbi_write_png(char const *filename, int w, int h, int comp, const void *data, int stride_in_bytes) {
    if (filename == nullptr || w <= 0 || h <= 0 || (comp != 3 && comp != 4) || data == nullptr) {
        return 0;
    }

    FILE *f = fopen(filename, "wb");
    if (!f) return 0;

    // 1. PNG Signature
    const uint8_t signature[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };
    fwrite(signature, 1, 8, f);

    // 2. IHDR Chunk
    uint8_t ihdr[13];
    write_u32_be(ihdr, (uint32_t)w);
    write_u32_be(ihdr + 4, (uint32_t)h);
    ihdr[8] = 8; // 8 bits per channel
    ihdr[9] = (comp == 3) ? 2 : 6; // Color type: 2=RGB, 6=RGBA
    ihdr[10] = 0; // Deflate compression
    ihdr[11] = 0; // Filter
    ihdr[12] = 0; // Non-interlaced
    write_chunk(f, "IHDR", ihdr, 13);

    // 3. IDAT Chunk with Deflate non-compressed blocks (0x00) and Adler32
    int row_stride = (stride_in_bytes > 0) ? stride_in_bytes : (w * comp);
    const uint8_t *src_bytes = (const uint8_t *)data;

    // Construct raw scanlines with leading 0 filter byte
    std::vector<uint8_t> raw_stream;
    raw_stream.reserve(h * (1 + w * comp));

    for (int y = 0; y < h; y++) {
        raw_stream.push_back(0); // Filter byte: None
        const uint8_t *row = src_bytes + (y * row_stride);
        raw_stream.insert(raw_stream.end(), row, row + (w * comp));
    }

    // Compute Adler-32 over raw scanlines
    uint32_t s1 = 1;
    uint32_t s2 = 0;
    for (size_t i = 0; i < raw_stream.size(); i++) {
        s1 = (s1 + raw_stream[i]) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    uint32_t adler = (s2 << 16) | s1;

    // Build ZLIB envelope
    std::vector<uint8_t> zlib_data;
    zlib_data.push_back(0x78); // CMF: Deflate, 32K window
    zlib_data.push_back(0x01); // FLG: No preset dict, check bits

    size_t offset = 0;
    size_t total_len = raw_stream.size();
    while (offset < total_len) {
        size_t block_size = total_len - offset;
        bool is_last = true;
        if (block_size > 65535) {
            block_size = 65535;
            is_last = false;
        }

        zlib_data.push_back(is_last ? 0x01 : 0x00); // BFINAL & BTYPE (stored)
        uint16_t len16 = (uint16_t)block_size;
        uint16_t nlen16 = ~len16;

        zlib_data.push_back((uint8_t)(len16 & 0xff));
        zlib_data.push_back((uint8_t)((len16 >> 8) & 0xff));
        zlib_data.push_back((uint8_t)(nlen16 & 0xff));
        zlib_data.push_back((uint8_t)((nlen16 >> 8) & 0xff));

        zlib_data.insert(
            zlib_data.end(),
            raw_stream.begin() + offset,
            raw_stream.begin() + offset + block_size
        );
        offset += block_size;
    }

    // Append Adler32 in big endian
    zlib_data.push_back((uint8_t)(adler >> 24));
    zlib_data.push_back((uint8_t)(adler >> 16));
    zlib_data.push_back((uint8_t)(adler >> 8));
    zlib_data.push_back((uint8_t)(adler & 0xff));

    write_chunk(f, "IDAT", zlib_data.data(), (uint32_t)zlib_data.size());

    // 4. IEND Chunk
    write_chunk(f, "IEND", nullptr, 0);

    fclose(f);
    return 1;
}

