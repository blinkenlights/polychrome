#include "ear_ring.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct ear_ring {
    uint32_t channels;
    uint32_t capacity; /* frames, a power of two */
    uint64_t mask;
    uint32_t target;
    double sample_rate;
    float *data; /* planar: channel * capacity + frame */

    _Atomic uint64_t write; /* frames written, ever */

    /* Reader thread only, one per channel. */
    uint64_t *read;
    int *primed;
    uint32_t primed_count;

    /* Ping, one per channel, reader thread only apart from the atomics. */
    _Atomic uint32_t ping_channel;
    _Atomic uint32_t ping_serial;
    uint32_t *ping_seen;
    float *ping_env;
    double *ping_phase;
    uint32_t noise;
    float ping_decay;

    /* Shared with the UI. */
    _Atomic uint32_t *levels; /* float bits */
    _Atomic uint32_t underruns;
    _Atomic uint32_t overruns;
    _Atomic int primed_flag;
};

static uint32_t next_power_of_two(uint32_t v) {
    uint32_t p = 1;
    while (p < v) p <<= 1;
    return p;
}

ear_ring *ear_ring_create(uint32_t channels, uint32_t capacity_frames, uint32_t target_frames,
                          double sample_rate) {
    if (channels == 0) return NULL;

    ear_ring *ring = calloc(1, sizeof(ear_ring));
    if (!ring) return NULL;

    ring->channels = channels;
    ring->capacity = next_power_of_two(capacity_frames < 1024 ? 1024 : capacity_frames);
    ring->mask = ring->capacity - 1;
    ring->target = target_frames;
    ring->sample_rate = sample_rate;
    ring->data = calloc((size_t)channels * ring->capacity, sizeof(float));
    ring->read = calloc(channels, sizeof(uint64_t));
    ring->primed = calloc(channels, sizeof(int));
    ring->ping_seen = calloc(channels, sizeof(uint32_t));
    ring->ping_env = calloc(channels, sizeof(float));
    ring->ping_phase = calloc(channels, sizeof(double));
    ring->levels = calloc(channels, sizeof(_Atomic uint32_t));
    ring->noise = 0x9e3779b9u;
    /* About 60 ms to fall by 1/e. */
    ring->ping_decay = (float)exp(-1.0 / (0.06 * sample_rate));
    atomic_init(&ring->ping_channel, UINT32_MAX);

    if (!ring->data || !ring->read || !ring->primed || !ring->ping_seen || !ring->ping_env || !ring->ping_phase || !ring->levels) {
        ear_ring_destroy(ring);
        return NULL;
    }
    return ring;
}

void ear_ring_destroy(ear_ring *ring) {
    if (!ring) return;
    free(ring->data);
    free(ring->read);
    free(ring->primed);
    free(ring->ping_seen);
    free(ring->ping_env);
    free(ring->ping_phase);
    free(ring->levels);
    free(ring);
}

uint32_t ear_ring_channels(const ear_ring *ring) { return ring->channels; }

void ear_ring_write(ear_ring *ring, const AudioBufferList *buffers, uint32_t frames) {
    uint64_t start = atomic_load_explicit(&ring->write, memory_order_relaxed);
    uint32_t channel = 0;

    /* One loop covers both layouts: planar is n buffers of one channel,
       interleaved is one buffer of n channels. */
    for (uint32_t b = 0; b < buffers->mNumberBuffers && channel < ring->channels; b++) {
        const AudioBuffer *buffer = &buffers->mBuffers[b];
        const float *samples = buffer->mData;
        uint32_t stride = buffer->mNumberChannels;
        if (!samples || stride == 0) continue;

        uint32_t available = buffer->mDataByteSize / (sizeof(float) * stride);
        uint32_t n = frames < available ? frames : available;

        for (uint32_t c = 0; c < stride && channel < ring->channels; c++, channel++) {
            float *dest = ring->data + (size_t)channel * ring->capacity;
            for (uint32_t i = 0; i < n; i++) {
                dest[(start + i) & ring->mask] = samples[(size_t)i * stride + c];
            }
            for (uint32_t i = n; i < frames; i++) {
                dest[(start + i) & ring->mask] = 0.0f;
            }
        }
    }

    for (; channel < ring->channels; channel++) {
        float *dest = ring->data + (size_t)channel * ring->capacity;
        for (uint32_t i = 0; i < frames; i++) dest[(start + i) & ring->mask] = 0.0f;
    }

    atomic_store_explicit(&ring->write, start + frames, memory_order_release);
}

/* Decides where this channel reads next, and how much of it is real. */
static uint32_t take(ear_ring *ring, uint32_t channel, uint32_t frames, uint64_t *start) {
    uint64_t written = atomic_load_explicit(&ring->write, memory_order_acquire);
    uint64_t read = ring->read[channel];
    uint64_t available = written >= read ? written - read : 0;
    uint32_t keep = ring->target > frames ? ring->target : frames;
    /* One channel stands for all of them; counting twelve of everything would
       say nothing more. */
    int counts = channel == 0;
    uint32_t taken = 0;

    if (!ring->primed[channel]) {
        if (available >= (uint64_t)keep + frames) {
            read = written - keep;
            ring->primed[channel] = 1;
            ring->primed_count++;
            taken = frames;
        }
    } else if (available < frames) {
        if (counts) atomic_fetch_add_explicit(&ring->underruns, 1, memory_order_relaxed);
        ring->primed[channel] = 0;
        ring->primed_count--;
    } else {
        if (available > (uint64_t)keep * 2 + frames || available > ring->capacity - frames) {
            if (counts) atomic_fetch_add_explicit(&ring->overruns, 1, memory_order_relaxed);
            read = written - keep;
        }
        taken = frames;
    }

    *start = read;
    ring->read[channel] = read + taken;
    atomic_store_explicit(&ring->primed_flag, ring->primed_count > 0, memory_order_relaxed);
    return taken;
}

static float next_noise(ear_ring *ring) {
    ring->noise = ring->noise * 1664525u + 1013904223u;
    return (float)(ring->noise >> 8) / (float)(1u << 23) - 1.0f;
}

void ear_ring_read(ear_ring *ring, uint32_t channel, float *out, uint32_t frames) {
    if (channel >= ring->channels) {
        memset(out, 0, sizeof(float) * frames);
        return;
    }

    uint64_t start = 0;
    uint32_t taken = take(ring, channel, frames, &start);
    const float *source = ring->data + (size_t)channel * ring->capacity;
    for (uint32_t i = 0; i < taken; i++) {
        out[i] = source[(start + i) & ring->mask];
    }
    if (taken < frames) memset(out + taken, 0, sizeof(float) * (frames - taken));

    /* The ping is a bright noise burst over a sine: broadband, so the HRTF has
       something to work with, and a pitch, so it reads as a signal. */
    uint32_t serial = atomic_load_explicit(&ring->ping_serial, memory_order_acquire);
    if (serial != ring->ping_seen[channel]) {
        ring->ping_seen[channel] = serial;
        if (atomic_load_explicit(&ring->ping_channel, memory_order_acquire) == channel) {
            ring->ping_env[channel] = 1.0f;
            ring->ping_phase[channel] = 0.0;
        }
    }
    float env = ring->ping_env[channel];
    if (env > 1.0e-4f) {
        double phase = ring->ping_phase[channel];
        double step = 2.0 * M_PI * 880.0 / ring->sample_rate;
        for (uint32_t i = 0; i < frames; i++) {
            out[i] += env * (0.25f * (float)sin(phase) + 0.2f * next_noise(ring));
            phase += step;
            env *= ring->ping_decay;
        }
        ring->ping_phase[channel] = fmod(phase, 2.0 * M_PI);
        ring->ping_env[channel] = env;
    }

    float peak = 0.0f;
    for (uint32_t i = 0; i < frames; i++) {
        float a = fabsf(out[i]);
        if (a > peak) peak = a;
    }
    float previous;
    uint32_t bits = atomic_load_explicit(&ring->levels[channel], memory_order_relaxed);
    memcpy(&previous, &bits, sizeof(float));
    float falling = previous * 0.9f;
    float level = peak > falling ? peak : falling;
    memcpy(&bits, &level, sizeof(float));
    atomic_store_explicit(&ring->levels[channel], bits, memory_order_relaxed);
}

uint64_t ear_ring_written(ear_ring *ring) {
    return atomic_load_explicit(&ring->write, memory_order_relaxed);
}

float ear_ring_level(ear_ring *ring, uint32_t channel) {
    if (channel >= ring->channels) return 0.0f;
    uint32_t bits = atomic_load_explicit(&ring->levels[channel], memory_order_relaxed);
    float level;
    memcpy(&level, &bits, sizeof(float));
    return level;
}

uint32_t ear_ring_underruns(ear_ring *ring) {
    return atomic_load_explicit(&ring->underruns, memory_order_relaxed);
}

uint32_t ear_ring_overruns(ear_ring *ring) {
    return atomic_load_explicit(&ring->overruns, memory_order_relaxed);
}

int ear_ring_primed(ear_ring *ring) {
    return atomic_load_explicit(&ring->primed_flag, memory_order_relaxed);
}

void ear_ring_ping(ear_ring *ring, uint32_t channel) {
    atomic_store_explicit(&ring->ping_channel, channel, memory_order_release);
    atomic_fetch_add_explicit(&ring->ping_serial, 1, memory_order_release);
}
