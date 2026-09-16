#ifndef EAR_RING_H
#define EAR_RING_H

#include <CoreAudioTypes/CoreAudioTypes.h>
#include <stdint.h>

/*
 * A multichannel ring buffer between two audio clocks: the capture device
 * writes, the playback device reads. One writer thread, one reader thread,
 * no locks, no allocation after create.
 *
 * AVAudioEnvironmentNode pulls every mono source on its own, in small and
 * uneven blocks, so each channel keeps its own read position. They stay
 * together anyway: one writer feeds all channels the same frames, and each
 * reader advances by exactly what it took.
 *
 * The clocks drift. Each reader keeps its fill near `target_frames`: when it
 * runs dry it goes silent until it is primed again, when it runs over it jumps
 * forward. Corrections are counted for the first channel, which stands for all
 * of them.
 */
typedef struct ear_ring ear_ring;

ear_ring *ear_ring_create(uint32_t channels, uint32_t capacity_frames, uint32_t target_frames,
                          double sample_rate);
void ear_ring_destroy(ear_ring *ring);

uint32_t ear_ring_channels(const ear_ring *ring);

/* Writer: planar or interleaved float32, as the capture unit delivers it. */
void ear_ring_write(ear_ring *ring, const AudioBufferList *buffers, uint32_t frames);

/* Reader: the next frames of one channel into a mono buffer. */
void ear_ring_read(ear_ring *ring, uint32_t channel, float *out, uint32_t frames);

/* Any thread. */
uint64_t ear_ring_written(ear_ring *ring);
float ear_ring_level(ear_ring *ring, uint32_t channel);
uint32_t ear_ring_underruns(ear_ring *ring);
uint32_t ear_ring_overruns(ear_ring *ring);
int ear_ring_primed(ear_ring *ring);

/* Any thread: a short ping on one channel, mixed in by the reader. */
void ear_ring_ping(ear_ring *ring, uint32_t channel);

#endif
