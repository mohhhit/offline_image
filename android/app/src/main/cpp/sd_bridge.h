#ifndef SD_BRIDGE_H
#define SD_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SD_EXPORT __declspec(dllexport)
#else
#define SD_EXPORT __attribute__((visibility("default")))
#endif

// Opaque handle for Stable Diffusion context
typedef void* sd_context_handle_t;

// Callback signature for step progress updates
// step: current step (1-indexed)
// total_steps: total steps configured
// elapsed_seconds: duration of the current step
typedef void (*sd_bridge_progress_cb_t)(int32_t step, int32_t total_steps, float elapsed_seconds);

// Logging callback
typedef void (*sd_bridge_log_cb_t)(int32_t level, const char* text);

// Completion callback:
// status_code: 0 = success, 1 = cancelled/aborted, negative = error
// message_or_path: output PNG path on success, or error/status message on failure/abort
typedef void (*sd_bridge_completion_cb_t)(int32_t status_code, const char* message_or_path);

/**
 * Sets a global logging callback that forwards internal engine logs to client.
 */
SD_EXPORT void sd_bridge_set_log_callback(sd_bridge_log_cb_t log_cb);

/**
 * Initializes the Stable Diffusion context from a GGUF model file.
 * 
 * @param model_path Absolute filesystem path to the .gguf model file.
 * @param n_threads Number of CPU inference threads (recommended: physical cores - 1).
 * @param vae_tiling If true, decodes VAE in tiles to reduce peak RAM from ~1.5GB to ~300MB.
 * @param use_metal If true and running on iOS/macOS, enables Metal GPU acceleration.
 * @return Context pointer on success, NULL on failure (e.g. file missing, invalid format, OOM).
 */
SD_EXPORT sd_context_handle_t sd_bridge_init(
    const char* model_path,
    int32_t n_threads,
    bool vae_tiling,
    bool use_metal
);

/**
 * Performs Text-to-Image generation asynchronously in a native background thread.
 * Does NOT block the calling Dart isolate, allowing real-time progress callbacks,
 * live log streaming, and instant cancellation.
 * 
 * @return 0 if async generation was started, negative if failed to start.
 */
SD_EXPORT int32_t sd_bridge_txt2img_async(
    sd_context_handle_t ctx,
    const char* prompt,
    const char* negative_prompt,
    float cfg_scale,
    int32_t width,
    int32_t height,
    int32_t sample_method,
    int32_t sample_steps,
    int64_t seed,
    const char* output_png_path,
    sd_bridge_progress_cb_t progress_cb,
    sd_bridge_completion_cb_t completion_cb
);

/**
 * Performs Text-to-Image generation synchronously and writes the resulting PNG directly to disk.
 * Direct disk writing avoids multi-megabyte memory copies across Dart FFI.
 * 
 * @param ctx Valid context pointer returned by sd_bridge_init.
 * @param prompt Positive text prompt.
 * @param negative_prompt Negative text prompt (empty string or NULL if none).
 * @param cfg_scale Classifier-Free Guidance scale (recommended: 7.0f).
 * @param width Image width in pixels (recommended: 512 for SD 2.1 mobile).
 * @param height Image height in pixels (recommended: 512 for SD 2.1 mobile).
 * @param sample_method 0=Euler_A, 1=Euler, 2=Heun, 3=DPM2, 4=DPMPP2S_A, 5=DPMPP2M.
 * @param sample_steps Sampling steps (recommended: 15-25).
 * @param seed Random seed (-1 for randomized seed).
 * @param output_png_path Absolute path where the final PNG image will be written.
 * @param progress_cb Callback invoked after each denoising step.
 * @return 0 on success, negative error code on failure.
 */
SD_EXPORT int32_t sd_bridge_txt2img_to_file(
    sd_context_handle_t ctx,
    const char* prompt,
    const char* negative_prompt,
    float cfg_scale,
    int32_t width,
    int32_t height,
    int32_t sample_method,
    int32_t sample_steps,
    int64_t seed,
    const char* output_png_path,
    sd_bridge_progress_cb_t progress_cb
);

/**
 * Aborts an active generation in progress.
 */
SD_EXPORT void sd_bridge_abort(sd_context_handle_t ctx);

/**
 * Frees the native context and releases all allocated model weights & VAE buffers from RAM.
 */
SD_EXPORT void sd_bridge_free(sd_context_handle_t ctx);

/**
 * Returns hardware and runtime info (e.g., NEON, OpenMP, Metal, ARM_F16).
 */
SD_EXPORT const char* sd_bridge_get_system_info(void);

#ifdef __cplusplus
}
#endif

#endif // SD_BRIDGE_H

