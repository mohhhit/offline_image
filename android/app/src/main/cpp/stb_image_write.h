#ifndef STB_IMAGE_WRITE_H
#define STB_IMAGE_WRITE_H

#ifdef __cplusplus
extern "C" {
#endif

// Writes an RGB or RGBA image buffer to a PNG file on disk
int stbi_write_png(char const *filename, int w, int h, int comp, const void *data, int stride_in_bytes);

#ifdef __cplusplus
}
#endif

#endif // STB_IMAGE_WRITE_H

