#include "sd_bridge.h"
#include "upstream/include/stable-diffusion.h"
#include "stb_image_write.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <atomic>
#include <thread>
#include <mutex>
#include <string>

#if defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "SD_CPP"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__)
#define LOGW(...) fprintf(stderr, __VA_ARGS__)
#define LOGE(...) fprintf(stderr, __VA_ARGS__)
#endif

static std::atomic<bool> g_abort_requested{false};
static std::atomic<bool> g_is_generating{false};
static std::thread g_worker_thread;
static std::mutex g_worker_mutex;
static sd_bridge_progress_cb_t g_active_progress_cb = nullptr;
static sd_bridge_log_cb_t g_active_log_cb = nullptr;

SD_EXPORT void sd_bridge_set_log_callback(sd_bridge_log_cb_t log_cb) {
    g_active_log_cb = log_cb;
}

static void bridge_emit_log(int32_t level, const char* text) {
    if (text == nullptr) return;
#if defined(__ANDROID__)
    android_LogPriority prio = ANDROID_LOG_INFO;
    switch (level) {
        case SD_LOG_DEBUG: prio = ANDROID_LOG_DEBUG; break;
        case SD_LOG_INFO: prio = ANDROID_LOG_INFO; break;
        case SD_LOG_WARN: prio = ANDROID_LOG_WARN; break;
        case SD_LOG_ERROR: prio = ANDROID_LOG_ERROR; break;
        default: prio = ANDROID_LOG_INFO; break;
    }
    __android_log_print(prio, LOG_TAG, "%s", text);
#else
    fprintf(stderr, "[SD_CPP] %s\n", text);
#endif

    if (g_active_log_cb != nullptr) {
        g_active_log_cb(level, text);
    }
}

static void internal_sd_log_cb(enum sd_log_level_t level, const char* text, void* data) {
    (void)data;
    if (text == nullptr) return;
    bridge_emit_log((int32_t)level, text);
}

static void internal_sd_progress_cb(int step, int steps, float time, void* data) {
    (void)data;
    char buf[128];
    snprintf(buf, sizeof(buf), "[STEP] Denoising step %d/%d (%.2fs)", step, steps, time);
    bridge_emit_log(SD_LOG_INFO, buf);

    if (g_active_progress_cb != nullptr) {
        g_active_progress_cb(step, steps, time);
    }
}

SD_EXPORT sd_context_handle_t sd_bridge_init(
    const char* model_path,
    int32_t n_threads,
    bool vae_tiling,
    bool use_metal
) {
    (void)use_metal;
    sd_set_log_callback(internal_sd_log_cb, nullptr);

    char msg[512];
    snprintf(msg, sizeof(msg), "[LOADER] Initializing Stable Diffusion context. Threads: %d, VAE Tiling: %s",
             n_threads, vae_tiling ? "ON" : "OFF");
    bridge_emit_log(SD_LOG_INFO, msg);

    if (model_path == nullptr || strlen(model_path) == 0) {
        bridge_emit_log(SD_LOG_ERROR, "[LOADER] Error: model_path argument is empty");
        return nullptr;
    }

    FILE* f = fopen(model_path, "rb");
    if (!f) {
        snprintf(msg, sizeof(msg), "[LOADER] Error: Cannot open file at '%s'", model_path);
        bridge_emit_log(SD_LOG_ERROR, msg);
        return nullptr;
    }
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fclose(f);

    snprintf(msg, sizeof(msg), "[LOADER] GGUF file verified on disk: %ld bytes (%.2f GB)",
             fsize, (double)fsize / (1024.0 * 1024.0 * 1024.0));
    bridge_emit_log(SD_LOG_INFO, msg);

    try {
        if (n_threads <= 0) {
            n_threads = sd_get_num_physical_cores();
            if (n_threads <= 0) n_threads = 4;
        }

        sd_ctx_params_t params;
        sd_ctx_params_init(&params);
        params.model_path = model_path;
        params.n_threads = n_threads;
        params.enable_mmap = true; // Use OS mmap to avoid duplicating 2.1GB in RAM
        params.batched_cfg = false; // Disable batched CFG to halve peak activation RAM on mobile

        bridge_emit_log(SD_LOG_INFO, "[LOADER] Loading weights & building GGML compute graphs (mmap)...");
        sd_ctx_t* ctx = new_sd_ctx(&params);
        if (ctx == nullptr) {
            bridge_emit_log(SD_LOG_ERROR, "[LOADER] new_sd_ctx() returned NULL! Context initialization failed.");
            return nullptr;
        }

        bridge_emit_log(SD_LOG_INFO, "[LOADER] Stable Diffusion 2.1 model ready in RAM.");
        return reinterpret_cast<sd_context_handle_t>(ctx);
    } catch (const std::exception& ex) {
        snprintf(msg, sizeof(msg), "[LOADER] std::exception during init: %s", ex.what());
        bridge_emit_log(SD_LOG_ERROR, msg);
        return nullptr;
    } catch (...) {
        bridge_emit_log(SD_LOG_ERROR, "[LOADER] Unknown exception caught during context initialization");
        return nullptr;
    }
}

static int32_t execute_txt2img(
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
) {
    char msg[512];
    snprintf(msg, sizeof(msg), "[INFERENCE] Starting generation: \"%s\" (%dx%d, %d steps, CFG %.1f)",
             prompt ? prompt : "", width, height, sample_steps, cfg_scale);
    bridge_emit_log(SD_LOG_INFO, msg);

    if (ctx == nullptr) {
        bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Context handle is NULL (-1)");
        return -1;
    }
    if (prompt == nullptr || strlen(prompt) == 0) {
        bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Prompt is empty (-2)");
        return -2;
    }
    if (output_png_path == nullptr || strlen(output_png_path) == 0) {
        bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Output PNG path is empty (-3)");
        return -3;
    }

    g_active_progress_cb = progress_cb;
    sd_set_progress_callback(internal_sd_progress_cb, nullptr);

    sd_ctx_t* sd_ctx = reinterpret_cast<sd_ctx_t*>(ctx);

    try {
        sd_img_gen_params_t gen_params;
        sd_img_gen_params_init(&gen_params);
        gen_params.prompt = prompt;
        gen_params.negative_prompt = negative_prompt ? negative_prompt : "";
        gen_params.width = width;
        gen_params.height = height;
        if (sample_method >= 0 && sample_method < SAMPLE_METHOD_COUNT) {
            gen_params.sample_params.sample_method = (sample_method_t)sample_method;
        } else {
            gen_params.sample_params.sample_method = sd_get_default_sample_method(sd_ctx);
        }
        gen_params.sample_params.scheduler = sd_get_default_scheduler(sd_ctx, gen_params.sample_params.sample_method);
        gen_params.sample_params.sample_steps = sample_steps;
        gen_params.sample_params.guidance.txt_cfg = cfg_scale;
        gen_params.seed = seed;
        gen_params.batch_count = 1;
        gen_params.vae_tiling_params.enabled = true; // Mobile RAM safety

        bridge_emit_log(SD_LOG_INFO, "[INFERENCE] Tokenizing prompt and calculating CLIP embeddings...");

        sd_image_t* images_out = nullptr;
        int num_images = 0;

        bool success = generate_image(sd_ctx, &gen_params, &images_out, &num_images);

        g_active_progress_cb = nullptr;

        if (g_abort_requested.load()) {
            bridge_emit_log(SD_LOG_WARN, "[INFERENCE] Generation was aborted by user.");
            if (images_out != nullptr) {
                for (int i = 0; i < num_images; i++) {
                    if (images_out[i].data) free(images_out[i].data);
                }
                free(images_out);
            }
            return 1;
        }

        if (!success || num_images == 0 || images_out == nullptr) {
            bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] generate_image failed or aborted (-4)");
            return -4;
        }

        sd_image_t* result = &images_out[0];
        if (result->data == nullptr || result->width == 0 || result->height == 0) {
            bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Invalid image result buffer (-5)");
            for (int i = 0; i < num_images; i++) {
                if (images_out[i].data) free(images_out[i].data);
            }
            free(images_out);
            return -5;
        }

        snprintf(msg, sizeof(msg), "[INFERENCE] Denoising complete. Decoding latents with VAE (%dx%d)...",
                 result->width, result->height);
        bridge_emit_log(SD_LOG_INFO, msg);

        int write_res = stbi_write_png(
            output_png_path,
            result->width,
            result->height,
            result->channel,
            result->data,
            result->width * result->channel
        );

        // Immediate cleanup of native unmanaged pixel buffers
        for (int i = 0; i < num_images; i++) {
            if (images_out[i].data) {
                free(images_out[i].data);
            }
        }
        free(images_out);

        if (write_res != 0) {
            bridge_emit_log(SD_LOG_INFO, "[INFERENCE] Image successfully written to disk.");
            return 0;
        } else {
            bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] stbi_write_png failed to write file (-6)");
            return -6;
        }
    } catch (const std::bad_alloc&) {
        bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Out of Memory (std::bad_alloc) (-10)");
        g_active_progress_cb = nullptr;
        return -10;
    } catch (const std::exception& ex) {
        snprintf(msg, sizeof(msg), "[INFERENCE] std::exception: %s (-99)", ex.what());
        bridge_emit_log(SD_LOG_ERROR, msg);
        g_active_progress_cb = nullptr;
        return -99;
    } catch (...) {
        bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Unknown native exception caught (-99)");
        g_active_progress_cb = nullptr;
        return -99;
    }
}

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
) {
    std::lock_guard<std::mutex> lock(g_worker_mutex);
    if (g_is_generating.load()) {
        bridge_emit_log(SD_LOG_ERROR, "[INFERENCE] Another generation is already active (-7)");
        if (completion_cb) completion_cb(-7, "Another generation is already active.");
        return -7;
    }

    if (g_worker_thread.joinable()) {
        g_worker_thread.join();
    }

    std::string s_prompt = prompt ? prompt : "";
    std::string s_neg_prompt = negative_prompt ? negative_prompt : "";
    std::string s_out_path = output_png_path ? output_png_path : "";

    g_is_generating.store(true);
    g_abort_requested.store(false);

    g_worker_thread = std::thread([=]() {
        int32_t res = execute_txt2img(
            ctx,
            s_prompt.c_str(),
            s_neg_prompt.c_str(),
            cfg_scale,
            width,
            height,
            sample_method,
            sample_steps,
            seed,
            s_out_path.c_str(),
            progress_cb
        );

        g_is_generating.store(false);

        if (completion_cb != nullptr) {
            if (res == 0) {
                completion_cb(0, s_out_path.c_str());
            } else if (g_abort_requested.load() || res == 1) {
                completion_cb(1, "Generation was stopped by user");
            } else {
                char err_buf[64];
                snprintf(err_buf, sizeof(err_buf), "Inference failed with code %d", res);
                completion_cb(res, err_buf);
            }
        }
    });

    return 0;
}

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
) {
    g_abort_requested.store(false);
    return execute_txt2img(
        ctx,
        prompt,
        negative_prompt,
        cfg_scale,
        width,
        height,
        sample_method,
        sample_steps,
        seed,
        output_png_path,
        progress_cb
    );
}

SD_EXPORT void sd_bridge_abort(sd_context_handle_t ctx) {
    bridge_emit_log(SD_LOG_WARN, "[INFERENCE] Abort signal sent to engine");
    g_abort_requested.store(true);
    if (ctx != nullptr) {
        sd_cancel_generation(reinterpret_cast<sd_ctx_t*>(ctx), SD_CANCEL_ALL);
    }
}

SD_EXPORT void sd_bridge_free(sd_context_handle_t ctx) {
    bridge_emit_log(SD_LOG_INFO, "[LOADER] Freeing Stable Diffusion context");
    sd_bridge_abort(ctx);
    {
        std::lock_guard<std::mutex> lock(g_worker_mutex);
        if (g_worker_thread.joinable()) {
            g_worker_thread.join();
        }
    }
    if (ctx != nullptr) {
        free_sd_ctx(reinterpret_cast<sd_ctx_t*>(ctx));
    }
}

SD_EXPORT const char* sd_bridge_get_system_info(void) {
    return sd_get_system_info();
}
